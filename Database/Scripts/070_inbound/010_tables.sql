INSERT INTO inbound.inbound_line_state_transitions VALUES
('EXP','PRC',0),
('PRC','PRC',0),  -- multiple partial receipts
('PRC','RCV',0),
('EXP','RCV',0),
('EXP','CNL',1),
('PRC','CNL',1),
('PRC', 'EXP', 1),
('RCV', 'PRC', 1),
('RCV', 'EXP', 1);
GO

/* Seed transitions (idempotent) */
MERGE inbound.inbound_expected_unit_state_transitions AS tgt
USING (VALUES
    ('EXP','CLM',0),  -- preview claim
    ('CLM','EXP',0),  -- auto-expire / release claim
    ('CLM','RCV',0),  -- confirm receive
    ('EXP','RCV',1),  -- optional: admin force receive without claim (usually NO; keep as 1)
    ('RCV', 'EXP', 1)
) AS src(from_state_code, to_state_code, requires_authority)
ON  tgt.from_state_code = src.from_state_code
AND tgt.to_state_code   = src.to_state_code
WHEN NOT MATCHED THEN
    INSERT (from_state_code, to_state_code, requires_authority)
    VALUES (src.from_state_code, src.to_state_code, src.requires_authority);
GO

CREATE NONCLUSTERED INDEX IX_inbound_receipts_line
ON inbound.inbound_receipts(inbound_line_id)
INCLUDE (received_qty, received_at);
GO

USE PW_Core_DEV;
GO

/* ============================================================
   View: inbound.vw_inbounds_activatable
   ------------------------------------------------------------
   Returns inbound deliveries eligible for activation.

   Criteria:
   - Status = 'EXP' (Expected — not yet activated)
   - Has at least one inbound line
   
   Used by:
   - CLI: ActivateInboundScreen.RenderList()
   - Application: IInboundQueryRepository.GetActivatableInbounds()

   Columns match SqlInboundQueryRepository.GetActivatableInbounds()
   ordinal read: inbound_id(0), inbound_ref(1),
                 expected_arrival_at(2), line_count(3)
   ============================================================ */
GO

CREATE TABLE inbound.inbound_statuses
(
    status_code VARCHAR(3) PRIMARY KEY,   -- EXP, ACT, RCV, CLS, CNL
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT NOT NULL DEFAULT(0)
);

INSERT INTO inbound.inbound_statuses VALUES
('EXP', 'Expected', 0),
('ACT', 'Activated', 0),
('RCV', 'Receiving', 0),
('CLS', 'Closed', 1),
('CNL', 'Cancelled', 1);

CREATE TABLE inbound.inbound_status_transitions
(
    from_status_code VARCHAR(3) NOT NULL,
    to_status_code   VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT(0),

    CONSTRAINT PK_inbound_status_transitions
        PRIMARY KEY (from_status_code, to_status_code),

    CONSTRAINT FK_inbound_transition_from
        FOREIGN KEY (from_status_code)
        REFERENCES inbound.inbound_statuses(status_code),

    CONSTRAINT FK_inbound_transition_to
        FOREIGN KEY (to_status_code)
        REFERENCES inbound.inbound_statuses(status_code)
);

INSERT INTO inbound.inbound_status_transitions VALUES
('EXP','ACT',0),
('ACT','RCV',0),
('RCV','CLS',0),
('EXP','CNL',0),
('ACT','CNL',1),
('CLS', 'RCV', 1);



/* ============================================================
   inbound.inbound_deliveries
   ------------------------------------------------------------
   Canonical inbound advice header table.

   One row = one advised inbound document (ASN / delivery note).

   This table represents INTENT, not execution.
   No stock, no pallets, no quantities live here.

   Purpose:
   - Planning
   - Visibility
   - Status progression
   - Linking parties before warehouse activity begins
   ============================================================ */
   /********************************************************************************************
    Table: inbound.inbound_modes
    Purpose: Reference table defining structural inbound receiving modes
             - SSCC   : Fully pre-advised handling units
             - MANUAL : Loose / quantity-based receiving
    ********************************************************************************************/
    IF NOT EXISTS (
        SELECT 1
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.name = 'inbound_modes'
          AND s.name = 'inbound'
    )
    BEGIN
        CREATE TABLE inbound.inbound_modes
        (
            mode_code   VARCHAR(6)  NOT NULL PRIMARY KEY,
            mode_name   NVARCHAR(50) NOT NULL,
            description NVARCHAR(200) NULL,
            is_active   BIT NOT NULL DEFAULT 1
        );
    END;
    GO

    /* --------------------------------------------------------
       Seed inbound mode reference data
    -------------------------------------------------------- */

    IF NOT EXISTS (
        SELECT 1 FROM inbound.inbound_modes WHERE mode_code = 'SSCC'
    )
    BEGIN
        INSERT INTO inbound.inbound_modes (mode_code, mode_name, description)
        VALUES ('SSCC', 'SSCC Controlled', 'Fully pre-advised handling units');
    END;

    IF NOT EXISTS (
        SELECT 1 FROM inbound.inbound_modes WHERE mode_code = 'MANUAL'
    )
    BEGIN
        INSERT INTO inbound.inbound_modes (mode_code, mode_name, description)
        VALUES ('MANUAL', 'Manual Quantity', 'Loose or bulk quantity receiving');
    END;
    GO

    CREATE TABLE inbound.inbound_deliveries
    (
        inbound_id           INT IDENTITY(1,1) PRIMARY KEY,

        inbound_ref          NVARCHAR(50) NOT NULL UNIQUE,

        supplier_party_id    INT NOT NULL,
        owner_party_id       INT NOT NULL,
        haulier_party_id     INT NULL,

        ship_to_address_id   INT NOT NULL,

        expected_arrival_at  DATETIME2(3) NULL,

        inbound_status_code  VARCHAR(3) NOT NULL DEFAULT 'EXP',

        -- Structural mode (set on activation, immutable afterwards)
        inbound_mode_code    VARCHAR(6) NULL,

        created_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        created_by           INT NULL,

        updated_at           DATETIME2(3) NULL,
        updated_by           INT NULL,

        CONSTRAINT FK_inbound_status
            FOREIGN KEY (inbound_status_code)
            REFERENCES inbound.inbound_statuses(status_code),

        CONSTRAINT FK_inbound_mode
            FOREIGN KEY (inbound_mode_code)
            REFERENCES inbound.inbound_modes(mode_code),

        CONSTRAINT fk_inbound_supplier
            FOREIGN KEY (supplier_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_owner
            FOREIGN KEY (owner_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_haulier
            FOREIGN KEY (haulier_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_ship_to
            FOREIGN KEY (ship_to_address_id)
            REFERENCES core.party_addresses(address_id)
    );
    GO

    CREATE INDEX IX_inbound_status_mode
    ON inbound.inbound_deliveries (inbound_status_code, inbound_mode_code);
    GO

/* ============================================================
   View: inbound.vw_inbound_overview
   ------------------------------------------------------------
   Operational overview of inbound advice.

   Used by:
   - CLI "View expected deliveries"
   - Desktop inbound list
   - Reporting / dashboards
   ============================================================ */
CREATE OR ALTER VIEW inbound.vw_inbound_overview
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.inbound_status_code,
    d.expected_arrival_at,

    s.display_name   AS supplier_name,
    o.display_name   AS owner_name,
    h.display_name   AS haulier_name,

    a.city,
    a.postal_code,
    a.country_code

FROM inbound.inbound_deliveries d
JOIN core.parties s ON s.party_id = d.supplier_party_id
JOIN core.parties o ON o.party_id = d.owner_party_id
LEFT JOIN core.parties h ON h.party_id = d.haulier_party_id
JOIN core.party_addresses a ON a.address_id = d.ship_to_address_id;
GO

/* ============================================================
   View: inbound.vw_inbound_by_supplier
   ------------------------------------------------------------
   Supplier-centric workload view.

   Used for:
   - Planning
   - Supplier performance insight
   ============================================================ */
CREATE OR ALTER VIEW inbound.vw_inbound_by_supplier
AS
SELECT
    s.party_code     AS supplier_code,
    s.display_name   AS supplier_name,
    COUNT(*)         AS open_inbounds
FROM inbound.inbound_deliveries d
JOIN core.parties s ON s.party_id = d.supplier_party_id
WHERE d.inbound_status_code IN ('EXP','ACT','RCV')
GROUP BY s.party_code, s.display_name;
GO

/* ============================================================
   logistics.vw_inbound_by_haulier
   ============================================================ */
CREATE OR ALTER VIEW logistics.vw_inbound_by_haulier
AS
SELECT
    h.display_name AS haulier_name,
    COUNT(*)       AS scheduled_deliveries,
    MIN(d.expected_arrival_at) AS next_eta
FROM inbound.inbound_deliveries d
JOIN core.parties h ON h.party_id = d.haulier_party_id
WHERE d.inbound_status_code IN ('EXP','ACT','RCV')
GROUP BY h.display_name;
GO

/* ============================================================
   Trigger: audit inbound advice changes
   ------------------------------------------------------------
   Records meaningful lifecycle and header changes
   to inbound advice documents.

   Mirrors audit.party_changes pattern.
   ============================================================ */
/*
CREATE OR ALTER TRIGGER inbound.tr_inbound_deliveries_audit
ON inbound.inbound_deliveries
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.party_changes
    (
        party_id,
        action,
        details,
        changed_at,
        changed_by,
        session_id
    )
    SELECT
        -- Owner is the most stable auditing anchor
        COALESCE(i.owner_party_id, d.owner_party_id),

        CASE
            WHEN d.inbound_id IS NULL THEN 'CREATE_INBOUND'
            WHEN i.inbound_id IS NULL THEN 'DELETE_INBOUND'
            WHEN d.inbound_status <> i.inbound_status THEN 'INBOUND_STATUS_CHANGE'
            ELSE 'UPDATE_INBOUND_HEADER'
        END,

        CONCAT(
            'inbound_ref=', COALESCE(i.inbound_ref, d.inbound_ref),
            '; status=', COALESCE(i.inbound_status, d.inbound_status)
        ),

        SYSUTCDATETIME(),
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)

    FROM inserted i
    FULL JOIN deleted d
        ON d.inbound_id = i.inbound_id;
END;
GO

*/
CREATE TABLE inbound.inbound_line_states
(
    state_code      VARCHAR(3) PRIMARY KEY, -- EXP, PRC, RCV, CNL
    state_desc      NVARCHAR(30) NOT NULL,
    is_terminal     BIT NOT NULL DEFAULT 0
);

INSERT INTO inbound.inbound_line_states
VALUES
('EXP','EXPECTED',0),
('PRC','PARTIALLY_RECEIVED',0),
('RCV','RECEIVED',1),
('CNL','CANCELLED',1);

CREATE TABLE inbound.inbound_line_state_transitions
(
    from_state_code VARCHAR(3) NOT NULL,
    to_state_code   VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT(0),

    CONSTRAINT PK_inbound_line_transitions
        PRIMARY KEY (from_state_code, to_state_code),

    CONSTRAINT FK_inbound_line_transition_from
        FOREIGN KEY (from_state_code)
        REFERENCES inbound.inbound_line_states(state_code),

    CONSTRAINT FK_inbound_line_transition_to
        FOREIGN KEY (to_state_code)
        REFERENCES inbound.inbound_line_states(state_code)
);
GO

CREATE TABLE inbound.inbound_lines
(
    inbound_line_id     INT IDENTITY(1,1) PRIMARY KEY,
    inbound_id          INT NOT NULL,
    line_no             INT NOT NULL,

    sku_id              INT NOT NULL,
    expected_qty        INT NOT NULL CHECK (expected_qty > 0),
    received_qty        INT NOT NULL DEFAULT (0),

    arrival_stock_status_code VARCHAR(2) NOT NULL DEFAULT 'AV',
    batch_number        NVARCHAR(100) NULL,
    best_before_date    DATE NULL,

    line_state_code     VARCHAR(3) NOT NULL DEFAULT 'EXP',

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,
    updated_at                  DATETIME2(3) NULL,
    updated_by                  INT NULL,

    CONSTRAINT FK_inbound_lines_header
        FOREIGN KEY (inbound_id)
        REFERENCES inbound.inbound_deliveries(inbound_id),

    CONSTRAINT FK_inbound_lines_sku
        FOREIGN KEY (sku_id)
        REFERENCES inventory.skus(sku_id),

    CONSTRAINT FK_inbound_line_state
        FOREIGN KEY (line_state_code)
        REFERENCES inbound.inbound_line_states(state_code),

    CONSTRAINT UQ_inbound_line
        UNIQUE (inbound_id, line_no),

    CONSTRAINT CK_received_qty_valid
        CHECK (received_qty <= expected_qty),

    CONSTRAINT FK_inbound_lines_arrival_status
        FOREIGN KEY (arrival_stock_status_code)
        REFERENCES inventory.stock_statuses(status_code)
);

/* ============================================================
   inbound.inbound_expected_units
   ------------------------------------------------------------
   Pre-advised handling units (SSCC-level expectations).
   One row = one expected handling unit for an inbound line.
   ============================================================ */
   CREATE TABLE inbound.inbound_expected_unit_states
    (
        state_code VARCHAR(3) PRIMARY KEY,
        description NVARCHAR(50) NOT NULL
    );

    INSERT INTO inbound.inbound_expected_unit_states VALUES
        ('EXP', 'EXPECTED'),
        ('CLM', 'CLAIMED'),
        ('RCV', 'RECEIVED'),
        ('CNL', 'CANCELLED');

/* =========================================================================================
   TABLE: inbound.inbound_expected_unit_state_transitions
   Purpose: Allowed state changes for SSCC expected units (EXP/CLM/RCV/...)
========================================================================================= */
IF OBJECT_ID('inbound.inbound_expected_unit_state_transitions', 'U') IS NULL
BEGIN
    CREATE TABLE inbound.inbound_expected_unit_state_transitions
    (
        from_state_code     VARCHAR(3) NOT NULL,
        to_state_code       VARCHAR(3) NOT NULL,
        requires_authority  BIT NOT NULL DEFAULT(0),

        CONSTRAINT PK_inbound_expected_unit_state_transitions
            PRIMARY KEY (from_state_code, to_state_code)
    );
END;
GO

/* ============================================================
   inbound.inbound_expected_units (WITH CLAIM FIELDS)
   Includes optional updated_at / updated_by
   ============================================================ */

    IF OBJECT_ID('inbound.inbound_expected_units', 'U') IS NULL
    BEGIN
        CREATE TABLE inbound.inbound_expected_units
        (
            inbound_expected_unit_id    INT IDENTITY(1,1) PRIMARY KEY,

            inbound_line_id             INT NOT NULL,

            -- Expected SSCC from ASN / EDI
            expected_external_ref       NVARCHAR(100) NOT NULL,

            expected_quantity           INT NOT NULL CHECK (expected_quantity > 0),

            batch_number                NVARCHAR(100) NULL,
            best_before_date            DATE NULL,

            expected_unit_state_code    VARCHAR(3) NOT NULL
                CONSTRAINT DF_inbexp_state_code DEFAULT ('EXP'),

            received_inventory_unit_id  INT NULL,

            -- Claim / lock fields (two-scan confirm hardening)
            claimed_session_id          UNIQUEIDENTIFIER NULL,
            claimed_by_user_id          INT NULL,
            claimed_at                  DATETIME2(3) NULL,
            claim_expires_at            DATETIME2(3) NULL,
            claim_token                 UNIQUEIDENTIFIER NULL,

            created_at                  DATETIME2(3) NOT NULL
                CONSTRAINT DF_inbexp_created_at DEFAULT (SYSUTCDATETIME()),

            created_by                  INT NULL,

            updated_at                  DATETIME2(3) NULL,
            updated_by                  INT NULL,

            CONSTRAINT FK_inbexp_line
                FOREIGN KEY (inbound_line_id)
                REFERENCES inbound.inbound_lines(inbound_line_id),

            CONSTRAINT FK_inbexp_inventory_unit
                FOREIGN KEY (received_inventory_unit_id)
                REFERENCES inventory.inventory_units(inventory_unit_id),

            CONSTRAINT FK_inbexp_state
                FOREIGN KEY (expected_unit_state_code)
                REFERENCES inbound.inbound_expected_unit_states(state_code),

            CONSTRAINT UQ_inbexp_external_ref
                UNIQUE (expected_external_ref),

            CONSTRAINT CK_inbexp_quantity
                CHECK (expected_quantity > 0)
        );

        CREATE INDEX IX_inbexp_line
        ON inbound.inbound_expected_units(inbound_line_id);

        CREATE INDEX IX_inbexp_claim_session 
        ON inbound.inbound_expected_units(claimed_session_id, claim_expires_at);

        CREATE INDEX IX_inbexp_units_claim
        ON inbound.inbound_expected_units (expected_external_ref)
        INCLUDE (received_inventory_unit_id, claimed_session_id, claim_expires_at);

        /* OPTIONAL (recommended): helps clean up / find expiring claims fast */
        CREATE INDEX IX_inbexp_claim_expires
        ON inbound.inbound_expected_units (claim_expires_at)
        INCLUDE (expected_external_ref, claimed_session_id, received_inventory_unit_id);

    END;
    GO

/* ============================================================
   
   ============================================================ */
    IF OBJECT_ID('inbound.inbound_expected_units', 'U') IS NOT NULL
    AND NOT EXISTS
    (
        SELECT 1
        FROM sys.default_constraints dc
        JOIN sys.columns c
            ON c.object_id = dc.parent_object_id
           AND c.column_id = dc.parent_column_id
        WHERE dc.parent_object_id = OBJECT_ID('inbound.inbound_expected_units')
          AND c.name = 'created_by'
    )
    BEGIN
        ALTER TABLE inbound.inbound_expected_units
        ADD CONSTRAINT DF_inbexp_created_by
        DEFAULT (CONVERT(int, SESSION_CONTEXT(N'user_id')))
        FOR created_by;
    END;
    GO

/* ============================================================
   inbound.inbound_receipts
   ------------------------------------------------------------
   Physical receipt events against inbound lines.

   One row = one receive transaction.
   Immutable business event.
   ============================================================ */
   IF OBJECT_ID('inbound.inbound_receipts','U') IS NOT NULL
    DROP TABLE inbound.inbound_receipts;
GO

CREATE TABLE inbound.inbound_receipts
(
    receipt_id              INT IDENTITY(1,1)
                            CONSTRAINT PK_inbound_receipts
                            PRIMARY KEY,

    inbound_line_id         INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_line
                            REFERENCES inbound.inbound_lines(inbound_line_id),

    inbound_expected_unit_id INT NULL
                            CONSTRAINT FK_inbound_receipts_expected_unit
                            REFERENCES inbound.inbound_expected_units(inbound_expected_unit_id),

    inventory_unit_id       INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_inventory
                            REFERENCES inventory.inventory_units(inventory_unit_id),

    received_qty            INT NOT NULL CHECK (received_qty > 0),

    received_by_user_id     INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_user
                            REFERENCES auth.users(id),

    session_id              UNIQUEIDENTIFIER NULL,

    received_at             DATETIME2(3) NOT NULL
                            CONSTRAINT DF_inbound_receipts_received_at
                            DEFAULT SYSUTCDATETIME(),

    is_reversal             BIT NOT NULL DEFAULT(0),
    reversed_receipt_id     INT NULL
                            CONSTRAINT FK_inbound_receipts_reversal
                            REFERENCES inbound.inbound_receipts(receipt_id)
);
GO

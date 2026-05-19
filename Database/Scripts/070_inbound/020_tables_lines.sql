USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

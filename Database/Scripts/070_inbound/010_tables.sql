USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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
GO

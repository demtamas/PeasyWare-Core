USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   Stock counting
   ------------------------------------------------------------
   count_sessions  one count of one kind over one scope.
                   EMPTY_BIN today (scope = a storage type);
                   CYCLE / ADHOC later reuse the same header.
   count_lines     one row per bin in the count, snapshotted at
                   start so the walk list is stable and "bins not
                   yet counted" is reportable.
   count_findings  what an operator found in a bin the system
                   believed was empty - one row per pallet
                   scanned, so a bin holding several pallets
                   records each.

   A count line's own outcome:
     PENDING          not visited yet
     CONFIRMED_EMPTY  operator scanned the bin and it is empty
     STOCK_FOUND      one or more pallets found (see findings)
     OCCUPIED_SINCE   the system recorded stock there after the
                      snapshot, so "empty" no longer holds - not
                      an exception, just no longer an empty bin

   One OPEN session per type + scope, so a count can be left and
   resumed (or shared) rather than duplicated.
   ============================================================ */
CREATE TABLE warehouse.count_sessions
(
    count_id         INT IDENTITY(1,1) PRIMARY KEY,

    count_type_code  VARCHAR(20)  NOT NULL,          -- EMPTY_BIN
    storage_type_id  INT          NULL,              -- scope

    status_code      VARCHAR(10)  NOT NULL DEFAULT 'OPEN',
        -- OPEN      in progress / resumable
        -- REVIEW    the physical count is finished, but it found something a
        --           person has to deal with (see count_findings). Stays on the
        --           review list until a manager marks it reviewed. Does NOT
        --           block a new count of the same scope - only OPEN does.
        -- COMPLETE  finished with every bin counted, nothing outstanding
        -- CLOSED    finished with bins still uncounted, nothing outstanding

    started_at       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    started_by       INT          NULL,

    -- When the physical count ended
    completed_at     DATETIME2(3) NULL,
    completed_by     INT          NULL,

    -- When a person dealt with what it found, and what they did about it
    reviewed_at      DATETIME2(3)  NULL,
    reviewed_by      INT           NULL,
    review_note      NVARCHAR(500) NULL,

    CONSTRAINT CK_count_sessions_status
        CHECK (status_code IN ('OPEN', 'REVIEW', 'COMPLETE', 'CLOSED')),

    CONSTRAINT FK_count_sessions_storage_type
        FOREIGN KEY (storage_type_id)
        REFERENCES locations.storage_types(storage_type_id)
);

CREATE UNIQUE INDEX UX_count_sessions_open_scope
ON warehouse.count_sessions (count_type_code, storage_type_id)
WHERE status_code = 'OPEN';

CREATE TABLE warehouse.count_lines
(
    count_line_id     INT IDENTITY(1,1) PRIMARY KEY,

    count_id          INT NOT NULL,
    bin_id            INT NOT NULL,

    line_status_code  VARCHAR(16) NOT NULL DEFAULT 'PENDING',

    counted_at        DATETIME2(3) NULL,
    counted_by        INT NULL,

    CONSTRAINT FK_count_lines_session
        FOREIGN KEY (count_id)
        REFERENCES warehouse.count_sessions(count_id),

    CONSTRAINT FK_count_lines_bin
        FOREIGN KEY (bin_id)
        REFERENCES locations.bins(bin_id),

    CONSTRAINT UQ_count_lines_bin
        UNIQUE (count_id, bin_id),

    CONSTRAINT CK_count_lines_status
        CHECK (line_status_code IN ('PENDING', 'CONFIRMED_EMPTY', 'STOCK_FOUND', 'OCCUPIED_SINCE'))
);

CREATE INDEX IX_count_lines_status
ON warehouse.count_lines (count_id, line_status_code);

CREATE TABLE warehouse.count_findings
(
    finding_id         INT IDENTITY(1,1) PRIMARY KEY,

    count_line_id      INT NOT NULL,

    scanned_ref        NVARCHAR(100) NOT NULL,   -- exactly what was scanned
    inventory_unit_id  INT NULL,                 -- NULL when the SSCC is unknown

    finding_code       VARCHAR(20) NOT NULL,
        -- RECORD_CORRECTED  pallet's recorded location moved to this bin
        -- UNKNOWN_UNIT      SSCC not in the system; nothing created
        -- NOT_CORRECTED     pallet known but could not be relocated by
        --                   rule (see reason_code) - for supervisor review

    reason_code        NVARCHAR(20) NULL,        -- the rule code, when NOT_CORRECTED
    previous_bin_id    INT NULL,                 -- where the system had it
    movement_id        INT NULL,                 -- ledger row, when corrected

    found_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    found_by           INT NULL,

    CONSTRAINT FK_count_findings_line
        FOREIGN KEY (count_line_id)
        REFERENCES warehouse.count_lines(count_line_id),

    CONSTRAINT FK_count_findings_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT FK_count_findings_previous_bin
        FOREIGN KEY (previous_bin_id)
        REFERENCES locations.bins(bin_id),

    CONSTRAINT FK_count_findings_movement
        FOREIGN KEY (movement_id)
        REFERENCES inventory.inventory_movements(movement_id),

    CONSTRAINT CK_count_findings_code
        CHECK (finding_code IN ('RECORD_CORRECTED', 'UNKNOWN_UNIT', 'NOT_CORRECTED'))
);

CREATE INDEX IX_count_findings_line
ON warehouse.count_findings (count_line_id);
GO
PRINT 'warehouse.count_sessions / count_lines / count_findings created.';
GO

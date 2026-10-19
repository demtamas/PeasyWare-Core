USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   Stock counting
   ------------------------------------------------------------
   count_sessions  one count of one kind over one scope.
                   EMPTY_BIN  scope = a storage type; bins the system
                              believes are empty
                   BIN_COUNT  scope = a storage type, every storage type
                              (a sweep), or a hand-picked list of bins (ad
                              hoc); bins that hold stock - an ad hoc count
                              may also name an empty bin
   count_lines     one row per bin in the count, snapshotted at
                   start so the walk list is stable and "bins not
                   yet counted" is reportable.
   count_scans     BIN_COUNT only: one row per pallet the operator
                   scanned in a bin, with the quantity they counted.
                   Kept after the count as the evidence of what was
                   seen - matched pallets included.
   count_findings  what a count found that a person has to know about:
                   EMPTY_BIN  a pallet in a bin the system believed empty
                   BIN_COUNT  a difference between what was counted and
                              what the system holds

   A count line's own outcome:
     PENDING          not visited yet
     -- EMPTY_BIN
     CONFIRMED_EMPTY  operator scanned the bin and it is empty
     STOCK_FOUND      one or more pallets found (see findings)
     OCCUPIED_SINCE   the system recorded stock there after the
                      snapshot, so "empty" no longer holds - not
                      an exception, just no longer an empty bin
     -- BIN_COUNT
     COUNTING         the bin is open: held by a COUNT reservation while
                      the operator scans it
     MATCHED          counted, and everything agreed with the system
     DIFFERENCES      counted, and findings were recorded (see findings)

   One OPEN session per type + scope, so a count can be left and
   resumed (or shared) rather than duplicated.
   ============================================================ */
CREATE TABLE warehouse.count_sessions
(
    count_id         INT IDENTITY(1,1) PRIMARY KEY,

    count_type_code  VARCHAR(20)  NOT NULL,          -- EMPTY_BIN | BIN_COUNT
    storage_type_id  INT          NULL,              -- the storage type, for scope STORAGE_TYPE

    -- What the count covers:
    --   STORAGE_TYPE  one storage type (storage_type_id set). EMPTY_BIN counts
    --                 and bin counts of a single storage type.
    --   ALL           every storage type - a BIN_COUNT sweep (storage_type_id NULL)
    --   ADHOC         a hand-picked list of bins - BIN_COUNT only (storage_type_id NULL)
    scope_code       VARCHAR(12)  NOT NULL DEFAULT 'STORAGE_TYPE',

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

    CONSTRAINT CK_count_sessions_scope
        CHECK (   (scope_code = 'STORAGE_TYPE' AND storage_type_id IS NOT NULL)
               OR (scope_code IN ('ALL', 'ADHOC') AND storage_type_id IS NULL)),

    CONSTRAINT FK_count_sessions_storage_type
        FOREIGN KEY (storage_type_id)
        REFERENCES locations.storage_types(storage_type_id)
);

-- A storage type, or the whole warehouse (a sweep), is one scope like any other
-- here: SQL Server treats NULLs as equal in a unique index, so there is at most
-- one OPEN sweep. Ad hoc counts are deliberately exempt: each is its own
-- hand-picked list, several can be open at once, and none of them is a sweep.
CREATE UNIQUE INDEX UX_count_sessions_open_scope
ON warehouse.count_sessions (count_type_code, storage_type_id)
WHERE status_code = 'OPEN' AND scope_code <> 'ADHOC';

CREATE TABLE warehouse.count_lines
(
    count_line_id     INT IDENTITY(1,1) PRIMARY KEY,

    count_id          INT NOT NULL,
    bin_id            INT NOT NULL,

    line_status_code  VARCHAR(16) NOT NULL DEFAULT 'PENDING',

    -- BIN_COUNT: when the bin was first opened. The bin is accepted at finish
    -- only if the movement ledger shows no change to it since this moment.
    opened_at         DATETIME2(3) NULL,
    opened_by         INT NULL,

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
        CHECK (line_status_code IN
            ('PENDING', 'CONFIRMED_EMPTY', 'STOCK_FOUND', 'OCCUPIED_SINCE',
             'COUNTING', 'MATCHED', 'DIFFERENCES'))
);

CREATE INDEX IX_count_lines_status
ON warehouse.count_lines (count_id, line_status_code);

/* ============================================================
   count_scans - BIN_COUNT observations, one per pallet per bin.
   Scanning the same SSCC again replaces the earlier quantity (a
   mis-keyed number is corrected by scanning again), so there is
   never more than one row per pallet per line.
   ============================================================ */
CREATE TABLE warehouse.count_scans
(
    count_scan_id       INT IDENTITY(1,1) PRIMARY KEY,

    count_line_id       INT NOT NULL,

    scanned_ref         NVARCHAR(100) NOT NULL,   -- exactly what was scanned
    counted_qty         INT NOT NULL,

    -- 1 when the quantity differed from the system record and the operator
    -- confirmed it when asked. The system's figure is never shown to them.
    quantity_confirmed  BIT NOT NULL DEFAULT 0,

    scanned_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    scanned_by          INT NULL,

    CONSTRAINT FK_count_scans_line
        FOREIGN KEY (count_line_id)
        REFERENCES warehouse.count_lines(count_line_id),

    CONSTRAINT UQ_count_scans_line_ref
        UNIQUE (count_line_id, scanned_ref),

    CONSTRAINT CK_count_scans_qty
        CHECK (counted_qty > 0)
);

CREATE TABLE warehouse.count_findings
(
    finding_id         INT IDENTITY(1,1) PRIMARY KEY,

    count_line_id      INT NOT NULL,

    -- Exactly what was scanned. For MISSING nothing was scanned: this is the
    -- SSCC the system expected (UNIT-<id> for a unit that has no SSCC).
    scanned_ref        NVARCHAR(100) NOT NULL,
    inventory_unit_id  INT NULL,                 -- NULL when the SSCC is unknown

    finding_code       VARCHAR(20) NOT NULL,
        -- EMPTY_BIN counts
        --   RECORD_CORRECTED  pallet's recorded location moved to this bin
        --   UNKNOWN_UNIT      SSCC not in the system; nothing created
        --   NOT_CORRECTED     pallet known but could not be relocated by
        --                     rule (see reason_code) - for supervisor review
        -- BIN_COUNT (nothing here is ever applied by the count itself; each
        -- finding waits for someone with counts.adjust - see resolution_*)
        --   QTY_DIFFERENCE    counted quantity <> system quantity, pallet
        --                     recorded in this bin (counted_qty / system_qty)
        --   MISSING           the system has it in this bin, it was not scanned
        --   MISPLACED         scanned here, but the system has it in another
        --                     bin (previous_bin_id)
        --   UNKNOWN_UNIT, NOT_CORRECTED as above (shipped / reversed pallets
        --   are NOT_CORRECTED with ERRCNT06 / ERRCNT07, never reinstated)

    reason_code        NVARCHAR(20) NULL,        -- the rule code, when NOT_CORRECTED
    previous_bin_id    INT NULL,                 -- where the system had it
    movement_id        INT NULL,                 -- ledger row, when corrected at count time

    counted_qty        INT NULL,                 -- BIN_COUNT: what the operator counted
    system_qty         INT NULL,                 -- BIN_COUNT: what the system held

    found_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    found_by           INT NULL,

    -- BIN_COUNT: what a person with counts.adjust decided. NULL = undecided.
    --   APPLIED   the record was changed to match the count; the ledger row
    --             that did it is resolution_movement_id (so it can be reversed)
    --   DECLINED  the records were left as they are; resolution_note says why
    resolution_code        VARCHAR(10)   NULL,
    resolved_at            DATETIME2(3)  NULL,
    resolved_by            INT           NULL,
    resolution_note        NVARCHAR(500) NULL,
    resolution_movement_id INT           NULL,

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

    CONSTRAINT FK_count_findings_resolution_movement
        FOREIGN KEY (resolution_movement_id)
        REFERENCES inventory.inventory_movements(movement_id),

    CONSTRAINT CK_count_findings_code
        CHECK (finding_code IN
            ('RECORD_CORRECTED', 'UNKNOWN_UNIT', 'NOT_CORRECTED',
             'QTY_DIFFERENCE', 'MISSING', 'MISPLACED')),

    CONSTRAINT CK_count_findings_resolution
        CHECK (resolution_code IS NULL OR resolution_code IN ('APPLIED', 'DECLINED'))
);

CREATE INDEX IX_count_findings_line
ON warehouse.count_findings (count_line_id);
GO
PRINT 'warehouse.count_sessions / count_lines / count_scans / count_findings created.';
GO

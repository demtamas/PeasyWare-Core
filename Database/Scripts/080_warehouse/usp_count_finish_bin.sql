USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_finish_bin
   ------------------------------------------------------------
   The operator has scanned every pallet in the bin. This compares what was
   scanned with what the system holds, records every difference as a finding,
   and releases the bin.

   It changes NO stock record. Every finding waits for a person with
   counts.adjust (usp_count_apply_finding); the count only records what was
   seen. (Contrast the empty-bin count, which corrects locations as it goes.)

   THE SAFEGUARD: before comparing anything, the movement ledger is checked.
   If ANY movement touched this bin (in or out) since the count opened it, the
   bin changed while it was being counted and the comparison would be
   meaningless - so nothing is recorded, the bin goes back to PENDING with its
   scans cleared, and the operator counts it again (WARNCNT11). This does not
   depend on the COUNT hold having been honoured by every writer: a path that
   ignores the lock can only make a bin be counted again, never corrupt a
   count.

   Findings, per scanned SSCC (live unit preferred over a shipped / reversed
   one with the same SSCC):
     not in the system at all              UNKNOWN_UNIT
     shipped / reversed                    NOT_CORRECTED, ERRCNT06 / ERRCNT07
     in the system, no location            NOT_CORRECTED, ERRMOVE03
     recorded in this bin, qty differs     QTY_DIFFERENCE (counted / system)
     recorded in another bin               MISPLACED (previous_bin_id)
     recorded in this bin, qty agrees      no finding
   and per pallet the system holds in this bin that was not scanned:
                                           MISSING

   The line ends MATCHED (no findings) or DIFFERENCES. The scans are kept as
   the evidence of what was seen.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | pallets_scanned INT | differences INT | pending_bins INT
     | recount_required BIT
   Codes: SUCCNT12 bin counted | WARNCNT11 bin changed, count it again
          ERRCNT03 / 04 / 05 / 10 | ERRCNT15 bin not opened | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_finish_bin
(
    @count_id   INT,
    @bin_code   NVARCHAR(100),
    @user_id    INT              = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @success      BIT = 0,
        @commit       BIT = 0,      -- commit even though not successful (the recount reset)
        @recount      BIT = 0,
        @result_code  NVARCHAR(20),
        @count_status VARCHAR(10),
        @count_type   VARCHAR(20),
        @line_id      INT,
        @line_status  VARCHAR(16),
        @bin_id       INT,
        @opened_at    DATETIME2(3),
        @scanned      INT,
        @differences  INT,
        @pending      INT,
        @now          DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @resolved TABLE
    (
        scanned_ref NVARCHAR(100) NOT NULL,
        counted_qty INT           NOT NULL,
        unit_id     INT           NULL,
        unit_state  VARCHAR(3)    NULL,
        system_qty  INT           NULL,
        unit_bin_id INT           NULL
    );

    BEGIN TRY
        BEGIN TRAN;

        -- Bin codes are matched exactly (IdentifierPolicy)
        SET @bin_code = LTRIM(RTRIM(@bin_code)) COLLATE Latin1_General_CS_AS;

        SELECT
            @count_status = status_code,
            @count_type   = count_type_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_status IS NULL OR @count_status <> 'OPEN'
        BEGIN
            SET @result_code = N'ERRCNT03';
            GOTO Finish;
        END

        IF @count_type <> 'BIN_COUNT'
        BEGIN
            SET @result_code = N'ERRCNT10';
            GOTO Finish;
        END

        SELECT
            @line_id     = cl.count_line_id,
            @line_status = cl.line_status_code,
            @bin_id      = cl.bin_id,
            @opened_at   = cl.opened_at
        FROM warehouse.count_lines cl
        JOIN locations.bins b ON b.bin_id = cl.bin_id
        WHERE cl.count_id = @count_id
          AND b.bin_code  = @bin_code COLLATE Latin1_General_CS_AS;

        IF @line_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT04';
            GOTO Finish;
        END

        IF @line_status = 'PENDING'
        BEGIN
            SET @result_code = N'ERRCNT15';
            GOTO Finish;
        END

        IF @line_status <> 'COUNTING'
        BEGIN
            SET @result_code = N'ERRCNT05';
            GOTO Finish;
        END

        -- Lock the bin: nothing is recorded into it while we compare
        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_id = @bin_id;

        ------------------------------------------------------------
        -- The safeguard: did anything touch this bin since it was opened?
        -- (>= : a movement in the very same millisecond is treated as
        -- a change - the safe direction is to count it again.)
        ------------------------------------------------------------
        IF EXISTS (
            SELECT 1
            FROM inventory.inventory_movements m
            WHERE (m.from_bin_id = @bin_id OR m.to_bin_id = @bin_id)
              AND m.moved_at >= @opened_at
        )
        BEGIN
            DELETE FROM warehouse.count_scans
            WHERE count_line_id = @line_id;

            DELETE FROM locations.bin_reservations
            WHERE reservation_type = N'COUNT'
              AND count_line_id    = @line_id;

            UPDATE warehouse.count_lines
            SET line_status_code = 'PENDING',
                opened_at        = NULL,
                opened_by        = NULL
            WHERE count_line_id = @line_id;

            SET @recount     = 1;
            SET @commit      = 1;
            SET @result_code = N'WARNCNT11';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- Resolve every scan against the system's records
        ------------------------------------------------------------
        INSERT INTO @resolved (scanned_ref, counted_qty, unit_id, unit_state, system_qty, unit_bin_id)
        SELECT
            s.scanned_ref,
            s.counted_qty,
            u.inventory_unit_id,
            u.stock_state_code,
            u.quantity,
            ip.bin_id
        FROM warehouse.count_scans s
        OUTER APPLY (
            SELECT TOP (1)
                u2.inventory_unit_id,
                u2.stock_state_code,
                u2.quantity
            FROM inventory.inventory_units u2
            WHERE u2.external_ref = s.scanned_ref
            ORDER BY
                CASE WHEN u2.stock_state_code IN ('REV', 'SHP') THEN 1 ELSE 0 END,
                u2.inventory_unit_id DESC
        ) u
        LEFT JOIN inventory.inventory_placements ip ON ip.inventory_unit_id = u.inventory_unit_id
        WHERE s.count_line_id = @line_id;

        ------------------------------------------------------------
        -- Differences in what was scanned
        ------------------------------------------------------------
        INSERT INTO warehouse.count_findings
            (count_line_id, scanned_ref, inventory_unit_id, finding_code, reason_code,
             previous_bin_id, counted_qty, system_qty, found_at, found_by)
        SELECT
            @line_id,
            r.scanned_ref,
            r.unit_id,
            CASE
                WHEN r.unit_id IS NULL                 THEN 'UNKNOWN_UNIT'
                WHEN r.unit_state IN ('SHP', 'REV')    THEN 'NOT_CORRECTED'
                WHEN r.unit_bin_id IS NULL             THEN 'NOT_CORRECTED'
                WHEN r.unit_bin_id = @bin_id           THEN 'QTY_DIFFERENCE'
                ELSE                                        'MISPLACED'
            END,
            CASE
                WHEN r.unit_state = 'SHP'                            THEN N'ERRCNT06'
                WHEN r.unit_state = 'REV'                            THEN N'ERRCNT07'
                WHEN r.unit_id IS NOT NULL AND r.unit_bin_id IS NULL THEN N'ERRMOVE03'
            END,
            CASE WHEN r.unit_bin_id <> @bin_id THEN r.unit_bin_id END,
            r.counted_qty,
            r.system_qty,
            @now,
            @user_id
        FROM @resolved r
        WHERE r.unit_id IS NULL
           OR r.unit_state IN ('SHP', 'REV')
           OR r.unit_bin_id IS NULL
           OR r.unit_bin_id <> @bin_id
           OR (r.unit_bin_id = @bin_id AND r.counted_qty <> r.system_qty);

        ------------------------------------------------------------
        -- Pallets the system holds in this bin that nobody scanned
        ------------------------------------------------------------
        INSERT INTO warehouse.count_findings
            (count_line_id, scanned_ref, inventory_unit_id, finding_code,
             counted_qty, system_qty, found_at, found_by)
        SELECT
            @line_id,
            COALESCE(u.external_ref, CONCAT(N'UNIT-', u.inventory_unit_id)),
            u.inventory_unit_id,
            'MISSING',
            NULL,
            u.quantity,
            @now,
            @user_id
        FROM inventory.inventory_placements ip
        JOIN inventory.inventory_units u ON u.inventory_unit_id = ip.inventory_unit_id
        WHERE ip.bin_id = @bin_id
          AND NOT EXISTS (
                SELECT 1
                FROM @resolved r
                WHERE r.unit_id = u.inventory_unit_id
          );

        SELECT @differences = COUNT(*)
        FROM warehouse.count_findings
        WHERE count_line_id = @line_id;

        SELECT @scanned = COUNT(*)
        FROM warehouse.count_scans
        WHERE count_line_id = @line_id;

        ------------------------------------------------------------
        -- Release the bin and settle the line
        ------------------------------------------------------------
        DELETE FROM locations.bin_reservations
        WHERE reservation_type = N'COUNT'
          AND count_line_id    = @line_id;

        UPDATE warehouse.count_lines
        SET line_status_code = CASE WHEN @differences = 0 THEN 'MATCHED' ELSE 'DIFFERENCES' END,
            counted_at       = @now,
            counted_by       = @user_id
        WHERE count_line_id = @line_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT12';

Finish:

        IF @success = 1 OR @commit = 1
        BEGIN
            COMMIT;
        END
        ELSE
        BEGIN
            ROLLBACK;
        END

        SELECT @pending = COUNT(*)
        FROM warehouse.count_lines
        WHERE count_id = @count_id
          AND line_status_code = 'PENDING';

        SELECT
            @success                AS success,
            @result_code            AS result_code,
            @count_id               AS count_id,
            ISNULL(@scanned, 0)     AS pallets_scanned,
            ISNULL(@differences, 0) AS differences,
            @pending                AS pending_bins,
            @recount                AS recount_required;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)    AS success,
            N'ERRCNT99'       AS result_code,
            @count_id         AS count_id,
            0                 AS pallets_scanned,
            0                 AS differences,
            CAST(NULL AS INT) AS pending_bins,
            CAST(0 AS BIT)    AS recount_required;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_finish_bin created.';
GO

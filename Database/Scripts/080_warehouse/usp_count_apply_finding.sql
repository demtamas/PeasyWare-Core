USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_apply_finding
   ------------------------------------------------------------
   A person with counts.adjust decides what to do about one finding of a
   bin count: APPLY it (change the stock record to match what was counted)
   or DECLINE it (leave the records as they are, with a note saying why).

   The count itself never changes a stock record - this is the only place a
   bin count does. Gated on counts.adjust (manager + admin; NOT operators),
   enforced here, not just by greying a button.

   Only a bin count that is in REVIEW (closed, waiting for someone) can be
   decided, and each finding only once.

   APPLY, by finding:
     QTY_DIFFERENCE  the unit's quantity is set to what was counted. Ledger:
                     ADJUSTMENT / COUNT, qty_before and qty_after recorded
                     (moved_qty is the size of the change).
     MISSING         the pallet is scrapped as a count loss through
                     inventory.usp_apply_scrap - the same primitive
                     usp_write_off_unit uses. Ledger: ADJUSTMENT / COUNT,
                     from the counted bin to nowhere.
     MISPLACED       the pallet's recorded location is moved to the counted bin
                     through warehouse.usp_apply_relocation, under the same
                     two shared rules a bin-to-bin move obeys. Ledger:
                     ADJUSTMENT / COUNT, old bin to new. (Its quantity is not
                     touched: a misplaced pallet whose quantity also differed
                     keeps both facts on the finding.)
     UNKNOWN_UNIT / NOT_CORRECTED
                     nothing to apply (ERRCNT23). They can be declined with a
                     note, which acknowledges them.

   Applying RE-CHECKS the world, because time has passed since the count: the
   unit must still sit where, and hold what, the count recorded (ERRCNT26);
   a quantity change needs stock whose status allows adjusting it (can_adjust,
   ERRCNT27); neither a quantity change nor a write-off may touch a pallet that
   is allocated to an order (ERRCNT28) or is mid-flow rather than PTW / RCD
   (ERRCNT29); nothing applies to a unit with an open task (ERRMOVE10). A
   refusal changes nothing and leaves the finding undecided.

   REVERSIBLE BY DESIGN: every apply writes exactly one ledger row that records
   what it changed (the bin it left, the quantity it replaced), and the finding
   records that row (resolution_movement_id). That is what a reversal needs.

   @result_code is also returned as an OUTPUT parameter so callers that want
   only the code (the SQL tests) need not read the result set.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | finding_id INT
     | finding_code VARCHAR(20) | count_id INT | movement_id INT
     | unresolved_findings INT      (undecided findings left in this count)
   Codes: SUCCNT20 applied | SUCCNT21 declined | ERRPERM01 not permitted
          ERRCNT10 not a bin count | ERRCNT20 not found | ERRCNT21 count not in REVIEW
          ERRCNT22 already decided | ERRCNT23 nothing to apply | ERRCNT24 note needed
          ERRCNT25 bad action | ERRCNT26 record changed since the count
          ERRCNT27 status blocks adjusting | ERRCNT28 allocated | ERRCNT29 mid-flow
          ERRCNT12 bin being counted | ERRMOVE* the move rules (MISPLACED)
          ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_apply_finding
(
    @finding_id  INT,
    @action      VARCHAR(10),
    @note        NVARCHAR(500)    = NULL,
    @user_id     INT              = NULL,
    @session_id  UNIQUEIDENTIFIER = NULL,
    @result_code NVARCHAR(20)     = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @success      BIT = 0,
        @count_id     INT,
        @count_type   VARCHAR(20),
        @count_status VARCHAR(10),
        @line_id      INT,
        @count_bin_id INT,
        @finding_code VARCHAR(20),
        @unit_id      INT,
        @counted_qty  INT,
        @system_qty   INT,
        @prev_bin_id  INT,
        @resolution   VARCHAR(10),
        @unit_state   VARCHAR(3),
        @unit_status  VARCHAR(2),
        @unit_qty     INT,
        @unit_sku_id  INT,
        @unit_bin_id  INT,
        @block_code   NVARCHAR(20),
        @movement_id  INT,
        @unresolved   INT,
        @now          DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SET @result_code = NULL;

        IF auth.fn_has_permission(@user_id, 'counts.adjust') = 0
        BEGIN
            SET @result_code = N'ERRPERM01';
            GOTO Finish;
        END

        SET @action = UPPER(LTRIM(RTRIM(ISNULL(@action, ''))));
        SET @note   = NULLIF(LTRIM(RTRIM(@note)), N'');

        IF @action NOT IN ('APPLY', 'DECLINE')
        BEGIN
            SET @result_code = N'ERRCNT25';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- The finding, its bin and its count
        ------------------------------------------------------------
        SELECT
            @line_id      = cl.count_line_id,
            @count_bin_id = cl.bin_id,
            @count_id     = cl.count_id,
            @finding_code = f.finding_code,
            @unit_id      = f.inventory_unit_id,
            @counted_qty  = f.counted_qty,
            @system_qty   = f.system_qty,
            @prev_bin_id  = f.previous_bin_id
        FROM warehouse.count_findings f
        JOIN warehouse.count_lines cl ON cl.count_line_id = f.count_line_id
        WHERE f.finding_id = @finding_id;

        IF @line_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT20';
            GOTO Finish;
        END

        SELECT
            @count_type   = count_type_code,
            @count_status = status_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_type <> 'BIN_COUNT'
        BEGIN
            SET @result_code = N'ERRCNT10';
            GOTO Finish;
        END

        IF @count_status <> 'REVIEW'
        BEGIN
            SET @result_code = N'ERRCNT21';
            GOTO Finish;
        END

        SELECT @resolution = resolution_code
        FROM warehouse.count_findings WITH (UPDLOCK, HOLDLOCK)
        WHERE finding_id = @finding_id;

        IF @resolution IS NOT NULL
        BEGIN
            SET @result_code = N'ERRCNT22';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- DECLINE: leave the records alone, say why
        ------------------------------------------------------------
        IF @action = 'DECLINE'
        BEGIN
            IF @note IS NULL
            BEGIN
                SET @result_code = N'ERRCNT24';
                GOTO Finish;
            END

            UPDATE warehouse.count_findings
            SET resolution_code = 'DECLINED',
                resolved_at     = @now,
                resolved_by     = @user_id,
                resolution_note = @note
            WHERE finding_id = @finding_id;

            SET @success     = 1;
            SET @result_code = N'SUCCNT21';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- APPLY
        ------------------------------------------------------------
        IF @finding_code NOT IN ('QTY_DIFFERENCE', 'MISSING', 'MISPLACED')
        BEGIN
            SET @result_code = N'ERRCNT23';
            GOTO Finish;
        END

        -- The unit, locked, as it is NOW
        SELECT
            @unit_state  = stock_state_code,
            @unit_status = stock_status_code,
            @unit_qty    = quantity,
            @unit_sku_id = sku_id
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @unit_id;

        IF @unit_state IS NULL
        BEGIN
            SET @result_code = N'ERRCNT26';
            GOTO Finish;
        END

        SELECT @unit_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @unit_id;

        -- Another count holding the bin right now
        IF locations.fn_bin_is_being_counted(@count_bin_id) = 1
        BEGIN
            SET @result_code = N'ERRCNT12';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- QTY_DIFFERENCE: set the quantity to what was counted
        ------------------------------------------------------------
        IF @finding_code = 'QTY_DIFFERENCE'
        BEGIN
            IF @unit_bin_id IS NULL OR @unit_bin_id <> @count_bin_id OR @unit_qty <> @system_qty
            BEGIN
                SET @result_code = N'ERRCNT26';
                GOTO Finish;
            END

            IF @unit_state NOT IN ('PTW', 'RCD')
            BEGIN
                SET @result_code = N'ERRCNT29';
                GOTO Finish;
            END

            IF EXISTS (
                SELECT 1
                FROM inventory.stock_operation_rules
                WHERE state_code  = @unit_state
                  AND status_code = @unit_status
                  AND can_adjust  = 0
            )
            BEGIN
                SET @result_code = N'ERRCNT27';
                GOTO Finish;
            END

            IF EXISTS (
                SELECT 1
                FROM warehouse.warehouse_tasks
                WHERE inventory_unit_id = @unit_id
                  AND task_state_code IN ('OPN', 'CLM')
            )
            BEGIN
                SET @result_code = N'ERRMOVE10';
                GOTO Finish;
            END

            IF EXISTS (
                SELECT 1
                FROM outbound.outbound_allocations
                WHERE inventory_unit_id = @unit_id
                  AND allocation_status IN ('PENDING', 'CONFIRMED', 'PICKED')
            )
            BEGIN
                SET @result_code = N'ERRCNT28';
                GOTO Finish;
            END

            UPDATE inventory.inventory_units
            SET quantity   = @counted_qty,
                updated_at = @now,
                updated_by = @user_id
            WHERE inventory_unit_id = @unit_id;

            INSERT INTO inventory.inventory_movements
                (inventory_unit_id, sku_id, moved_qty, qty_before, qty_after,
                 from_bin_id, to_bin_id,
                 from_state_code, to_state_code,
                 from_status_code, to_status_code,
                 movement_type, reference_type, reference_id,
                 moved_at, moved_by_user_id, session_id)
            VALUES
                (@unit_id, @unit_sku_id, ABS(@counted_qty - @unit_qty), @unit_qty, @counted_qty,
                 @count_bin_id, @count_bin_id,
                 @unit_state, @unit_state,
                 @unit_status, @unit_status,
                 N'ADJUSTMENT', N'COUNT', @line_id,
                 @now, @user_id, @session_id);

            SET @movement_id = SCOPE_IDENTITY();
        END

        ------------------------------------------------------------
        -- MISSING: scrap it as a count loss
        ------------------------------------------------------------
        ELSE IF @finding_code = 'MISSING'
        BEGIN
            IF @unit_bin_id IS NULL OR @unit_bin_id <> @count_bin_id
            BEGIN
                SET @result_code = N'ERRCNT26';
                GOTO Finish;
            END

            IF @unit_state NOT IN ('PTW', 'RCD')
            BEGIN
                SET @result_code = N'ERRCNT29';
                GOTO Finish;
            END

            IF EXISTS (
                SELECT 1
                FROM warehouse.warehouse_tasks
                WHERE inventory_unit_id = @unit_id
                  AND task_state_code IN ('OPN', 'CLM')
            )
            BEGIN
                SET @result_code = N'ERRMOVE10';
                GOTO Finish;
            END

            IF EXISTS (
                SELECT 1
                FROM outbound.outbound_allocations
                WHERE inventory_unit_id = @unit_id
                  AND allocation_status IN ('PENDING', 'CONFIRMED', 'PICKED')
            )
            BEGIN
                SET @result_code = N'ERRCNT28';
                GOTO Finish;
            END

            EXEC inventory.usp_apply_scrap
                @inventory_unit_id = @unit_id,
                @reference_type    = N'COUNT',
                @reference_id      = @line_id,
                @user_id           = @user_id,
                @session_id        = @session_id,
                @movement_id       = @movement_id OUTPUT;
        END

        ------------------------------------------------------------
        -- MISPLACED: move the record to the counted bin, by the move rules
        ------------------------------------------------------------
        ELSE
        BEGIN
            IF @unit_bin_id IS NULL OR @unit_bin_id <> @prev_bin_id
            BEGIN
                SET @result_code = N'ERRCNT26';
                GOTO Finish;
            END

            SET @block_code = warehouse.fn_unit_move_block_code(@unit_id, NULL);

            IF @block_code IS NULL
            BEGIN
                -- Lock the destination first so the capacity check and the move are one step
                SELECT @count_bin_id = bin_id
                FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
                WHERE bin_id = @count_bin_id;

                SET @block_code = warehouse.fn_bin_receive_block_code(@count_bin_id);
            END

            IF @block_code IS NOT NULL
            BEGIN
                SET @result_code = @block_code;
                GOTO Finish;
            END

            EXEC warehouse.usp_apply_relocation
                @inventory_unit_id  = @unit_id,
                @destination_bin_id = @count_bin_id,
                @movement_type      = N'ADJUSTMENT',
                @reference_type     = N'COUNT',
                @reference_id       = @line_id,
                @user_id            = @user_id,
                @session_id         = @session_id,
                @movement_id        = @movement_id OUTPUT;
        END

        ------------------------------------------------------------
        -- Record the decision, and the ledger row that carried it out
        ------------------------------------------------------------
        UPDATE warehouse.count_findings
        SET resolution_code        = 'APPLIED',
            resolved_at            = @now,
            resolved_by            = @user_id,
            resolution_note        = @note,
            resolution_movement_id = @movement_id
        WHERE finding_id = @finding_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT20';

Finish:

        IF @success = 1
        BEGIN
            COMMIT;
        END
        ELSE
        BEGIN
            ROLLBACK;
        END

        SELECT @unresolved = COUNT(*)
        FROM warehouse.count_findings f
        JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
        WHERE l.count_id = @count_id
          AND f.finding_code <> 'RECORD_CORRECTED'
          AND f.resolution_code IS NULL;

        SELECT
            @success                AS success,
            @result_code            AS result_code,
            @finding_id             AS finding_id,
            @finding_code           AS finding_code,
            @count_id               AS count_id,
            @movement_id            AS movement_id,
            ISNULL(@unresolved, 0)  AS unresolved_findings;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SET @result_code = N'ERRCNT99';

        SELECT
            CAST(0 AS BIT)    AS success,
            N'ERRCNT99'       AS result_code,
            @finding_id       AS finding_id,
            CAST(NULL AS VARCHAR(20)) AS finding_code,
            @count_id         AS count_id,
            CAST(NULL AS INT) AS movement_id,
            CAST(0 AS INT)    AS unresolved_findings;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_apply_finding created.';
GO

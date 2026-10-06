USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_bin_to_bin_move_confirm
   ------------------------------------------------------------
   Confirms a MOVE task by scanning the destination bin.

   Everything that was true at create time is re-checked here,
   under lock, because the task can sit open for minutes:
     - destination bin: active, unlocked, and under capacity
       (this task's own reservation is released first so it does
        not count against itself - rolled back with everything
        else on any failure)
     - unit: still free to be moved (e.g. not picked since), and
       still in the bin the task was created from (a count
       correction or another flow may have relocated it - writing
       the stale source bin into the ledger would corrupt history)

   The relocation itself (placement, RCD->PTW out of staging, ledger
   row) is warehouse.usp_apply_relocation, shared with the count
   correction.

   Expiry is deliberately NOT enforced here: an operator who has
   already carried the pallet across the warehouse should not be
   rejected on a clock. The capacity re-check is the real guard.
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_bin_to_bin_move_confirm
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @user_id          INT              = NULL,
    @session_id       UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code)) COLLATE Latin1_General_CS_AS;

        DECLARE
            @inventory_unit_id  INT,
            @locked_unit_id     INT,
            @source_bin_id      INT,
            @destination_bin_id INT,
            @dest_bin_code      NVARCHAR(100),
            @placement_bin_id   INT,
            @block_code         NVARCHAR(20),
            @movement_id        INT,
            @now                DATETIME2(3) = SYSUTCDATETIME();

        ------------------------------------------------------------
        -- 1. Load + lock the task
        ------------------------------------------------------------
        SELECT
            @inventory_unit_id  = inventory_unit_id,
            @source_bin_id      = source_bin_id,
            @destination_bin_id = destination_bin_id
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id        = @task_id
          AND task_type_code = 'MOVE'
          AND task_state_code IN ('OPN', 'CLM');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE05' AS result_code;
            ROLLBACK; RETURN;
        END

        ------------------------------------------------------------
        -- 2. Destination: must match the scan (or, for a task created
        --    with no destination, the scanned bin becomes it)
        ------------------------------------------------------------
        IF @destination_bin_id IS NOT NULL
        BEGIN
            SELECT @dest_bin_code = bin_code
            FROM locations.bins
            WHERE bin_id = @destination_bin_id;

            IF LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE06' AS result_code;
                ROLLBACK; RETURN;
            END
        END
        ELSE
        BEGIN
            SELECT
                @destination_bin_id = bin_id,
                @dest_bin_code      = bin_code
            FROM locations.bins
            WHERE bin_code = @scanned_bin_code COLLATE Latin1_General_CS_AS;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code;
                ROLLBACK; RETURN;
            END
        END

        IF @destination_bin_id = @source_bin_id
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE11' AS result_code;
            ROLLBACK; RETURN;
        END

        ------------------------------------------------------------
        -- 3. Lock the destination bin, release this task's own hold
        --    on it, then check it can take the unit
        ------------------------------------------------------------
        SELECT @destination_bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_id = @destination_bin_id;

        DELETE FROM locations.bin_reservations
        WHERE task_id = @task_id;

        SET @block_code = warehouse.fn_bin_receive_block_code(@destination_bin_id);

        IF @block_code IS NOT NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, @block_code AS result_code;
            ROLLBACK; RETURN;
        END

        ------------------------------------------------------------
        -- 4. Lock the unit; still where the task says, still movable?
        ------------------------------------------------------------
        SELECT @locked_unit_id = inventory_unit_id
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

        SELECT @placement_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NOT NULL
           AND @placement_bin_id IS NOT NULL
           AND @placement_bin_id <> @source_bin_id
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE12' AS result_code;
            ROLLBACK; RETURN;
        END

        SET @block_code = warehouse.fn_unit_move_block_code(@inventory_unit_id, @task_id);

        IF @block_code IS NOT NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, @block_code AS result_code;
            ROLLBACK; RETURN;
        END

        ------------------------------------------------------------
        -- 5. Apply (shared with the count correction)
        ------------------------------------------------------------
        EXEC warehouse.usp_apply_relocation
            @inventory_unit_id  = @inventory_unit_id,
            @destination_bin_id = @destination_bin_id,
            @movement_type      = N'MOVE',
            @reference_type     = N'TASK',
            @reference_id       = @task_id,
            @user_id            = @user_id,
            @session_id         = @session_id,
            @movement_id        = @movement_id OUTPUT;

        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRMOVE99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_confirm created.';
GO

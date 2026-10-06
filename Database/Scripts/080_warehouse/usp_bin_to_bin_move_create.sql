USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_bin_to_bin_move_create
   ------------------------------------------------------------
   Creates a MOVE task for a unit (found by SSCC / external_ref).

   Rules live in two shared functions so every relocation path
   applies the same ones:
     warehouse.fn_unit_move_block_code   - is the unit free to move
     warehouse.fn_bin_receive_block_code - can the bin take it

   Behaviour:
     - A live open MOVE task for the unit is resumed (returned as-is).
     - An open MOVE task past its TTL is expired (EXP) and replaced -
       nothing else sweeps tasks, and a stale one would otherwise
       pin the unit and its old destination indefinitely.
     - The destination bin row is locked while it is checked, and a
       MOVE reservation (tied to the task by task_id) holds the slot
       until confirm / cancel / TTL. This also stops
       usp_suggest_putaway_bin offering a bin a move is heading for.
     - No destination supplied: the system suggests one. If it finds
       none the task is still created with no destination (operator
       decides at confirm; confirm re-checks the rules then).
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_bin_to_bin_move_create
(
    @external_ref         NVARCHAR(100),
    @destination_bin_code NVARCHAR(100)    = NULL,
    @user_id              INT              = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @inventory_unit_id  INT,
        @source_bin_id      INT,
        @source_bin_code    NVARCHAR(100),
        @destination_bin_id INT,
        @existing_dest_code NVARCHAR(100),
        @task_id            INT,
        @task_dest_bin_id   INT,
        @task_expires_at    DATETIME2(3),
        @block_code         NVARCHAR(20),
        @ttl_seconds        INT,
        @expires_at         DATETIME2(3),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SET @external_ref = LTRIM(RTRIM(@external_ref));
        IF @destination_bin_code IS NOT NULL
            SET @destination_bin_code = LTRIM(RTRIM(@destination_bin_code)) COLLATE Latin1_General_CS_AS;

        ------------------------------------------------------------
        -- 1. Resolve the unit (locked, so two creates for the same
        --    SSCC serialise rather than race)
        ------------------------------------------------------------
        SELECT @inventory_unit_id = inventory_unit_id
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE external_ref = @external_ref
          AND stock_state_code NOT IN ('REV', 'SHP');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE01' AS result_code,
                   NULL AS task_id, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        ------------------------------------------------------------
        -- 2. Existing open MOVE task: resume it, or expire it if stale
        ------------------------------------------------------------
        SELECT TOP (1)
            @task_id          = task_id,
            @task_dest_bin_id = destination_bin_id,
            @task_expires_at  = expires_at
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_type_code    = 'MOVE'
          AND task_state_code  IN ('OPN', 'CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
           AND @task_expires_at IS NOT NULL
           AND @task_expires_at <= @now
        BEGIN
            UPDATE warehouse.warehouse_tasks
            SET task_state_code = 'EXP',
                updated_at      = @now,
                updated_by      = @user_id
            WHERE task_id = @task_id;

            DELETE FROM locations.bin_reservations
            WHERE task_id = @task_id;

            SET @task_id          = NULL;
            SET @task_dest_bin_id = NULL;
        END

        ------------------------------------------------------------
        -- 3. Is the unit free to be moved?
        ------------------------------------------------------------
        SET @block_code = warehouse.fn_unit_move_block_code(@inventory_unit_id, @task_id);

        IF @block_code IS NOT NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, @block_code AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        SELECT
            @source_bin_id   = ip.bin_id,
            @source_bin_code = b.bin_code
        FROM inventory.inventory_placements ip
        JOIN locations.bins b ON b.bin_id = ip.bin_id
        WHERE ip.inventory_unit_id = @inventory_unit_id;

        ------------------------------------------------------------
        -- 4. Resume the live task if there is one
        ------------------------------------------------------------
        IF @task_id IS NOT NULL
        BEGIN
            SELECT @existing_dest_code = bin_code
            FROM locations.bins
            WHERE bin_id = @task_dest_bin_id;

            COMMIT;

            SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
                   @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
                   @source_bin_code AS source_bin_code, @existing_dest_code AS destination_bin_code;
            RETURN;
        END

        ------------------------------------------------------------
        -- 5. Destination: supplied, or suggested
        ------------------------------------------------------------
        IF @destination_bin_code IS NOT NULL
        BEGIN
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @destination_bin_code COLLATE Latin1_General_CS_AS;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END
        ELSE
        BEGIN
            EXEC locations.usp_suggest_putaway_bin
                @inventory_unit_id = @inventory_unit_id,
                @suggested_bin_id  = @destination_bin_id OUTPUT;
        END

        ------------------------------------------------------------
        -- 6. Can the destination take it? (bin row locked first so
        --    the check and the reservation below are one atomic step)
        ------------------------------------------------------------
        IF @destination_bin_id IS NOT NULL
        BEGIN
            IF @destination_bin_id = @source_bin_id
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE11' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @source_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END

            SELECT @destination_bin_code = bin_code
            FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
            WHERE bin_id = @destination_bin_id;

            SET @block_code = warehouse.fn_bin_receive_block_code(@destination_bin_id);

            IF @block_code IS NOT NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, @block_code AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        ------------------------------------------------------------
        -- 7. Create the task, and hold the destination bin for it
        ------------------------------------------------------------
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
             task_state_code, expires_at,
             claimed_by_user_id, claimed_at,
             created_by)
        VALUES
            ('MOVE', @inventory_unit_id, @source_bin_id, @destination_bin_id,
             'OPN', @expires_at,
             @user_id, @now,
             @user_id);

        SET @task_id = SCOPE_IDENTITY();

        IF @destination_bin_id IS NOT NULL
        BEGIN
            INSERT INTO locations.bin_reservations
                (bin_id, reservation_type, reserved_by, expires_at, task_id)
            VALUES
                (@destination_bin_id, N'MOVE', ISNULL(@user_id, 0), @expires_at, @task_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
               @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
               @source_bin_code AS source_bin_code,
               @destination_bin_code AS destination_bin_code;

    END TRY
    BEGIN CATCH
        -- A unique-index violation here is the one-open-task-per-unit index
        -- (UX_tasks_open_unit) catching a concurrent create that slipped
        -- past the checks above - report it as what it is, not as a crash.
        DECLARE @err_no INT = ERROR_NUMBER();

        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT CAST(0 AS BIT) AS success,
               CASE WHEN @err_no IN (2601, 2627) THEN N'ERRMOVE10' ELSE N'ERRMOVE99' END AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_create created.';
GO

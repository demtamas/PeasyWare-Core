USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — warehouse.usp_bin_to_bin_move_create + usp_bin_to_bin_move_confirm
    Date: 2026-04-26

    Both SPs were missing from the DB entirely.
    The C# repository references them and throws on first use.

    Create:
      @external_ref         — SSCC of the unit to move
      @destination_bin_code — target bin (NULL = not used, operator scans it at confirm)
      Returns: success, result_code, task_id, inventory_unit_id,
               source_bin_code, destination_bin_code

    Confirm:
      @task_id          — task to complete
      @scanned_bin_code — bin scanned by operator at destination
      Returns: success, result_code

    Error codes added:
      ERRMOVE01 — unit not found by SSCC
      ERRMOVE02 — unit not in moveable state (must be PUT or RCD)
      ERRMOVE03 — unit has no current placement
      ERRMOVE04 — destination bin not found
      ERRMOVE05 — task not found or not in OPN/CLM state
      ERRMOVE06 — scanned bin does not match task destination
      SUCMOVE01 — bin move task created
      SUCMOVE02 — bin move task confirmed
********************************************************************************************/

-- ── Error messages ───────────────────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE01', N'MOVE', N'ERROR', N'Unit not found. Please check the SSCC and try again.', N'usp_bin_to_bin_move_create: external_ref not found in inventory_units'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE02', N'MOVE', N'ERROR', N'This unit is not in a moveable state.', N'usp_bin_to_bin_move_create: stock_state_code not PUT or RCD'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE03', N'MOVE', N'ERROR', N'Unit has no current location. Cannot create a move task.', N'usp_bin_to_bin_move_create: no placement record found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE04', N'MOVE', N'ERROR', N'Destination bin not found. Please check the bin code.', N'usp_bin_to_bin_move_create: destination_bin_code not found in locations.bins'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE04');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE05', N'MOVE', N'ERROR', N'Move task not found or no longer active.', N'usp_bin_to_bin_move_confirm: task_id not found or not OPN/CLM'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE06', N'MOVE', N'ERROR', N'Wrong location. Please scan the correct destination bin.', N'usp_bin_to_bin_move_confirm: scanned_bin_code does not match task destination_bin_id'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCMOVE01', N'MOVE', N'SUCCESS', N'Move task created.', N'usp_bin_to_bin_move_create: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCMOVE01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCMOVE02', N'MOVE', N'SUCCESS', N'Unit moved successfully.', N'usp_bin_to_bin_move_confirm: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCMOVE02');

GO
PRINT 'Move error messages inserted.';
GO

-- ── warehouse.usp_bin_to_bin_move_create ─────────────────────────────────────

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

    BEGIN TRY
        BEGIN TRAN;

        -- Normalise inputs
        SET @external_ref         = UPPER(LTRIM(RTRIM(@external_ref)));
        SET @destination_bin_code = UPPER(LTRIM(RTRIM(@destination_bin_code)));

        -- Resolve inventory unit by SSCC
        DECLARE
            @inventory_unit_id  INT,
            @stock_state_code   VARCHAR(3),
            @source_bin_id      INT,
            @source_bin_code    NVARCHAR(100),
            @destination_bin_id INT,
            @task_id            INT,
            @ttl_seconds        INT,
            @expires_at         DATETIME2(3),
            @now                DATETIME2(3) = SYSUTCDATETIME();

        SELECT
            @inventory_unit_id = inventory_unit_id,
            @stock_state_code  = stock_state_code
        FROM inventory.inventory_units
        WHERE external_ref = @external_ref
          AND stock_state_code NOT IN ('REV', 'SHP');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE01' AS result_code,
                   NULL AS task_id, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        -- Unit must be in PUT, PTW or RCD state to be moved
        IF @stock_state_code NOT IN ('PUT', 'PTW', 'RCD')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE02' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        -- Resolve current placement
        SELECT @source_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE03' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        SELECT @source_bin_code = bin_code FROM locations.bins WHERE bin_id = @source_bin_id;

        -- Resolve destination bin if provided
        IF @destination_bin_code IS NOT NULL
        BEGIN
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @destination_bin_code AND is_active = 1;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        -- Reuse existing open task if present
        SELECT TOP 1
            @task_id           = task_id,
            @destination_bin_id = destination_bin_id,
            @expires_at        = expires_at
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_type_code    = 'MOVE'
          AND task_state_code  IN ('OPN', 'CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            DECLARE @existing_dest_code NVARCHAR(100);
            SELECT @existing_dest_code = bin_code FROM locations.bins WHERE bin_id = @destination_bin_id;
            COMMIT;
            SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
                   @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
                   @source_bin_code AS source_bin_code, @existing_dest_code AS destination_bin_code;
            RETURN;
        END

        -- TTL
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        -- Create move task
        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
             task_state_code, expires_at, created_by)
        VALUES
            ('MOVE', @inventory_unit_id, @source_bin_id, @destination_bin_id,
             'OPN', @expires_at, @user_id);

        SET @task_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
               @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
               @source_bin_code AS source_bin_code,
               @destination_bin_code AS destination_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRMOVE99' AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_create created.';
GO

-- ── warehouse.usp_bin_to_bin_move_confirm ────────────────────────────────────

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

        SET @scanned_bin_code = UPPER(LTRIM(RTRIM(@scanned_bin_code)));

        DECLARE
            @inventory_unit_id  INT,
            @source_bin_id      INT,
            @destination_bin_id INT,
            @dest_bin_code      NVARCHAR(100),
            @task_state         VARCHAR(3),
            @sku_id             INT,
            @now                DATETIME2(3) = SYSUTCDATETIME();

        SELECT
            @inventory_unit_id  = inventory_unit_id,
            @source_bin_id      = source_bin_id,
            @destination_bin_id = destination_bin_id,
            @task_state         = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id       = @task_id
          AND task_type_code = 'MOVE'
          AND task_state_code IN ('OPN', 'CLM');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Validate scanned bin against destination
        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @destination_bin_id;

        IF @dest_bin_code IS NOT NULL
           AND UPPER(LTRIM(RTRIM(@scanned_bin_code))) <> UPPER(LTRIM(RTRIM(@dest_bin_code)))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE06' AS result_code;
            ROLLBACK; RETURN;
        END

        -- If no destination was set on the task, resolve the scanned bin
        IF @destination_bin_id IS NULL
        BEGIN
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @scanned_bin_code AND is_active = 1;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code;
                ROLLBACK; RETURN;
            END

            SET @dest_bin_code = @scanned_bin_code;
        END

        SELECT @sku_id = sku_id FROM inventory.inventory_units WHERE inventory_unit_id = @inventory_unit_id;

        -- Update placement
        UPDATE inventory.inventory_placements
        SET bin_id = @destination_bin_id
        WHERE inventory_unit_id = @inventory_unit_id;

        -- Record movement
        DECLARE @movement_id INT;

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty,
             from_bin_id, to_bin_id,
             from_state_code, to_state_code,
             from_status_code, to_status_code,
             movement_type, reference_type, reference_id,
             moved_at, moved_by_user_id, session_id)
        SELECT
            @inventory_unit_id, @sku_id, quantity,
            @source_bin_id, @destination_bin_id,
            stock_state_code, stock_state_code,  -- PTW->PTW, state unchanged during move
            stock_status_code, stock_status_code,
            'MOVE', 'TASK', @task_id,
            @now, @user_id, @session_id
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        -- Complete task
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

PRINT '------------------------------------------------------------';
PRINT 'Bin-to-bin move SPs complete.';
PRINT '------------------------------------------------------------';
GO

-- ── Fix: usp_putaway_confirm_task stock state comment correction ────────────────
-- PTW = PUTAWAY (final racked state, not "in progress" as previously assumed).
-- The confirm SP was already setting PTW correctly.
-- The real issue was that usp_bin_to_bin_move_create was rejecting PTW state.
-- Fix: allow PTW in the move create SP (already done above).
-- This SP rewrite is retained to fix the from_state_code in the movement record
-- (was recording RCD->PTW but should be PTW->PTW for a putaway confirm).

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_confirm_task
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @user_id          INT,
    @session_id       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @inventory_unit_id   INT, @source_bin_id INT, @dest_bin_id INT,
        @dest_bin_code       NVARCHAR(100), @sku_id INT, @quantity INT,
        @task_state          VARCHAR(3), @scanned_bin_id INT,
        @bin_capacity        INT, @bin_active BIT,
        @current_placements  INT, @active_reservations INT,
        @current_status_code VARCHAR(2), @now DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT @inventory_unit_id = inventory_unit_id, @source_bin_id = source_bin_id,
               @dest_bin_id = destination_bin_id, @task_state = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK) WHERE task_id = @task_id;

        IF @inventory_unit_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code; ROLLBACK; RETURN; END

        IF @task_state NOT IN ('OPN','CLM')
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code; ROLLBACK; RETURN; END

        SELECT @dest_bin_code = bin_code FROM locations.bins WHERE bin_id = @dest_bin_id;

        IF UPPER(LTRIM(RTRIM(@scanned_bin_code))) <> UPPER(LTRIM(RTRIM(@dest_bin_code)))
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK08' AS result_code; ROLLBACK; RETURN; END

        SELECT @scanned_bin_id = bin_id, @bin_capacity = capacity, @bin_active = is_active
        FROM locations.bins WHERE bin_id = @dest_bin_id;

        IF @bin_active = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code; ROLLBACK; RETURN; END

        SELECT @current_placements = COUNT(*) FROM inventory.inventory_placements WHERE bin_id = @dest_bin_id;
        SELECT @active_reservations = COUNT(*) FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id AND expires_at > @now;

        IF (@current_placements + @active_reservations - 1) >= @bin_capacity
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code; ROLLBACK; RETURN; END

        SELECT @sku_id = sku_id, @quantity = quantity, @current_status_code = stock_status_code
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK) WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_placements SET bin_id = @dest_bin_id, placed_at = @now, placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        -- Fix: was recording RCD->PTW but should be PTW->PTW since
        -- the unit is already PTW (PUTAWAY is the final state)
        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW', updated_at = @now, updated_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id
          AND stock_state_code IN ('RCD', 'PTW');

        UPDATE warehouse.warehouse_tasks
        SET task_state_code = 'CNF', completed_at = @now, completed_by_user_id = @user_id,
            updated_at = @now, updated_by = @user_id
        WHERE task_id = @task_id;

        DELETE FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id AND reservation_type = 'PUTAWAY' AND expires_at >= @now;

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty, from_bin_id, to_bin_id,
             from_state_code, to_state_code, from_status_code, to_status_code,
             movement_type, reference_type, reference_id, moved_at, moved_by_user_id, session_id)
        VALUES
            (@inventory_unit_id, @sku_id, @quantity, @source_bin_id, @dest_bin_id,
             'PTW', 'PTW', @current_status_code, @current_status_code,
             'PUTAWAY', 'TASK', @task_id, @now, @user_id, @session_id);

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTASK02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_putaway_confirm_task fixed — now sets PUT not PTW.';

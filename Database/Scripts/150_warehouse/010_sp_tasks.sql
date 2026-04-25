CREATE OR ALTER PROCEDURE warehouse.usp_create_putaway_task
(
    @inventory_unit_id INT, @user_id INT = NULL, @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @sku_id INT, @stock_state VARCHAR(3), @current_bin_id INT,
            @dest_bin_id INT, @ttl_seconds INT, @expires_at DATETIME2(3), @task_id INT;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @sku_id = sku_id, @stock_state = stock_state_code
        FROM inventory.inventory_units WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code, NULL AS task_id, NULL AS destination_bin_id; ROLLBACK; RETURN; END

        IF @stock_state <> 'RCD'
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK02' AS result_code, NULL AS task_id, NULL AS destination_bin_id; ROLLBACK; RETURN; END

        SELECT @current_bin_id = bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @inventory_unit_id;

        IF @current_bin_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code, NULL AS task_id, NULL AS destination_bin_id; ROLLBACK; RETURN; END

        IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @inventory_unit_id AND task_state_code IN ('OPN','CLM'))
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK05' AS result_code, NULL AS task_id, NULL AS destination_bin_id; ROLLBACK; RETURN; END

        EXEC locations.usp_suggest_putaway_bin @inventory_unit_id = @inventory_unit_id, @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK04' AS result_code, NULL AS task_id, NULL AS destination_bin_id; ROLLBACK; RETURN; END

        SELECT @ttl_seconds = TRY_CONVERT(INT, setting_value) FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0 SET @ttl_seconds = 300;
        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
        VALUES ('PUTAWAY', @inventory_unit_id, @current_bin_id, @dest_bin_id, 'OPN', @expires_at, @user_id);

        SET @task_id = SCOPE_IDENTITY();
        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
               @task_id AS task_id, @dest_bin_id AS destination_bin_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code, NULL AS task_id, NULL AS destination_bin_id;
    END CATCH
END;
GO

GO

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_create_task_for_unit
(
    @inventory_unit_id INT,
    @user_id           INT,
    @session_id        UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @task_id            INT,
        @dest_bin_id        INT,
        @dest_bin_code      NVARCHAR(100),
        @source_bin_id      INT,
        @ttl_seconds        INT,
        @expires_at         DATETIME2(3),
        @sku_id             INT,
        @state_code         VARCHAR(3),
        @stock_status_code  VARCHAR(2),
        @source_bin_code    NVARCHAR(100),
        @zone_code          NVARCHAR(50);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @sku_id = sku_id, @state_code = stock_state_code, @stock_status_code = stock_status_code
        FROM inventory.inventory_units WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                   NULL AS expires_at, NULL AS zone_code;
            ROLLBACK; RETURN;
        END

        IF @state_code <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK02' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                   NULL AS expires_at, NULL AS zone_code;
            ROLLBACK; RETURN;
        END

        SELECT @source_bin_id = bin_id FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                   NULL AS expires_at, NULL AS zone_code;
            ROLLBACK; RETURN;
        END

        SELECT @source_bin_code = b.bin_code, @zone_code = z.zone_code
        FROM locations.bins b
        LEFT JOIN locations.zones z ON z.zone_id = b.zone_id
        WHERE b.bin_id = @source_bin_id;

        SELECT TOP (1) @task_id = task_id, @dest_bin_id = destination_bin_id, @expires_at = expires_at
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id AND task_state_code IN ('OPN','CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            SELECT @dest_bin_code = bin_code FROM locations.bins WHERE bin_id = @dest_bin_id;
            COMMIT;
            SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
                   @task_id AS task_id, @dest_bin_code AS destination_bin_code,
                   @inventory_unit_id AS inventory_unit_id, @source_bin_code AS source_bin_code,
                   @state_code AS stock_state_code, @stock_status_code AS stock_status_code,
                   @expires_at AS expires_at, @zone_code AS zone_code;
            RETURN;
        END

        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id, @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK04' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                   NULL AS expires_at, NULL AS zone_code;
            ROLLBACK; RETURN;
        END

        SELECT @dest_bin_code = bin_code FROM locations.bins WHERE bin_id = @dest_bin_id;

        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL SET @ttl_seconds = 300;
        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
        VALUES ('PUTAWAY', @inventory_unit_id, @source_bin_id, @dest_bin_id, 'OPN', @expires_at, @user_id);

        SET @task_id = SCOPE_IDENTITY();

        INSERT INTO locations.bin_reservations (bin_id, reservation_type, reserved_by, expires_at)
        VALUES (@dest_bin_id, 'PUTAWAY', @user_id, @expires_at);

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
               @task_id AS task_id, @dest_bin_code AS destination_bin_code,
               @inventory_unit_id AS inventory_unit_id, @source_bin_code AS source_bin_code,
               @state_code AS stock_state_code, @stock_status_code AS stock_status_code,
               @expires_at AS expires_at, @zone_code AS zone_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code,
               NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
               NULL AS expires_at, NULL AS zone_code;
    END CATCH
END;
GO

GO

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

        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW', updated_at = @now, updated_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id AND stock_state_code = 'RCD';

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
             'RCD', 'PTW', @current_status_code, @current_status_code,
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

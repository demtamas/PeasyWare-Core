USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

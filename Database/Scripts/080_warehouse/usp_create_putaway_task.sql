USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

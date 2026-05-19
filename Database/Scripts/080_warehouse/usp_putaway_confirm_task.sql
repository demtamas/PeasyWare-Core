USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

        IF LTRIM(RTRIM(@scanned_bin_code)) COLLATE Latin1_General_CS_AS <> LTRIM(RTRIM(@dest_bin_code)) COLLATE Latin1_General_CS_AS
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

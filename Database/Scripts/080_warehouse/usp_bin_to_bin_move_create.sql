USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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
        SET @external_ref         = LTRIM(RTRIM(@external_ref));
        IF @destination_bin_code IS NOT NULL
            SET @destination_bin_code = LTRIM(RTRIM(@destination_bin_code)) COLLATE Latin1_General_CS_AS;

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
            DECLARE @dest_bin_is_active BIT;

            SELECT @destination_bin_id = bin_id,
                   @dest_bin_is_active = is_active
            FROM locations.bins
            WHERE bin_code = @destination_bin_code COLLATE Latin1_General_CS_AS;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END

            IF @dest_bin_is_active = 0
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE07' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        -- Suggest destination if not provided
        IF @destination_bin_code IS NULL
        BEGIN
            EXEC locations.usp_suggest_putaway_bin
                @inventory_unit_id = @inventory_unit_id,
                @suggested_bin_id  = @destination_bin_id OUTPUT;

            IF @destination_bin_id IS NOT NULL
                SELECT @destination_bin_code = bin_code FROM locations.bins WHERE bin_id = @destination_bin_id;
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
             task_state_code, expires_at,
             claimed_by_user_id, claimed_at,
             created_by)
        VALUES
            ('MOVE', @inventory_unit_id, @source_bin_id, @destination_bin_id,
             'OPN', @expires_at,
             @user_id, @now,
             @user_id);

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
GO

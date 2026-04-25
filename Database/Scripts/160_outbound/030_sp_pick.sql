PRINT 'outbound.usp_pick_create updated — @destination_bin_code parameter added.';
GO

-----------------------------------------------------------------------
-- Used SSMS to script out the below 7 SP creations -- 
-----------------------------------------------------------------------


/****** Object:  StoredProcedure [outbound].[usp_add_order_to_shipment]    Script Date: 18/04/2026 09:29:22 ******/



/********************************************************************************************
    4. outbound.usp_add_order_to_shipment
    Links an allocated order to an open shipment.
    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
GO

/****** Object:  StoredProcedure [outbound].[usp_pick_create]    Script Date: 18/04/2026 09:32:04 ******/


/********************************************************************************************
    WIP PATCH — Pick flow improvements
    Date: 2026-04-18

    1. usp_pick_create: add @destination_bin_code parameter
       Operator can specify which staging bay to pick into.
       If NULL, falls back to first active staging bin (existing behaviour).
********************************************************************************************/
GO

/****** Object:  StoredProcedure [outbound].[usp_ship]    Script Date: 18/04/2026 09:32:17 ******/



/********************************************************************************************
    7. outbound.usp_ship
    Closes a shipment. All orders on the shipment must be PICKED or LOADED.
    Transitions all allocated units to SHP, writes SHIP movement per unit,
    sets actual_departure, closes shipment to DEPARTED.

    Contract: success BIT | result_code NVARCHAR(20) | shipment_id INT
              | units_shipped INT
********************************************************************************************/
GO

CREATE OR ALTER PROCEDURE outbound.usp_pick_create
(
    @allocation_id          INT,
    @destination_bin_code   NVARCHAR(100)    = NULL,   -- NULL = auto-select first staging bin
    @user_id                INT,
    @session_id             UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inventory_unit_id  INT,
        @outbound_line_id   INT,
        @alloc_status       VARCHAR(10),
        @unit_state         VARCHAR(3),
        @source_bin_id      INT,
        @source_bin_code    NVARCHAR(100),
        @staging_bin_id     INT,
        @staging_bin_code   NVARCHAR(100),
        @task_id            INT,
        @ttl_seconds        INT,
        @expires_at         DATETIME2(3),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve allocation ── */
        SELECT
            @inventory_unit_id = a.inventory_unit_id,
            @outbound_line_id  = a.outbound_line_id,
            @alloc_status      = a.allocation_status
        FROM outbound.outbound_allocations a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.allocation_id = @allocation_id;

        IF @inventory_unit_id IS NULL OR @alloc_status <> 'PENDING'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK01' AS result_code,
                   NULL AS task_id, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate unit state ── */
        SELECT @unit_state = stock_state_code
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @unit_state <> 'PTW'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK02' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Get source bin ── */
        SELECT
            @source_bin_id   = b.bin_id,
            @source_bin_code = b.bin_code
        FROM inventory.inventory_placements ip
        JOIN locations.bins b ON b.bin_id = ip.bin_id
        WHERE ip.inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Resolve destination staging bin ── */
        IF @destination_bin_code IS NOT NULL
        BEGIN
            -- Operator specified a staging bin — validate it
            SELECT
                @staging_bin_id   = b.bin_id,
                @staging_bin_code = b.bin_code
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.bin_code            = UPPER(LTRIM(RTRIM(@destination_bin_code)))
              AND b.is_active           = 1
              AND st.storage_type_code  = 'STAGE';

            IF @staging_bin_id IS NULL
            BEGIN
                -- Not a valid active staging bin
                SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END
        ELSE
        BEGIN
            -- Auto-select first active staging bin
            SELECT TOP 1
                @staging_bin_id   = b.bin_id,
                @staging_bin_code = b.bin_code
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE st.storage_type_code = 'STAGE'
              AND b.is_active = 1
            ORDER BY b.bin_code;

            IF @staging_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRTASK04' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, NULL AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        /* ── 5. Create PICK task ── */
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code, inventory_unit_id,
            source_bin_id, destination_bin_id,
            task_state_code, expires_at, created_by
        )
        VALUES
        (
            'PICK', @inventory_unit_id,
            @source_bin_id, @staging_bin_id,
            'OPN', @expires_at, @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        /* ── 6. Update allocation → CONFIRMED ── */
        UPDATE outbound.outbound_allocations
        SET allocation_status = 'CONFIRMED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE allocation_id = @allocation_id;

        /* ── 7. Update line → PICKING ── */
        UPDATE outbound.outbound_lines
        SET line_status_code = 'PICKING',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE outbound_line_id = @outbound_line_id
          AND line_status_code = 'ALLOCATED';

        /* ── 8. Update order → PICKING ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'PICKING',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = (
            SELECT outbound_order_id
            FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id
        )
        AND order_status_code = 'ALLOCATED';

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
               @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
               @source_bin_code AS source_bin_code,
               @staging_bin_code AS destination_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE outbound.usp_pick_confirm
(
    @task_id            INT,
    @scanned_bin_code   NVARCHAR(100),
    @scanned_sscc       NVARCHAR(100),
    @user_id            INT,
    @session_id         UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inventory_unit_id   INT,
        @sku_id              INT,
        @quantity            INT,
        @stock_status_code   VARCHAR(2),
        @source_bin_id       INT,
        @source_bin_code     NVARCHAR(100),
        @dest_bin_id         INT,
        @dest_bin_code       NVARCHAR(100),
        @task_state          VARCHAR(3),
        @unit_external_ref   NVARCHAR(100),
        @outbound_line_id    INT,
        @allocation_id       INT,
        @outbound_order_id   INT,
        @now                 DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve task ── */
        SELECT
            @inventory_unit_id = t.inventory_unit_id,
            @source_bin_id     = t.source_bin_id,
            @dest_bin_id       = t.destination_bin_id,
            @task_state        = t.task_state_code
        FROM warehouse.warehouse_tasks t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.task_id       = @task_id
          AND t.task_type_code = 'PICK';

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @task_state NOT IN ('OPN','CLM')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate scanned bin matches source ── */
        SELECT @source_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @source_bin_id;

        IF UPPER(LTRIM(RTRIM(@scanned_bin_code))) <> UPPER(LTRIM(RTRIM(@source_bin_code)))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK03' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Validate scanned SSCC matches allocated unit ── */
        SELECT
            @unit_external_ref = iu.external_ref,
            @sku_id            = iu.sku_id,
            @quantity          = iu.quantity,
            @stock_status_code = iu.stock_status_code
        FROM inventory.inventory_units iu WITH (UPDLOCK, HOLDLOCK)
        WHERE iu.inventory_unit_id = @inventory_unit_id;

        IF LTRIM(RTRIM(@scanned_sscc)) <> LTRIM(RTRIM(@unit_external_ref))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Get destination bin code ── */
        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        /* ── 5. Move placement to staging ── */
        UPDATE inventory.inventory_placements
        SET bin_id    = @dest_bin_id,
            placed_at = @now,
            placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        /* ── 6. Transition unit → PKD ── */
        UPDATE inventory.inventory_units
        SET stock_state_code = 'PKD',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        /* ── 7. Complete task ── */
        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        /* ── 8. Write PICK movement ── */
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id
        )
        VALUES
        (
            @inventory_unit_id, @sku_id, @quantity,
            @source_bin_id, @dest_bin_id,
            'PTW', 'PKD',
            @stock_status_code, @stock_status_code,
            'PICK', 'TASK', @task_id,
            @now, @user_id, @session_id
        );

        /* ── 9. Update allocation → PICKED ── */
        SELECT @allocation_id = allocation_id
        FROM outbound.outbound_allocations
        WHERE inventory_unit_id = @inventory_unit_id
          AND allocation_status = 'CONFIRMED';

        IF @allocation_id IS NOT NULL
        BEGIN
            UPDATE outbound.outbound_allocations
            SET allocation_status = 'PICKED',
                updated_at        = @now,
                updated_by        = @user_id
            WHERE allocation_id = @allocation_id;

            /* ── 10. Update line picked_qty and status ── */
            SELECT @outbound_line_id = outbound_line_id
            FROM outbound.outbound_allocations
            WHERE allocation_id = @allocation_id;

            UPDATE outbound.outbound_lines
            SET picked_qty       = picked_qty + @quantity,
                line_status_code = CASE
                    WHEN (picked_qty + @quantity) >= ordered_qty THEN 'PICKED'
                    ELSE 'PICKING'
                END,
                updated_at = @now,
                updated_by = @user_id
            WHERE outbound_line_id = @outbound_line_id;

            /* ── 11. Check if all lines picked → update order ── */
            SELECT @outbound_order_id = outbound_order_id
            FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id;

            IF NOT EXISTS (
                SELECT 1 FROM outbound.outbound_lines
                WHERE outbound_order_id = @outbound_order_id
                  AND line_status_code NOT IN ('PICKED','CNL')
            )
            BEGIN
                UPDATE outbound.outbound_orders
                SET order_status_code = 'PICKED',
                    updated_at        = @now,
                    updated_by        = @user_id
                WHERE outbound_order_id = @outbound_order_id;
            END
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCPICK01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO

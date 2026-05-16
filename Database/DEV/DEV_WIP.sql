USE PW_Core_DEV;
GO

-- ── outbound.usp_pick_create: remove UPPER() from bin lookup ─────────────────
-- Destination staging bin is now exact-match, consistent with all other SPs.
-- Trim whitespace only — operator must supply uppercase bin code.

CREATE OR ALTER PROCEDURE outbound.usp_pick_create
(
    @allocation_id          INT,
    @destination_bin_code   NVARCHAR(100)    = NULL,
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

    -- Trim whitespace only — no case normalisation
    IF @destination_bin_code IS NOT NULL
        SET @destination_bin_code = LTRIM(RTRIM(@destination_bin_code));

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve allocation ── */
        SELECT
            @inventory_unit_id = a.inventory_unit_id,
            @outbound_line_id  = a.outbound_line_id,
            @alloc_status      = a.allocation_status
        FROM outbound.outbound_allocations a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.allocation_id = @allocation_id;

        IF @inventory_unit_id IS NULL OR @alloc_status NOT IN ('PENDING', 'CONFIRMED')
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
            -- Exact match — no UPPER()
            SELECT
                @staging_bin_id   = b.bin_id,
                @staging_bin_code = b.bin_code
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.bin_code           = @destination_bin_code
              AND b.is_active          = 1
              AND st.storage_type_code = 'STAGE';

            IF @staging_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END
        ELSE
        BEGIN
            -- Auto-select first available staging bin
            SELECT TOP 1
                @staging_bin_id   = b.bin_id,
                @staging_bin_code = b.bin_code
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.is_active          = 1
              AND st.storage_type_code = 'STAGE'
            ORDER BY b.bin_code;

            IF @staging_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, NULL AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        /* ── 5. Check for existing open pick task ── */
        SELECT TOP 1 @task_id = task_id
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_type_code    = 'PICK'
          AND task_state_code  IN ('OPN','CLM');

        IF @task_id IS NOT NULL
        BEGIN
            -- Return existing task
            COMMIT;
            SELECT CAST(1 AS BIT) AS success, N'SUCPICK01' AS result_code,
                   @task_id           AS task_id,
                   @inventory_unit_id AS inventory_unit_id,
                   @source_bin_code   AS source_bin_code,
                   @staging_bin_code  AS destination_bin_code;
            RETURN;
        END

        /* ── 6. Get TTL ── */
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        /* ── 7. Create pick task ── */
        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
             task_state_code, expires_at, created_by)
        VALUES
            ('PICK', @inventory_unit_id, @source_bin_id, @staging_bin_id,
             'OPN', @expires_at, @user_id);

        SET @task_id = SCOPE_IDENTITY();

        /* ── 8. Mark allocation CONFIRMED ── */
        UPDATE outbound.outbound_allocations
        SET allocation_status = 'CONFIRMED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE allocation_id = @allocation_id;

        /* ── 9. Mark order as PICKING ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'PICKING',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = (
            SELECT ol.outbound_order_id
            FROM outbound.outbound_lines ol
            WHERE ol.outbound_line_id = @outbound_line_id
        )
        AND order_status_code = 'ALLOCATED';

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCPICK01' AS result_code,
               @task_id           AS task_id,
               @inventory_unit_id AS inventory_unit_id,
               @source_bin_code   AS source_bin_code,
               @staging_bin_code  AS destination_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRPICK99' AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_pick_create: UPPER() removed from bin lookup.';
GO

-- ── outbound.usp_pick_confirm: remove UPPER() from bin comparison ─────────────

CREATE OR ALTER PROCEDURE outbound.usp_pick_confirm
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @scanned_sscc     NVARCHAR(100),
    @user_id          INT,
    @session_id       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Trim whitespace only — no case normalisation
    SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code));
    SET @scanned_sscc     = LTRIM(RTRIM(@scanned_sscc));

    DECLARE
        @inventory_unit_id  INT,
        @outbound_line_id   INT,
        @allocation_id      INT,
        @outbound_order_id  INT,
        @dest_bin_id        INT,
        @dest_bin_code      NVARCHAR(100),
        @source_bin_code    NVARCHAR(100),
        @unit_external_ref  NVARCHAR(100),
        @sku_id             INT,
        @quantity           INT,
        @stock_status_code  VARCHAR(2),
        @source_bin_id      INT,
        @task_state         VARCHAR(3),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve task ── */
        SELECT
            @inventory_unit_id = t.inventory_unit_id,
            @source_bin_id     = t.source_bin_id,
            @dest_bin_id       = t.destination_bin_id,
            @task_state        = t.task_state_code
        FROM warehouse.warehouse_tasks t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.task_id        = @task_id
          AND t.task_type_code = 'PICK'
          AND t.task_state_code IN ('OPN','CLM');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK01' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate scanned source bin — exact match, no UPPER() ── */
        SELECT @source_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @source_bin_id;

        IF @scanned_bin_code <> @source_bin_code
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK03' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Validate scanned SSCC ── */
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

        /* ── 7. Confirm task ── */
        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        /* ── 8. Mark allocation PICKED ── */
        SELECT @allocation_id = allocation_id
        FROM outbound.outbound_allocations
        WHERE inventory_unit_id = @inventory_unit_id
          AND allocation_status = 'CONFIRMED';

        IF @allocation_id IS NOT NULL
            UPDATE outbound.outbound_allocations
            SET allocation_status = 'PICKED',
                updated_at        = @now,
                updated_by        = @user_id
            WHERE allocation_id = @allocation_id;

        /* ── 9. Record movement ── */
        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty,
             from_bin_id, to_bin_id,
             from_state_code, to_state_code,
             from_status_code, to_status_code,
             movement_type, reference_type, reference_id,
             moved_at, moved_by_user_id, session_id)
        VALUES
            (@inventory_unit_id, @sku_id, @quantity,
             @source_bin_id, @dest_bin_id,
             'PTW', 'PKD',
             @stock_status_code, @stock_status_code,
             'PICK', 'TASK', @task_id,
             @now, @user_id, @session_id);

        /* ── 10. Check if all allocations confirmed → mark order PICKED ── */
        SELECT @outbound_order_id = ol.outbound_order_id
        FROM outbound.outbound_allocations a
        JOIN outbound.outbound_lines ol ON ol.outbound_line_id = a.outbound_line_id
        WHERE a.inventory_unit_id = @inventory_unit_id
          AND a.allocation_id     = @allocation_id;

        IF @outbound_order_id IS NOT NULL
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM outbound.outbound_allocations a
                JOIN outbound.outbound_lines ol ON ol.outbound_line_id = a.outbound_line_id
                WHERE ol.outbound_order_id = @outbound_order_id
                  AND a.allocation_status IN ('PENDING', 'CONFIRMED')
            )
            BEGIN
                UPDATE outbound.outbound_orders
                SET order_status_code = 'PICKED',
                    updated_at        = @now,
                    updated_by        = @user_id
                WHERE outbound_order_id = @outbound_order_id
                  AND order_status_code = 'PICKING';
            END
        END

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCPICK01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRPICK99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_pick_confirm: UPPER() removed from bin comparison.';
GO

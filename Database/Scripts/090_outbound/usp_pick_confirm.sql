USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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
    SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code)) COLLATE Latin1_General_CS_AS;
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


        /* ── 9. Update line picked_qty and line_status_code ── */
        DECLARE @pick_line_id INT;
        SELECT @pick_line_id = outbound_line_id
        FROM outbound.outbound_allocations
        WHERE allocation_id = @allocation_id;

        IF @pick_line_id IS NOT NULL
        BEGIN
            UPDATE outbound.outbound_lines
            SET picked_qty       = picked_qty + @quantity,
                line_status_code = CASE
                    WHEN (picked_qty + @quantity) >= ordered_qty THEN 'PICKED'
                    ELSE 'PICKING'
                END,
                updated_at = @now,
                updated_by = @user_id
            WHERE outbound_line_id = @pick_line_id;
        END
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

PRINT 'outbound.usp_pick_confirm: UPPER() removed from bin comparison.';
GO


-- ── outbound.usp_pick_create: UPPER() removed from bin lookup ────────────────


PRINT 'outbound.usp_pick_create: UPPER() removed from bin lookup.';
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

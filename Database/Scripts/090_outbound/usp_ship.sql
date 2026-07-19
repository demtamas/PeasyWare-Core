USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_ship
(
    @shipment_id    INT,
    @vehicle_ref    NVARCHAR(50),
    @user_id        INT,
    @session_id     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @shipment_status VARCHAR(10),
        @units_shipped   INT = 0,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_id = @shipment_id;

        IF @shipment_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code,
                   NULL AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        IF @shipment_status NOT IN ('OPEN','LOADING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Require vehicle ref at departure ── */
        IF @vehicle_ref IS NULL OR LTRIM(RTRIM(@vehicle_ref)) = ''
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP05' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Stamp vehicle ref onto shipment ── */
        UPDATE outbound.shipments
        SET vehicle_ref = LTRIM(RTRIM(@vehicle_ref)),
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @user_id
        WHERE shipment_id = @shipment_id;

        /* ── Check all orders are PICKED or LOADED ── */
        IF EXISTS (
            SELECT 1 FROM outbound.outbound_orders
            WHERE shipment_id       = @shipment_id
              AND order_status_code NOT IN ('PICKED','LOADED','CNL')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP04' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Load is mandatory before ship: reject if anything on this
               shipment is still sitting at PICKED (load never confirmed) ── */
        IF EXISTS (
            SELECT 1 FROM outbound.outbound_orders
            WHERE shipment_id       = @shipment_id
              AND order_status_code = 'PICKED'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP09' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Ship each allocated unit ── */
        DECLARE
            @unit_id           INT,
            @sku_id            INT,
            @qty               INT,
            @status_code       VARCHAR(2),
            @from_state        VARCHAR(3),
            @from_bin_id       INT;

        DECLARE ship_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                iu.inventory_unit_id,
                iu.sku_id,
                iu.quantity,
                iu.stock_status_code,
                iu.stock_state_code,
                ip.bin_id
            FROM outbound.outbound_orders o
            JOIN outbound.outbound_lines ol
                ON ol.outbound_order_id = o.outbound_order_id
            JOIN outbound.outbound_allocations a
                ON a.outbound_line_id = ol.outbound_line_id
               AND a.allocation_status = 'PICKED'
            JOIN inventory.inventory_units iu WITH (UPDLOCK)
                ON iu.inventory_unit_id = a.inventory_unit_id
            LEFT JOIN inventory.inventory_placements ip
                ON ip.inventory_unit_id = iu.inventory_unit_id
            WHERE o.shipment_id = @shipment_id;

        OPEN ship_cursor;
        FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_state, @from_bin_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* Transition unit → SHP (from whichever state it's actually in -
               LDD if load was confirmed, PKD in the (now blocked-by-default)
               case load was somehow skipped) */
            UPDATE inventory.inventory_units
            SET stock_state_code = 'SHP',
                updated_at       = @now,
                updated_by       = @user_id
            WHERE inventory_unit_id = @unit_id;

            /* Remove placement — unit is no longer in the warehouse.
               No-op if LOAD already removed it. */
            DELETE FROM inventory.inventory_placements
            WHERE inventory_unit_id = @unit_id;

            /* Write SHIP movement */
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
                @unit_id, @sku_id, @qty,
                @from_bin_id, NULL,
                @from_state, 'SHP',
                @status_code, @status_code,
                'SHIP', 'SHIPMENT', @shipment_id,
                @now, @user_id, @session_id
            );

            SET @units_shipped += 1;

            FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_state, @from_bin_id;
        END

        CLOSE ship_cursor;
        DEALLOCATE ship_cursor;

        /* ── Update all orders on shipment → SHIPPED ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'SHIPPED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE shipment_id       = @shipment_id
          AND order_status_code IN ('PICKED','LOADED');

        /* ── Update all lines on these orders → PICKED (terminal) ── */
        UPDATE ol
        SET ol.line_status_code = 'PICKED',
            ol.updated_at       = @now,
            ol.updated_by       = @user_id
        FROM outbound.outbound_lines ol
        JOIN outbound.outbound_orders o
            ON o.outbound_order_id = ol.outbound_order_id
        WHERE o.shipment_id = @shipment_id
          AND ol.line_status_code <> 'CNL';

        /* ── Close shipment ── */
        UPDATE outbound.shipments
        SET shipment_status  = 'DEPARTED',
            actual_departure = @now,
            updated_at       = @now,
            updated_by       = @user_id
        WHERE shipment_id = @shipment_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP02' AS result_code,
               @shipment_id AS shipment_id, @units_shipped AS units_shipped;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF CURSOR_STATUS('local','ship_cursor') >= 0 BEGIN CLOSE ship_cursor; DEALLOCATE ship_cursor; END
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code,
               NULL AS shipment_id, 0 AS units_shipped;
    END CATCH
END;

GO
GO


/********************************************************************************************
    LOAD CONFIRMATION SP + SUCLOAD01 MESSAGE
    usp_confirm_load redesigned — order-level confirmation, no SSCC scanning
********************************************************************************************/

/********************************************************************************************
    WIP PATCH — Load confirmation redesign
    Date: 2026-04-18

    usp_confirm_load: redesigned — takes order_id + shipment_id
    Operator confirms an order is loaded onto the vehicle.
    No SSCC scanning — pick already confirmed which units are where.

    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
GO

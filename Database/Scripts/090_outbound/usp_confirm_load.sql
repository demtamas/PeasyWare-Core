USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_confirm_load
(
    @outbound_order_id  INT,
    @shipment_id        INT,
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
        @order_status    VARCHAR(10),
        @order_shipment  INT,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order exists and belongs to this shipment ── */
        SELECT
            @order_status   = order_status_code,
            @order_shipment = shipment_id
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_shipment <> @shipment_id
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('PICKED', 'LOADED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Transition order → LOADED ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'LOADED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        /* ── 3. Transition every picked unit on this order: PKD → LDD,
               remove its placement (physically leaving the warehouse
               floor the moment it's loaded, same convention usp_ship
               already uses at SHP), and log a LOAD movement. Mirrors
               usp_ship's own ship_cursor almost exactly, just scoped to
               one order instead of a whole shipment, and one step earlier
               in the lifecycle. ── */
        DECLARE
            @unit_id      INT,
            @sku_id       INT,
            @qty          INT,
            @status_code  VARCHAR(2),
            @from_bin_id  INT;

        DECLARE load_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                iu.inventory_unit_id,
                iu.sku_id,
                iu.quantity,
                iu.stock_status_code,
                ip.bin_id
            FROM outbound.outbound_lines ol
            JOIN outbound.outbound_allocations a
                ON a.outbound_line_id = ol.outbound_line_id
               AND a.allocation_status = 'PICKED'
            JOIN inventory.inventory_units iu WITH (UPDLOCK)
                ON iu.inventory_unit_id = a.inventory_unit_id
               AND iu.stock_state_code  = 'PKD'
            LEFT JOIN inventory.inventory_placements ip
                ON ip.inventory_unit_id = iu.inventory_unit_id
            WHERE ol.outbound_order_id = @outbound_order_id;

        OPEN load_cursor;
        FETCH NEXT FROM load_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            UPDATE inventory.inventory_units
            SET stock_state_code = 'LDD',
                updated_at       = @now,
                updated_by       = @user_id
            WHERE inventory_unit_id = @unit_id;

            DELETE FROM inventory.inventory_placements
            WHERE inventory_unit_id = @unit_id;

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
                'PKD', 'LDD',
                @status_code, @status_code,
                'LOAD', 'OUTBOUND', @outbound_order_id,
                @now, @user_id, @session_id
            );

            FETCH NEXT FROM load_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;
        END

        CLOSE load_cursor;
        DEALLOCATE load_cursor;

        /* ── 4. Transition shipment → LOADING if still OPEN ── */
        UPDATE outbound.shipments
        SET shipment_status = 'LOADING',
            updated_at      = @now,
            updated_by      = @user_id
        WHERE shipment_id     = @shipment_id
          AND shipment_status = 'OPEN';

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCLOAD01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF CURSOR_STATUS('local','load_cursor') >= 0 BEGIN CLOSE load_cursor; DEALLOCATE load_cursor; END
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_confirm_load redesigned.';
GO

-- Add SUCLOAD01 message
GO

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

PRINT 'outbound.usp_confirm_load redesigned.';
GO

-- Add SUCLOAD01 message
INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCLOAD01', N'LOAD', N'INFO',
    N'Order loaded onto vehicle successfully.',
    N'Load.Confirm: order status LOADED, shipment LOADING'
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCLOAD01'
);
GO

PRINT 'SUCLOAD01 message inserted.';
GO

GO

-- ============================================================
-- API creation error codes and stored procedures
-- Merged from WIP: 2026-04-24
-- ============================================================
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU01', N'SKU', N'ERROR', N'SKU not found.', N'inventory.usp_create_sku: sku_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU02', N'SKU', N'ERROR', N'A SKU with this code already exists.', N'inventory.usp_create_sku: duplicate sku_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSKU01', N'SKU', N'SUCCESS', N'SKU created successfully.', N'inventory.usp_create_sku: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB02', N'INB', N'ERROR', N'An inbound delivery with this reference already exists.', N'inbound.usp_create_inbound: duplicate inbound_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINB02', N'INB', N'SUCCESS', N'Inbound delivery created successfully.', N'inbound.usp_create_inbound: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBL02', N'INB', N'SUCCESS', N'Inbound line created successfully.', N'inbound.usp_create_inbound_line: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBL02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBU01', N'INB', N'SUCCESS', N'Expected unit created successfully.', N'inbound.usp_create_expected_unit: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINBU01', N'INB', N'ERROR', N'This SSCC is already registered on this inbound delivery.', N'inbound.usp_create_expected_unit: duplicate sscc on inbound'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINBU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD02', N'ORD', N'ERROR', N'An order with this reference already exists.', N'outbound.usp_create_order: duplicate order_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCORD01', N'ORD', N'SUCCESS', N'Order created successfully.', N'outbound.usp_create_order: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCORD01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP02', N'SHIP', N'ERROR', N'A shipment with this reference already exists.', N'outbound.usp_create_shipment: duplicate shipment_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP01', N'SHIP', N'SUCCESS', N'Shipment created successfully.', N'outbound.usp_create_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP03', N'SHIP', N'ERROR', N'Shipment not found.', N'outbound.usp_add_order_to_shipment: shipment_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD03', N'ORD', N'ERROR', N'Order not found.', N'outbound.usp_add_order_to_shipment: order_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP03', N'SHIP', N'SUCCESS', N'Order added to shipment successfully.', N'outbound.usp_add_order_to_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP03');
GO

-- ── 1. inventory.usp_create_sku ─────────────────────────────────────────
GO

CREATE OR ALTER PROCEDURE outbound.usp_ship
(
    @shipment_id    INT,
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

        /* ── Ship each allocated unit ── */
        DECLARE
            @unit_id           INT,
            @sku_id            INT,
            @qty               INT,
            @status_code       VARCHAR(2),
            @from_bin_id       INT;

        DECLARE ship_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                iu.inventory_unit_id,
                iu.sku_id,
                iu.quantity,
                iu.stock_status_code,
                ip.bin_id
            FROM outbound.outbound_orders o
            JOIN outbound.outbound_lines ol
                ON ol.outbound_order_id = o.outbound_order_id
            JOIN outbound.outbound_allocations a
                ON a.outbound_line_id = ol.outbound_line_id
               AND a.allocation_status = 'PICKED'
            JOIN inventory.inventory_units iu WITH (UPDLOCK)
                ON iu.inventory_unit_id = a.inventory_unit_id
            JOIN inventory.inventory_placements ip
                ON ip.inventory_unit_id = iu.inventory_unit_id
            WHERE o.shipment_id = @shipment_id;

        OPEN ship_cursor;
        FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* Transition unit → SHP */
            UPDATE inventory.inventory_units
            SET stock_state_code = 'SHP',
                updated_at       = @now,
                updated_by       = @user_id
            WHERE inventory_unit_id = @unit_id;

            /* Remove placement — unit is no longer in the warehouse */
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
                'PKD', 'SHP',
                @status_code, @status_code,
                'SHIP', 'SHIPMENT', @shipment_id,
                @now, @user_id, @session_id
            );

            SET @units_shipped += 1;

            FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;
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

        /* ── 3. Transition shipment → LOADING if still OPEN ── */
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
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO

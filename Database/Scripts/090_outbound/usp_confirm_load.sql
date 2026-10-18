USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   outbound.usp_confirm_load
   ------------------------------------------------------------
   Order-level load confirmation: the operator confirms an order
   is physically on the vehicle. No SSCC scanning - the pick
   already confirmed which units are where.

   On the first confirmation, every picked unit on the order goes
   PKD -> LDD, its placement is removed (a loaded pallet no longer
   occupies the floor), and a LOAD movement is written. The order
   becomes LOADED and the shipment LOADING.

   Guards, in order:
     ERRORD01   order not found
     ERRLOAD01  order is not on THIS shipment - including an order
                that is on no shipment at all. (A plain
                "order_shipment <> @shipment_id" is UNKNOWN when
                order_shipment is NULL and lets an unlinked order
                through: its units would go LDD with no placement
                and the ship cursor, which filters on the order's
                shipment, would never ship them.)
     ERRSHIP01/02  shipment not found / not OPEN or LOADING
     ERRORD02   order not PICKED or LOADED

   Repeating the call on an order that is already LOADED changes
   nothing and says so (SUCLOAD02) instead of reporting a fresh
   load - provided every picked unit really is LDD. If one is not,
   the order is inconsistent and is refused (ERRLOAD02) rather than
   reported clean.

   Reconciliation: the number of units moved to LDD must equal the
   number of PICKED allocations on the order. If any picked unit
   was not in PKD (and so was silently skipped by the cursor), the
   whole confirmation rolls back (ERRLOAD02): an order is never
   declared LOADED while stock behind it is not.

   Contract: success BIT | result_code NVARCHAR(20)
   ============================================================ */
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
        @shipment_status VARCHAR(10),
        @expected_units  INT,
        @units_loaded    INT = 0,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Order exists ── */
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

        /* ── 2. Order belongs to THIS shipment (NULL-safe) ── */
        IF @order_shipment IS NULL OR @order_shipment <> @shipment_id
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRLOAD01' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Shipment can still be loaded ── */
        SELECT @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_id = @shipment_id;

        IF @shipment_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @shipment_status NOT IN ('OPEN', 'LOADING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Order is in a loadable status ── */
        IF @order_status NOT IN ('PICKED', 'LOADED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 5. Already loaded: change nothing, say so - but only if the
               stock behind the order really is loaded ── */
        IF @order_status = 'LOADED'
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM outbound.outbound_lines ol
                JOIN outbound.outbound_allocations a
                    ON a.outbound_line_id = ol.outbound_line_id
                   AND a.allocation_status = 'PICKED'
                JOIN inventory.inventory_units iu
                    ON iu.inventory_unit_id = a.inventory_unit_id
                WHERE ol.outbound_order_id = @outbound_order_id
                  AND iu.stock_state_code <> 'LDD'
            )
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRLOAD02' AS result_code;
                ROLLBACK; RETURN;
            END

            COMMIT;
            SELECT CAST(1 AS BIT) AS success, N'SUCLOAD02' AS result_code;
            RETURN;
        END

        /* ── 6. First load. How many units should move? ── */
        SELECT @expected_units = COUNT(*)
        FROM outbound.outbound_lines ol
        JOIN outbound.outbound_allocations a
            ON a.outbound_line_id = ol.outbound_line_id
           AND a.allocation_status = 'PICKED'
        WHERE ol.outbound_order_id = @outbound_order_id;

        UPDATE outbound.outbound_orders
        SET order_status_code = 'LOADED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        /* ── 7. Transition every picked unit on this order: PKD -> LDD,
               remove its placement (physically leaving the warehouse
               floor the moment it's loaded, same convention usp_ship
               uses at SHP), and log a LOAD movement. Mirrors usp_ship's
               own ship_cursor, scoped to one order and one step earlier. ── */
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

            SET @units_loaded += 1;

            FETCH NEXT FROM load_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;
        END

        CLOSE load_cursor;
        DEALLOCATE load_cursor;

        /* ── 8. Reconcile: every picked allocation must have moved a unit.
               Otherwise nothing is loaded - the rollback undoes the order
               status, the unit moves and the ledger rows together. ── */
        IF @units_loaded <> @expected_units
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRLOAD02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 9. Shipment -> LOADING if still OPEN ── */
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
        SELECT CAST(0 AS BIT) AS success, N'ERRLOAD99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_confirm_load created.';
GO

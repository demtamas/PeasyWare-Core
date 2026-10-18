-- ==========================================================
-- TEST: Lifecycle integrity - try to create contradictions
--
-- Each case builds a state the normal flows cannot produce, then calls
-- the procedure that should refuse it, and asserts that the database
-- said no AND changed nothing.
--
--   A  Order LOADED, but one of its units is still PKD
--        -> usp_ship refuses (ERRSHIP10): nothing ships, no SHIP ledger
--           rows, the LDD unit is not shipped without its sibling.
--   B  A PICKED order that is on NO shipment is "loaded for" one
--        -> usp_confirm_load refuses (ERRLOAD01): units stay PKD and
--           keep their placement. (The NULL case: an unlinked order's
--           shipment_id compared with <> is UNKNOWN, not true.)
--   C  Load confirmed twice
--        -> first call SUCLOAD01 and does the work; second SUCLOAD02 and
--           changes nothing: still exactly one LOAD ledger row.
--   D  Move confirmed after the unit's placement has vanished
--        -> usp_bin_to_bin_move_confirm refuses; no placement is invented,
--           no MOVE ledger row is written, the task stays open.
--   E  usp_apply_relocation called directly on a unit with no placement,
--      and on a unit that does not exist
--        -> it THROWs by itself: no ledger row, no placement.
--
-- Deliberately NOT here: a shipment departing with an incompletely
-- allocated order. Partial allocation is an allowed, operator-prompted
-- business case, so shipping what was picked is legitimate.
--
-- No outer transaction: these procedures ROLLBACK internally on their
-- refusal paths (see 146 / 150 / 160), so fixtures are prefixed LIFTEST-
-- and cleaned in a block that always runs. Cases A-C need an existing
-- customer party and ship-from address and skip without them; D and E do
-- not. Allocation across several lines is 041.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id IN (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref LIKE 'LIFTEST-%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'LIFTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'LIFTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'LIFTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'LIFTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'LIFTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'LIFTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'LIFTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'LIFTEST-%';
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
GO

DECLARE @err NVARCHAR(2048) = NULL;

BEGIN TRY

    DECLARE @UserId  INT = (SELECT TOP (1) id FROM auth.users WHERE username = 'system');
    DECLARE @PartyId INT = (SELECT TOP (1) party_id   FROM core.parties         ORDER BY party_id);
    DECLARE @AddrId  INT = (SELECT TOP (1) address_id FROM core.party_addresses ORDER BY address_id);
    DECLARE @HasOutbound BIT = CASE WHEN @PartyId IS NOT NULL AND @AddrId IS NOT NULL THEN 1 ELSE 0 END;

    IF @UserId IS NULL
        RAISERROR('TEST SETUP FAILED: system user not found.', 16, 1);

    ----------------------------------------------------------------
    -- Fixture
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name)
    VALUES ('LIFTEST-STYPE', 'Lifecycle Test Type');

    DECLARE @St INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'LIFTEST-STYPE');

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
        ('LIFTEST-B1', @St, 1, 1, 0),
        ('LIFTEST-B2', @St, 1, 1, 0),
        ('LIFTEST-B3', @St, 1, 1, 0),
        ('LIFTEST-B4', @St, 1, 1, 0),
        ('LIFTEST-B5', @St, 1, 1, 0);

    DECLARE @B1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'LIFTEST-B1');
    DECLARE @B2 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'LIFTEST-B2');
    DECLARE @B3 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'LIFTEST-B3');
    DECLARE @B4 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'LIFTEST-B4');
    DECLARE @B5 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'LIFTEST-B5');

    INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id)
    VALUES ('LIFTEST-SKU', 'Lifecycle Test SKU', '09999900004201', 'EA', @St);
    DECLARE @Sku INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'LIFTEST-SKU');

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
        (@Sku, 'LIFTEST-UA1', 10, 'LDD', 'AV'),   -- A: loaded
        (@Sku, 'LIFTEST-UA2', 10, 'PKD', 'AV'),   -- A: never transitioned
        (@Sku, 'LIFTEST-UB1', 10, 'PKD', 'AV'),   -- B: on an unlinked order
        (@Sku, 'LIFTEST-UC1', 10, 'PKD', 'AV'),   -- C: loaded twice
        (@Sku, 'LIFTEST-UD1', 10, 'PTW', 'AV'),   -- D: move
        (@Sku, 'LIFTEST-UE1', 10, 'PTW', 'AV');   -- E: no placement

    DECLARE @UA1 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UA1');
    DECLARE @UA2 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UA2');
    DECLARE @UB1 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UB1');
    DECLARE @UC1 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UC1');
    DECLARE @UD1 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UD1');
    DECLARE @UE1 INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'LIFTEST-UE1');

    -- UA1 (LDD) and UE1 deliberately have no placement
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES
        (@UA2, @B1),
        (@UB1, @B2),
        (@UC1, @B3),
        (@UD1, @B4);

    DECLARE @SA INT, @SB INT, @SC INT, @OA INT, @OB INT, @OC INT;

    IF @HasOutbound = 1
    BEGIN
        INSERT INTO outbound.shipments (shipment_ref, ship_from_address_id, shipment_status) VALUES
            ('LIFTEST-SA', @AddrId, 'LOADING'),
            ('LIFTEST-SB', @AddrId, 'OPEN'),
            ('LIFTEST-SC', @AddrId, 'OPEN');

        SET @SA = (SELECT shipment_id FROM outbound.shipments WHERE shipment_ref = 'LIFTEST-SA');
        SET @SB = (SELECT shipment_id FROM outbound.shipments WHERE shipment_ref = 'LIFTEST-SB');
        SET @SC = (SELECT shipment_id FROM outbound.shipments WHERE shipment_ref = 'LIFTEST-SC');

        INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, shipment_id, order_status_code) VALUES
            ('LIFTEST-OA', @PartyId, @SA,  'LOADED'),   -- A: labelled LOADED
            ('LIFTEST-OB', @PartyId, NULL, 'PICKED'),   -- B: on no shipment at all
            ('LIFTEST-OC', @PartyId, @SC,  'PICKED');   -- C: normal, loaded twice

        SET @OA = (SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = 'LIFTEST-OA');
        SET @OB = (SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = 'LIFTEST-OB');
        SET @OC = (SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = 'LIFTEST-OC');

        INSERT INTO outbound.outbound_lines
            (outbound_order_id, line_no, sku_id, ordered_qty, allocated_qty, picked_qty, line_status_code) VALUES
            (@OA, 1, @Sku, 20, 20, 20, 'PICKED'),
            (@OB, 1, @Sku, 10, 10, 10, 'PICKED'),
            (@OC, 1, @Sku, 10, 10, 10, 'PICKED');

        INSERT INTO outbound.outbound_allocations
            (outbound_line_id, inventory_unit_id, allocated_qty, allocation_status) VALUES
            ((SELECT outbound_line_id FROM outbound.outbound_lines WHERE outbound_order_id = @OA), @UA1, 10, 'PICKED'),
            ((SELECT outbound_line_id FROM outbound.outbound_lines WHERE outbound_order_id = @OA), @UA2, 10, 'PICKED'),
            ((SELECT outbound_line_id FROM outbound.outbound_lines WHERE outbound_order_id = @OB), @UB1, 10, 'PICKED'),
            ((SELECT outbound_line_id FROM outbound.outbound_lines WHERE outbound_order_id = @OC), @UC1, 10, 'PICKED');
    END

    ----------------------------------------------------------------
    -- A. Order LOADED but a unit still PKD: ship must refuse
    ----------------------------------------------------------------
    IF @HasOutbound = 1
    BEGIN
        EXEC outbound.usp_ship
            @shipment_id = @SA, @vehicle_ref = N'LIFTEST-VEH', @user_id = @UserId, @session_id = NULL;

        IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UA2) <> 'PKD'
            RAISERROR('FAIL (A): the unit that never reached LDD was shipped anyway.', 16, 1);

        IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UA1) <> 'LDD'
            RAISERROR('FAIL (A): the loaded unit was shipped while its sibling was not - the shipment was split.', 16, 1);

        IF EXISTS (SELECT 1 FROM inventory.inventory_movements
                   WHERE inventory_unit_id IN (@UA1, @UA2) AND movement_type = 'SHIP')
            RAISERROR('FAIL (A): a SHIP ledger row was written for a refused shipment.', 16, 1);

        IF ISNULL((SELECT shipment_status FROM outbound.shipments WHERE shipment_id = @SA), '') <> 'LOADING'
            RAISERROR('FAIL (A): the shipment departed despite an unloaded unit.', 16, 1);

        IF ISNULL((SELECT order_status_code FROM outbound.outbound_orders WHERE outbound_order_id = @OA), '') <> 'LOADED'
            RAISERROR('FAIL (A): the order status changed on a refused shipment.', 16, 1);

        PRINT 'PASS (A): an order labelled LOADED with a PKD unit cannot ship.';
    END
    ELSE PRINT 'SKIPPED (A): needs an existing customer party and ship-from address.';

    ----------------------------------------------------------------
    -- B. Unlinked order cannot be "loaded for" a shipment
    ----------------------------------------------------------------
    IF @HasOutbound = 1
    BEGIN
        EXEC outbound.usp_confirm_load
            @outbound_order_id = @OB, @shipment_id = @SB, @user_id = @UserId, @session_id = NULL;

        IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UB1) <> 'PKD'
            RAISERROR('FAIL (B): an unlinked order''s unit was moved to LDD.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UB1)
            RAISERROR('FAIL (B): an unlinked order''s unit lost its placement - it would be stuck LDD with no way to ship.', 16, 1);

        IF ISNULL((SELECT order_status_code FROM outbound.outbound_orders WHERE outbound_order_id = @OB), '') <> 'PICKED'
            RAISERROR('FAIL (B): an unlinked order was marked LOADED.', 16, 1);

        IF ISNULL((SELECT shipment_status FROM outbound.shipments WHERE shipment_id = @SB), '') <> 'OPEN'
            RAISERROR('FAIL (B): a shipment was moved to LOADING by an order that is not on it.', 16, 1);

        IF EXISTS (SELECT 1 FROM inventory.inventory_movements WHERE inventory_unit_id = @UB1 AND movement_type = 'LOAD')
            RAISERROR('FAIL (B): a LOAD ledger row was written for a refused load.', 16, 1);

        PRINT 'PASS (B): an order on no shipment cannot be loaded for one.';
    END
    ELSE PRINT 'SKIPPED (B): needs an existing customer party and ship-from address.';

    ----------------------------------------------------------------
    -- C. Load confirmed twice: second call does nothing, and says so
    ----------------------------------------------------------------
    IF @HasOutbound = 1
    BEGIN
        CREATE TABLE #r (success BIT, result_code NVARCHAR(20));

        -- Neither call hits a ROLLBACK, so INSERT...EXEC can capture the code
        INSERT INTO #r EXEC outbound.usp_confirm_load
            @outbound_order_id = @OC, @shipment_id = @SC, @user_id = @UserId, @session_id = NULL;

        IF NOT EXISTS (SELECT 1 FROM #r WHERE success = 1 AND result_code = N'SUCLOAD01')
            RAISERROR('FAIL (C): the first load confirmation did not return SUCLOAD01.', 16, 1);

        IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UC1) <> 'LDD'
           OR EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UC1)
            RAISERROR('FAIL (C): after loading, the unit should be LDD with no placement.', 16, 1);

        IF ISNULL((SELECT order_status_code FROM outbound.outbound_orders WHERE outbound_order_id = @OC), '') <> 'LOADED'
           OR ISNULL((SELECT shipment_status FROM outbound.shipments WHERE shipment_id = @SC), '') <> 'LOADING'
            RAISERROR('FAIL (C): after loading, the order should be LOADED and the shipment LOADING.', 16, 1);

        DELETE FROM #r;

        INSERT INTO #r EXEC outbound.usp_confirm_load
            @outbound_order_id = @OC, @shipment_id = @SC, @user_id = @UserId, @session_id = NULL;

        IF NOT EXISTS (SELECT 1 FROM #r WHERE success = 1 AND result_code = N'SUCLOAD02')
            RAISERROR('FAIL (C): repeating a load did not return the distinct SUCLOAD02 outcome.', 16, 1);

        IF (SELECT COUNT(*) FROM inventory.inventory_movements
            WHERE inventory_unit_id = @UC1 AND movement_type = 'LOAD') <> 1
            RAISERROR('FAIL (C): repeating a load wrote a second LOAD ledger row (or the first was missing).', 16, 1);

        PRINT 'PASS (C): load confirmation is idempotent and says so.';
    END
    ELSE PRINT 'SKIPPED (C): needs an existing customer party and ship-from address.';

    ----------------------------------------------------------------
    -- D. Move confirmed after the source placement has vanished
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = N'LIFTEST-UD1', @destination_bin_code = N'LIFTEST-B5',
        @user_id = @UserId, @session_id = NULL;

    DECLARE @TaskD INT = (SELECT task_id FROM warehouse.warehouse_tasks
                          WHERE inventory_unit_id = @UD1 AND task_type_code = 'MOVE' AND task_state_code = 'OPN');

    IF @TaskD IS NULL
        RAISERROR('TEST SETUP FAILED (D): the move task was not created.', 16, 1);

    -- The contradiction: the task expects a source bin, the unit has no placement
    DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @UD1;

    EXEC warehouse.usp_bin_to_bin_move_confirm
        @task_id = @TaskD, @scanned_bin_code = N'LIFTEST-B5', @user_id = @UserId, @session_id = NULL;

    IF EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UD1)
        RAISERROR('FAIL (D): a move confirmed against a missing placement invented one.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_movements WHERE inventory_unit_id = @UD1 AND movement_type = 'MOVE')
        RAISERROR('FAIL (D): a MOVE ledger row was written for a unit that was not in any bin.', 16, 1);

    IF ISNULL((SELECT task_state_code FROM warehouse.warehouse_tasks WHERE task_id = @TaskD), '') <> 'OPN'
        RAISERROR('FAIL (D): the task was confirmed despite the refusal.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bin_reservations WHERE task_id = @TaskD)
        RAISERROR('FAIL (D): the refused confirm left the task without its destination reservation (rollback incomplete).', 16, 1);

    PRINT 'PASS (D): a move cannot be confirmed once the unit has no placement.';

    ----------------------------------------------------------------
    -- E. usp_apply_relocation refuses by itself
    ----------------------------------------------------------------
    DECLARE @mvE INT, @threw BIT;

    SET @threw = 0;
    BEGIN TRY
        EXEC warehouse.usp_apply_relocation
            @inventory_unit_id = @UE1, @destination_bin_id = @B5,
            @movement_type = N'MOVE', @reference_type = N'TEST', @reference_id = 0,
            @user_id = @UserId, @session_id = NULL, @movement_id = @mvE OUTPUT;
    END TRY
    BEGIN CATCH
        SET @threw = 1;
    END CATCH

    IF @threw = 0
        RAISERROR('FAIL (E): usp_apply_relocation "relocated" a unit that has no placement.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_movements WHERE inventory_unit_id = @UE1)
        RAISERROR('FAIL (E): a ledger row was written for a relocation that did not happen.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UE1)
        RAISERROR('FAIL (E): a placement appeared for a unit that had none.', 16, 1);

    SET @threw = 0;
    BEGIN TRY
        EXEC warehouse.usp_apply_relocation
            @inventory_unit_id = -1, @destination_bin_id = @B5,
            @movement_type = N'MOVE', @reference_type = N'TEST', @reference_id = 0,
            @user_id = @UserId, @session_id = NULL, @movement_id = @mvE OUTPUT;
    END TRY
    BEGIN CATCH
        SET @threw = 1;
    END CATCH

    IF @threw = 0
        RAISERROR('FAIL (E): usp_apply_relocation accepted a unit that does not exist.', 16, 1);

    PRINT 'PASS (E): usp_apply_relocation refuses a missing placement and a missing unit on its own.';

    PRINT 'TEST PASSED: lifecycle integrity.';

END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH

-- Cleanup (always runs)
IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id IN (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref LIKE 'LIFTEST-%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'LIFTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'LIFTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'LIFTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'LIFTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'LIFTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'LIFTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'LIFTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'LIFTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'LIFTEST-%';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO

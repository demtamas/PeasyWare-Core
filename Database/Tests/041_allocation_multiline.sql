-- ==========================================================
-- TEST: Allocation across several order lines
--
-- 040 covers one line and one pallet. The cases that actually
-- stress usp_allocate_order are the ones where lines differ:
--
--   Partial allowed (order ALLTEST-OP, three lines)
--     line 1  SKU A - a pallet exists            -> allocated
--     line 2  SKU B - NO stock                   -> nothing, and left
--                                                   exactly as it was
--     line 3  SKU C - a pallet exists            -> allocated
--   Both pallets are allocated, line 2 stays at 0 allocated / NEW, and
--   the order is ALLOCATED. An earlier success must not mask a later
--   shortfall, and a later shortfall must not undo an earlier success.
--
--   Partial NOT allowed (order ALLTEST-ON, two lines)
--     line 1  SKU D - a pallet exists
--     line 2  SKU E - NO stock
--   The call fails and EVERYTHING rolls back: no allocation row for
--   line 1's pallet, line 1 still 0 / NEW, order still NEW. All-or-nothing.
--
-- No outer transaction: the failing call ROLLBACKs inside the procedure,
-- which would end an outer one and take the fixtures with it (so the
-- "nothing allocated" assertions would pass trivially). Fixtures are built
-- with an ALLTEST- prefix and cleaned in a block that always runs (as in
-- 146 / 150 / 160). Needs any existing customer party; skips without one.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE a FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines ol  ON ol.outbound_line_id = a.outbound_line_id
    JOIN outbound.outbound_orders o  ON o.outbound_order_id = ol.outbound_order_id
    WHERE o.order_ref LIKE 'ALLTEST-%';
DELETE ol FROM outbound.outbound_lines ol
    JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id
    WHERE o.order_ref LIKE 'ALLTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'ALLTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'ALLTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'ALLTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'ALLTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'ALLTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'ALLTEST-%';
GO

DECLARE @err NVARCHAR(2048) = NULL;

BEGIN TRY

    DECLARE @UserId  INT = (SELECT TOP (1) id FROM auth.users WHERE username = 'system');
    DECLARE @PartyId INT = (SELECT TOP (1) party_id FROM core.parties ORDER BY party_id);

    IF @UserId IS NULL
        RAISERROR('TEST SETUP FAILED: system user not found.', 16, 1);

    IF @PartyId IS NULL
    BEGIN
        PRINT 'SKIPPED: multi-line allocation test needs an existing customer party (none in the database).';
    END
    ELSE
    BEGIN

        ----------------------------------------------------------------
        -- Fixture: pallets for SKUs A, C and D only (B and E have none)
        ----------------------------------------------------------------
        INSERT INTO locations.storage_types (storage_type_code, storage_type_name)
        VALUES ('ALLTEST-STYPE', 'Allocation Test Type');

        DECLARE @St INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'ALLTEST-STYPE');

        INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
            ('ALLTEST-BA', @St, 1, 1, 0),
            ('ALLTEST-BC', @St, 1, 1, 0),
            ('ALLTEST-BD', @St, 1, 1, 0);

        INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id) VALUES
            ('ALLTEST-SKU-A', 'Allocation Test A', '09999900004101', 'EA', @St),
            ('ALLTEST-SKU-B', 'Allocation Test B', '09999900004102', 'EA', @St),
            ('ALLTEST-SKU-C', 'Allocation Test C', '09999900004103', 'EA', @St),
            ('ALLTEST-SKU-D', 'Allocation Test D', '09999900004104', 'EA', @St),
            ('ALLTEST-SKU-E', 'Allocation Test E', '09999900004105', 'EA', @St);

        DECLARE @SkuA INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ALLTEST-SKU-A');
        DECLARE @SkuB INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ALLTEST-SKU-B');
        DECLARE @SkuC INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ALLTEST-SKU-C');
        DECLARE @SkuD INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ALLTEST-SKU-D');
        DECLARE @SkuE INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ALLTEST-SKU-E');

        INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
            (@SkuA, 'ALLTEST-UA', 60, 'PTW', 'AV'),
            (@SkuC, 'ALLTEST-UC', 60, 'PTW', 'AV'),
            (@SkuD, 'ALLTEST-UD', 60, 'PTW', 'AV');

        DECLARE @UA INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ALLTEST-UA');
        DECLARE @UC INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ALLTEST-UC');
        DECLARE @UD INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ALLTEST-UD');

        INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES
            (@UA, (SELECT bin_id FROM locations.bins WHERE bin_code = 'ALLTEST-BA')),
            (@UC, (SELECT bin_id FROM locations.bins WHERE bin_code = 'ALLTEST-BC')),
            (@UD, (SELECT bin_id FROM locations.bins WHERE bin_code = 'ALLTEST-BD'));

        INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
        VALUES ('ALLTEST-OP', @PartyId, 'NEW', CAST(SYSUTCDATETIME() AS DATE));
        DECLARE @OrdP INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
        VALUES ('ALLTEST-ON', @PartyId, 'NEW', CAST(SYSUTCDATETIME() AS DATE));
        DECLARE @OrdN INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_lines (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code) VALUES
            (@OrdP, 1, @SkuA, 60, 'NEW'),
            (@OrdP, 2, @SkuB, 60, 'NEW'),
            (@OrdP, 3, @SkuC, 60, 'NEW'),
            (@OrdN, 1, @SkuD, 60, 'NEW'),
            (@OrdN, 2, @SkuE, 60, 'NEW');

        ----------------------------------------------------------------
        -- 1. Partial allowed: line 2 has no stock, lines 1 and 3 do
        ----------------------------------------------------------------
        EXEC outbound.usp_allocate_order
            @outbound_order_id = @OrdP, @allow_partial = 1, @user_id = @UserId;

        IF ISNULL((SELECT order_status_code FROM outbound.outbound_orders WHERE outbound_order_id = @OrdP), '') <> 'ALLOCATED'
            RAISERROR('FAIL: a partial allocation with some stock should leave the order ALLOCATED.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM outbound.outbound_allocations WHERE inventory_unit_id = @UA AND allocation_status = 'PENDING')
            RAISERROR('FAIL: line 1''s pallet was not allocated.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM outbound.outbound_allocations WHERE inventory_unit_id = @UC AND allocation_status = 'PENDING')
            RAISERROR('FAIL: line 3''s pallet was not allocated - an earlier shortfall (line 2) stopped the pass.', 16, 1);

        IF EXISTS (SELECT 1 FROM outbound.outbound_allocations a
                   JOIN outbound.outbound_lines ol ON ol.outbound_line_id = a.outbound_line_id
                   WHERE ol.outbound_order_id = @OrdP AND ol.line_no = 2)
            RAISERROR('FAIL: the line with no stock somehow received an allocation.', 16, 1);

        IF (SELECT allocated_qty FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 1) <> 60
           OR (SELECT line_status_code FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 1) <> 'ALLOCATED'
            RAISERROR('FAIL: line 1 should be 60 allocated / ALLOCATED.', 16, 1);

        IF (SELECT allocated_qty FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 2) <> 0
           OR (SELECT line_status_code FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 2) <> 'NEW'
            RAISERROR('FAIL: the line with no stock should stay 0 allocated / NEW.', 16, 1);

        IF (SELECT allocated_qty FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 3) <> 60
           OR (SELECT line_status_code FROM outbound.outbound_lines WHERE outbound_order_id = @OrdP AND line_no = 3) <> 'ALLOCATED'
            RAISERROR('FAIL: line 3 should be 60 allocated / ALLOCATED.', 16, 1);

        PRINT 'PASS: partial allocation across lines - earlier and later successes stand, the empty line is untouched.';

        ----------------------------------------------------------------
        -- 2. Partial NOT allowed: line 1 could be filled, line 2 cannot
        ----------------------------------------------------------------
        EXEC outbound.usp_allocate_order
            @outbound_order_id = @OrdN, @allow_partial = 0, @user_id = @UserId;

        IF EXISTS (SELECT 1 FROM outbound.outbound_allocations WHERE inventory_unit_id = @UD)
            RAISERROR('FAIL: all-or-nothing broken - line 1''s pallet stayed allocated after line 2 failed.', 16, 1);

        IF (SELECT allocated_qty FROM outbound.outbound_lines WHERE outbound_order_id = @OrdN AND line_no = 1) <> 0
           OR (SELECT line_status_code FROM outbound.outbound_lines WHERE outbound_order_id = @OrdN AND line_no = 1) <> 'NEW'
            RAISERROR('FAIL: line 1 should be back to 0 allocated / NEW after the failed all-or-nothing call.', 16, 1);

        IF ISNULL((SELECT order_status_code FROM outbound.outbound_orders WHERE outbound_order_id = @OrdN), '') <> 'NEW'
            RAISERROR('FAIL: the order should still be NEW after a failed all-or-nothing allocation.', 16, 1);

        PRINT 'PASS: all-or-nothing - a later line with no stock leaves nothing allocated.';

        PRINT 'TEST PASSED: allocation across several order lines.';

    END

END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH

-- Cleanup (always runs)
DELETE a FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines ol  ON ol.outbound_line_id = a.outbound_line_id
    JOIN outbound.outbound_orders o  ON o.outbound_order_id = ol.outbound_order_id
    WHERE o.order_ref LIKE 'ALLTEST-%';
DELETE ol FROM outbound.outbound_lines ol
    JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id
    WHERE o.order_ref LIKE 'ALLTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'ALLTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'ALLTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'ALLTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'ALLTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'ALLTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'ALLTEST-%';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO

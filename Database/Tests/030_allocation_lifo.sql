-- ==========================================================
-- TEST: Allocation LIFO
-- Verifies that when outbound.allocation_strategy = 'LIFO',
-- the pallet with the LATEST created_at is allocated first.
--
-- Setup:
--   Two pallets of the same SKU, both PTW/AV.
--   Pallet A — created earlier
--   Pallet B — created later (should be picked)
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

BEGIN TRY

    UPDATE operations.settings
    SET setting_value = 'LIFO'
    WHERE setting_name = 'outbound.allocation_strategy';

    DECLARE @SkuId INT;
    INSERT INTO inventory.skus
        (sku_code, sku_description, uom_code, preferred_storage_type_id, is_active)
    VALUES
        ('TEST-LIFO-SKU', 'Test LIFO SKU', 'Case',
         (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK'), 1);
    SET @SkuId = SCOPE_IDENTITY();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @BinA INT, @BinB INT;

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-LIFO-A', @RackTypeId, 1, 1);
    SET @BinA = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-LIFO-B', @RackTypeId, 1, 1);
    SET @BinB = SCOPE_IDENTITY();

    DECLARE @UnitA INT, @UnitB INT;

    -- Pallet A: older
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_at)
    VALUES (@SkuId, 'TEST-SSCC-LIFO-A', 60, 'PTW', 'AV', '2026-01-01T06:00:00');
    SET @UnitA = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitA, @BinA);

    -- Pallet B: newer — should be picked by LIFO
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_at)
    VALUES (@SkuId, 'TEST-SSCC-LIFO-B', 60, 'PTW', 'AV', '2026-05-01T06:00:00');
    SET @UnitB = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitB, @BinB);

    DECLARE @CustomerId INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_CUSTOMER01');
    DECLARE @OrderId INT;

    INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
    VALUES ('TEST-ORD-LIFO', @CustomerId, 'NEW', CAST(GETDATE() AS DATE));
    SET @OrderId = SCOPE_IDENTITY();

    INSERT INTO outbound.outbound_lines (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code)
    VALUES (@OrderId, 1, @SkuId, 60, 'NEW');

    EXEC outbound.usp_allocate_order @outbound_order_id = @OrderId, @allow_partial = 0, @user_id = 1;

    -- Pallet B (newer) must be allocated
    IF NOT EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitB AND a.allocation_status = 'PENDING'
    )
        RAISERROR('LIFO TEST FAILED: Pallet B (newer, 2026-05-01) was not allocated.', 16, 1);

    -- Pallet A (older) must NOT be allocated
    IF EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitA AND a.allocation_status = 'PENDING'
    )
        RAISERROR('LIFO TEST FAILED: Pallet A (older, 2026-01-01) was incorrectly allocated.', 16, 1);

    PRINT 'TEST PASSED: Allocation LIFO — correct pallet selected.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

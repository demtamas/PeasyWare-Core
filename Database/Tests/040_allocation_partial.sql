-- ==========================================================
-- TEST: Allocation Partial
-- Verifies that when allow_partial = 1 and stock is
-- insufficient, the available units are allocated and the
-- SP returns success (not ERRALLOC01).
--
-- Setup:
--   Order requests 120 units (2 pallets of 60).
--   Only 1 pallet of 60 is available.
--   allow_partial = 1.
--
-- Expected: 1 pallet allocated, SP returns success.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

BEGIN TRY

    UPDATE operations.settings
    SET setting_value = 'FEFO'
    WHERE setting_name = 'outbound.allocation_strategy';

    DECLARE @SkuId INT;
    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, preferred_storage_type_id, is_active)
    VALUES
        ('TEST-PART-SKU', 'Test Partial SKU', '09999900000401', 'Case',
         (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK'), 1);
    SET @SkuId = SCOPE_IDENTITY();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @BinA INT;

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-PART-A', @RackTypeId, 1, 1);
    SET @BinA = SCOPE_IDENTITY();

    -- Only ONE pallet available
    DECLARE @UnitA INT;
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TEST-SSCC-PART-A', 60, 'PTW', 'AV');
    SET @UnitA = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitA, @BinA);

    DECLARE @CustomerId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_TEST-CUST-PART', 'Test Customer PART', 'Test Customer', 'GB', 1, SYSUTCDATETIME());
    SET @CustomerId = SCOPE_IDENTITY();
    DECLARE @OrderId INT;

    INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
    VALUES ('TEST-ORD-PART', @CustomerId, 'NEW', CAST(GETDATE() AS DATE));
    SET @OrderId = SCOPE_IDENTITY();

    -- Order wants 120 but only 60 available
    INSERT INTO outbound.outbound_lines (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code)
    VALUES (@OrderId, 1, @SkuId, 120, 'NEW');

    DECLARE @success BIT, @code NVARCHAR(20);

    -- allow_partial = 1
    CREATE TABLE #result (success BIT, result_code NVARCHAR(20), outbound_order_id INT);
    INSERT INTO #result
    EXEC outbound.usp_allocate_order @outbound_order_id = @OrderId, @allow_partial = 1, @user_id = 1;

    SELECT @success = success, @code = result_code FROM #result;

    IF @success = 0
        RAISERROR('PARTIAL TEST FAILED: SP returned failure with allow_partial=1. Code: %s', 16, 1, @code);

    -- The one available pallet must be allocated
    IF NOT EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitA AND a.allocation_status = 'PENDING'
    )
        RAISERROR('PARTIAL TEST FAILED: Available pallet was not allocated.', 16, 1);

    -- Allocated qty on the line must be 60 (not 120)
    DECLARE @allocQty INT;
    SELECT @allocQty = allocated_qty FROM outbound.outbound_lines
    WHERE outbound_order_id = @OrderId AND line_no = 1;

    IF @allocQty <> 60
        RAISERROR('PARTIAL TEST FAILED: allocated_qty expected 60, got %d.', 16, 1, @allocQty);

    PRINT 'TEST PASSED: Allocation partial — available stock committed, SP succeeded.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

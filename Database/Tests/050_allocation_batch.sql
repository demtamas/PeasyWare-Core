-- ==========================================================
-- TEST: Allocation Batch Filter
-- Verifies that when an order line specifies a requested
-- batch, only units with that batch are allocated.
--
-- Setup:
--   Two pallets, same SKU, different batches.
--   Pallet A — BATCH-X  (matches request)
--   Pallet B — BATCH-Y  (does not match)
--   Order line requests BATCH-X.
--
-- Expected: Only Pallet A is allocated.
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
        ('TEST-BATCH-SKU', 'Test Batch SKU', '09999900000501', 'Case',
         (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK'), 1);
    SET @SkuId = SCOPE_IDENTITY();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @BinA INT, @BinB INT;

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-BATCH-A', @RackTypeId, 1, 1);
    SET @BinA = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-BATCH-B', @RackTypeId, 1, 1);
    SET @BinB = SCOPE_IDENTITY();

    DECLARE @UnitA INT, @UnitB INT;

    -- Pallet A: requested batch
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, batch_number, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TEST-SSCC-BATCH-A', 'BATCH-X', 60, 'PTW', 'AV');
    SET @UnitA = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitA, @BinA);

    -- Pallet B: wrong batch
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, batch_number, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TEST-SSCC-BATCH-B', 'BATCH-Y', 60, 'PTW', 'AV');
    SET @UnitB = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitB, @BinB);

    DECLARE @CustomerId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_TEST-CUST-BATCH', 'Test Customer BATCH', 'Test Customer', 'GB', 1, SYSUTCDATETIME());
    SET @CustomerId = SCOPE_IDENTITY();
    DECLARE @OrderId INT;

    INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
    VALUES ('TEST-ORD-BATCH', @CustomerId, 'NEW', CAST(GETDATE() AS DATE));
    SET @OrderId = SCOPE_IDENTITY();

    -- Request specifically BATCH-X
    INSERT INTO outbound.outbound_lines
        (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code, requested_batch)
    VALUES (@OrderId, 1, @SkuId, 60, 'NEW', 'BATCH-X');

    EXEC outbound.usp_allocate_order @outbound_order_id = @OrderId, @allow_partial = 0, @user_id = 1;

    -- Pallet A (BATCH-X) must be allocated
    IF NOT EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitA AND a.allocation_status = 'PENDING'
    )
        RAISERROR('BATCH TEST FAILED: Pallet A (BATCH-X) was not allocated.', 16, 1);

    -- Pallet B (BATCH-Y) must NOT be allocated
    IF EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitB AND a.allocation_status = 'PENDING'
    )
        RAISERROR('BATCH TEST FAILED: Pallet B (BATCH-Y) was incorrectly allocated.', 16, 1);

    PRINT 'TEST PASSED: Allocation batch filter — only matching batch allocated.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

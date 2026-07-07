-- ==========================================================
-- TEST: Allocation Blocked — RCD state
-- Verifies that units in RCD (received, not yet put away)
-- state are NOT allocated, even if they match the SKU.
--
-- Setup:
--   Pallet A — RCD state (not yet put away) — must be ignored
--   Pallet B — PTW state (available)        — must be allocated
--
-- Expected: Only Pallet B is allocated.
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
        ('TEST-RCD-SKU', 'Test RCD Blocked SKU', '09999900000601', 'Case',
         (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK'), 1);
    SET @SkuId = SCOPE_IDENTITY();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @StageTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'STAGE');
    DECLARE @BinA INT, @BinB INT;

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-RCD-STAGE', @StageTypeId, 99, 1);
    SET @BinA = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-RCD-RACK', @RackTypeId, 1, 1);
    SET @BinB = SCOPE_IDENTITY();

    DECLARE @UnitA INT, @UnitB INT;

    -- Pallet A: RCD state — not yet put away, must be ignored
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TEST-SSCC-RCD-A', 60, 'RCD', 'AV');
    SET @UnitA = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitA, @BinA);

    -- Pallet B: PTW state — available for allocation
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TEST-SSCC-RCD-B', 60, 'PTW', 'AV');
    SET @UnitB = SCOPE_IDENTITY();
    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id) VALUES (@UnitB, @BinB);

    DECLARE @CustomerId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_TEST-CUST-RCD', 'Test Customer RCD', 'Test Customer', 'GB', 1, SYSUTCDATETIME());
    SET @CustomerId = SCOPE_IDENTITY();
    DECLARE @OrderId INT;

    INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, order_status_code, required_date)
    VALUES ('TEST-ORD-RCD', @CustomerId, 'NEW', CAST(GETDATE() AS DATE));
    SET @OrderId = SCOPE_IDENTITY();

    INSERT INTO outbound.outbound_lines (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code)
    VALUES (@OrderId, 1, @SkuId, 60, 'NEW');

    EXEC outbound.usp_allocate_order @outbound_order_id = @OrderId, @allow_partial = 0, @user_id = 1;

    -- Pallet A (RCD) must NOT be allocated
    IF EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitA AND a.allocation_status = 'PENDING'
    )
        RAISERROR('RCD BLOCKED TEST FAILED: RCD pallet was incorrectly allocated.', 16, 1);

    -- Pallet B (PTW) must be allocated
    IF NOT EXISTS (
        SELECT 1 FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitB AND a.allocation_status = 'PENDING'
    )
        RAISERROR('RCD BLOCKED TEST FAILED: PTW pallet was not allocated.', 16, 1);

    PRINT 'TEST PASSED: Allocation blocked RCD — only PTW unit allocated.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

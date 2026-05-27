-- ==========================================================
-- TEST: Allocation FIFO
-- Verifies that when outbound.allocation_strategy = 'FIFO',
-- the pallet with the EARLIEST created_at is allocated first.
--
-- Setup:
--   Two pallets of the same SKU in rack bins, both PTW/AV.
--   Pallet A — created earlier (older stock)
--   Pallet B — created later  (newer stock)
--   Order line requests 1 pallet.
--
-- Expected: Pallet A (older created_at) is allocated.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

BEGIN TRY

    -- ── 0. Set strategy to FIFO ────────────────────────────────────
    UPDATE operations.settings
    SET setting_value = 'FIFO'
    WHERE setting_name = 'outbound.allocation_strategy';

    -- ── 1. Test SKU ────────────────────────────────────────────────
    DECLARE @SkuId INT;

    INSERT INTO inventory.skus
        (sku_code, sku_description, uom_code, preferred_storage_type_id, is_active)
    VALUES
        ('TEST-FIFO-SKU', 'Test FIFO SKU', 'Case',
         (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK'),
         1);

    SET @SkuId = SCOPE_IDENTITY();

    -- ── 2. Two rack bins ───────────────────────────────────────────
    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @BinA INT, @BinB INT;

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-FIFO-A', @RackTypeId, 1, 1);
    SET @BinA = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active)
    VALUES ('TEST-FIFO-B', @RackTypeId, 1, 1);
    SET @BinB = SCOPE_IDENTITY();

    -- ── 3. Two inventory units — PTW / AV ──────────────────────────
    --    Force created_at via explicit insert to control ordering.
    DECLARE @UnitA INT, @UnitB INT;

    -- Pallet A: older — should be picked by FIFO
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, best_before_date, quantity, stock_state_code, stock_status_code, created_at)
    VALUES
        (@SkuId, 'TEST-SSCC-FIFO-A', '2026-12-01', 60, 'PTW', 'AV', '2026-01-01T06:00:00');
    SET @UnitA = SCOPE_IDENTITY();

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    VALUES (@UnitA, @BinA);

    -- Pallet B: newer
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, best_before_date, quantity, stock_state_code, stock_status_code, created_at)
    VALUES
        (@SkuId, 'TEST-SSCC-FIFO-B', '2026-12-01', 60, 'PTW', 'AV', '2026-05-01T06:00:00');
    SET @UnitB = SCOPE_IDENTITY();

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    VALUES (@UnitB, @BinB);

    -- ── 4. Customer and outbound order ─────────────────────────────
    DECLARE @CustomerId INT =
        (SELECT party_id FROM core.parties WHERE party_code = 'PW_CUSTOMER01');

    DECLARE @OrderId INT;
    INSERT INTO outbound.outbound_orders
        (order_ref, customer_party_id, order_status_code, required_date)
    VALUES
        ('TEST-ORD-FIFO', @CustomerId, 'NEW', CAST(GETDATE() AS DATE));
    SET @OrderId = SCOPE_IDENTITY();

    INSERT INTO outbound.outbound_lines
        (outbound_order_id, line_no, sku_id, ordered_qty, line_status_code)
    VALUES
        (@OrderId, 1, @SkuId, 60, 'NEW');

    -- ── 5. Allocate ────────────────────────────────────────────────
    EXEC outbound.usp_allocate_order
        @outbound_order_id = @OrderId,
        @allow_partial     = 0,
        @user_id           = 1;

    -- ── 6. Assert: Pallet A (older created_at) must be allocated ───
    IF NOT EXISTS (
        SELECT 1
        FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitA
          AND a.allocation_status = 'PENDING'
    )
    BEGIN
        RAISERROR('FIFO TEST FAILED: Pallet A (older stock, 2026-01-01) was not allocated.', 16, 1);
    END

    -- Assert: Pallet B (newer) must NOT be allocated
    IF EXISTS (
        SELECT 1
        FROM outbound.outbound_allocations a
        WHERE a.inventory_unit_id = @UnitB
          AND a.allocation_status = 'PENDING'
    )
    BEGIN
        RAISERROR('FIFO TEST FAILED: Pallet B (newer stock, 2026-05-01) was incorrectly allocated.', 16, 1);
    END

    PRINT 'TEST PASSED: Allocation FIFO — correct pallet selected.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

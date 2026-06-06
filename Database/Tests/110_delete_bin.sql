-- ==========================================================
-- TEST: usp_delete_bin
-- Verifies:
--   1. Active bin cannot be deleted — bin still exists after call
--   2. Inactive bin with no history IS deleted — bin gone
--   3. Inactive bin with inventory placements — bin still exists
--
-- Note: SP manages its own transaction. Assertions check DB
-- state directly. Cleanup is explicit.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

BEGIN TRY

    DECLARE @RackTypeId INT =
        (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @UserId    INT              = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    -- ── 1. Active bin — must be blocked
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('TDEL-ACTIVE', @RackTypeId, 1, 1, @UserId);

    EXEC locations.usp_delete_bin
        @bin_code       = 'TDEL-ACTIVE',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TDEL-ACTIVE' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: Active bin must NOT be deleted.', 16, 1);

    -- ── 2. Inactive bin with no history — must succeed (bin gone)
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('TDEL-CLEAN', @RackTypeId, 1, 0, @UserId);

    EXEC locations.usp_delete_bin
        @bin_code       = 'TDEL-CLEAN',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TDEL-CLEAN' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: Clean inactive bin must be deleted.', 16, 1);

    -- ── 3. Inactive bin with inventory placement — must be blocked
    DECLARE @SkuId INT;
    INSERT INTO inventory.skus
        (sku_code, sku_description, uom_code, preferred_storage_type_id, is_active)
    VALUES ('TEST-DEL-SKU', 'Delete Test SKU', 'Case', @RackTypeId, 1);
    SET @SkuId = SCOPE_IDENTITY();

    DECLARE @BinHistId INT;
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('TDEL-HIST', @RackTypeId, 1, 0, @UserId);
    SET @BinHistId = SCOPE_IDENTITY();

    DECLARE @UnitId INT;
    INSERT INTO inventory.inventory_units
        (sku_id, external_ref, batch_number, best_before_date, quantity, stock_state_code, stock_status_code)
    VALUES (@SkuId, 'TDEL-SSCC', 'TDEL-BATCH', '2027-01-01', 60, 'SHP', 'AV');
    SET @UnitId = SCOPE_IDENTITY();

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    VALUES (@UnitId, @BinHistId);

    EXEC locations.usp_delete_bin
        @bin_code       = 'TDEL-HIST',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TDEL-HIST' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: Bin with placement history must NOT be deleted.', 16, 1);

    PRINT 'TEST PASSED: usp_delete_bin — active guard, clean delete, placement history guard.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DECLARE @bh INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'TDEL-HIST' COLLATE Latin1_General_CS_AS);
    IF @bh IS NOT NULL DELETE FROM inventory.inventory_placements WHERE bin_id = @bh;
    DELETE FROM inventory.inventory_units WHERE external_ref = 'TDEL-SSCC';
    DELETE FROM inventory.skus            WHERE sku_code     = 'TEST-DEL-SKU';
    DELETE FROM locations.bins WHERE bin_code IN ('TDEL-ACTIVE','TDEL-CLEAN','TDEL-HIST');
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DECLARE @bh2 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'TDEL-HIST' COLLATE Latin1_General_CS_AS);
IF @bh2 IS NOT NULL DELETE FROM inventory.inventory_placements WHERE bin_id = @bh2;
DELETE FROM inventory.inventory_units WHERE external_ref = 'TDEL-SSCC';
DELETE FROM inventory.skus            WHERE sku_code     = 'TEST-DEL-SKU';
DELETE FROM locations.bins WHERE bin_code IN ('TDEL-ACTIVE','TDEL-HIST');
GO

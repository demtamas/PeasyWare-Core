-- ==========================================================
-- TEST: usp_delete_storage_type
-- Verifies:
--   1. Clean type (no bins, no SKUs) is deleted
--   2. Type with bins assigned is blocked (ERRTYP03)
--   3. Type referenced by a SKU preferred type is blocked (ERRTYP04)
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

BEGIN TRY

    DECLARE @UserId    INT              = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    -- ── 1. Clean type — must be deleted
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'TDEL-CLEAN',
        @storage_type_name = 'Delete Test Clean',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'TDEL-CLEAN',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    IF EXISTS (SELECT 1 FROM locations.storage_types
               WHERE storage_type_code = 'TDEL-CLEAN' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: clean storage type must be deleted.', 16, 1);

    -- ── 2. Type with bins — must be blocked (ERRTYP03)
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'TDEL-BINS',
        @storage_type_name = 'Delete Test With Bins',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    DECLARE @TypeWithBinsId INT = (
        SELECT storage_type_id FROM locations.storage_types
        WHERE storage_type_code = 'TDEL-BINS' COLLATE Latin1_General_CS_AS
    );

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('TDEL-BIN-01', @TypeWithBinsId, 1, 0, @UserId);

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'TDEL-BINS',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    IF NOT EXISTS (SELECT 1 FROM locations.storage_types
                   WHERE storage_type_code = 'TDEL-BINS' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: type with bins must NOT be deleted (ERRTYP03).', 16, 1);

    -- ── 3. Type referenced by SKU preferred type — must be blocked (ERRTYP04)
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'TDEL-SKU',
        @storage_type_name = 'Delete Test SKU Ref',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    DECLARE @TypeWithSkuId INT = (
        SELECT storage_type_id FROM locations.storage_types
        WHERE storage_type_code = 'TDEL-SKU' COLLATE Latin1_General_CS_AS
    );

    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, preferred_storage_type_id, is_active)
    VALUES ('TDEL-SKU-001', 'Delete Test SKU', '09999900013101', 'Case', @TypeWithSkuId, 1);

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'TDEL-SKU',
        @user_id = @UserId, @session_id = @SessionId, @correlation_id = @CorrId;

    IF NOT EXISTS (SELECT 1 FROM locations.storage_types
                   WHERE storage_type_code = 'TDEL-SKU' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: type referenced by SKU must NOT be deleted (ERRTYP04).', 16, 1);

    PRINT 'TEST PASSED: usp_delete_storage_type — clean delete, bins guard, SKU ref guard.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    -- Cleanup on failure
    DELETE FROM inventory.skus    WHERE sku_code      = 'TDEL-SKU-001';
    DELETE FROM locations.bins    WHERE bin_code       = 'TDEL-BIN-01';
    DELETE FROM locations.storage_types WHERE storage_type_code LIKE 'TDEL-%' COLLATE Latin1_General_CS_AS;
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM inventory.skus    WHERE sku_code  = 'TDEL-SKU-001';
DELETE FROM locations.bins    WHERE bin_code   = 'TDEL-BIN-01';
DELETE FROM locations.storage_types WHERE storage_type_code LIKE 'TDEL-%' COLLATE Latin1_General_CS_AS;
GO

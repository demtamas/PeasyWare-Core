-- ==========================================================
-- TEST: usp_create_bins_bulk
-- Verifies:
--   1. Bins are created as INACTIVE (is_active = 0)
--   2. Naming convention: {prefix}{row:2}{bay:2}{level_letter}
--   3. Duplicate bin codes are skipped, not errored
--   4. created_count and skipped_count are returned correctly
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

BEGIN TRY

    DECLARE @RackTypeId INT =
        (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');

    -- ── 1. Bulk create 4 bins: prefix=TX, rows 1-2, levels A-B, bay 1
    DECLARE @UserId INT = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    EXEC locations.usp_create_bins_bulk
        @prefix            = 'TX',
        @storage_type_code = 'RACK',
        @row_from          = 1,
        @row_to            = 2,
        @col_from          = 'A',
        @col_to            = 'B',
        @depth_from        = 1,
        @depth_to          = 1,
        @capacity          = 1,
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;

    -- ── 2. All four bins must exist
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TX0101A' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: TX0101A not created.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TX0101B' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: TX0101B not created.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TX0201A' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: TX0201A not created.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TX0201B' COLLATE Latin1_General_CS_AS)
        RAISERROR('TEST FAILED: TX0201B not created.', 16, 1);

    -- ── 3. All bins must be INACTIVE
    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code LIKE 'TX%' AND is_active = 1)
        RAISERROR('TEST FAILED: Newly created bins should be inactive (is_active = 0).', 16, 1);

    -- ── 4. Naming: row 2, bay 1, level B => TX0201B
    IF NOT EXISTS (
        SELECT 1 FROM locations.bins
        WHERE bin_code = 'TX0201B' COLLATE Latin1_General_CS_AS
    )
        RAISERROR('TEST FAILED: Bin TX0201B — naming convention {prefix}{row:2}{bay:2}{level}.', 16, 1);

    -- ── 5. Running again must skip (not error) and report skipped_count
    DECLARE @t TABLE (success BIT, result_code NVARCHAR(20),
                      created_count INT, skipped_count INT);

    INSERT INTO @t
    EXEC locations.usp_create_bins_bulk
        @prefix            = 'TX',
        @storage_type_code = 'RACK',
        @row_from          = 1,
        @row_to            = 1,
        @col_from          = 'A',
        @col_to            = 'A',
        @depth_from        = 1,
        @depth_to          = 1,
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;

    IF NOT EXISTS (SELECT 1 FROM @t WHERE skipped_count = 1 AND created_count = 0)
        RAISERROR('TEST FAILED: Duplicate bin not skipped correctly.', 16, 1);

    PRINT 'TEST PASSED: usp_create_bins_bulk — naming, inactive default, duplicate skip.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

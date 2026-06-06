-- ==========================================================
-- TEST: usp_activate_bins
-- Verifies:
--   1. Inactive bins are activated (is_active flips to 1)
--   2. Already-active bins are counted as skipped, not errored
--   3. activated_count and skipped_count are returned correctly
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

BEGIN TRY

    DECLARE @RackTypeId INT =
        (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @UserId    INT              = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    -- ── 1. Create two inactive test bins directly
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES
        ('TACT-01', @RackTypeId, 1, 0, @UserId),
        ('TACT-02', @RackTypeId, 1, 0, @UserId);

    -- Create one ACTIVE bin to test skipped_count
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('TACT-03', @RackTypeId, 1, 1, @UserId);

    -- ── 2. Activate all three — two inactive, one already active
    DECLARE @t TABLE (success BIT, result_code NVARCHAR(20),
                      activated_count INT, skipped_count INT);

    INSERT INTO @t
    EXEC locations.usp_activate_bins
        @bin_codes_json = '["TACT-01","TACT-02","TACT-03"]',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    -- ── 3. Both inactive bins are now active
    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code IN ('TACT-01','TACT-02') AND is_active = 0)
        RAISERROR('TEST FAILED: Inactive bins were not activated.', 16, 1);

    -- ── 4. Counts: 2 activated, 1 skipped
    IF NOT EXISTS (SELECT 1 FROM @t WHERE activated_count = 2 AND skipped_count = 1)
        RAISERROR('TEST FAILED: activated_count / skipped_count incorrect.', 16, 1);

    -- ── 5. Success flag set
    IF NOT EXISTS (SELECT 1 FROM @t WHERE success = 1)
        RAISERROR('TEST FAILED: success flag not set.', 16, 1);

    PRINT 'TEST PASSED: usp_activate_bins — activation, skip of active, correct counts.';

END TRY
BEGIN CATCH
    ROLLBACK;
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

ROLLBACK;
GO

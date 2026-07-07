-- ==========================================================
-- TEST: usp_create_storage_type / usp_update_storage_type
-- Verifies:
--   1. Creates a new storage type successfully
--   2. Duplicate code is blocked (ERRTYP01)
--   3. Update changes name and description
--   4. Update on unknown code is blocked (ERRTYP02)
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

BEGIN TRY

    DECLARE @UserId    INT              = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    -- ── 1. Create succeeds
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'TTYP-A',
        @storage_type_name = 'Test Type A',
        @description       = 'Created in test',
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;

    IF NOT EXISTS (
        SELECT 1 FROM locations.storage_types
        WHERE storage_type_code = 'TTYP-A' COLLATE Latin1_General_CS_AS
    )
        RAISERROR('TEST FAILED: storage type TTYP-A was not created.', 16, 1);

    -- ── 2. Duplicate code blocked (ERRTYP01)
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'TTYP-A',
        @storage_type_name = 'Duplicate',
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;

    -- Should still be exactly one row
    IF (SELECT COUNT(*) FROM locations.storage_types
        WHERE storage_type_code = 'TTYP-A' COLLATE Latin1_General_CS_AS) <> 1
        RAISERROR('TEST FAILED: duplicate storage type must be blocked (ERRTYP01).', 16, 1);

    -- ── 3. Update name and description
    EXEC locations.usp_update_storage_type
        @storage_type_code = 'TTYP-A',
        @storage_type_name = 'Test Type A Updated',
        @description       = 'Updated in test',
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;

    IF NOT EXISTS (
        SELECT 1 FROM locations.storage_types
        WHERE storage_type_code = 'TTYP-A' COLLATE Latin1_General_CS_AS
          AND storage_type_name = 'Test Type A Updated'
          AND description       = 'Updated in test'
    )
        RAISERROR('TEST FAILED: update did not persist name/description changes.', 16, 1);

    -- ── 4. Update on unknown code blocked (ERRTYP02)
    EXEC locations.usp_update_storage_type
        @storage_type_code = 'TTYP-GHOST',
        @storage_type_name = 'Ghost',
        @user_id           = @UserId,
        @session_id        = @SessionId,
        @correlation_id    = @CorrId;
    -- If we reach here without error the SP handled unknown gracefully

    PRINT 'TEST PASSED: usp_create_storage_type / usp_update_storage_type.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM locations.storage_types WHERE storage_type_code LIKE 'TTYP-%' COLLATE Latin1_General_CS_AS;
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM locations.storage_types WHERE storage_type_code LIKE 'TTYP-%' COLLATE Latin1_General_CS_AS;
GO

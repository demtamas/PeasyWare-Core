-- ==========================================================
-- TEST: RBAC lifecycle coverage - storage_types.manage
-- Covers create/update/deactivate/reactivate (delete is already
-- covered in 140/141). One operator (denied) and one admin
-- (granted) actor, fixtures reused sequentially within each half.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

DECLARE @OperatorId INT;
DECLARE @AdminId INT;

BEGIN TRY

    DECLARE @OperatorRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    DECLARE @AdminRoleId    INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_operator_143', 'RBAC Test Operator 143', 'rbac_test_operator_143@pw.local', 0x00, 1);
    SET @OperatorId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@OperatorId, @OperatorRoleId);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_admin_143', 'RBAC Test Admin 143', 'rbac_test_admin_143@pw.local', 0x00, 1);
    SET @AdminId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@AdminId, @AdminRoleId);

    -- Baseline fixture (active) and a separate inactive fixture, for
    -- update/deactivate/reactivate. "-NEW" code is left free for the
    -- create test itself.
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-143', 'Original Name 143', @AdminId);

    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, is_active, created_by)
    VALUES ('RBAC-TEST-STYPE-143-INACTIVE', 'Inactive Fixture 143', 0, @AdminId);

    ----------------------------------------------------------------
    -- DENIED (operator)
    ----------------------------------------------------------------
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143-NEW', @storage_type_name = 'Should Not Exist',
        @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143-NEW')
        RAISERROR('TEST FAILED: usp_create_storage_type was not denied for operator.', 16, 1);

    EXEC locations.usp_update_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143', @storage_type_name = 'Changed By Operator',
        @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143' AND storage_type_name = 'Original Name 143')
        RAISERROR('TEST FAILED: usp_update_storage_type was not denied for operator.', 16, 1);

    EXEC locations.usp_deactivate_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_deactivate_storage_type was not denied for operator.', 16, 1);

    EXEC locations.usp_reactivate_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143-INACTIVE', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143-INACTIVE' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_reactivate_storage_type was not denied for operator.', 16, 1);

    PRINT 'PASS: storage_types.manage denies operator on create/update/deactivate/reactivate.';

    ----------------------------------------------------------------
    -- GRANTED (admin) - same fixtures, now actually mutated
    ----------------------------------------------------------------
    EXEC locations.usp_create_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143-NEW', @storage_type_name = 'Created By Admin',
        @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143-NEW')
        RAISERROR('TEST FAILED: usp_create_storage_type did not go through for admin.', 16, 1);

    EXEC locations.usp_update_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143', @storage_type_name = 'Changed By Admin',
        @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143' AND storage_type_name = 'Changed By Admin')
        RAISERROR('TEST FAILED: usp_update_storage_type did not go through for admin.', 16, 1);

    EXEC locations.usp_deactivate_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_deactivate_storage_type did not go through for admin.', 16, 1);

    EXEC locations.usp_reactivate_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-143-INACTIVE', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-143-INACTIVE' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_reactivate_storage_type did not go through for admin.', 16, 1);

    PRINT 'TEST PASSED: storage_types.manage lifecycle guard confirmed for operator (denied) and admin (granted).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM locations.storage_types WHERE storage_type_code IN
        ('RBAC-TEST-STYPE-143', 'RBAC-TEST-STYPE-143-INACTIVE', 'RBAC-TEST-STYPE-143-NEW');
    DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
    DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM locations.storage_types WHERE storage_type_code IN
    ('RBAC-TEST-STYPE-143', 'RBAC-TEST-STYPE-143-INACTIVE', 'RBAC-TEST-STYPE-143-NEW');
DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
GO

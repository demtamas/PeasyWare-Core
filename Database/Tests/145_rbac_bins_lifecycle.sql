-- ==========================================================
-- TEST: RBAC lifecycle coverage - bins.manage
-- Covers lock/unlock/create/create_bulk/update/deactivate/
-- reactivate/activate_bins (delete is already covered in
-- 140/141). One operator (denied) and one admin (granted)
-- actor, fixtures reused sequentially within each half.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

DECLARE @OperatorId INT;
DECLARE @AdminId INT;
DECLARE @StypeId INT;

BEGIN TRY

    DECLARE @OperatorRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    DECLARE @AdminRoleId    INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_operator_145', 'RBAC Test Operator 145', 'rbac_test_operator_145@pw.local', 0x00, 1);
    SET @OperatorId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@OperatorId, @OperatorRoleId);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_admin_145', 'RBAC Test Admin 145', 'rbac_test_admin_145@pw.local', 0x00, 1);
    SET @AdminId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@AdminId, @AdminRoleId);

    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-145', 'RBAC Test Type 145', @AdminId);
    SET @StypeId = SCOPE_IDENTITY();

    -- Fixtures: one plain bin (lock/update/deactivate), one pre-locked
    -- bin (unlock), one pre-inactive bin (reactivate), a second
    -- pre-inactive bin dedicated to the activate_bins bulk test.
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked, created_by)
    VALUES ('RBAC-TEST-BIN-145', @StypeId, 1, 1, 0, @AdminId);

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked, created_by)
    VALUES ('RBAC-TEST-BIN-145-LOCKED', @StypeId, 1, 1, 1, @AdminId);

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BIN-145-INACTIVE', @StypeId, 1, 0, @AdminId);

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BIN-145-INACTIVE2', @StypeId, 1, 0, @AdminId);

    ----------------------------------------------------------------
    -- DENIED (operator)
    ----------------------------------------------------------------
    EXEC locations.usp_lock_bin @bin_code = 'RBAC-TEST-BIN-145', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND is_locked = 0)
        RAISERROR('TEST FAILED: usp_lock_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_unlock_bin @bin_code = 'RBAC-TEST-BIN-145-LOCKED', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-LOCKED' AND is_locked = 1)
        RAISERROR('TEST FAILED: usp_unlock_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_create_bin
        @bin_code = 'RBAC-TEST-BIN-145-NEW', @storage_type_code = 'RBAC-TEST-STYPE-145', @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-NEW')
        RAISERROR('TEST FAILED: usp_create_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_create_bins_bulk
        @prefix = 'RBTBD145', @storage_type_code = 'RBAC-TEST-STYPE-145',
        @row_from = 1, @row_to = 1, @col_from = 'A', @col_to = 'A', @depth_from = 1, @depth_to = 1,
        @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBTBD1450101A')
        RAISERROR('TEST FAILED: usp_create_bins_bulk was not denied for operator.', 16, 1);

    EXEC locations.usp_update_bin
        @bin_code_current = 'RBAC-TEST-BIN-145', @notes = 'Changed By Operator', @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND notes = 'Changed By Operator')
        RAISERROR('TEST FAILED: usp_update_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_deactivate_bin @bin_code = 'RBAC-TEST-BIN-145', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_deactivate_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_reactivate_bin @bin_code = 'RBAC-TEST-BIN-145-INACTIVE', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-INACTIVE' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_reactivate_bin was not denied for operator.', 16, 1);

    EXEC locations.usp_activate_bins
        @bin_codes_json = '["RBAC-TEST-BIN-145-INACTIVE2"]', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-INACTIVE2' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_activate_bins was not denied for operator.', 16, 1);

    PRINT 'PASS: bins.manage denies operator across the full bin lifecycle.';

    ----------------------------------------------------------------
    -- GRANTED (admin) - same fixtures, now actually mutated
    ----------------------------------------------------------------
    EXEC locations.usp_lock_bin @bin_code = 'RBAC-TEST-BIN-145', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND is_locked = 1)
        RAISERROR('TEST FAILED: usp_lock_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_unlock_bin @bin_code = 'RBAC-TEST-BIN-145-LOCKED', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-LOCKED' AND is_locked = 0)
        RAISERROR('TEST FAILED: usp_unlock_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_create_bin
        @bin_code = 'RBAC-TEST-BIN-145-NEW', @storage_type_code = 'RBAC-TEST-STYPE-145', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-NEW')
        RAISERROR('TEST FAILED: usp_create_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_create_bins_bulk
        @prefix = 'RBTBG145', @storage_type_code = 'RBAC-TEST-STYPE-145',
        @row_from = 1, @row_to = 1, @col_from = 'A', @col_to = 'A', @depth_from = 1, @depth_to = 1,
        @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBTBG1450101A')
        RAISERROR('TEST FAILED: usp_create_bins_bulk did not go through for admin.', 16, 1);

    -- Note: usp_update_bin blocks storage-type/rename changes once a bin
    -- has active stock, but not notes changes; this fixture has none.
    EXEC locations.usp_update_bin
        @bin_code_current = 'RBAC-TEST-BIN-145', @notes = 'Changed By Admin', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND notes = 'Changed By Admin')
        RAISERROR('TEST FAILED: usp_update_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_deactivate_bin @bin_code = 'RBAC-TEST-BIN-145', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_deactivate_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_reactivate_bin @bin_code = 'RBAC-TEST-BIN-145-INACTIVE', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-INACTIVE' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_reactivate_bin did not go through for admin.', 16, 1);

    EXEC locations.usp_activate_bins
        @bin_codes_json = '["RBAC-TEST-BIN-145-INACTIVE2"]', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-145-INACTIVE2' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_activate_bins did not go through for admin.', 16, 1);

    PRINT 'TEST PASSED: bins.manage full lifecycle guard confirmed for operator (denied) and admin (granted).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM locations.bins WHERE bin_code IN (
        'RBAC-TEST-BIN-145', 'RBAC-TEST-BIN-145-LOCKED', 'RBAC-TEST-BIN-145-INACTIVE',
        'RBAC-TEST-BIN-145-INACTIVE2', 'RBAC-TEST-BIN-145-NEW', 'RBTBD1450101A', 'RBTBG1450101A');
    DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-145';
    DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
    DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM locations.bins WHERE bin_code IN (
    'RBAC-TEST-BIN-145', 'RBAC-TEST-BIN-145-LOCKED', 'RBAC-TEST-BIN-145-INACTIVE',
    'RBAC-TEST-BIN-145-INACTIVE2', 'RBAC-TEST-BIN-145-NEW', 'RBTBD1450101A', 'RBTBG1450101A');
DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-145';
DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
GO

-- ==========================================================
-- TEST: RBAC edge cases - system-role bypass and bootstrap escape hatch
--
-- Part A: an account whose role has is_system_role = 1 but ZERO rows
--         in auth.role_permissions must still pass every guard - it's
--         a trusted automation identity, not something governed by
--         grants (this is also what lets the existing Tests/*.sql
--         suite run everything under the seeded api account).
--         Uses a real, clean fixture and checks DB state directly
--         (no INSERT...EXEC - usp_delete_storage_type ROLLBACKs on
--         its own guard/not-found paths, and SQL Server does not
--         allow ROLLBACK inside an INSERT-EXEC target proc).
--
-- Part B: usp_create_user's bootstrap escape hatch - while no admin
--         role assignment exists anywhere in the system, the guard is
--         skipped so the very first admin can be created with no
--         session context set (exactly how the seed script bootstraps
--         it). The moment that admin exists, the hatch must close.
--         This is destructive to real admin role assignments mid-test
--         by design, so it is wrapped in one explicit transaction that
--         is always rolled back, pass or fail.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

------------------------------------------------------------------
-- Part A - system-role bypass
------------------------------------------------------------------
DECLARE @SysRoleId INT;
DECLARE @SysUserId INT;

BEGIN TRY

    INSERT INTO auth.roles (role_name, description, is_active, is_system_role)
    VALUES ('rbac_test_system_role_temp', 'Temp role for system-bypass test - zero permissions', 1, 1);
    SET @SysRoleId = SCOPE_IDENTITY();

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_system_bypass_user', 'RBAC Test System Bypass', 'rbac_test_system_bypass_user@pw.local', 0x00, 1);
    SET @SysUserId = SCOPE_IDENTITY();

    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@SysUserId, @SysRoleId);

    -- Sanity: confirm this role really does hold zero permissions
    IF EXISTS (SELECT 1 FROM auth.role_permissions WHERE role_id = @SysRoleId)
        RAISERROR('TEST SETUP FAILED: temp system role unexpectedly has permissions.', 16, 1);

    -- Real, clean fixture - no bins/SKUs reference it, so a non-RBAC
    -- delete would succeed. If the guard wrongly blocked this account
    -- the row would still be here afterward.
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-SYS', 'RBAC Test Type Sys', @SysUserId);

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE-SYS', @user_id = @SysUserId;

    IF EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-SYS')
        RAISERROR('TEST FAILED: is_system_role account was blocked by the RBAC guard (should bypass).', 16, 1);

    PRINT 'PASS: is_system_role bypass confirmed (Part A).';

END TRY
BEGIN CATCH
    DECLARE @msgA NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-SYS';
    DELETE FROM auth.user_roles WHERE user_id = @SysUserId OR role_id = @SysRoleId;
    DELETE FROM auth.users WHERE id = @SysUserId;
    DELETE FROM auth.roles WHERE id = @SysRoleId;
    RAISERROR(@msgA, 16, 1);
    RETURN;
END CATCH

DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-SYS';
DELETE FROM auth.user_roles WHERE user_id = @SysUserId OR role_id = @SysRoleId;
DELETE FROM auth.users WHERE id = @SysUserId;
DELETE FROM auth.roles WHERE id = @SysRoleId;

------------------------------------------------------------------
-- Part B - bootstrap escape hatch (fully rolled back, pass or fail)
------------------------------------------------------------------
BEGIN TRAN BootstrapTest;

BEGIN TRY

    DECLARE @AdminRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');
    IF @AdminRoleId IS NULL
        RAISERROR('TEST SETUP FAILED: admin role not found.', 16, 1);

    -- Simulate "no admin exists yet" - safe because this whole block rolls back
    DELETE FROM auth.user_roles WHERE role_id = @AdminRoleId;

    IF EXISTS (SELECT 1 FROM auth.user_roles WHERE role_id = @AdminRoleId)
        RAISERROR('TEST SETUP FAILED: could not simulate an admin-free system.', 16, 1);

    -- No session context set at all - this mirrors exactly how the
    -- seed script creates the first admin/api accounts.
    DECLARE @rcB1 NVARCHAR(20), @fmB1 NVARCHAR(400);
    EXEC auth.usp_create_user
        @username = 'rbac_test_bootstrap_admin', @display_name = 'Bootstrap Test Admin',
        @role_name = 'admin', @email = 'rbac_test_bootstrap_admin@pw.local', @password = 'Test1234!',
        @result_code = @rcB1 OUTPUT, @friendly_msg = @fmB1 OUTPUT;

    IF @rcB1 <> 'SUCAUTHUSR01'
        RAISERROR('TEST FAILED: bootstrap escape hatch did not allow first-admin creation.', 16, 1);

    -- The hatch must now be closed - a second unprivileged attempt,
    -- still with no session context, must be blocked.
    DECLARE @rcB2 NVARCHAR(20), @fmB2 NVARCHAR(400);
    EXEC auth.usp_create_user
        @username = 'rbac_test_bootstrap_second', @display_name = 'Should Not Be Created',
        @role_name = 'admin', @email = 'rbac_test_bootstrap_second@pw.local', @password = 'Test1234!',
        @result_code = @rcB2 OUTPUT, @friendly_msg = @fmB2 OUTPUT;

    IF @rcB2 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: bootstrap escape hatch did not close after the first admin was created.', 16, 1);

    PRINT 'PASS: bootstrap escape hatch opens for the first admin and closes immediately after (Part B).';

    ROLLBACK TRAN BootstrapTest;

END TRY
BEGIN CATCH
    DECLARE @msgB NVARCHAR(2048) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRAN BootstrapTest;
    RAISERROR(@msgB, 16, 1);
    RETURN;
END CATCH
GO

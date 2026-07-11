-- ==========================================================
-- TEST: RBAC guard grants a privileged (admin) actor
-- Verifies each guarded permission category falls through to
-- normal business logic for a role that holds the permission,
-- using real fixtures and checking DB state directly (no
-- INSERT...EXEC -- these SPs can ROLLBACK on some branches, and
-- SQL Server does not allow ROLLBACK inside an INSERT-EXEC
-- target proc; plain EXEC avoids the question entirely).
--
-- Exception: usp_logout_all_sessions actually would revoke real
-- active sessions if left unguarded against side effects, so
-- that one call is wrapped in its own explicit transaction and
-- rolled back regardless of outcome.
--
-- Note: inbound.reverse is not covered here -- see 140 for why.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

DECLARE @TestAdminId INT;
DECLARE @VictimUserId INT;
DECLARE @StypeId INT;
DECLARE @SkuId INT;

BEGIN TRY

    DECLARE @AdminRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');
    IF @AdminRoleId IS NULL
        RAISERROR('TEST SETUP FAILED: admin role not found.', 16, 1);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_admin_granted', 'RBAC Test Admin (temp)', 'rbac_test_admin_granted@pw.local', 0x00, 1);
    SET @TestAdminId = SCOPE_IDENTITY();

    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@TestAdminId, @AdminRoleId);

    ----------------------------------------------------------------
    -- users.manage - usp_update_user
    ----------------------------------------------------------------
    INSERT INTO auth.users (username, display_name, email, password_hash, salt, is_active)
    VALUES ('rbac_test_victim_141', 'Original Name', 'rbac_test_victim_141@pw.local', 0x01, 0x01, 1);
    SET @VictimUserId = SCOPE_IDENTITY();

    EXEC auth.usp_update_user
        @user_id = @VictimUserId, @display_name = 'Changed By RBAC Test', @admin_user_id = @TestAdminId;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = @VictimUserId AND display_name = 'Changed By RBAC Test')
        RAISERROR('TEST FAILED: usp_update_user did not go through for admin (users.manage).', 16, 1);

    ----------------------------------------------------------------
    -- sessions.terminate_all - usp_logout_all_sessions
    -- Wrapped and rolled back: guard passing means this SP will try
    -- to actually revoke real active sessions.
    ----------------------------------------------------------------
    BEGIN TRAN LogoutAllGrantTest;

        DECLARE @rc2 NVARCHAR(20), @fm2 NVARCHAR(400), @sc2 BIT, @tc2 INT;
        EXEC auth.usp_logout_all_sessions
            @admin_user_id = @TestAdminId,
            @exclude_session_id = NULL,
            @result_code = @rc2 OUTPUT, @friendly_msg = @fm2 OUTPUT,
            @success = @sc2 OUTPUT, @terminated_count = @tc2 OUTPUT;

        IF @rc2 = 'ERRPERM01'
        BEGIN
            ROLLBACK TRAN LogoutAllGrantTest;
            RAISERROR('TEST FAILED: usp_logout_all_sessions blocked admin (sessions.terminate_all).', 16, 1);
        END

    ROLLBACK TRAN LogoutAllGrantTest;

    ----------------------------------------------------------------
    -- bins.manage - usp_delete_bin
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-141', 'RBAC Test Type 141', @TestAdminId);
    SET @StypeId = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BIN-141', @StypeId, 1, 0, @TestAdminId);

    EXEC locations.usp_delete_bin
        @bin_code = 'RBAC-TEST-BIN-141', @user_id = @TestAdminId;

    IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-141')
        RAISERROR('TEST FAILED: usp_delete_bin did not go through for admin (bins.manage).', 16, 1);

    ----------------------------------------------------------------
    -- zones.manage - usp_delete_zone
    ----------------------------------------------------------------
    INSERT INTO locations.zones (zone_code, zone_name, created_by)
    VALUES ('RBAC-TEST-ZONE-141', 'RBAC Test Zone 141', @TestAdminId);

    EXEC locations.usp_delete_zone
        @zone_code = 'RBAC-TEST-ZONE-141', @user_id = @TestAdminId;

    IF EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-141')
        RAISERROR('TEST FAILED: usp_delete_zone did not go through for admin (zones.manage).', 16, 1);

    ----------------------------------------------------------------
    -- storage_types.manage - usp_delete_storage_type (separate clean type)
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE2-141', 'RBAC Test Type 2 141', @TestAdminId);

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE2-141', @user_id = @TestAdminId;

    IF EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE2-141')
        RAISERROR('TEST FAILED: usp_delete_storage_type did not go through for admin (storage_types.manage).', 16, 1);

    ----------------------------------------------------------------
    -- stock.status_change - usp_update_stock_status
    ----------------------------------------------------------------
    INSERT INTO inventory.skus (sku_code, sku_description, uom_code, preferred_storage_type_id, created_by)
    VALUES ('RBAC-TEST-SKU-141', 'RBAC Test SKU 141', 'EA', @StypeId, @TestAdminId);
    SET @SkuId = SCOPE_IDENTITY();

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_by)
    VALUES (@SkuId, 'RBAC-TEST-SSCC-141', 1, 'RCD', 'AV', @TestAdminId);

    EXEC inventory.usp_update_stock_status
        @sscc_list = 'RBAC-TEST-SSCC-141', @new_status = 'QC', @user_id = @TestAdminId;

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-141' AND stock_status_code = 'QC')
        RAISERROR('TEST FAILED: usp_update_stock_status did not go through for admin (stock.status_change).', 16, 1);

    ----------------------------------------------------------------
    -- settings.write - usp_setting_update - expect ERRSET01 (not found), proving guard passed
    ----------------------------------------------------------------
    EXEC sys.sp_set_session_context @key = N'user_id', @value = @TestAdminId;
    DECLARE @FakeSessionId UNIQUEIDENTIFIER = NEWID();
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @FakeSessionId;

    DECLARE @rc3 NVARCHAR(20), @fm3 NVARCHAR(400);
    EXEC operations.usp_setting_update
        @setting_name = 'rbac.test.nonexistent.setting', @setting_value = 'x',
        @result_code = @rc3 OUTPUT, @friendly_msg = @fm3 OUTPUT;

    IF @rc3 = 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_setting_update blocked admin (settings.write).', 16, 1);
    IF @rc3 <> 'ERRSET01'
        RAISERROR('TEST FAILED: usp_setting_update unexpected result_code for admin.', 16, 1);

    ----------------------------------------------------------------
    -- users.manage - usp_admin_reset_password / usp_set_user_active
    -- (session context already set to the admin above; reset the
    -- password BEFORE deactivating the account, since usp_change_password
    -- correctly refuses to reset a password on an inactive user - that
    -- would be a business-logic rejection, not an RBAC one)
    ----------------------------------------------------------------
    DECLARE @rc11 NVARCHAR(20), @fm11 NVARCHAR(400);
    EXEC auth.usp_admin_reset_password
        @target_user_id = @VictimUserId, @new_password = 'Test1234!',
        @result_code = @rc11 OUTPUT, @friendly_message = @fm11 OUTPUT;

    IF @rc11 = 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_admin_reset_password blocked admin (users.manage).', 16, 1);
    IF @rc11 NOT LIKE 'SUC%'
        RAISERROR('TEST FAILED: usp_admin_reset_password unexpected result_code for admin.', 16, 1);

    DECLARE @rc10 NVARCHAR(20), @fm10 NVARCHAR(400);
    EXEC auth.usp_set_user_active
        @user_id = @VictimUserId, @is_active = 0,
        @result_code = @rc10 OUTPUT, @friendly_msg = @fm10 OUTPUT;

    IF @rc10 = 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_set_user_active blocked admin (users.manage).', 16, 1);
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = @VictimUserId AND is_active = 0)
        RAISERROR('TEST FAILED: usp_set_user_active did not go through for admin.', 16, 1);

    ----------------------------------------------------------------
    -- users.manage - usp_create_user - really creates a user, clean it up
    ----------------------------------------------------------------
    DECLARE @rc9 NVARCHAR(20), @fm9 NVARCHAR(400);
    EXEC auth.usp_create_user
        @username = 'rbac_test_created_by_admin', @display_name = 'Created By Admin Test',
        @role_name = 'operator', @email = 'rbac_test_created_by_admin@pw.local', @password = 'Test1234!',
        @result_code = @rc9 OUTPUT, @friendly_msg = @fm9 OUTPUT;

    IF @rc9 = 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_create_user blocked admin (users.manage).', 16, 1);
    IF @rc9 <> 'SUCAUTHUSR01'
        RAISERROR('TEST FAILED: usp_create_user did not succeed for admin.', 16, 1);
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username = 'rbac_test_created_by_admin')
        RAISERROR('TEST FAILED: usp_create_user reported success but no row was created.', 16, 1);

    PRINT 'TEST PASSED: RBAC guards grant admin across 7 permission categories (inbound.reverse not covered here).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
    DELETE FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-141';
    DELETE FROM inventory.skus WHERE sku_code = 'RBAC-TEST-SKU-141';
    DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-141';
    DELETE FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-141';
    DELETE FROM locations.storage_types WHERE storage_type_code IN ('RBAC-TEST-STYPE-141', 'RBAC-TEST-STYPE2-141');
    DELETE FROM auth.password_history WHERE user_id IN (@TestAdminId, @VictimUserId);
    DELETE FROM auth.user_roles WHERE user_id = @TestAdminId;
    DELETE FROM auth.users WHERE id IN (@TestAdminId, @VictimUserId);
    DELETE FROM auth.user_roles WHERE user_id = (SELECT id FROM auth.users WHERE username = 'rbac_test_created_by_admin');
    DELETE FROM auth.users WHERE username = 'rbac_test_created_by_admin';
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-141';
DELETE FROM inventory.skus WHERE sku_code = 'RBAC-TEST-SKU-141';
DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-141';
DELETE FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-141';
DELETE FROM locations.storage_types WHERE storage_type_code IN ('RBAC-TEST-STYPE-141', 'RBAC-TEST-STYPE2-141');
DELETE FROM auth.password_history WHERE user_id IN (@TestAdminId, @VictimUserId);
DELETE FROM auth.user_roles WHERE user_id = @TestAdminId;
DELETE FROM auth.users WHERE id IN (@TestAdminId, @VictimUserId);
DELETE FROM auth.user_roles WHERE user_id = (SELECT id FROM auth.users WHERE username = 'rbac_test_created_by_admin');
DELETE FROM auth.users WHERE username = 'rbac_test_created_by_admin';
GO

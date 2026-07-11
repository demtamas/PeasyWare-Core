-- ==========================================================
-- TEST: RBAC guard denies an unprivileged (operator) actor
-- Verifies each guarded permission category blocks an operator,
-- using real fixtures and checking DB state directly (no
-- INSERT...EXEC -- these SPs ROLLBACK on their denial/not-found
-- paths, and SQL Server does not allow ROLLBACK inside an
-- INSERT-EXEC target proc).
--
-- Note: inbound.reverse is not covered here -- a real reversal
-- fixture needs a full inbound delivery/line/receipt chain,
-- which is heavier than the other categories. Worth a dedicated
-- test later; for now this covers the other 7 categories.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

DECLARE @TestOperatorId INT;
DECLARE @VictimUserId INT;
DECLARE @StypeId INT;
DECLARE @SkuId INT;

BEGIN TRY

    DECLARE @OperatorRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    IF @OperatorRoleId IS NULL
        RAISERROR('TEST SETUP FAILED: operator role not found.', 16, 1);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_operator_denied', 'RBAC Test Operator (temp)', 'rbac_test_operator_denied@pw.local', 0x00, 1);
    SET @TestOperatorId = SCOPE_IDENTITY();

    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@TestOperatorId, @OperatorRoleId);

    ----------------------------------------------------------------
    -- users.manage - usp_update_user
    ----------------------------------------------------------------
    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_victim_140', 'Original Name', 'rbac_test_victim_140@pw.local', 0x00, 1);
    SET @VictimUserId = SCOPE_IDENTITY();

    EXEC auth.usp_update_user
        @user_id = @VictimUserId, @display_name = 'Changed By RBAC Test', @admin_user_id = @TestOperatorId;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = @VictimUserId AND display_name = 'Original Name')
        RAISERROR('TEST FAILED: usp_update_user was not denied for operator (users.manage).', 16, 1);

    ----------------------------------------------------------------
    -- sessions.terminate_all - usp_logout_all_sessions (OUTPUT params, safe as-is)
    ----------------------------------------------------------------
    DECLARE @rc2 NVARCHAR(20), @fm2 NVARCHAR(400), @sc2 BIT, @tc2 INT;
    EXEC auth.usp_logout_all_sessions
        @admin_user_id = @TestOperatorId,
        @result_code = @rc2 OUTPUT, @friendly_msg = @fm2 OUTPUT,
        @success = @sc2 OUTPUT, @terminated_count = @tc2 OUTPUT;

    IF @rc2 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_logout_all_sessions did not deny operator (sessions.terminate_all).', 16, 1);

    ----------------------------------------------------------------
    -- bins.manage - usp_delete_bin
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-140', 'RBAC Test Type 140', @TestOperatorId);
    SET @StypeId = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BIN-140', @StypeId, 1, 0, @TestOperatorId);

    EXEC locations.usp_delete_bin
        @bin_code = 'RBAC-TEST-BIN-140', @user_id = @TestOperatorId;

    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-140')
        RAISERROR('TEST FAILED: usp_delete_bin was not denied for operator (bins.manage).', 16, 1);

    ----------------------------------------------------------------
    -- zones.manage - usp_delete_zone
    ----------------------------------------------------------------
    INSERT INTO locations.zones (zone_code, zone_name, created_by)
    VALUES ('RBAC-TEST-ZONE-140', 'RBAC Test Zone 140', @TestOperatorId);

    EXEC locations.usp_delete_zone
        @zone_code = 'RBAC-TEST-ZONE-140', @user_id = @TestOperatorId;

    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-140')
        RAISERROR('TEST FAILED: usp_delete_zone was not denied for operator (zones.manage).', 16, 1);

    ----------------------------------------------------------------
    -- storage_types.manage - usp_delete_storage_type (separate clean type)
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE2-140', 'RBAC Test Type 2 140', @TestOperatorId);

    EXEC locations.usp_delete_storage_type
        @storage_type_code = 'RBAC-TEST-STYPE2-140', @user_id = @TestOperatorId;

    IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE2-140')
        RAISERROR('TEST FAILED: usp_delete_storage_type was not denied for operator (storage_types.manage).', 16, 1);

    ----------------------------------------------------------------
    -- stock.status_change - usp_update_stock_status
    ----------------------------------------------------------------
    INSERT INTO inventory.skus (sku_code, sku_description, uom_code, preferred_storage_type_id, created_by)
    VALUES ('RBAC-TEST-SKU-140', 'RBAC Test SKU 140', 'EA', @StypeId, @TestOperatorId);
    SET @SkuId = SCOPE_IDENTITY();

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_by)
    VALUES (@SkuId, 'RBAC-TEST-SSCC-140', 1, 'RCD', 'AV', @TestOperatorId);

    EXEC inventory.usp_update_stock_status
        @sscc_list = 'RBAC-TEST-SSCC-140', @new_status = 'QC', @user_id = @TestOperatorId;

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-140' AND stock_status_code = 'AV')
        RAISERROR('TEST FAILED: usp_update_stock_status was not denied for operator (stock.status_change).', 16, 1);

    ----------------------------------------------------------------
    -- settings.write - usp_setting_update (OUTPUT params, safe as-is)
    ----------------------------------------------------------------
    EXEC sys.sp_set_session_context @key = N'user_id', @value = @TestOperatorId;
    DECLARE @FakeSessionId UNIQUEIDENTIFIER = NEWID();
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @FakeSessionId;

    DECLARE @rc3 NVARCHAR(20), @fm3 NVARCHAR(400);
    EXEC operations.usp_setting_update
        @setting_name = 'core.version', @setting_value = '1.0.0',
        @result_code = @rc3 OUTPUT, @friendly_msg = @fm3 OUTPUT;

    IF @rc3 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_setting_update did not deny operator (settings.write).', 16, 1);

    ----------------------------------------------------------------
    -- users.manage - usp_create_user / usp_set_user_active / usp_admin_reset_password
    -- (session context already set to the operator above)
    ----------------------------------------------------------------
    DECLARE @rc9 NVARCHAR(20), @fm9 NVARCHAR(400);
    EXEC auth.usp_create_user
        @username = 'rbac_test_should_not_be_created', @display_name = 'Should Not Exist',
        @role_name = 'operator', @email = 'rbac_test_should_not_exist@pw.local', @password = 'Test1234!',
        @result_code = @rc9 OUTPUT, @friendly_msg = @fm9 OUTPUT;

    IF @rc9 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_create_user did not deny operator (users.manage).', 16, 1);
    IF EXISTS (SELECT 1 FROM auth.users WHERE username = 'rbac_test_should_not_be_created')
        RAISERROR('TEST FAILED: usp_create_user created a user despite denial.', 16, 1);

    DECLARE @rc10 NVARCHAR(20), @fm10 NVARCHAR(400);
    EXEC auth.usp_set_user_active
        @user_id = @VictimUserId, @is_active = 0,
        @result_code = @rc10 OUTPUT, @friendly_msg = @fm10 OUTPUT;

    IF @rc10 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_set_user_active did not deny operator (users.manage).', 16, 1);
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = @VictimUserId AND is_active = 1)
        RAISERROR('TEST FAILED: usp_set_user_active changed state despite denial.', 16, 1);

    DECLARE @rc11 NVARCHAR(20), @fm11 NVARCHAR(400);
    EXEC auth.usp_admin_reset_password
        @target_user_id = @VictimUserId, @new_password = 'Test1234!',
        @result_code = @rc11 OUTPUT, @friendly_message = @fm11 OUTPUT;

    IF @rc11 <> 'ERRPERM01'
        RAISERROR('TEST FAILED: usp_admin_reset_password did not deny operator (users.manage).', 16, 1);

    PRINT 'TEST PASSED: RBAC guards deny operator across 7 permission categories (inbound.reverse not covered here).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-140';
    DELETE FROM inventory.skus WHERE sku_code = 'RBAC-TEST-SKU-140';
    DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-140';
    DELETE FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-140';
    DELETE FROM locations.storage_types WHERE storage_type_code IN ('RBAC-TEST-STYPE-140', 'RBAC-TEST-STYPE2-140');
    DELETE FROM auth.user_roles WHERE user_id = @TestOperatorId;
    DELETE FROM auth.users WHERE id IN (@TestOperatorId, @VictimUserId);
    DELETE FROM auth.users WHERE username = 'rbac_test_should_not_be_created';
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-140';
DELETE FROM inventory.skus WHERE sku_code = 'RBAC-TEST-SKU-140';
DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-140';
DELETE FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-140';
DELETE FROM locations.storage_types WHERE storage_type_code IN ('RBAC-TEST-STYPE-140', 'RBAC-TEST-STYPE2-140');
DELETE FROM auth.user_roles WHERE user_id = @TestOperatorId;
DELETE FROM auth.users WHERE id IN (@TestOperatorId, @VictimUserId);
DELETE FROM auth.users WHERE username = 'rbac_test_should_not_be_created';
GO

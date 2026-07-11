-- ==========================================================
-- TEST: RBAC lifecycle coverage - zones.manage
-- Covers create/update/deactivate/reactivate for both zones and
-- sections (delete is already covered in 140/141), plus
-- assign-bins-to-zone/section. One operator (denied) and one
-- admin (granted) actor, fixtures reused sequentially.
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
    VALUES ('rbac_test_operator_144', 'RBAC Test Operator 144', 'rbac_test_operator_144@pw.local', 0x00, 1);
    SET @OperatorId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@OperatorId, @OperatorRoleId);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_admin_144', 'RBAC Test Admin 144', 'rbac_test_admin_144@pw.local', 0x00, 1);
    SET @AdminId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@AdminId, @AdminRoleId);

    -- Zone fixtures
    INSERT INTO locations.zones (zone_code, zone_name, created_by)
    VALUES ('RBAC-TEST-ZONE-144', 'Original Zone Name 144', @AdminId);
    INSERT INTO locations.zones (zone_code, zone_name, is_active, created_by)
    VALUES ('RBAC-TEST-ZONE-144-INACTIVE', 'Inactive Zone Fixture 144', 0, @AdminId);

    -- Section fixtures
    INSERT INTO locations.storage_sections (section_code, section_name, created_by)
    VALUES ('RBAC-TEST-SEC-144', 'Original Section Name 144', @AdminId);
    INSERT INTO locations.storage_sections (section_code, section_name, is_active, created_by)
    VALUES ('RBAC-TEST-SEC-144-INACTIVE', 'Inactive Section Fixture 144', 0, @AdminId);

    -- Bin fixture (for assign-to-zone/section), with its own storage type
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-144', 'RBAC Test Type 144', @AdminId);
    SET @StypeId = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BIN-144', @StypeId, 1, 0, @AdminId);

    ----------------------------------------------------------------
    -- DENIED (operator)
    ----------------------------------------------------------------
    EXEC locations.usp_create_zone
        @zone_code = 'RBAC-TEST-ZONE-144-NEW', @zone_name = 'Should Not Exist', @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144-NEW')
        RAISERROR('TEST FAILED: usp_create_zone was not denied for operator.', 16, 1);

    EXEC locations.usp_update_zone
        @zone_code = 'RBAC-TEST-ZONE-144', @zone_name = 'Changed By Operator', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144' AND zone_name = 'Original Zone Name 144')
        RAISERROR('TEST FAILED: usp_update_zone was not denied for operator.', 16, 1);

    EXEC locations.usp_deactivate_zone
        @zone_code = 'RBAC-TEST-ZONE-144', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_deactivate_zone was not denied for operator.', 16, 1);

    EXEC locations.usp_reactivate_zone
        @zone_code = 'RBAC-TEST-ZONE-144-INACTIVE', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144-INACTIVE' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_reactivate_zone was not denied for operator.', 16, 1);

    EXEC locations.usp_create_section
        @section_code = 'RBAC-TEST-SEC-144-NEW', @section_name = 'Should Not Exist', @user_id = @OperatorId;
    IF EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144-NEW')
        RAISERROR('TEST FAILED: usp_create_section was not denied for operator.', 16, 1);

    EXEC locations.usp_update_section
        @section_code = 'RBAC-TEST-SEC-144', @section_name = 'Changed By Operator', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144' AND section_name = 'Original Section Name 144')
        RAISERROR('TEST FAILED: usp_update_section was not denied for operator.', 16, 1);

    EXEC locations.usp_deactivate_section
        @section_code = 'RBAC-TEST-SEC-144', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_deactivate_section was not denied for operator.', 16, 1);

    EXEC locations.usp_reactivate_section
        @section_code = 'RBAC-TEST-SEC-144-INACTIVE', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144-INACTIVE' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_reactivate_section was not denied for operator.', 16, 1);

    EXEC locations.usp_assign_bins_to_zone
        @zone_code = 'RBAC-TEST-ZONE-144', @bin_codes_json = '["RBAC-TEST-BIN-144"]', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-144' AND zone_id IS NULL)
        RAISERROR('TEST FAILED: usp_assign_bins_to_zone was not denied for operator.', 16, 1);

    EXEC locations.usp_assign_bins_to_section
        @section_code = 'RBAC-TEST-SEC-144', @bin_codes_json = '["RBAC-TEST-BIN-144"]', @user_id = @OperatorId;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-144' AND storage_section_id IS NULL)
        RAISERROR('TEST FAILED: usp_assign_bins_to_section was not denied for operator.', 16, 1);

    PRINT 'PASS: zones.manage denies operator on zone/section lifecycle and bin assignment.';

    ----------------------------------------------------------------
    -- GRANTED (admin) - same fixtures, now actually mutated
    ----------------------------------------------------------------
    EXEC locations.usp_create_zone
        @zone_code = 'RBAC-TEST-ZONE-144-NEW', @zone_name = 'Created By Admin', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144-NEW')
        RAISERROR('TEST FAILED: usp_create_zone did not go through for admin.', 16, 1);

    EXEC locations.usp_update_zone
        @zone_code = 'RBAC-TEST-ZONE-144', @zone_name = 'Changed By Admin', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144' AND zone_name = 'Changed By Admin')
        RAISERROR('TEST FAILED: usp_update_zone did not go through for admin.', 16, 1);

    EXEC locations.usp_deactivate_zone
        @zone_code = 'RBAC-TEST-ZONE-144', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_deactivate_zone did not go through for admin.', 16, 1);

    EXEC locations.usp_reactivate_zone
        @zone_code = 'RBAC-TEST-ZONE-144-INACTIVE', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = 'RBAC-TEST-ZONE-144-INACTIVE' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_reactivate_zone did not go through for admin.', 16, 1);

    EXEC locations.usp_create_section
        @section_code = 'RBAC-TEST-SEC-144-NEW', @section_name = 'Created By Admin', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144-NEW')
        RAISERROR('TEST FAILED: usp_create_section did not go through for admin.', 16, 1);

    EXEC locations.usp_update_section
        @section_code = 'RBAC-TEST-SEC-144', @section_name = 'Changed By Admin', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144' AND section_name = 'Changed By Admin')
        RAISERROR('TEST FAILED: usp_update_section did not go through for admin.', 16, 1);

    EXEC locations.usp_deactivate_section
        @section_code = 'RBAC-TEST-SEC-144', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144' AND is_active = 0)
        RAISERROR('TEST FAILED: usp_deactivate_section did not go through for admin.', 16, 1);

    EXEC locations.usp_reactivate_section
        @section_code = 'RBAC-TEST-SEC-144-INACTIVE', @user_id = @AdminId;
    IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'RBAC-TEST-SEC-144-INACTIVE' AND is_active = 1)
        RAISERROR('TEST FAILED: usp_reactivate_section did not go through for admin.', 16, 1);

    EXEC locations.usp_assign_bins_to_zone
        @zone_code = 'RBAC-TEST-ZONE-144-NEW', @bin_codes_json = '["RBAC-TEST-BIN-144"]', @user_id = @AdminId;
    IF NOT EXISTS (
        SELECT 1 FROM locations.bins b
        JOIN locations.zones z ON z.zone_id = b.zone_id
        WHERE b.bin_code = 'RBAC-TEST-BIN-144' AND z.zone_code = 'RBAC-TEST-ZONE-144-NEW'
    )
        RAISERROR('TEST FAILED: usp_assign_bins_to_zone did not go through for admin.', 16, 1);

    EXEC locations.usp_assign_bins_to_section
        @section_code = 'RBAC-TEST-SEC-144-NEW', @bin_codes_json = '["RBAC-TEST-BIN-144"]', @user_id = @AdminId;
    IF NOT EXISTS (
        SELECT 1 FROM locations.bins b
        JOIN locations.storage_sections s ON s.storage_section_id = b.storage_section_id
        WHERE b.bin_code = 'RBAC-TEST-BIN-144' AND s.section_code = 'RBAC-TEST-SEC-144-NEW'
    )
        RAISERROR('TEST FAILED: usp_assign_bins_to_section did not go through for admin.', 16, 1);

    PRINT 'TEST PASSED: zones.manage lifecycle and bin-assignment guard confirmed for operator (denied) and admin (granted).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-144';
    DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-144';
    DELETE FROM locations.zones WHERE zone_code IN ('RBAC-TEST-ZONE-144', 'RBAC-TEST-ZONE-144-INACTIVE', 'RBAC-TEST-ZONE-144-NEW');
    DELETE FROM locations.storage_sections WHERE section_code IN ('RBAC-TEST-SEC-144', 'RBAC-TEST-SEC-144-INACTIVE', 'RBAC-TEST-SEC-144-NEW');
    DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
    DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM locations.bins WHERE bin_code = 'RBAC-TEST-BIN-144';
DELETE FROM locations.storage_types WHERE storage_type_code = 'RBAC-TEST-STYPE-144';
DELETE FROM locations.zones WHERE zone_code IN ('RBAC-TEST-ZONE-144', 'RBAC-TEST-ZONE-144-INACTIVE', 'RBAC-TEST-ZONE-144-NEW');
DELETE FROM locations.storage_sections WHERE section_code IN ('RBAC-TEST-SEC-144', 'RBAC-TEST-SEC-144-INACTIVE', 'RBAC-TEST-SEC-144-NEW');
DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
GO

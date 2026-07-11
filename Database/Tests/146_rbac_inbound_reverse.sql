-- ==========================================================
-- TEST: RBAC coverage - inbound.reverse
-- Builds one real, reversible receipt through the actual business
-- procs (same pattern as 132_batch_required_receive.sql: party ->
-- address -> bin -> SKU -> delivery -> line -> usp_activate_inbound
-- -> usp_receive_inbound_line), then tries to reverse it as an
-- operator (must be denied, receipt stays open) followed by an
-- admin (must succeed) on that SAME receipt - denial leaves it
-- reversible, so one fixture covers both halves.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous failed run.
DECLARE @preUid INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-146');
IF @preUid IS NOT NULL
BEGIN
    DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @preUid;
    DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @preUid;
    DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @preUid;
    DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @preUid;
END
DELETE FROM inbound.inbound_lines      WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146');
DELETE FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146';
DELETE FROM inventory.skus             WHERE sku_code    = 'RBAC-TEST-SKU-146';
DELETE FROM locations.bins             WHERE bin_code    = 'RBAC-TEST-BAY-146';
DELETE FROM locations.storage_types    WHERE storage_type_code = 'RBAC-TEST-STYPE-146';
DECLARE @prePartyId INT = (SELECT party_id FROM core.parties WHERE party_code = '_RBAC146-SUPP');
IF @prePartyId IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @prePartyId;
DELETE FROM audit.party_changes WHERE details LIKE '%[_]RBAC146-SUPP%' ESCAPE '[';
DELETE FROM core.party_addresses WHERE party_id IN (SELECT party_id FROM core.parties WHERE party_code = '_RBAC146-SUPP');
DELETE FROM core.parties         WHERE party_code = '_RBAC146-SUPP';
DELETE FROM auth.users WHERE username IN ('rbac_test_operator_146', 'rbac_test_admin_146');
GO

DECLARE @OperatorId INT;
DECLARE @AdminId INT;
DECLARE @ReceiptId INT;

BEGIN TRY

    DECLARE @OperatorRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    DECLARE @AdminRoleId    INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_operator_146', 'RBAC Test Operator 146', 'rbac_test_operator_146@pw.local', 0x00, 1);
    SET @OperatorId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@OperatorId, @OperatorRoleId);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('rbac_test_admin_146', 'RBAC Test Admin 146', 'rbac_test_admin_146@pw.local', 0x00, 1);
    SET @AdminId = SCOPE_IDENTITY();
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@AdminId, @AdminRoleId);

    -- Minimal supplier + address
    DECLARE @SupplierId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_RBAC146-SUPP', 'RBAC Test Supplier', 'RBAC Test Supplier', 'GB', 1, SYSUTCDATETIME());
    SET @SupplierId = SCOPE_IDENTITY();

    DECLARE @AddrId INT;
    INSERT INTO core.party_addresses
        (party_id, address_type, line_1, city, postal_code, country_code, is_primary, is_active, created_at)
    VALUES (@SupplierId, 'WAREHOUSE', '1 RBAC Test St', 'Test City', 'T1 1TT', 'GB', 1, 1, SYSUTCDATETIME());
    SET @AddrId = SCOPE_IDENTITY();

    -- Own storage type + staging bin (avoids depending on demo seed data)
    DECLARE @StypeId INT;
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
    VALUES ('RBAC-TEST-STYPE-146', 'RBAC Test Type 146', @AdminId);
    SET @StypeId = SCOPE_IDENTITY();

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES ('RBAC-TEST-BAY-146', @StypeId, 999, 1, @AdminId);

    -- SKU (not batch-required, so manual receive needs no batch number)
    DECLARE @SkuId INT;
    INSERT INTO inventory.skus (sku_code, sku_description, uom_code, preferred_storage_type_id, created_by)
    VALUES ('RBAC-TEST-SKU-146', 'RBAC Test SKU 146', 'EA', @StypeId, @AdminId);
    SET @SkuId = SCOPE_IDENTITY();

    -- Inbound header + line (EXP -> add line -> activate, manual mode)
    DECLARE @InbId INT;
    INSERT INTO inbound.inbound_deliveries
        (inbound_ref, supplier_party_id, owner_party_id, ship_to_address_id,
         inbound_status_code, expected_arrival_at, created_by)
    VALUES ('RBAC-TEST-INB-146', @SupplierId, @SupplierId, @AddrId, 'EXP', SYSUTCDATETIME(), @AdminId);
    SET @InbId = SCOPE_IDENTITY();

    DECLARE @LineId INT;
    INSERT INTO inbound.inbound_lines
        (inbound_id, line_no, sku_id, expected_qty, received_qty, line_state_code, created_by)
    VALUES (@InbId, 1, @SkuId, 10, 0, 'EXP', @AdminId);
    SET @LineId = SCOPE_IDENTITY();

    EXEC inbound.usp_activate_inbound @inbound_id = @InbId, @user_id = @AdminId;

    -- Receive (this SP is not RBAC-guarded; actor choice here is just
    -- for audit attribution of the fixture setup itself)
    EXEC inbound.usp_receive_inbound_line
        @inbound_line_id  = @LineId,
        @received_qty     = 10,
        @staging_bin_code = 'RBAC-TEST-BAY-146',
        @external_ref     = 'RBAC-TEST-SSCC-146',
        @best_before_date = '2027-01-01',
        @user_id          = @AdminId;

    DECLARE @UnitId INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-146');
    IF @UnitId IS NULL
        RAISERROR('TEST SETUP FAILED: fixture receipt was not created.', 16, 1);

    SET @ReceiptId = (SELECT receipt_id FROM inbound.inbound_receipts WHERE inventory_unit_id = @UnitId AND is_reversal = 0);
    IF @ReceiptId IS NULL
        RAISERROR('TEST SETUP FAILED: could not resolve receipt_id for fixture.', 16, 1);

    ----------------------------------------------------------------
    -- DENIED (operator) - receipt must stay open
    ----------------------------------------------------------------
    EXEC inbound.usp_reverse_inbound_receipt
        @receipt_id = @ReceiptId, @reason_code = 'MAN', @reason_text = 'RBAC test - should be denied',
        @user_id = @OperatorId;

    IF EXISTS (SELECT 1 FROM inventory.inventory_units WHERE inventory_unit_id = @UnitId AND stock_state_code = 'REV')
        RAISERROR('TEST FAILED: usp_reverse_inbound_receipt was not denied for operator.', 16, 1);

    PRINT 'PASS: inbound.reverse denies operator.';

    ----------------------------------------------------------------
    -- GRANTED (admin) - same receipt, now actually reversed
    ----------------------------------------------------------------
    EXEC inbound.usp_reverse_inbound_receipt
        @receipt_id = @ReceiptId, @reason_code = 'MAN', @reason_text = 'RBAC test - should succeed',
        @user_id = @AdminId;

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_units WHERE inventory_unit_id = @UnitId AND stock_state_code = 'REV')
        RAISERROR('TEST FAILED: usp_reverse_inbound_receipt did not go through for admin.', 16, 1);

    PRINT 'TEST PASSED: inbound.reverse guard confirmed for operator (denied) and admin (granted).';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DECLARE @uidCatch INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-146');
    IF @uidCatch IS NOT NULL
    BEGIN
        DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @uidCatch;
        DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @uidCatch;
        DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @uidCatch;
        DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @uidCatch;
    END
    DELETE FROM inbound.inbound_lines      WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146');
    DELETE FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146';
    DELETE FROM inventory.skus             WHERE sku_code    = 'RBAC-TEST-SKU-146';
    DELETE FROM locations.bins             WHERE bin_code    = 'RBAC-TEST-BAY-146';
    DELETE FROM locations.storage_types    WHERE storage_type_code = 'RBAC-TEST-STYPE-146';
    DECLARE @suppIdCatch INT = (SELECT party_id FROM core.parties WHERE party_code = '_RBAC146-SUPP');
    IF @suppIdCatch IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppIdCatch;
    DELETE FROM core.party_addresses WHERE party_id = @suppIdCatch;
    DELETE FROM core.parties WHERE party_code = '_RBAC146-SUPP';
    DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
    DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DECLARE @uidPost INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'RBAC-TEST-SSCC-146');
IF @uidPost IS NOT NULL
BEGIN
    DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @uidPost;
    DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @uidPost;
    DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @uidPost;
    DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @uidPost;
END
DELETE FROM inbound.inbound_lines      WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146');
DELETE FROM inbound.inbound_deliveries WHERE inbound_ref = 'RBAC-TEST-INB-146';
DELETE FROM inventory.skus             WHERE sku_code    = 'RBAC-TEST-SKU-146';
DELETE FROM locations.bins             WHERE bin_code    = 'RBAC-TEST-BAY-146';
DELETE FROM locations.storage_types    WHERE storage_type_code = 'RBAC-TEST-STYPE-146';
DECLARE @suppIdPost INT = (SELECT party_id FROM core.parties WHERE party_code = '_RBAC146-SUPP');
IF @suppIdPost IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppIdPost;
DELETE FROM core.party_addresses WHERE party_id = @suppIdPost;
DELETE FROM core.parties WHERE party_code = '_RBAC146-SUPP';
DELETE FROM auth.user_roles WHERE user_id IN (@OperatorId, @AdminId);
DELETE FROM auth.users WHERE id IN (@OperatorId, @AdminId);
GO

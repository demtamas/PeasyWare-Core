-- ==========================================================
-- TEST: usp_create_expected_unit — batch required guard (ERRINBU02)
-- Verifies:
--   1. Creating an expected unit for a batch-required SKU without a
--      batch number is blocked (ERRINBU02) — unit not created
--   2. Creating the same expected unit WITH a batch number succeeds
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from previous failed runs
DISABLE TRIGGER core.tr_parties_audit ON core.parties;
DELETE FROM inbound.inbound_expected_units WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB'));
DELETE FROM inbound.inbound_lines          WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB');
DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref = 'TEU-INB';
DELETE FROM inventory.skus                 WHERE sku_code    = 'TEU-SKU';
DECLARE @preCleanId2 INT = (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
IF @preCleanId2 IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @preCleanId2;
DELETE FROM core.party_addresses WHERE party_id IN (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
DELETE FROM core.parties         WHERE party_code = '_TEU-SUPP';
ENABLE TRIGGER core.tr_parties_audit ON core.parties;
GO

BEGIN TRY

    DECLARE @UserId    INT              = (SELECT id FROM auth.users WHERE username = 'admin');
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');

    -- ── Minimal test supplier + address (no demo parties required) ──
    DECLARE @SupplierId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_TEU-SUPP', 'Test Supplier EU', 'Test Supplier', 'GB', 1, SYSUTCDATETIME());
    SET @SupplierId = SCOPE_IDENTITY();

    DECLARE @AddrId INT;
    INSERT INTO core.party_addresses
        (party_id, address_type, line_1, city, postal_code, country_code, is_primary, is_active, created_at)
    VALUES (@SupplierId, 'WAREHOUSE', '1 Test St', 'Test City', 'T1 1TT', 'GB', 1, 1, SYSUTCDATETIME());
    SET @AddrId = SCOPE_IDENTITY();

    -- Batch-required SKU (explicit EAN to avoid NULL unique collision)
    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, preferred_storage_type_id, is_batch_required, is_active)
    VALUES ('TEU-SKU', 'Expected Unit Test SKU', '09999999990002', 'Case', @RackTypeId, 1, 1);

    -- Inbound header (EXP — must be in EXP to add lines/expected units)
    DECLARE @InbId INT;
    INSERT INTO inbound.inbound_deliveries
        (inbound_ref, supplier_party_id, owner_party_id, ship_to_address_id,
         inbound_status_code, expected_arrival_at, created_by)
    VALUES ('TEU-INB', @SupplierId, @SupplierId, @AddrId, 'EXP', SYSUTCDATETIME(), @UserId);
    SET @InbId = SCOPE_IDENTITY();

    -- Inbound line
    INSERT INTO inbound.inbound_lines
        (inbound_id, line_no, sku_id, expected_qty, received_qty, line_state_code, created_by)
    VALUES (
        @InbId, 1,
        (SELECT sku_id FROM inventory.skus WHERE sku_code = 'TEU-SKU'),
        100, 0, 'EXP', @UserId
    );

    -- ── 1. No batch — must be blocked (ERRINBU02), no row created ──
    EXEC inbound.usp_create_expected_unit
        @inbound_ref      = 'TEU-INB',
        @sscc             = 'TEU-SSCC-01',
        @quantity         = 60,
        @batch_number     = NULL,
        @best_before_date = '2027-01-01',
        @user_id          = @UserId,
        @session_id       = @SessionId;

    IF EXISTS (
        SELECT 1 FROM inbound.inbound_expected_units
        WHERE expected_external_ref = 'TEU-SSCC-01'
    )
        RAISERROR('TEST FAILED: expected unit must NOT be created without batch when SKU is batch-required (ERRINBU02).', 16, 1);

    -- ── 2. With batch — must succeed ─────────────────────────────
    EXEC inbound.usp_create_expected_unit
        @inbound_ref      = 'TEU-INB',
        @sscc             = 'TEU-SSCC-01',
        @quantity         = 60,
        @batch_number     = 'TEU-BATCH-001',
        @best_before_date = '2027-01-01',
        @user_id          = @UserId,
        @session_id       = @SessionId;

    IF NOT EXISTS (
        SELECT 1 FROM inbound.inbound_expected_units
        WHERE expected_external_ref = 'TEU-SSCC-01' AND batch_number = 'TEU-BATCH-001'
    )
        RAISERROR('TEST FAILED: expected unit must be created when batch is provided.', 16, 1);

    PRINT 'TEST PASSED: usp_create_expected_unit — ERRINBU02 batch guard, success with batch.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DELETE FROM inbound.inbound_expected_units WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB'));
    DELETE FROM inbound.inbound_lines          WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB');
    DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref  = 'TEU-INB';
    DELETE FROM inventory.skus                 WHERE sku_code     = 'TEU-SKU';
    DECLARE @suppId3 INT = (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
    IF @suppId3 IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppId3;
    DISABLE TRIGGER core.tr_parties_audit ON core.parties;
    DELETE FROM core.party_addresses           WHERE party_id     = (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
    DELETE FROM core.parties                   WHERE party_code   = '_TEU-SUPP';
    ENABLE TRIGGER core.tr_parties_audit ON core.parties;
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DELETE FROM inbound.inbound_expected_units WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB'));
DELETE FROM inbound.inbound_lines          WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TEU-INB');
DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref  = 'TEU-INB';
DELETE FROM inventory.skus                 WHERE sku_code     = 'TEU-SKU';
DECLARE @suppId4 INT = (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
IF @suppId4 IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppId4;
DISABLE TRIGGER core.tr_parties_audit ON core.parties;
DELETE FROM core.party_addresses           WHERE party_id     = (SELECT party_id FROM core.parties WHERE party_code = '_TEU-SUPP');
DELETE FROM core.parties                   WHERE party_code   = '_TEU-SUPP';
ENABLE TRIGGER core.tr_parties_audit ON core.parties;
GO

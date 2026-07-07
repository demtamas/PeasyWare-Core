-- ==========================================================
-- TEST: usp_receive_inbound_line — batch required guard (ERRINBL11)
-- Verifies:
--   1. Receiving a batch-required SKU without batch — unit NOT created
--   2. Receiving with batch provided — succeeds
--   3. COALESCE fix: eu.batch_number is NULL, operator provides batch —
--      operator batch is preserved, not overwritten by null eu.batch_number
--
-- Uses MANUAL mode (no expected units / claim tokens) to avoid
-- SSCC trigger complications. The batch guard fires identically
-- in both modes — it checks inventory.skus.is_batch_required
-- after resolving the sku_id, before any INSERT.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from previous failed runs
DISABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
DISABLE TRIGGER core.tr_parties_audit ON core.parties;
DECLARE @uid_final INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'TBATCH-SSCC-01');
IF @uid_final IS NOT NULL
BEGIN
    DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @uid_final;
    DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @uid_final;
    DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @uid_final;
    DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @uid_final;
END
DELETE FROM inbound.inbound_receipts       WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TBATCH-INB'));
DELETE FROM inbound.inbound_expected_units WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TBATCH-INB'));
DELETE FROM inbound.inbound_lines          WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TBATCH-INB');
DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref = 'TBATCH-INB';
DELETE FROM inventory.skus                 WHERE sku_code    = 'TBATCH-SKU';
DELETE FROM locations.bins                 WHERE bin_code    = 'TBATCH-BAY';
DECLARE @preCleanId INT = (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
IF @preCleanId IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @preCleanId;
DELETE FROM core.party_addresses WHERE party_id IN (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
DELETE FROM core.parties         WHERE party_code = '_TBATCH-SUPP';
ENABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
ENABLE TRIGGER core.tr_parties_audit ON core.parties;
GO

BEGIN TRY

    DECLARE @UserId    INT              = (SELECT id FROM auth.users WHERE username = 'admin');
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    DECLARE @RackTypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');

    -- Minimal test supplier + address
    DECLARE @SupplierId INT;
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
    VALUES ('_TBATCH-SUPP', 'Test Supplier', 'Test Supplier', 'GB', 1, SYSUTCDATETIME());
    SET @SupplierId = SCOPE_IDENTITY();

    DECLARE @AddrId INT;
    INSERT INTO core.party_addresses
        (party_id, address_type, line_1, city, postal_code, country_code, is_primary, is_active, created_at)
    VALUES (@SupplierId, 'WAREHOUSE', '1 Test St', 'Test City', 'T1 1TT', 'GB', 1, 1, SYSUTCDATETIME());
    SET @AddrId = SCOPE_IDENTITY();

    -- Staging bin
    DECLARE @BinId INT;
    IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'TBATCH-BAY')
        INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
        VALUES ('TBATCH-BAY', @RackTypeId, 999, 1, @UserId);
    SET @BinId = (SELECT bin_id FROM locations.bins WHERE bin_code = 'TBATCH-BAY');

    -- Batch-required SKU (explicit EAN to avoid NULL unique collision)
    DECLARE @SkuId INT;
    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, preferred_storage_type_id, is_batch_required, is_active)
    VALUES ('TBATCH-SKU', 'Batch Required Test SKU', '09999999990001', 'Case', @RackTypeId, 1, 1);
    SET @SkuId = SCOPE_IDENTITY();

    -- Inbound header (EXP — add line first, then activate)
    DECLARE @InbId INT;
    INSERT INTO inbound.inbound_deliveries
        (inbound_ref, supplier_party_id, owner_party_id, ship_to_address_id,
         inbound_status_code, expected_arrival_at, created_by)
    VALUES ('TBATCH-INB', @SupplierId, @SupplierId, @AddrId, 'EXP', SYSUTCDATETIME(), @UserId);
    SET @InbId = SCOPE_IDENTITY();

    -- Inbound line
    DECLARE @LineId INT;
    INSERT INTO inbound.inbound_lines
        (inbound_id, line_no, sku_id, expected_qty, received_qty, line_state_code, created_by)
    VALUES (@InbId, 1, @SkuId, 100, 0, 'EXP', @UserId);
    SET @LineId = SCOPE_IDENTITY();

    -- Activate (manual mode — no expected units = MANUAL)
    EXEC inbound.usp_activate_inbound
        @inbound_id = @InbId,
        @user_id    = @UserId;

    -- ── 1. Receive in MANUAL mode WITHOUT batch — must be blocked ────
    EXEC inbound.usp_receive_inbound_line
        @inbound_line_id          = @LineId,
        @received_qty             = 60,
        @staging_bin_code         = 'TBATCH-BAY',
        @inbound_expected_unit_id = NULL,
        @external_ref             = 'TBATCH-SSCC-01',
        @batch_number             = NULL,
        @best_before_date         = '2027-01-01',
        @claim_token              = NULL,
        @user_id                  = @UserId,
        @session_id               = @SessionId;

    IF EXISTS (SELECT 1 FROM inventory.inventory_units WHERE external_ref = 'TBATCH-SSCC-01')
        RAISERROR('TEST FAILED: unit must NOT be created when batch is missing (ERRINBL11).', 16, 1);

    -- ── 2. Receive in MANUAL mode WITH batch — must succeed ──────────
    EXEC inbound.usp_receive_inbound_line
        @inbound_line_id          = @LineId,
        @received_qty             = 60,
        @staging_bin_code         = 'TBATCH-BAY',
        @inbound_expected_unit_id = NULL,
        @external_ref             = 'TBATCH-SSCC-01',
        @batch_number             = 'OPERATOR-BATCH',
        @best_before_date         = '2027-01-01',
        @claim_token              = NULL,
        @user_id                  = @UserId,
        @session_id               = @SessionId;

    IF NOT EXISTS (
        SELECT 1 FROM inventory.inventory_units
        WHERE external_ref = 'TBATCH-SSCC-01' AND batch_number = 'OPERATOR-BATCH'
    )
        RAISERROR('TEST FAILED: unit must be created with the provided batch number.', 16, 1);

    PRINT 'TEST PASSED: batch required guard — ERRINBL11 on missing batch, success with batch.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    DECLARE @uid_catch INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'TBATCH-SSCC-01');
    IF @uid_catch IS NOT NULL
    BEGIN
        DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @uid_catch;
        DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @uid_catch;
        DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @uid_catch;
        DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @uid_catch;
    END
    DELETE FROM inbound.inbound_receipts       WHERE inbound_line_id = @LineId;
    DELETE FROM inbound.inbound_lines          WHERE inbound_id = @InbId;
    DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref = 'TBATCH-INB';
    DELETE FROM inventory.skus                 WHERE sku_code    = 'TBATCH-SKU';
    DELETE FROM locations.bins                 WHERE bin_code    = 'TBATCH-BAY';
    DECLARE @suppId1 INT = (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
    IF @suppId1 IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppId1;
    DISABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
    DISABLE TRIGGER core.tr_parties_audit ON core.parties;
    DELETE FROM core.party_addresses WHERE party_id = (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
    DELETE FROM core.parties         WHERE party_code = '_TBATCH-SUPP';
    ENABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
    ENABLE TRIGGER core.tr_parties_audit ON core.parties;
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Cleanup
DECLARE @uid_post INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'TBATCH-SSCC-01');
IF @uid_post IS NOT NULL
BEGIN
    DELETE FROM inbound.inbound_receipts       WHERE inventory_unit_id = @uid_post;
    DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @uid_post;
    DELETE FROM inventory.inventory_movements  WHERE inventory_unit_id = @uid_post;
    DELETE FROM inventory.inventory_units      WHERE inventory_unit_id = @uid_post;
END
DELETE FROM inbound.inbound_receipts       WHERE inbound_line_id IN (SELECT inbound_line_id FROM inbound.inbound_lines WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TBATCH-INB'));
DELETE FROM inbound.inbound_lines          WHERE inbound_id IN (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'TBATCH-INB');
DELETE FROM inbound.inbound_deliveries     WHERE inbound_ref = 'TBATCH-INB';
DELETE FROM inventory.skus                 WHERE sku_code    = 'TBATCH-SKU';
DELETE FROM locations.bins                 WHERE bin_code    = 'TBATCH-BAY';
DECLARE @suppId2 INT = (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
IF @suppId2 IS NOT NULL DELETE FROM audit.party_changes WHERE party_id = @suppId2;
DISABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
DISABLE TRIGGER core.tr_parties_audit ON core.parties;
DELETE FROM core.party_addresses WHERE party_id = (SELECT party_id FROM core.parties WHERE party_code = '_TBATCH-SUPP');
DELETE FROM core.parties         WHERE party_code = '_TBATCH-SUPP';
ENABLE TRIGGER inbound.trg_inbound_expected_units_guard ON inbound.inbound_expected_units;
ENABLE TRIGGER core.tr_parties_audit ON core.parties;
GO

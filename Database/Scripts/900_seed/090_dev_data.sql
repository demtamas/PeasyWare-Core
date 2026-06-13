USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

-- ============================================================
-- DEV seed data: SKUs + Inbound deliveries + Expected units
-- Idempotent — safe to re-run after any reset.
-- ============================================================

DECLARE @AdminId INT = (SELECT id FROM auth.users WHERE username = 'admin');

-- ── SKUs ──────────────────────────────────────────────────────────────────
-- All SKUs are batch required.
-- Sections map to what the SettingsView shows: FLOOR / MID / TOP / (none).

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-001')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-001',
        @sku_description                = 'Pale Ale 500ml 24x1',
        @ean                            = '05010128502431',
        @uom_code                       = 'Case',
        @weight_per_unit                = 14400.000,
        @standard_hu_quantity           = 60,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'RACK',
        @preferred_storage_section_code = 'FLOOR',
        @user_id                        = @AdminId;

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-002')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-002',
        @sku_description                = 'Lager 330ml 24x1',
        @ean                            = '05010128502448',
        @uom_code                       = 'Case',
        @weight_per_unit                = 9600.000,
        @standard_hu_quantity           = 80,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'RACK',
        @preferred_storage_section_code = NULL,
        @user_id                        = @AdminId;

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-003')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-003',
        @sku_description                = 'Stout 440ml 24x1',
        @ean                            = '05010128502455',
        @uom_code                       = 'Case',
        @weight_per_unit                = 12800.000,
        @standard_hu_quantity           = 60,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'RACK',
        @preferred_storage_section_code = 'MID',
        @user_id                        = @AdminId;

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-004')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-004',
        @sku_description                = 'IPA 330ml 12x1',
        @ean                            = '05010128502462',
        @uom_code                       = 'Case',
        @weight_per_unit                = 5200.000,
        @standard_hu_quantity           = 100,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'RACK',
        @preferred_storage_section_code = NULL,
        @user_id                        = @AdminId;

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-005')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-005',
        @sku_description                = 'Cider 500ml 12x1',
        @ean                            = '05010128502479',
        @uom_code                       = 'Case',
        @weight_per_unit                = 7800.000,
        @standard_hu_quantity           = 80,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'RACK',
        @preferred_storage_section_code = 'TOP',
        @user_id                        = @AdminId;

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = 'PWS-006')
    EXEC inventory.usp_create_sku
        @sku_code                       = 'PWS-006',
        @sku_description                = 'Mineral Water 750ml 12x1',
        @ean                            = '05010128502486',
        @uom_code                       = 'Case',
        @weight_per_unit                = 10200.000,
        @standard_hu_quantity           = 100,
        @is_hazardous                   = 0,
        @is_batch_required              = 1,
        @preferred_storage_type_code    = 'BULK',
        @preferred_storage_section_code = NULL,
        @user_id                        = @AdminId;

PRINT 'SKUs done.';
GO

-- ── Inbound INB-2026-001 (Ales & Lager) ─────────────────────────────────
-- Lines: PWS-001 (300 units / 5 pallets), PWS-002 (160 / 2), PWS-003 (120 / 2)
-- All batch-required — each expected unit carries a batch number.

DECLARE @AdminId INT = (SELECT id FROM auth.users WHERE username = 'admin');

IF NOT EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = 'INB-2026-001')
BEGIN
    DECLARE @InbId1 INT;

    EXEC inbound.usp_create_inbound
        @inbound_ref         = 'INB-2026-001',
        @supplier_party_code = 'PW_BREWERY01',
        @haulier_party_code  = 'PW_HAULIER01',
        @expected_arrival_at = '2026-06-15 08:00:00',
        @user_id             = @AdminId;

    -- Line 1: PWS-001 Pale Ale, 300 units
    EXEC inbound.usp_create_inbound_line
        @inbound_ref  = 'INB-2026-001',
        @sku_code     = 'PWS-001',
        @expected_qty = 300,
        @user_id      = @AdminId;

    -- 5 pallets x 60 cases = 300
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-001', @sscc='340100000000000011', @quantity=60, @batch_number='B-PA-260601', @best_before_date='2026-12-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-001', @sscc='340100000000000012', @quantity=60, @batch_number='B-PA-260601', @best_before_date='2026-12-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-001', @sscc='340100000000000013', @quantity=60, @batch_number='B-PA-260601', @best_before_date='2026-12-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-001', @sscc='340100000000000014', @quantity=60, @batch_number='B-PA-260601', @best_before_date='2026-12-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-001', @sscc='340100000000000015', @quantity=60, @batch_number='B-PA-260601', @best_before_date='2026-12-01', @user_id=@AdminId;

    -- Line 2: PWS-002 Lager, 160 units
    EXEC inbound.usp_create_inbound_line
        @inbound_ref  = 'INB-2026-001',
        @sku_code     = 'PWS-002',
        @expected_qty = 160,
        @user_id      = @AdminId;

    -- 2 pallets x 80 cases = 160
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-002', @sscc='340100000000000021', @quantity=80, @batch_number='B-LG-260701', @best_before_date='2027-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sku_code='PWS-002', @sscc='340100000000000022', @quantity=80, @batch_number='B-LG-260701', @best_before_date='2027-01-01', @user_id=@AdminId;

    -- Line 3: PWS-003 Stout, 120 units
    EXEC inbound.usp_create_inbound_line
        @inbound_ref  = 'INB-2026-001',
        @sku_code     = 'PWS-003',
        @expected_qty = 120,
        @user_id      = @AdminId;

    -- 2 pallets x 60 cases = 120
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sscc='340100000000000031', @quantity=60, @batch_number='B-ST-260801', @best_before_date='2027-02-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-001', @sscc='340100000000000032', @quantity=60, @batch_number='B-ST-260801', @best_before_date='2027-02-01', @user_id=@AdminId;

    -- Activate
    SET @InbId1 = (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'INB-2026-001');
    EXEC inbound.usp_activate_inbound @inbound_id=@InbId1, @user_id=@AdminId;

    PRINT 'INB-2026-001 created and activated (9 SSCCs).';
END
ELSE PRINT 'INB-2026-001 already exists.';
GO

-- ── Inbound INB-2026-002 (Mineral Water) ─────────────────────────────────
-- Line: PWS-006 (600 units / 6 pallets x 100)
-- Batch required — each expected unit carries the same batch number.

DECLARE @AdminId INT = (SELECT id FROM auth.users WHERE username = 'admin');

IF NOT EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = 'INB-2026-002')
BEGIN
    DECLARE @InbId2 INT;

    EXEC inbound.usp_create_inbound
        @inbound_ref         = 'INB-2026-002',
        @supplier_party_code = 'PW_BREWERY01',
        @haulier_party_code  = 'PW_HAULIER02',
        @expected_arrival_at = '2026-06-16 09:00:00',
        @user_id             = @AdminId;

    -- Line 1: PWS-006 Mineral Water, 600 units
    EXEC inbound.usp_create_inbound_line
        @inbound_ref  = 'INB-2026-002',
        @sku_code     = 'PWS-006',
        @expected_qty = 600,
        @user_id      = @AdminId;

    -- 6 pallets x 100 cases = 600, all same batch
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000071', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000072', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000073', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000074', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000075', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;
    EXEC inbound.usp_create_expected_unit @inbound_ref='INB-2026-002', @sscc='340100000000000076', @quantity=100, @batch_number='B-MW-260101', @best_before_date='2028-01-01', @user_id=@AdminId;

    -- Activate
    SET @InbId2 = (SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = 'INB-2026-002');
    EXEC inbound.usp_activate_inbound @inbound_id=@InbId2, @user_id=@AdminId;

    PRINT 'INB-2026-002 created and activated (6 SSCCs, batch B-MW-260101).';
END
ELSE PRINT 'INB-2026-002 already exists.';
GO

SET NOCOUNT OFF;
GO
PRINT 'Dev data seed complete.';
GO

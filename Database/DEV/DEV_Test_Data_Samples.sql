USE PW_Core_DEV;
GO

/********************************************************************************************
    PW Core — Minimal Test Data
    ----------------------------
    Stripped to bare minimum for API development and label testing.

    Covers:
      - 1 test SKU (real Britvic label format)
      - 2 inbounds: 1 SSCC pre-advised, 1 manual (blind)
      - 3 outbound orders
      - 2 shipments: 1 single-order, 1 two-order

    Roles, users, parties, locations, and SKUs are seeded here.
    Further test data will be inserted via API once available.
********************************************************************************************/

PRINT '------------------------------------------------------------';
PRINT 'PW Core Test Data v2.0';
PRINT '------------------------------------------------------------';
GO

-- ============================================================
-- Auth: roles + admin user
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'admin')
BEGIN
    DECLARE @AdminRoleId INT;
    EXEC auth.usp_add_role
        @RoleName    = 'admin',
        @Description = 'System administrator',
        @CreatedBy   = @SystemUserId,
        @NewRoleId   = @AdminRoleId OUTPUT;
    PRINT 'Role admin created.';
END
ELSE PRINT 'Role admin already exists — skipped.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'manager')
BEGIN
    DECLARE @ManagerRoleId INT;
    EXEC auth.usp_add_role
        @RoleName    = 'manager',
        @Description = 'Manager with elevated access',
        @CreatedBy   = @SystemUserId,
        @NewRoleId   = @ManagerRoleId OUTPUT;
    PRINT 'Role manager created.';
END
ELSE PRINT 'Role manager already exists — skipped.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'operator')
BEGIN
    DECLARE @OperatorRoleId INT;
    EXEC auth.usp_add_role
        @RoleName    = 'operator',
        @Description = 'Operator with basic access',
        @CreatedBy   = @SystemUserId,
        @NewRoleId   = @OperatorRoleId OUTPUT;
    PRINT 'Role operator created.';
END
ELSE PRINT 'Role operator already exists — skipped.';

IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username = 'admin')
BEGIN
    EXEC auth.usp_create_user
        @username     = 'admin',
        @display_name = 'Wannabee WMS Engineer',
        @role_name    = 'admin',
        @email        = 'tamas.demjen@pw.local',
        @password     = 'admin0',
        @result_code  = NULL,
        @friendly_msg = NULL;
    PRINT 'User admin created.';
END
ELSE PRINT 'User admin already exists — skipped.';
GO

-- ============================================================
-- Parties
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_WAREHOUSE01')
BEGIN
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_WAREHOUSE01', 'Peasy WH', 'Dummy Own Place', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);
END

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_SUPPLIER')
BEGIN
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_SUPPLIER', 'Dummy Supplier PLC', 'Dummy Supplier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);
END

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_CUSTOMER')
BEGIN
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_CUSTOMER', 'Dummy Customer LTD', 'Dummy Customer', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);
END

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_HAULIER')
BEGIN
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_HAULIER', 'Dummy Haulage CORP', 'Dummy Haulier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);
END

DECLARE @Own        INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_WAREHOUSE01');
DECLARE @SupplierId INT = (SELECT party_id FROM core.parties WHERE party_code = 'DUMMY_SUPPLIER');
DECLARE @CustomerId INT = (SELECT party_id FROM core.parties WHERE party_code = 'DUMMY_CUSTOMER');
DECLARE @HaulierId  INT = (SELECT party_id FROM core.parties WHERE party_code = 'DUMMY_HAULIER');

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @Own AND role_code = 'WAREHOUSE')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@Own, 'WAREHOUSE', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @SupplierId AND role_code = 'SUPPLIER')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@SupplierId, 'SUPPLIER', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @CustomerId AND role_code = 'CUSTOMER')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@CustomerId, 'CUSTOMER', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @HaulierId AND role_code = 'HAULIER')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@HaulierId, 'HAULIER', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @Own)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, dock_info, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@Own, 'WAREHOUSE', '1 Peasy Ware Ind Est', 'Peasy', 'PW5 5PW', 'GB', NULL, 'Warehouse', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @SupplierId)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@SupplierId, 'YARD', '1 Dummy Logistics Park', 'Testville', 'TE5 7ST', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @CustomerId)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@CustomerId, 'YARD', '19 Dummy Logistics Park', 'Testvillage', 'TE6 7ST', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @HaulierId)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@HaulierId, 'YARD', '1 Dummy Logistics Park', 'Testing', 'TE7 7ST', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM customers.customers WHERE party_id = @CustomerId)
    INSERT INTO customers.customers (party_id, customer_type, default_delivery_days, preferred_haulier_id, allow_crossdock, created_at, created_by)
    VALUES (@CustomerId, 'RETAIL', 0, NULL, 0, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM suppliers.suppliers WHERE party_id = @SupplierId)
    INSERT INTO suppliers.suppliers (party_id, supplier_type, default_lead_days, preferred_haulier_id, created_at, created_by)
    VALUES (@SupplierId, 'OWNER', 0, NULL, SYSUTCDATETIME(), @SystemUserId);

PRINT 'Parties done.';
GO

-- ============================================================
-- Locations
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'STAGE')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('STAGE', 'Staging area', 'Inbound / outbound staging area', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RACK')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('RACK', 'Pallet racking', 'Standard pallet racking', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'BULK')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('BULK', 'Bulk storage', 'Bulk storage on the floor', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'BULK')
    INSERT INTO locations.storage_sections (section_code, section_name, description, is_active, created_at, created_by)
    VALUES ('BULK', 'Bulk', 'Floor level', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'FLOOR')
    INSERT INTO locations.storage_sections (section_code, section_name, description, is_active, created_at, created_by)
    VALUES ('FLOOR', 'Floor level', 'Racking floor level', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'MID')
    INSERT INTO locations.storage_sections (section_code, section_name, description, is_active, created_at, created_by)
    VALUES ('MID', 'Middle level(s)', 'Middle level', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = 'TOP')
    INSERT INTO locations.storage_sections (section_code, section_name, description, is_active, created_at, created_by)
    VALUES ('TOP', 'Top level', 'Top level', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = '1')
    INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by)
    VALUES ('1', 'Aisle 1', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = '2')
    INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by)
    VALUES ('2', 'Aisle 2', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = '3')
    INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by)
    VALUES ('3', 'Aisle 3', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = '4')
    INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by)
    VALUES ('4', 'Aisle 4', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

DECLARE @StageId    INT = (SELECT storage_type_id    FROM locations.storage_types    WHERE storage_type_code = 'STAGE');
DECLARE @RackId     INT = (SELECT storage_type_id    FROM locations.storage_types    WHERE storage_type_code = 'RACK');
DECLARE @BulkTypeId INT = (SELECT storage_type_id    FROM locations.storage_types    WHERE storage_type_code = 'BULK');
DECLARE @BulkSecId  INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'BULK');
DECLARE @FloorId    INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'FLOOR');
DECLARE @MidId      INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'MID');
DECLARE @TopId      INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'TOP');
DECLARE @Z1 INT = (SELECT zone_id FROM locations.zones WHERE zone_code = '1');
DECLARE @Z2 INT = (SELECT zone_id FROM locations.zones WHERE zone_code = '2');
DECLARE @Z3 INT = (SELECT zone_id FROM locations.zones WHERE zone_code = '3');
DECLARE @Z4 INT = (SELECT zone_id FROM locations.zones WHERE zone_code = '4');

-- Staging bays
IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY01')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY01', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY02')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY02', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId);

-- Bulk bins
IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BULK01')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BULK01', @BulkTypeId, @BulkSecId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BULK02')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BULK02', @BulkTypeId, @BulkSecId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId);

-- Rack bins — 8 bays x 4 levels (A=floor, B=mid, C=mid, D=top)
DECLARE @Bins TABLE (bin_code NVARCHAR(10), sec_id INT, zone_id INT);
INSERT INTO @Bins VALUES
    ('R0101A',@FloorId,@Z1),('R0101B',@MidId,@Z1),('R0101C',@MidId,@Z1),('R0101D',@TopId,@Z1),
    ('R0201A',@FloorId,@Z2),('R0201B',@MidId,@Z2),('R0201C',@MidId,@Z2),('R0201D',@TopId,@Z2),
    ('R0301A',@FloorId,@Z3),('R0301B',@MidId,@Z3),('R0301C',@MidId,@Z3),('R0301D',@TopId,@Z3),
    ('R0401A',@FloorId,@Z4),('R0401B',@MidId,@Z4),('R0401C',@MidId,@Z4),('R0401D',@TopId,@Z4),
    ('R0501A',@FloorId,@Z1),('R0501B',@MidId,@Z1),('R0501C',@MidId,@Z1),('R0501D',@TopId,@Z1),
    ('R0601A',@FloorId,@Z2),('R0601B',@MidId,@Z2),('R0601C',@MidId,@Z2),('R0601D',@TopId,@Z2),
    ('R0701A',@FloorId,@Z3),('R0701B',@MidId,@Z3),('R0701C',@MidId,@Z3),('R0701D',@TopId,@Z3),
    ('R0801A',@FloorId,@Z4),('R0801B',@MidId,@Z4),('R0801C',@MidId,@Z4),('R0801D',@TopId,@Z4);

INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
SELECT b.bin_code, @RackId, b.sec_id, b.zone_id, 1, 1, SYSUTCDATETIME(), @SystemUserId
FROM @Bins b
WHERE NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = b.bin_code);

PRINT 'Locations done.';
GO

-- ============================================================
-- SKUs
-- Seeding only the real Britvic SKU used in label testing.
-- Additional SKUs will be inserted via API.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @RackId  INT = (SELECT storage_type_id    FROM locations.storage_types    WHERE storage_type_code = 'RACK');
DECLARE @MidId   INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'MID');
DECLARE @TopId   INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'TOP');

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = '290812')
BEGIN
    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, weight_per_unit,
         standard_hu_quantity, is_full_hu_required,
         preferred_storage_type_id, preferred_storage_section_id,
         is_hazardous, is_active, created_at, created_by)
    VALUES
        ('290812', 'PEPSI MAX 2L PET X6 P2.19', '04062139024766',
         'Each', 700, 80, 0, @RackId, @MidId, 0, 1, SYSUTCDATETIME(), @SystemUserId);
    PRINT 'SKU 290812 created.';
END
ELSE PRINT 'SKU 290812 already exists — skipped.';

IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = '251130')
BEGIN
    INSERT INTO inventory.skus
        (sku_code, sku_description, ean, uom_code, weight_per_unit,
         standard_hu_quantity, is_full_hu_required,
         preferred_storage_type_id, preferred_storage_section_id,
         is_hazardous, is_active, created_at, created_by)
    VALUES
        ('251130', '7UP ZERO 330ML CAN MP18X1', '05010102322523',
         'Each', 800, 180, 0, @RackId, @TopId, 0, 1, SYSUTCDATETIME(), @SystemUserId);
    PRINT 'SKU 251130 created.';
END
ELSE PRINT 'SKU 251130 already exists — skipped.';
GO

-- ============================================================
-- Inbound 1 — SSCC pre-advised
-- 13 pallets of 290812, matching real Britvic label format
-- BBE: 31-01-2027, Batch: 001442331A
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SupplierId   INT = (SELECT party_id  FROM core.parties        WHERE party_code  = 'DUMMY_SUPPLIER');
DECLARE @HaulierId    INT = (SELECT party_id  FROM core.parties        WHERE party_code  = 'DUMMY_HAULIER');
DECLARE @OwnAddrId    INT = (SELECT address_id FROM core.party_addresses WHERE party_id  = (SELECT party_id FROM core.parties WHERE party_code = 'PW_WAREHOUSE01') AND is_primary = 1);
DECLARE @Sku290812    INT = (SELECT sku_id    FROM inventory.skus       WHERE sku_code   = '290812');

IF NOT EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = 'TESTINB01')
BEGIN
    INSERT INTO inbound.inbound_deliveries
        (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id,
         ship_to_address_id, expected_arrival_at, created_at, created_by)
    VALUES
        ('TESTINB01', @SupplierId, @SupplierId, @HaulierId,
         @OwnAddrId, DATEADD(DAY, 1, SYSUTCDATETIME()), SYSUTCDATETIME(), @SystemUserId);

    DECLARE @Inb1Id INT = SCOPE_IDENTITY();

    INSERT INTO inbound.inbound_lines
        (inbound_id, line_no, sku_id, expected_qty, received_qty,
         batch_number, best_before_date, created_at, created_by)
    VALUES
        (@Inb1Id, 10, @Sku290812, 1040, 0, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId);

    DECLARE @Inb1LineId INT = SCOPE_IDENTITY();

    -- 13 SSCCs matching real Britvic pallet label sequence
    INSERT INTO inbound.inbound_expected_units
        (inbound_line_id, expected_external_ref, expected_quantity,
         batch_number, best_before_date, created_at, created_by)
    VALUES
        (@Inb1LineId, '250101027140166844', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166851', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166868', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166875', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166882', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166899', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166905', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166912', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166929', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166936', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166943', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166950', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId),
        (@Inb1LineId, '250101027140166967', 80, '001442331A', '2026-12-31', SYSUTCDATETIME(), @SystemUserId);

    PRINT 'TESTINB01 created (SSCC pre-advised, 13 units).';
END
ELSE PRINT 'TESTINB01 already exists — skipped.';
GO

-- ============================================================
-- Inbound 2 — Manual (blind)
-- 5 pallets of 251130, no pre-advised units
-- Operator scans product + SSCC labels at receipt
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SupplierId   INT = (SELECT party_id  FROM core.parties         WHERE party_code = 'DUMMY_SUPPLIER');
DECLARE @HaulierId    INT = (SELECT party_id  FROM core.parties         WHERE party_code = 'DUMMY_HAULIER');
DECLARE @OwnAddrId    INT = (SELECT address_id FROM core.party_addresses WHERE party_id  = (SELECT party_id FROM core.parties WHERE party_code = 'PW_WAREHOUSE01') AND is_primary = 1);
DECLARE @Sku251130    INT = (SELECT sku_id    FROM inventory.skus        WHERE sku_code  = '251130');

IF NOT EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = 'TESTINB02')
BEGIN
    INSERT INTO inbound.inbound_deliveries
        (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id,
         ship_to_address_id, expected_arrival_at, created_at, created_by)
    VALUES
        ('TESTINB02', @SupplierId, @SupplierId, @HaulierId,
         @OwnAddrId, DATEADD(DAY, 1, SYSUTCDATETIME()), SYSUTCDATETIME(), @SystemUserId);

    DECLARE @Inb2Id INT = SCOPE_IDENTITY();

    INSERT INTO inbound.inbound_lines
        (inbound_id, line_no, sku_id, expected_qty, received_qty,
         batch_number, best_before_date, created_at, created_by)
    VALUES
        (@Inb2Id, 10, @Sku251130, 1080, 0, NULL, NULL, SYSUTCDATETIME(), @SystemUserId);

    PRINT 'TESTINB02 created (manual/blind, 600 units expected).';
END
ELSE PRINT 'TESTINB02 already exists — skipped.';
GO

-- ============================================================
-- Outbound orders + shipments
--
-- Order 1: 160 units 290812 (2 pallets), any batch
-- Order 2: 240 units 290812 (3 pallets), any batch
-- Order 3: 400 units 290812 (5 pallets), any batch
--
-- Shipment 1: carries Order 1 only
-- Shipment 2: carries Order 2 + Order 3
--
-- Run usp_allocate_order after stock is received and put away.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

-- Order 1
IF NOT EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = 'TESTORD01')
BEGIN
    DECLARE @Ord1Lines NVARCHAR(MAX) = N'[
        {"line_no":1,"sku_code":"290812","ordered_qty":160,
         "requested_batch":null,"requested_bbe":null,"notes":"2 pallets"}
    ]';
    EXEC outbound.usp_create_order
        @order_ref           = 'TESTORD01',
        @customer_party_code = 'DUMMY_CUSTOMER',
        @haulier_party_code  = 'DUMMY_HAULIER',
        @required_date       = '2027-06-30',
        @notes               = 'Test order 1 — 2 pallets 290812',
        @lines_json          = @Ord1Lines,
        @user_id             = @SystemUserId;
    PRINT 'TESTORD01 created.';
END
ELSE PRINT 'TESTORD01 already exists — skipped.';

-- Order 2
IF NOT EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = 'TESTORD02')
BEGIN
    DECLARE @Ord2Lines NVARCHAR(MAX) = N'[
        {"line_no":1,"sku_code":"290812","ordered_qty":240,
         "requested_batch":null,"requested_bbe":null,"notes":"3 pallets"}
    ]';
    EXEC outbound.usp_create_order
        @order_ref           = 'TESTORD02',
        @customer_party_code = 'DUMMY_CUSTOMER',
        @haulier_party_code  = 'DUMMY_HAULIER',
        @required_date       = '2027-06-30',
        @notes               = 'Test order 2 — 3 pallets 290812',
        @lines_json          = @Ord2Lines,
        @user_id             = @SystemUserId;
    PRINT 'TESTORD02 created.';
END
ELSE PRINT 'TESTORD02 already exists — skipped.';

-- Order 3
IF NOT EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = 'TESTORD03')
BEGIN
    DECLARE @Ord3Lines NVARCHAR(MAX) = N'[
        {"line_no":1,"sku_code":"290812","ordered_qty":400,
         "requested_batch":null,"requested_bbe":null,"notes":"5 pallets"}
    ]';
    EXEC outbound.usp_create_order
        @order_ref           = 'TESTORD03',
        @customer_party_code = 'DUMMY_CUSTOMER',
        @haulier_party_code  = 'DUMMY_HAULIER',
        @required_date       = '2027-06-30',
        @notes               = 'Test order 3 — 5 pallets 290812',
        @lines_json          = @Ord3Lines,
        @user_id             = @SystemUserId;
    PRINT 'TESTORD03 created.';
END
ELSE PRINT 'TESTORD03 already exists — skipped.';
GO

-- Shipments (separate batch — orders must exist first)
DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

-- Shipment 1: Order 1 only
IF NOT EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = 'TESTSHIP01')
BEGIN
    EXEC outbound.usp_create_shipment
        @shipment_ref       = 'TESTSHIP01',
        @haulier_party_code = 'DUMMY_HAULIER',
        @vehicle_ref        = 'TEST-VEH-01',
        @notes              = 'Test shipment 1 — single order',
        @user_id            = @SystemUserId;

    EXEC outbound.usp_add_order_to_shipment
        @shipment_ref = 'TESTSHIP01',
        @order_ref    = 'TESTORD01',
        @user_id      = @SystemUserId;

    PRINT 'TESTSHIP01 created — linked to TESTORD01.';
END
ELSE PRINT 'TESTSHIP01 already exists — skipped.';

-- Shipment 2: Orders 2 + 3
IF NOT EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = 'TESTSHIP02')
BEGIN
    EXEC outbound.usp_create_shipment
        @shipment_ref       = 'TESTSHIP02',
        @haulier_party_code = 'DUMMY_HAULIER',
        @vehicle_ref        = 'TEST-VEH-02',
        @notes              = 'Test shipment 2 — two orders',
        @user_id            = @SystemUserId;

    EXEC outbound.usp_add_order_to_shipment
        @shipment_ref = 'TESTSHIP02',
        @order_ref    = 'TESTORD02',
        @user_id      = @SystemUserId;

    EXEC outbound.usp_add_order_to_shipment
        @shipment_ref = 'TESTSHIP02',
        @order_ref    = 'TESTORD03',
        @user_id      = @SystemUserId;

    PRINT 'TESTSHIP02 created — linked to TESTORD02 + TESTORD03.';
END
ELSE PRINT 'TESTSHIP02 already exists — skipped.';
GO

PRINT '------------------------------------------------------------';
PRINT 'Test data load complete.';
PRINT '------------------------------------------------------------';
GO

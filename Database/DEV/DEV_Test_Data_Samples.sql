USE PW_Core_DEV;
GO

/********************************************************************************************
    IUTPUT
********************************************************************************************/
PRINT '------------------------------------------------------------';
PRINT 'PW Core Test Data Load v1.0';
PRINT '------------------------------------------------------------';

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @OutputId INT;

EXEC auth.usp_add_role 
    @RoleName = 'admin', 
    @Description = 'System administrator', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;

EXEC auth.usp_add_role 
    @RoleName = 'manager', 
    @Description = 'Manager with elevated access', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;

EXEC auth.usp_add_role 
    @RoleName = 'operator', 
    @Description = 'Operator with basic access', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;

EXEC auth.usp_create_user
    @username = 'admin',
    @display_name = 'Wannabee WMS Engineer',
    @role_name = 'admin',
    @email = 'tamas.demjen@pw.local',
    @password = 'admin0',
    @result_code = NULL,
    @friendly_msg = NULL;

/* ============================================================
   Seed: dummy supplier, customer, haulier, party
   ------------------------------------------------------------
   Minimal data to allow early testing without full population.
   ============================================================ */

INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by) VALUES
    ('PW_WAREHOUSE01', 'Peasy WH', 'Dummy Own Place', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('DUMMY_SUPPLIER', 'Dummy Supplier PLC', 'Dummy Supplier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('DUMMY_CUSTOMER', 'Dummy Customer LTD', 'Dummy Customer', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('DUMMY_HAULIER', 'Dummy Haulage CORP', 'Dummy Haulier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

    DECLARE @Own INT = (SELECT party_id FROM core.parties WHERE display_name = 'Dummy Own Place');
	DECLARE @SupplierId INT = (SELECT party_id FROM core.parties WHERE display_name = 'Dummy Supplier');
	DECLARE @CustomerId INT = (SELECT party_id FROM core.parties WHERE display_name = 'Dummy Customer');
	DECLARE @HaulierId INT = (SELECT party_id FROM core.parties WHERE display_name = 'Dummy Haulier');

INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by) VALUES
    (@Own, 'WAREHOUSE', SYSUTCDATETIME(), @SystemUserId),
	(@SupplierId, 'SUPPLIER', SYSUTCDATETIME(), @SystemUserId),
	(@CustomerId, 'CUSTOMER', SYSUTCDATETIME(), @SystemUserId),
	(@HaulierId, 'HAULIER', SYSUTCDATETIME(), @SystemUserId);

INSERT INTO core.party_addresses (party_id, address_type, line_1, line_2, city, region, postal_code, country_code, dock_info, instructions, is_primary, is_active, created_at, created_by) VALUES
    (@Own, 'WAREHOUSE', '1 Peasy Ware Ind Est', NULL, 'Peasy', NULL, 'PW5 5PW', 'GB', NULL, 'Warehouse', 1, 1, SYSUTCDATETIME(), @SystemUserId),
	(@SupplierId, 'YARD', '1 Dummy Logistics Park', NULL, 'Testville', NULL, 'TE5 7ST', 'GB', NULL, 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId),
	(@CustomerId, 'YARD', '19 Dummy Logistics Park', NULL, 'Testvillage', NULL, 'TE6 7ST', 'GB', NULL, 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId),
	(@HaulierId, 'YARD', '1 Dummy Logistics Park', NULL, 'Testing', NULL, 'TE7 7ST', 'GB', NULL, 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

INSERT INTO core.party_contacts (party_id, contact_role, contact_name, email, phone, is_primary, is_active, created_at, created_by) VALUES
	(@SupplierId, 'SUPPLIER', 'Dummy SUpplier Desk', 'transport@dummysupplier.local', '+44 0000 0001', 1, 1, SYSUTCDATETIME(), @SystemUserId),
	(@CustomerId, 'Customer', 'Dummy Customer Desk', 'contact@dummycustomer.local', '+44 0000 0002', 1, 1, SYSUTCDATETIME(), @SystemUserId),
	(@HaulierId, 'TRANSPORT', 'Dummy Transport Desk', 'admin@dummyhaulage.local', '+44 0000 0003', 1, 1, SYSUTCDATETIME(), @SystemUserId);

INSERT INTO customers.customers (party_id, customer_type, default_delivery_days, preferred_haulier_id, allow_crossdock, created_at, created_by) VALUES
	(@CustomerId, 'RETAIL', 0, NULL, 0, SYSUTCDATETIME(), @SystemUserId);

INSERT INTO suppliers.suppliers (party_id, supplier_type, default_lead_days, preferred_haulier_id, created_at, created_by) VALUES 
	(@SupplierId, 'OWNER', 0, NULL, SYSUTCDATETIME(), @SystemUserId);

/* ============================================================
   locations.**
   ============================================================ */
INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by) VALUES
	('STAGE', 'Staging area', 'Inbound / outbound staging area', 1, SYSUTCDATETIME(), @SystemUserId),
	('RACK', 'Pallet racking', 'Standard pallet racking', 1, SYSUTCDATETIME(), @SystemUserId),
	('BULK', 'Bulk storage', 'Bulk storage on the floor', 1, SYSUTCDATETIME(), @SystemUserId);

INSERT INTO locations.storage_sections (section_code, section_name, description, is_active, created_at, created_by) VALUES
	('BULK', 'Bulk', 'Floor level', 1, SYSUTCDATETIME(), @SystemUserId),
	('FLOOR', 'Floor level', 'Racking floor level', 1, SYSUTCDATETIME(), @SystemUserId),
	('MID', 'Middle level(s)', 'Middle level', 1, SYSUTCDATETIME(), @SystemUserId),
	('TOP', 'Top level', 'Top level', 1, SYSUTCDATETIME(), @SystemUserId);

INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by) VALUES
	('1', 'Aisle 1', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('2', 'Aisle 2', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('3', 'Aisle 3', NULL, 1, SYSUTCDATETIME(), @SystemUserId),
	('4', 'Aisle 4', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

DECLARE @StageId INT = (SELECT storage_type_id from locations.storage_types WHERE storage_type_code = 'STAGE');
DECLARE @RackId INT = (SELECT storage_type_id from locations.storage_types WHERE storage_type_code = 'RACK');
DECLARE @BulkId INT = (SELECT storage_type_id from locations.storage_types WHERE storage_type_code = 'BULK');

DECLARE @BulkSection INT = (SELECT storage_section_id from locations.storage_sections WHERE section_code = 'BULK');
DECLARE @FloorId INT = (SELECT storage_section_id from locations.storage_sections WHERE section_code = 'FLOOR');
DECLARE @MidId INT = (SELECT storage_section_id from locations.storage_sections WHERE section_code = 'MID');
DECLARE @TopId INT = (SELECT storage_section_id from locations.storage_sections WHERE section_code = 'TOP');

INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, notes, created_at, created_by) VALUES
	('BAY01', @StageId, @FloorId, NULL, 999, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('BAY02', @StageId, @FloorId, NULL, 999, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('BULK01', @BulkId, @BulkSection, NULL, 999, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('BULK02', @BulkId, @BulkSection, NULL, 999, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0101A', @RackId, @FloorId, 1, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0101B', @RackId, @MidId, 1, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0101C', @RackId, @MidId, 1, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0101D', @RackId, @TopId, 1, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0201A', @RackId, @FloorId, 2, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0201B', @RackId, @MidId, 2, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0201C', @RackId, @MidId, 2, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0201D', @RackId, @TopId, 2, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0301A', @RackId, @FloorId, 3, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0301B', @RackId, @MidId, 3, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0301C', @RackId, @MidId, 3, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0301D', @RackId, @TopId, 3, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0401A', @RackId, @FloorId, 4, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0401B', @RackId, @MidId, 4, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0401C', @RackId, @MidId, 4, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId),
	('R0401D', @RackId, @TopId, 4, 1, 1, NULL, SYSUTCDATETIME(), @SystemUserId);

/* ============================================================
   inventory.skus
   ============================================================ */
INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, weight_per_unit, standard_hu_quantity, is_full_hu_required, preferred_storage_type_id, preferred_storage_section_id, is_hazardous, is_active, created_at, created_by)
	VALUES
	('SKU001', 'First test SKU', '01234567899', 'UNIT', 600, 1, 0, @RackId, @FloorId, 0, 1, SYSUTCDATETIME(), @SystemUserId),
	('SKU002', 'Second test SKU', '11223344556',  'Each', 800, 120, 0, @RackId, @TopId, 0, 1, SYSUTCDATETIME(), @SystemUserId),
	('SKU003', 'Third test SKU', '55568998745', 'Each', 700, 80, 0, @RackId, @MidId, 0, 1, SYSUTCDATETIME(), @SystemUserId);


/* ============================================================
   Seed inbound header #1 (SSCC-based)
   ============================================================ */
DECLARE @Shipto INT = (SELECT address_id FROM core.party_addresses WHERE party_id = @Own);

INSERT INTO deliveries.inbound_deliveries (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id, ship_to_address_id, expected_arrival_at, created_at, created_by) VALUES
	('TESTINB001', @SupplierId, @SupplierId, @HaulierId, @Shipto, (SELECT DATEADD(day, 1, SYSUTCDATETIME())), SYSUTCDATETIME(), @SystemUserId),
	('TESTINB002', @SupplierId, @SupplierId, @HaulierId, @Shipto, (SELECT DATEADD(day, 1, SYSUTCDATETIME())), SYSUTCDATETIME(), @SystemUserId),
	('TESTINB003', @SupplierId, @SupplierId, @HaulierId, @Shipto, (SELECT DATEADD(day, 1, SYSUTCDATETIME())), SYSUTCDATETIME(), @SystemUserId);

INSERT INTO deliveries.inbound_lines (inbound_id, line_no, sku_id, expected_qty, received_qty, batch_number, best_before_date, created_at, created_by) VALUES
	((SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB001'), 10, (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU001'), 2, 0, 'SKU001BATCH', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
	((SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB002'), 10, (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU002'), 240, 0, 'SKU002BATCH', '2027-01-31', SYSUTCDATETIME(), @SystemUserId),
	((SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB002'), 20, (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU003'), 800, 0, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	((SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB003'), 10, (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU003'), 880, 0, 'SKU001BATCH', '2027-03-08', SYSUTCDATETIME(), @SystemUserId);

DECLARE @Line11 INT = (SELECT inbound_line_id FROM deliveries.inbound_lines WHERE inbound_id = (SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB001') AND sku_id = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU001'));
DECLARE @Line21 INT = (SELECT inbound_line_id FROM deliveries.inbound_lines WHERE inbound_id = (SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB002') AND sku_id = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU002'));
DECLARE @Line22 INT = (SELECT inbound_line_id FROM deliveries.inbound_lines WHERE inbound_id = (SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB002') AND sku_id = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU003'));

INSERT INTO deliveries.inbound_expected_units (inbound_line_id, expected_external_ref, expected_quantity,batch_number, best_before_date, created_at, created_by) VALUES
	(@Line11, 'SSCC0000000000000001', 1, 'SKU001BATCH', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
	(@Line11, 'SSCC0000000000000003', 1, 'SKU001BATCH', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
	(@Line21, 'SKU00200000000000001', 120, 'SKU002BATCH', '2027-01-31', SYSUTCDATETIME(), @SystemUserId),
	(@Line21, 'SKU00200000000000003', 120, 'SKU002BATCH', '2027-01-31', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000001', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000002', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000003', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000004', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000005', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000006', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000007', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000008', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000009', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId),
	(@Line22, 'SKU00300000000000010', 80, 'SKU003BATCH', '2027-02-28', SYSUTCDATETIME(), @SystemUserId);


/* ============================================================
   TESTINB004 — arrival status test
   Two lines, same SKU, different arrival_stock_status_code
   Line 10: 5 units AV  (normal stock)
   Line 20: 5 units BL  (blocked — e.g. supplier quality hold)
   Both SSCC mode with pre-advised units
   ============================================================ */

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SupplierId   INT = (SELECT party_id FROM core.parties WHERE party_code = 'DUMMY_SUPPLIER');
DECLARE @HaulierId    INT = (SELECT party_id FROM core.parties WHERE party_code = 'DUMMY_HAULIER');
DECLARE @Own          INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_WAREHOUSE01');
DECLARE @Shipto       INT = (SELECT address_id FROM core.party_addresses WHERE party_id = @Own AND address_type = 'WAREHOUSE');
DECLARE @RackId       INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
DECLARE @FloorId      INT = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = 'FLOOR');
DECLARE @Sku001       INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'SKU001');

INSERT INTO deliveries.inbound_deliveries
    (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id,
     ship_to_address_id, expected_arrival_at, created_at, created_by)
VALUES
    ('TESTINB004', @SupplierId, @SupplierId, @HaulierId,
     @Shipto, DATEADD(DAY, 1, SYSUTCDATETIME()), SYSUTCDATETIME(), @SystemUserId);

DECLARE @Inb4 INT = (SELECT inbound_id FROM deliveries.inbound_deliveries WHERE inbound_ref = 'TESTINB004');

INSERT INTO deliveries.inbound_lines
    (inbound_id, line_no, sku_id, expected_qty, received_qty,
     batch_number, best_before_date, arrival_stock_status_code, created_at, created_by)
VALUES
    (@Inb4, 10, @Sku001, 5, 0, 'SKU001BATCH_AV', '2027-03-31', 'AV', SYSUTCDATETIME(), @SystemUserId),
    (@Inb4, 20, @Sku001, 5, 0, 'SKU001BATCH_BL', '2027-03-31', 'BL', SYSUTCDATETIME(), @SystemUserId);

DECLARE @Line4AV INT = (SELECT inbound_line_id FROM deliveries.inbound_lines WHERE inbound_id = @Inb4 AND line_no = 10);
DECLARE @Line4BL INT = (SELECT inbound_line_id FROM deliveries.inbound_lines WHERE inbound_id = @Inb4 AND line_no = 20);

INSERT INTO deliveries.inbound_expected_units
    (inbound_line_id, expected_external_ref, expected_quantity,
     batch_number, best_before_date, created_at, created_by)
VALUES
    (@Line4AV, 'SSCC0000000000000010', 1, 'SKU001BATCH_AV', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4AV, 'SSCC0000000000000011', 1, 'SKU001BATCH_AV', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4AV, 'SSCC0000000000000012', 1, 'SKU001BATCH_AV', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4AV, 'SSCC0000000000000013', 1, 'SKU001BATCH_AV', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4AV, 'SSCC0000000000000014', 1, 'SKU001BATCH_AV', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4BL, 'SSCC0000000000000015', 1, 'SKU001BATCH_BL', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4BL, 'SSCC0000000000000016', 1, 'SKU001BATCH_BL', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4BL, 'SSCC0000000000000017', 1, 'SKU001BATCH_BL', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4BL, 'SSCC0000000000000018', 1, 'SKU001BATCH_BL', '2027-03-31', SYSUTCDATETIME(), @SystemUserId),
    (@Line4BL, 'SSCC0000000000000019', 1, 'SKU001BATCH_BL', '2027-03-31', SYSUTCDATETIME(), @SystemUserId);
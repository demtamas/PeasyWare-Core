USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Reference data required for all environments.
-- Roles, admin user, parties, location types, zones.
-- Idempotent — safe to re-run.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

-- ── Roles ─────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'admin')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('admin', 'System administrator', @SystemUserId);
    PRINT 'Role admin created.';
END
ELSE PRINT 'Role admin already exists.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'manager')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('manager', 'Manager with elevated access', @SystemUserId);
    PRINT 'Role manager created.';
END
ELSE PRINT 'Role manager already exists.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'operator')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('operator', 'Operator with basic access', @SystemUserId);
    PRINT 'Role operator created.';
END
ELSE PRINT 'Role operator already exists.';
GO

-- ── Admin user ────────────────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

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
ELSE PRINT 'User admin already exists.';
GO

-- ── Parties ───────────────────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_WAREHOUSE01')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_WAREHOUSE01', 'Peasy WH', 'Dummy Own Place', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_SUPPLIER')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_SUPPLIER', 'Dummy Supplier PLC', 'Dummy Supplier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_CUSTOMER')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_CUSTOMER', 'Dummy Customer LTD', 'Dummy Customer', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'DUMMY_HAULIER')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('DUMMY_HAULIER', 'Dummy Haulage CORP', 'Dummy Haulier', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

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

-- ── Location reference data ───────────────────────────────────────────────

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

IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = '5')
    INSERT INTO locations.zones (zone_code, zone_name, description, is_active, created_at, created_by)
    VALUES ('5', 'Aisle 5', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

PRINT 'Location reference data done.';


-- ── Bins ─────────────────────────────────────────────────────────────────

DECLARE @SystemUserId2 INT = (SELECT id FROM auth.users WHERE username = 'system');

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
DECLARE @Z5 INT = (SELECT zone_id FROM locations.zones WHERE zone_code = '5');

-- Staging bays
IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY01')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY01', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY02')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY02', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY11')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY11', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BAY12')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BAY12', @StageId, @FloorId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

-- Bulk bins
IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BULK01')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BULK01', @BulkTypeId, @BulkSecId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

IF NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = 'BULK02')
    INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
    VALUES ('BULK02', @BulkTypeId, @BulkSecId, NULL, 999, 1, SYSUTCDATETIME(), @SystemUserId2);

-- Rack bins — 8 bays x 4 levels (A=floor, B=mid, C=mid, D=top)
DECLARE @Bins TABLE (bin_code NVARCHAR(10), sec_id INT, zone_id INT);
INSERT INTO @Bins VALUES
    ('R0101A',@FloorId,@Z1),('R0101B',@MidId,@Z1),('R0101C',@MidId,@Z1),('R0101D',@TopId,@Z1),
    ('R0201A',@FloorId,@Z2),('R0201B',@MidId,@Z2),('R0201C',@MidId,@Z2),('R0201D',@TopId,@Z2),
    ('R0301A',@FloorId,@Z2),('R0301B',@MidId,@Z2),('R0301C',@MidId,@Z2),('R0301D',@TopId,@Z2),
    ('R0401A',@FloorId,@Z3),('R0401B',@MidId,@Z3),('R0401C',@MidId,@Z3),('R0401D',@TopId,@Z3),
    ('R0501A',@FloorId,@Z3),('R0501B',@MidId,@Z3),('R0501C',@MidId,@Z3),('R0501D',@TopId,@Z3),
    ('R0601A',@FloorId,@Z4),('R0601B',@MidId,@Z4),('R0601C',@MidId,@Z4),('R0601D',@TopId,@Z4),
    ('R0701A',@FloorId,@Z4),('R0701B',@MidId,@Z4),('R0701C',@MidId,@Z4),('R0701D',@TopId,@Z4),
    ('R0801A',@FloorId,@Z5),('R0801B',@MidId,@Z5),('R0801C',@MidId,@Z5),('R0801D',@TopId,@Z5);

INSERT INTO locations.bins (bin_code, storage_type_id, storage_section_id, zone_id, capacity, is_active, created_at, created_by)
SELECT b.bin_code, @RackId, b.sec_id, b.zone_id, 1, 1, SYSUTCDATETIME(), @SystemUserId2
FROM @Bins b
WHERE NOT EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = b.bin_code);

PRINT 'Bins done.';
GO
-- ── System user role assignment ───────────────────────────────────────────
-- Must run after both system user and system role exist.

DECLARE @SysUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SysRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'system');

IF @SysUserId IS NOT NULL AND @SysRoleId IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = @SysUserId AND role_id = @SysRoleId)
BEGIN
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@SysUserId, @SysRoleId);
    PRINT 'System user assigned to system role.';
END

PRINT 'Reference data complete.';
GO

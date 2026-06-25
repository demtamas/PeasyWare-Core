USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- DEMO DATA — fictional parties (suppliers, customers, hauliers).
-- Not required for the app to function. Skip with: reset-db --no-demo
-- Idempotent — safe to re-run.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_WAREHOUSE01')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_WAREHOUSE01', 'Peasy WH', 'Dummy Own Place', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

-- Suppliers
IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_BREWERY01')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_BREWERY01', 'Peasy Brewing Co. Ltd', 'Peasy Brewing Co.', 'GB', 'GB123456789', 1, SYSUTCDATETIME(), @SystemUserId);

-- Customers
IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_CUSTOMER01')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_CUSTOMER01', 'The Hop & Barrel Ltd', 'Hop & Barrel', 'GB', 'GB987654321', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_CUSTOMER02')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_CUSTOMER02', 'Festival Drinks PLC', 'Festival Drinks', 'GB', 'GB456789123', 1, SYSUTCDATETIME(), @SystemUserId);

-- Hauliers
IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_HAULIER01')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_HAULIER01', 'Swift Freight Ltd', 'Swift Freight', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_code = 'PW_HAULIER02')
    INSERT INTO core.parties (party_code, legal_name, display_name, country_code, tax_id, is_active, created_at, created_by)
    VALUES ('PW_HAULIER02', 'Rapid Logistics Ltd', 'Rapid Logistics', 'GB', NULL, 1, SYSUTCDATETIME(), @SystemUserId);

DECLARE @Own        INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_WAREHOUSE01');
DECLARE @SupplierId INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_BREWERY01');
DECLARE @CustomerId INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_CUSTOMER01');
DECLARE @HaulierId  INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_HAULIER01');

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
    VALUES (@SupplierId, 'YARD', '12 Brewery Lane', 'Burton upon Trent', 'DE14 1JZ', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @CustomerId)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@CustomerId, 'YARD', '45 High Street', 'Manchester', 'M1 2AB', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @HaulierId)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@HaulierId, 'YARD', 'Unit 3 Freight Park', 'Coventry', 'CV1 5TL', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM customers.customers WHERE party_id = @CustomerId)
    INSERT INTO customers.customers (party_id, customer_type, default_delivery_days, preferred_haulier_id, allow_crossdock, created_at, created_by)
    VALUES (@CustomerId, 'RETAIL', 0, NULL, 0, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM suppliers.suppliers WHERE party_id = @SupplierId)
    INSERT INTO suppliers.suppliers (party_id, supplier_type, default_lead_days, preferred_haulier_id, created_at, created_by)
    VALUES (@SupplierId, 'OWNER', 0, NULL, SYSUTCDATETIME(), @SystemUserId);

-- Second customer and second haulier
DECLARE @Customer2Id INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_CUSTOMER02');
DECLARE @Haulier2Id  INT = (SELECT party_id FROM core.parties WHERE party_code = 'PW_HAULIER02');

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @Customer2Id AND role_code = 'CUSTOMER')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@Customer2Id, 'CUSTOMER', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_roles WHERE party_id = @Haulier2Id AND role_code = 'HAULIER')
    INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
    VALUES (@Haulier2Id, 'HAULIER', SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @Customer2Id)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@Customer2Id, 'YARD', '8 Festival Way', 'Birmingham', 'B1 1BB', 'GB', 'Use loading bay 3', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM core.party_addresses WHERE party_id = @Haulier2Id)
    INSERT INTO core.party_addresses (party_id, address_type, line_1, city, postal_code, country_code, instructions, is_primary, is_active, created_at, created_by)
    VALUES (@Haulier2Id, 'YARD', '22 Distribution Road', 'Leicester', 'LE1 4RD', 'GB', 'Report to gatehouse on arrival', 1, 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM customers.customers WHERE party_id = @Customer2Id)
    INSERT INTO customers.customers (party_id, customer_type, default_delivery_days, preferred_haulier_id, allow_crossdock, created_at, created_by)
    VALUES (@Customer2Id, 'EVENTS', 0, NULL, 0, SYSUTCDATETIME(), @SystemUserId);

PRINT 'Demo parties done.';
GO

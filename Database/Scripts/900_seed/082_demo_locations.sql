USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- DEMO DATA — sample warehouse layout (types, sections, zones, bins).
-- Not required for the app to function. Skip with: reset-db --no-demo
--
-- A real PeasyWare install starts with NOTHING here — the operator
-- defines their own storage types/sections/zones/bins from scratch via
-- the Warehouse menu (Storage Types / Zones / Sections / Locations).
-- This file exists purely to give a demo/dev environment something to
-- look at out of the box. Idempotent — safe to re-run.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

-- ── Storage types ─────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'STAGE')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('STAGE', 'Staging area', 'Inbound / outbound staging area', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'RACK')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('RACK', 'Pallet racking', 'Standard pallet racking', 1, SYSUTCDATETIME(), @SystemUserId);

IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = 'BULK')
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, is_active, created_at, created_by)
    VALUES ('BULK', 'Bulk storage', 'Bulk storage on the floor', 1, SYSUTCDATETIME(), @SystemUserId);

PRINT 'Demo storage types done.';
GO

-- ── Sections ────────────────────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

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

-- ── Zones ───────────────────────────────────────────────────────────────────

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

PRINT 'Demo sections + zones done.';
GO

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

PRINT 'Demo bins done.';
GO

PRINT 'Demo locations complete.';
GO

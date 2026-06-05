USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- Add updated_at / updated_by to zones
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('locations.zones') AND name = 'updated_at')
BEGIN
    ALTER TABLE locations.zones
        ADD updated_at DATETIME2(3) NULL,
            updated_by INT          NULL;
    PRINT 'locations.zones: updated_at/updated_by added.';
END

-- Add updated_at / updated_by to storage_sections
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('locations.storage_sections') AND name = 'updated_at')
BEGIN
    ALTER TABLE locations.storage_sections
        ADD updated_at DATETIME2(3) NULL,
            updated_by INT          NULL;
    PRINT 'locations.storage_sections: updated_at/updated_by added.';
END
GO

-- ============================================================
-- v_zones — zones with bin count
-- ============================================================
CREATE OR ALTER VIEW locations.v_zones
AS
SELECT
    z.zone_id,
    z.zone_code,
    z.zone_name,
    z.description,
    z.is_active,
    z.created_at,
    cb.username                          AS created_by_username,
    z.updated_at,
    ub.username                          AS updated_by_username,
    COUNT(b.bin_id)                      AS total_bins,
    SUM(CASE WHEN b.is_active = 1 THEN 1 ELSE 0 END) AS active_bins
FROM locations.zones z
LEFT JOIN auth.users cb ON cb.id = z.created_by
LEFT JOIN auth.users ub ON ub.id = z.updated_by
LEFT JOIN locations.bins b ON b.zone_id = z.zone_id
GROUP BY
    z.zone_id, z.zone_code, z.zone_name, z.description,
    z.is_active, z.created_at, cb.username, z.updated_at, ub.username;
GO

-- ============================================================
-- v_sections — sections with bin count
-- ============================================================
CREATE OR ALTER VIEW locations.v_sections
AS
SELECT
    s.storage_section_id,
    s.section_code,
    s.section_name,
    s.description,
    s.is_active,
    s.created_at,
    cb.username                          AS created_by_username,
    s.updated_at,
    ub.username                          AS updated_by_username,
    COUNT(b.bin_id)                      AS total_bins,
    SUM(CASE WHEN b.is_active = 1 THEN 1 ELSE 0 END) AS active_bins
FROM locations.storage_sections s
LEFT JOIN auth.users cb ON cb.id = s.created_by
LEFT JOIN auth.users ub ON ub.id = s.updated_by
LEFT JOIN locations.bins b ON b.storage_section_id = s.storage_section_id
GROUP BY
    s.storage_section_id, s.section_code, s.section_name, s.description,
    s.is_active, s.created_at, cb.username, s.updated_at, ub.username;
GO
PRINT 'v_zones and v_sections created.';
GO

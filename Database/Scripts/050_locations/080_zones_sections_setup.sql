USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- updated_at/updated_by are now part of 010_tables.sql for both zones and storage_sections.
-- This file creates the summary views that depend on those columns.

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

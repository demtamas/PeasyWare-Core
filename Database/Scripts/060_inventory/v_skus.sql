USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inventory.v_skus
AS
SELECT
    s.sku_id,
    s.sku_code,
    s.sku_description,
    s.ean,
    s.uom_code,
    s.weight_per_unit,
    s.standard_hu_quantity,
    s.is_hazardous,
    s.is_batch_required,
    s.is_full_hu_required,
    s.is_active,
    st.storage_type_code        AS preferred_storage_type_code,
    ss.section_code             AS preferred_section_code,
    s.created_at,
    cu.username                 AS created_by_username,
    s.updated_at,
    uu.username                 AS updated_by_username
FROM inventory.skus s
LEFT JOIN locations.storage_types    st ON st.storage_type_id    = s.preferred_storage_type_id
LEFT JOIN locations.storage_sections ss ON ss.storage_section_id = s.preferred_storage_section_id
LEFT JOIN auth.users cu              ON cu.id = s.created_by
LEFT JOIN auth.users uu              ON uu.id = s.updated_by;
GO
PRINT 'inventory.v_skus created.';
GO

-- ── Error codes ───────────────────────────────────────────────────────────────
GO

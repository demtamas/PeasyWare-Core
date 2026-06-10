USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW locations.v_locations
AS
SELECT
    b.bin_id,
    b.bin_code,
    st.storage_type_code,
    st.storage_type_name,
    ss.section_code,
    z.zone_code,
    z.zone_name,
    b.capacity,
    b.is_active,
    b.is_locked,
    b.locked_reason,
    b.notes,
    b.locked_at,
    lb.username                                     AS locked_by_username,

    -- Stock summary
    COUNT(iu.inventory_unit_id)                     AS unit_count,
    ISNULL(SUM(iu.quantity), 0)                     AS total_qty,

    -- Single-unit convenience columns (NULL when multi-unit)
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(iu.external_ref)  END             AS sscc,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(sk.sku_code)      END             AS sku_code,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(sk.sku_description) END           AS sku_description,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(iu.batch_number)  END             AS batch_number,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(iu.best_before_date) END          AS best_before_date,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(iu.stock_state_code) END          AS stock_state,
    CASE WHEN COUNT(iu.inventory_unit_id) = 1
         THEN MAX(iu.stock_status_code) END         AS stock_status

FROM locations.bins b
JOIN locations.storage_types st      ON st.storage_type_id  = b.storage_type_id
LEFT JOIN locations.storage_sections ss ON ss.storage_section_id = b.storage_section_id
LEFT JOIN locations.zones z          ON z.zone_id           = b.zone_id
LEFT JOIN auth.users lb              ON lb.id               = b.locked_by

-- Active inventory placements only (one row per unit — PK guarantees single active placement)
LEFT JOIN inventory.inventory_placements ip
    ON ip.bin_id      = b.bin_id
LEFT JOIN inventory.inventory_units iu
    ON iu.inventory_unit_id = ip.inventory_unit_id
    AND iu.stock_state_code NOT IN ('SHP', 'REV')
LEFT JOIN inventory.skus sk
    ON sk.sku_id = iu.sku_id

GROUP BY
    b.bin_id, b.bin_code,
    st.storage_type_code, st.storage_type_name,
    ss.section_code,
    z.zone_code, z.zone_name,
    b.capacity, b.is_active, b.is_locked,
    b.locked_reason, b.notes, b.locked_at,
    lb.username;
GO
PRINT 'locations.v_locations created.';
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.v_empty_bins
   ------------------------------------------------------------
   The single definition of "an empty bin" for counting: active,
   unlocked, in an active storage type, holding no placements,
   and with no unexpired reservation (a reservation means stock
   is on its way - not an empty bay to audit).

   Used for both the storage-type picker (empty bins per type)
   and the snapshot taken when an empty-bin count starts.
   ============================================================ */
CREATE OR ALTER VIEW warehouse.v_empty_bins
AS
SELECT
    b.bin_id,
    b.bin_code,
    b.storage_type_id,
    st.storage_type_code,
    st.storage_type_name,
    b.zone_id,
    z.zone_code,
    b.storage_section_id,
    b.capacity
FROM locations.bins b
JOIN locations.storage_types st
    ON st.storage_type_id = b.storage_type_id
LEFT JOIN locations.zones z
    ON z.zone_id = b.zone_id
WHERE b.is_active  = 1
  AND b.is_locked  = 0
  AND st.is_active = 1
  AND NOT EXISTS (
        SELECT 1
        FROM inventory.inventory_placements ip
        WHERE ip.bin_id = b.bin_id
  )
  AND NOT EXISTS (
        SELECT 1
        FROM locations.bin_reservations br
        WHERE br.bin_id     = b.bin_id
          AND br.expires_at > SYSUTCDATETIME()
  );
GO
PRINT 'warehouse.v_empty_bins created.';
GO

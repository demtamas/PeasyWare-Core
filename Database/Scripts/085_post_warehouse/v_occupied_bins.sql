USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.v_occupied_bins
   ------------------------------------------------------------
   The single definition of "a bin to bin-count": active, in an active
   storage type, and holding at least one pallet. (The mirror of
   warehouse.v_empty_bins.)

   A locked bin still counts - locking a bin does not make its stock
   disappear - and no reservation matters here: stock that is there is there.

   Used for both the storage-type picker (bins to count per type) and the
   snapshot taken when a bin count starts. Deliberately says nothing about
   WHAT is in the bin: the count is blind.
   ============================================================ */
CREATE OR ALTER VIEW warehouse.v_occupied_bins
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
  AND st.is_active = 1
  AND EXISTS (
        SELECT 1
        FROM inventory.inventory_placements ip
        WHERE ip.bin_id = b.bin_id
  );
GO
PRINT 'warehouse.v_occupied_bins created.';
GO

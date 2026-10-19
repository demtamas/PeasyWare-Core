USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.v_count_lines
   ------------------------------------------------------------
   One row per bin in a count. The CLI reads PENDING rows for a
   count (ordered by zone, then bin) as the walk list; the Desktop
   view shows the lot.

   Deliberately says nothing about what the system holds in the bin: the
   walk list of a bin count is blind. pallets_scanned is what the operator
   has scanned so far (BIN_COUNT; 0 for an empty-bin count).
   ============================================================ */
CREATE OR ALTER VIEW warehouse.v_count_lines
AS
SELECT
    cl.count_line_id,
    cl.count_id,
    b.bin_code,
    z.zone_code,
    st.storage_type_code,
    cl.line_status_code,
    cl.opened_at,
    cl.counted_at,
    u.username                                                    AS counted_by,
    (SELECT COUNT(*)
     FROM warehouse.count_scans s
     WHERE s.count_line_id = cl.count_line_id)                    AS pallets_scanned,
    (SELECT COUNT(*)
     FROM warehouse.count_findings f
     WHERE f.count_line_id = cl.count_line_id)                    AS finding_count
FROM warehouse.count_lines cl
JOIN locations.bins b                ON b.bin_id = cl.bin_id
LEFT JOIN locations.zones z          ON z.zone_id = b.zone_id
LEFT JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
LEFT JOIN auth.users u               ON u.id = cl.counted_by;
GO
PRINT 'warehouse.v_count_lines created.';
GO

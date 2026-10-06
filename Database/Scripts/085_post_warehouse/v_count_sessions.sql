USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.v_count_sessions
   ------------------------------------------------------------
   One row per count with its progress, for the Desktop Counting
   view and the CLI "resume" check.

   findings_to_review  pallets the count found but could not put right
                       (everything except RECORD_CORRECTED). A count in
                       REVIEW has at least one; the number stays after
                       the review so the record shows what was dealt with.
   reviewed_at / reviewed_by / review_note
                       who dealt with it, when, and what they did.
   ============================================================ */
CREATE OR ALTER VIEW warehouse.v_count_sessions
AS
SELECT
    cs.count_id,
    cs.count_type_code,
    st.storage_type_code,
    cs.status_code,
    cs.started_at,
    su.username                                                   AS started_by,
    cs.completed_at,
    cu.username                                                   AS completed_by,

    COUNT(cl.count_line_id)                                       AS total_bins,
    ISNULL(SUM(CASE WHEN cl.line_status_code = 'PENDING'         THEN 1 ELSE 0 END), 0) AS pending_bins,
    ISNULL(SUM(CASE WHEN cl.line_status_code = 'CONFIRMED_EMPTY' THEN 1 ELSE 0 END), 0) AS confirmed_empty,
    ISNULL(SUM(CASE WHEN cl.line_status_code = 'STOCK_FOUND'     THEN 1 ELSE 0 END), 0) AS stock_found,
    ISNULL(SUM(CASE WHEN cl.line_status_code = 'OCCUPIED_SINCE'  THEN 1 ELSE 0 END), 0) AS occupied_since,

    (SELECT COUNT(*)
     FROM warehouse.count_findings f
     JOIN warehouse.count_lines l2 ON l2.count_line_id = f.count_line_id
     WHERE l2.count_id = cs.count_id
       AND f.finding_code <> 'RECORD_CORRECTED')                  AS findings_to_review,

    cs.reviewed_at,
    ru.username                                                   AS reviewed_by,
    cs.review_note
FROM warehouse.count_sessions cs
LEFT JOIN locations.storage_types st ON st.storage_type_id = cs.storage_type_id
LEFT JOIN warehouse.count_lines cl   ON cl.count_id = cs.count_id
LEFT JOIN auth.users su              ON su.id = cs.started_by
LEFT JOIN auth.users cu              ON cu.id = cs.completed_by
LEFT JOIN auth.users ru              ON ru.id = cs.reviewed_by
GROUP BY
    cs.count_id, cs.count_type_code, st.storage_type_code, cs.status_code,
    cs.started_at, su.username, cs.completed_at, cu.username,
    cs.reviewed_at, ru.username, cs.review_note;
GO
PRINT 'warehouse.v_count_sessions created.';
GO

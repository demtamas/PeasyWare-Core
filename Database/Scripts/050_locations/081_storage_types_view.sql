USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- v_storage_types — storage types with bin count
-- ============================================================
CREATE OR ALTER VIEW locations.v_storage_types
AS
SELECT
    st.storage_type_id,
    st.storage_type_code,
    st.storage_type_name,
    st.description,
    st.is_active,
    st.created_at,
    cb.username                          AS created_by_username,
    st.updated_at,
    ub.username                          AS updated_by_username,
    COUNT(b.bin_id)                      AS total_bins,
    SUM(CASE WHEN b.is_active = 1 THEN 1 ELSE 0 END) AS active_bins
FROM locations.storage_types st
LEFT JOIN auth.users cb ON cb.id = st.created_by
LEFT JOIN auth.users ub ON ub.id = st.updated_by
LEFT JOIN locations.bins b ON b.storage_type_id = st.storage_type_id
GROUP BY
    st.storage_type_id, st.storage_type_code, st.storage_type_name, st.description,
    st.is_active, st.created_at, cb.username, st.updated_at, ub.username;
GO
PRINT 'v_storage_types created.';
GO

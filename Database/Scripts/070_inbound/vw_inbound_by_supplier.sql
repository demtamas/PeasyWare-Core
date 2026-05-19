USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inbound.vw_inbound_by_supplier
AS
SELECT
    s.party_code     AS supplier_code,
    s.display_name   AS supplier_name,
    COUNT(*)         AS open_inbounds
FROM inbound.inbound_deliveries d
JOIN core.parties s ON s.party_id = d.supplier_party_id
WHERE d.inbound_status_code IN ('EXP','ACT','RCV')
GROUP BY s.party_code, s.display_name;
GO

/* ============================================================
   logistics.vw_inbound_by_haulier
   ============================================================ */
GO

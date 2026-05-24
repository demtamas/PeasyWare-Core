USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW core.v_parties
AS
SELECT
    p.party_id,
    p.party_code,
    p.legal_name,
    p.display_name,
    p.country_code,
    p.tax_id,
    p.is_active,
    p.created_at,
    cu.username                 AS created_by_username,
    p.updated_at,
    uu.username                 AS updated_by_username,
    -- Aggregated roles as comma-separated string for display
    ISNULL(
        STUFF((
            SELECT ', ' + pr2.role_code
            FROM core.party_roles pr2
            WHERE pr2.party_id = p.party_id
            ORDER BY pr2.role_code
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, ''),
    '') AS roles,
    -- Individual role flags for filtering
    CAST(MAX(CASE WHEN pr.role_code = 'SUPPLIER'  THEN 1 ELSE 0 END) AS BIT) AS is_supplier,
    CAST(MAX(CASE WHEN pr.role_code = 'CUSTOMER'  THEN 1 ELSE 0 END) AS BIT) AS is_customer,
    CAST(MAX(CASE WHEN pr.role_code = 'HAULIER'   THEN 1 ELSE 0 END) AS BIT) AS is_haulier,
    CAST(MAX(CASE WHEN pr.role_code = 'OWNER'     THEN 1 ELSE 0 END) AS BIT) AS is_owner,
    CAST(MAX(CASE WHEN pr.role_code = 'WAREHOUSE' THEN 1 ELSE 0 END) AS BIT) AS is_warehouse
FROM core.parties p
LEFT JOIN core.party_roles pr  ON pr.party_id = p.party_id
LEFT JOIN auth.users cu        ON cu.id = p.created_by
LEFT JOIN auth.users uu        ON uu.id = p.updated_by
GROUP BY
    p.party_id, p.party_code, p.legal_name, p.display_name,
    p.country_code, p.tax_id, p.is_active,
    p.created_at, cu.username,
    p.updated_at, uu.username;
GO
PRINT 'core.v_parties created.';
GO

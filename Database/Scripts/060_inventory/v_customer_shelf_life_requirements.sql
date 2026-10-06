USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   inventory.v_customer_shelf_life_requirements
   ------------------------------------------------------------
   Flattened, browsable list of customer+SKU shelf-life overrides,
   for the management screen.

   Lives here rather than 035_post_auth/ (where it originally sat)
   because it directly joins core.parties and inventory.skus/
   inventory.customer_shelf_life_requirements - none of which exist
   yet when reset-db reaches 035_post_auth in its strict alphabetical
   folder order. 060_inventory runs after 040_core and after this
   same folder's own table-creation script, so both dependencies are
   satisfied. Matches the existing v_skus.sql convention: a view
   sitting directly alongside the table it depends on, not off in a
   separate "post" folder.
   ============================================================ */
CREATE OR ALTER VIEW inventory.v_customer_shelf_life_requirements
AS
SELECT
    csl.customer_party_id,
    p.party_code                        AS customer_party_code,
    p.display_name                      AS customer_name,
    csl.sku_id,
    s.sku_code,
    s.sku_description,
    csl.minimum_remaining_shelf_life_days,
    csl.created_at,
    cu.username                         AS created_by_username,
    csl.updated_at,
    uu.username                         AS updated_by_username
FROM inventory.customer_shelf_life_requirements csl
JOIN core.parties p     ON p.party_id = csl.customer_party_id
JOIN inventory.skus s   ON s.sku_id   = csl.sku_id
LEFT JOIN auth.users cu ON cu.id = csl.created_by
LEFT JOIN auth.users uu ON uu.id = csl.updated_by;
GO

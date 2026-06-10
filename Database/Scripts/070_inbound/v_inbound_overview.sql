USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inbound.v_inbound_overview
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.inbound_status_code,
    d.expected_arrival_at,
    s.display_name   AS supplier_name,
    o.display_name   AS owner_name,
    h.display_name   AS haulier_name,
    a.city,
    a.postal_code,
    a.country_code
FROM inbound.inbound_deliveries d
JOIN  core.parties s ON s.party_id = d.supplier_party_id
JOIN  core.parties o ON o.party_id = d.owner_party_id
LEFT JOIN core.parties h ON h.party_id = d.haulier_party_id
JOIN  core.party_addresses a ON a.address_id = d.ship_to_address_id;
GO

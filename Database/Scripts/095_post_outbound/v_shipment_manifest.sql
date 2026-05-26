USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW outbound.v_shipment_manifest
AS
SELECT
    -- Shipment header
    s.shipment_id,
    s.shipment_ref,
    s.shipment_status,
    s.vehicle_ref,
    s.actual_departure,
    -- Haulier
    h.display_name                              AS haulier_name,
    h.party_code                                AS haulier_code,
    -- Customer (from first order on shipment — all orders on same shipment = same customer)
    cust.display_name                           AS customer_name,
    cust.party_code                             AS customer_code,
    -- Delivery address (from first order)
    ca.line_1                                AS delivery_line_1,
    ca.city                                     AS delivery_city,
    ca.postal_code                              AS delivery_postal_code,
    ca.country_code                             AS delivery_country,
    -- Pallet detail
    m.movement_id,
    iu.external_ref                             AS sscc,
    sk.sku_code,
    sk.sku_description,
    iu.batch_number,
    iu.best_before_date,
    m.moved_qty                                 AS quantity,
    sk.uom_code,
    sk.weight_per_unit,
    CAST(sk.weight_per_unit * m.moved_qty / 1000.0 AS DECIMAL(10,3)) AS total_weight_kg,
    -- Order reference for this unit
    ol_alloc.order_ref,
    -- Bin it was picked from
    fb.bin_code                                 AS picked_from_bin
FROM outbound.shipments s
LEFT JOIN core.parties h ON h.party_id = s.haulier_party_id
-- Get customer and delivery address from first order on shipment
OUTER APPLY (
    SELECT TOP 1
        o.customer_party_id,
        o.delivery_address_id
    FROM outbound.shipment_orders so2
    JOIN outbound.outbound_orders o ON o.outbound_order_id = so2.outbound_order_id
    WHERE so2.shipment_id = s.shipment_id
) first_order
LEFT JOIN core.parties cust ON cust.party_id = first_order.customer_party_id
LEFT JOIN core.party_addresses ca ON ca.address_id = first_order.delivery_address_id
-- Physical units shipped
JOIN inventory.inventory_movements m
    ON  m.reference_type = 'SHIPMENT'
    AND m.reference_id   = s.shipment_id
    AND m.movement_type  = 'SHIP'
    AND m.is_reversal    = 0
JOIN inventory.inventory_units iu ON iu.inventory_unit_id = m.inventory_unit_id
JOIN inventory.skus sk            ON sk.sku_id             = m.sku_id
LEFT JOIN locations.bins fb       ON fb.bin_id             = m.from_bin_id
-- Resolve which order this unit was on (via allocation)
OUTER APPLY (
    SELECT TOP 1 o.order_ref
    FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines ol ON ol.outbound_line_id = a.outbound_line_id
    JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id
    WHERE a.inventory_unit_id = iu.inventory_unit_id
      AND a.allocation_status  = 'PICKED'
) ol_alloc;
GO
PRINT 'outbound.v_shipment_manifest created.';
GO

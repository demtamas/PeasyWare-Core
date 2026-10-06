USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.v_count_findings
   ------------------------------------------------------------
   Every pallet found in a bin the system believed was empty,
   with what was done about it. NOT_CORRECTED rows carry the rule
   that stopped the correction (reason_code, and its plain-English
   reason_message) - the supervisor review list.

   For a pallet the system knows left the building, the finding
   also says WHERE it went - the question a supervisor asks first:
     shipment_ref / vehicle_ref / shipped_at   the delivery it left on
                                               (from the unit's SHIP movement)
     order_ref / customer_name                 the order it was picked for
   Order details also show for a picked pallet that has not shipped yet.
   All NULL for a pallet that was never on an order.

   Lives in 095_post_outbound (not 085_post_warehouse) because it joins
   the outbound tables, which are built after the warehouse views.
   ============================================================ */
CREATE OR ALTER VIEW warehouse.v_count_findings
AS
SELECT
    f.finding_id,
    cl.count_id,
    b.bin_code,
    f.scanned_ref,
    f.inventory_unit_id,
    s.sku_code,
    f.finding_code,
    f.reason_code,
    em.message_template                                           AS reason_message,
    pb.bin_code                                                   AS previous_bin_code,
    f.movement_id,
    f.found_at,
    u.username                                                    AS found_by,

    ship.shipment_ref,
    ship.vehicle_ref,
    ship.shipped_at,
    ord.order_ref,
    ord.customer_name
FROM warehouse.count_findings f
JOIN warehouse.count_lines cl           ON cl.count_line_id = f.count_line_id
JOIN locations.bins b                   ON b.bin_id = cl.bin_id
LEFT JOIN locations.bins pb             ON pb.bin_id = f.previous_bin_id
LEFT JOIN inventory.inventory_units iu  ON iu.inventory_unit_id = f.inventory_unit_id
LEFT JOIN inventory.skus s              ON s.sku_id = iu.sku_id
LEFT JOIN operations.error_messages em  ON em.error_code = f.reason_code
LEFT JOIN auth.users u                  ON u.id = f.found_by
OUTER APPLY (
    SELECT TOP (1)
        sh.shipment_ref,
        sh.vehicle_ref,
        COALESCE(sh.actual_departure, m.moved_at)                 AS shipped_at
    FROM inventory.inventory_movements m
    JOIN outbound.shipments sh ON sh.shipment_id = m.reference_id
    WHERE m.inventory_unit_id = f.inventory_unit_id
      AND m.movement_type     = 'SHIP'
      AND m.reference_type    = 'SHIPMENT'
    ORDER BY m.moved_at DESC, m.movement_id DESC
) ship
OUTER APPLY (
    SELECT TOP (1)
        o.order_ref,
        p.display_name                                            AS customer_name
    FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines  ol ON ol.outbound_line_id  = a.outbound_line_id
    JOIN outbound.outbound_orders o  ON o.outbound_order_id  = ol.outbound_order_id
    JOIN core.parties             p  ON p.party_id           = o.customer_party_id
    WHERE a.inventory_unit_id = f.inventory_unit_id
      AND a.allocation_status = 'PICKED'
    ORDER BY a.allocation_id DESC
) ord;
GO
PRINT 'warehouse.v_count_findings created.';
GO

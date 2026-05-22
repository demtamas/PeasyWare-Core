USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inventory.v_active_inventory
AS
SELECT
    iu.inventory_unit_id,
    iu.external_ref                                     AS sscc,
    s.sku_code,
    s.sku_description,
    iu.batch_number,
    iu.best_before_date,
    iu.quantity,
    ss.state_code_desc                                  AS stock_state,
    sst.status_desc                                     AS stock_status,
    b.bin_code,
    z.zone_code,
    st.storage_type_code,
    iu.created_at                                       AS received_at,
    rcv.username                                        AS received_by,
    -- Last physical movement
    lm.movement_type                                    AS last_movement_type,
    lm.moved_at                                         AS last_movement_at,
    lm_usr.username                                     AS last_moved_by,
    -- Allocation state
    ob.order_ref,
    ob.allocation_status,
    ob.allocated_by,
    ob.allocated_at,
    -- Inbound reference
    inb.inbound_ref,
    -- Stock owner (from SKU definition)
    owner_p.display_name                                AS owner_name
FROM inventory.inventory_units iu
JOIN inventory.skus s
    ON s.sku_id = iu.sku_id
JOIN inventory.stock_states ss
    ON ss.state_code = iu.stock_state_code
JOIN inventory.stock_statuses sst
    ON sst.status_code = iu.stock_status_code
JOIN inventory.inventory_placements ip
    ON ip.inventory_unit_id = iu.inventory_unit_id
JOIN locations.bins b
    ON b.bin_id = ip.bin_id
LEFT JOIN locations.zones z
    ON z.zone_id = b.zone_id
LEFT JOIN locations.storage_types st
    ON st.storage_type_id = b.storage_type_id
LEFT JOIN auth.users rcv
    ON rcv.id = iu.created_by
OUTER APPLY
(
    SELECT TOP 1
        m.movement_type,
        m.moved_at,
        m.moved_by_user_id
    FROM inventory.inventory_movements m
    WHERE m.inventory_unit_id = iu.inventory_unit_id
      AND m.is_reversal = 0
    ORDER BY m.moved_at DESC
) lm
LEFT JOIN auth.users lm_usr
    ON lm_usr.id = lm.moved_by_user_id
LEFT JOIN
(
    SELECT r.inventory_unit_id, d.inbound_ref
    FROM inbound.inbound_receipts r
    JOIN inbound.inbound_lines l ON l.inbound_line_id = r.inbound_line_id
    JOIN inbound.inbound_deliveries d ON d.inbound_id = l.inbound_id
    WHERE r.is_reversal = 0
) inb ON inb.inventory_unit_id = iu.inventory_unit_id
LEFT JOIN core.parties owner_p ON owner_p.party_id = s.owner_party_id
LEFT JOIN
(
    SELECT
        a.inventory_unit_id,
        o.order_ref,
        a.allocation_status,
        alloc_usr.username  AS allocated_by,
        a.allocated_at
    FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines ol ON ol.outbound_line_id = a.outbound_line_id
    JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id
    LEFT JOIN auth.users alloc_usr ON alloc_usr.id = a.allocated_by
    WHERE a.allocation_status <> 'CANCELLED'
) ob ON ob.inventory_unit_id = iu.inventory_unit_id;
GO

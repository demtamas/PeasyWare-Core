USE PW_Core_DEV;
GO

-- ── inventory.v_active_inventory ──────────────────────────────────────────────
-- Added:
--   inbound_ref   — the delivery reference the unit arrived on
--   order_ref     — the outbound order reference if currently allocated
--
-- Logic:
--   inbound_ref  : inventory_unit → inbound_receipts → inbound_lines
--                  → inbound_deliveries.inbound_ref
--                  (most recent non-reversal receipt; handles re-receives after reversal)
--
--   order_ref    : inventory_unit → outbound_allocations (active only)
--                  → outbound_lines → outbound_orders.order_ref
--
-- Display rule (application layer):
--   Show order_ref when allocated (state PKD or MOV, or order_ref IS NOT NULL)
--   Show inbound_ref otherwise
--   A single "Reference" column in the Desktop grid covers both cases

CREATE OR ALTER VIEW inventory.v_active_inventory
AS
SELECT
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
    lm.movement_type                                    AS last_movement_type,
    lm.moved_at                                         AS last_movement_at,
    lm_usr.username                                     AS last_moved_by,

    -- The inbound delivery reference this unit arrived on
    inb.inbound_ref,

    -- The outbound order reference if this unit is currently allocated
    alloc.order_ref

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

-- Last movement (non-reversal)
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

-- Inbound delivery reference (most recent non-reversal receipt)
OUTER APPLY
(
    SELECT TOP 1
        d.inbound_ref
    FROM inbound.inbound_receipts r
    JOIN inbound.inbound_lines l
        ON l.inbound_line_id = r.inbound_line_id
    JOIN inbound.inbound_deliveries d
        ON d.inbound_id = l.inbound_id
    WHERE r.inventory_unit_id = iu.inventory_unit_id
      AND r.is_reversal = 0
    ORDER BY r.received_at DESC
) inb

-- Active outbound order reference (if allocated)
OUTER APPLY
(
    SELECT TOP 1
        o.order_ref
    FROM outbound.outbound_allocations a
    JOIN outbound.outbound_lines ol
        ON ol.outbound_line_id = a.outbound_line_id
    JOIN outbound.outbound_orders o
        ON o.outbound_order_id = ol.outbound_order_id
    WHERE a.inventory_unit_id  = iu.inventory_unit_id
      AND a.allocation_status NOT IN ('CANCELLED', 'SHIPPED')
) alloc

WHERE iu.stock_state_code <> 'REV'
  AND iu.stock_state_code <> 'SHP';
GO
PRINT 'inventory.v_active_inventory: inbound_ref + order_ref added.';
GO

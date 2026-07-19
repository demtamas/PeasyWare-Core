USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inventory.v_movements
AS
SELECT
    m.movement_id,
    m.moved_at,
    u.username                              AS moved_by,
    iu.external_ref                         AS sscc,
    s.sku_code,
    s.sku_description,
    m.moved_qty,
    -- Location transition
    fb.bin_code                             AS from_bin,
    tb.bin_code                             AS to_bin,
    -- State transition
    m.from_state_code,
    m.to_state_code,
    -- Status transition
    m.from_status_code,
    m.to_status_code,
    -- Business context
    m.movement_type,
    m.reference_type,
    m.reference_id,
    -- Resolve reference display string
    CASE m.reference_type
        WHEN 'INBOUND'  THEN (SELECT inbound_ref  FROM inbound.inbound_deliveries  WHERE inbound_id        = m.reference_id)
        WHEN 'OUTBOUND' THEN (SELECT order_ref    FROM outbound.outbound_orders     WHERE outbound_order_id = m.reference_id)
        WHEN 'SHIPMENT' THEN (SELECT shipment_ref FROM outbound.shipments            WHERE shipment_id       = m.reference_id)
        WHEN 'RECEIPT'  THEN (
            SELECT d.inbound_ref
            FROM inbound.inbound_receipts r
            JOIN inbound.inbound_lines l    ON l.inbound_line_id = r.inbound_line_id
            JOIN inbound.inbound_deliveries d ON d.inbound_id   = l.inbound_id
            WHERE r.receipt_id = m.reference_id
        )
        WHEN 'TASK'     THEN (
            SELECT CASE t.task_type_code
                WHEN 'PUTAWAY' THEN 'PUT-'  + RIGHT('000000' + CAST(t.task_id AS VARCHAR(6)), 6)
                WHEN 'PICK'    THEN 'PICK-' + RIGHT('000000' + CAST(t.task_id AS VARCHAR(6)), 6)
                WHEN 'MOVE'    THEN 'MOVE-' + RIGHT('000000' + CAST(t.task_id AS VARCHAR(6)), 6)
                ELSE CAST(t.task_id AS NVARCHAR(20))
            END
            FROM warehouse.warehouse_tasks t
            WHERE t.task_id = m.reference_id
        )
        ELSE NULL
    END                                     AS reference_ref,
    -- Reversal flag
    m.is_reversal,
    m.reversed_movement_id
FROM inventory.inventory_movements m
JOIN inventory.inventory_units iu   ON iu.inventory_unit_id = m.inventory_unit_id
JOIN inventory.skus s               ON s.sku_id             = m.sku_id
JOIN auth.users u                   ON u.id                 = m.moved_by_user_id
LEFT JOIN locations.bins fb         ON fb.bin_id            = m.from_bin_id
LEFT JOIN locations.bins tb         ON tb.bin_id            = m.to_bin_id;
GO
PRINT 'inventory.v_movements created.';
GO

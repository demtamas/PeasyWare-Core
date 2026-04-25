/********************************************************************************************
    OUTBOUND SCHEMA
    Tables, status masters, transitions, error codes.
    Schema: outbound
********************************************************************************************/

/********************************************************************************************
    WIP PATCH — Outbound schema
    Date: 2026-04-17

    1.  Create outbound schema
    2.  Stock state additions: PTW->PKD, PKD->SHP, PKD->PTW
    3.  outbound_order_statuses + transitions
    4.  outbound_line_statuses + transitions
    5.  allocation_statuses
    6.  shipment_statuses + transitions
    7.  outbound_orders
    8.  outbound_lines
    9.  outbound_allocations
    10. shipments
    11. shipment_orders
    12. Indexes
    13. Error codes
********************************************************************************************/


/********************************************************************************************
    1. Schema
********************************************************************************************/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'outbound')
    EXEC('CREATE SCHEMA outbound');
GO

PRINT 'outbound schema ready.';
GO

/********************************************************************************************
    2. Stock state additions for outbound lifecycle
       PTW → PKD   unit picked from rack
       PKD → SHP   unit shipped
       PKD → PTW   pick reversed — unit returned to storage
********************************************************************************************/
MERGE inventory.stock_state_transitions AS tgt
USING (VALUES
    ('PTW', 'PKD', 0, 'Unit picked from storage'),
    ('PKD', 'SHP', 0, 'Unit shipped'),
    ('PKD', 'PTW', 1, 'Pick reversed — unit returned to storage')
) AS src (from_state_code, to_state_code, requires_authority, notes)
ON  tgt.from_state_code = src.from_state_code
AND tgt.to_state_code   = src.to_state_code
WHEN NOT MATCHED THEN
    INSERT (from_state_code, to_state_code, requires_authority, notes)
    VALUES (src.from_state_code, src.to_state_code, src.requires_authority, src.notes);
GO

PRINT 'Outbound stock state transitions merged.';
GO

/********************************************************************************************
    3. outbound_order_statuses + transitions
********************************************************************************************/
GO

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
    lm_usr.username                                     AS last_moved_by
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
WHERE iu.stock_state_code <> 'REV'
  AND iu.stock_state_code <> 'SHP';
GO

CREATE OR ALTER VIEW inventory.v_units_awaiting_putaway
AS
SELECT
    iu.inventory_unit_id,
    iu.external_ref,
    iu.sku_id,
    iu.quantity,
    iu.created_at
FROM inventory.inventory_units iu
WHERE
    iu.stock_state_code = 'RCD'
    AND NOT EXISTS
    (
        SELECT 1
        FROM warehouse.warehouse_tasks wt
        WHERE wt.inventory_unit_id = iu.inventory_unit_id
          AND wt.task_type_code = 'PUTAWAY'
          AND wt.task_state_code IN ('OPN','CLM')
    );
GO

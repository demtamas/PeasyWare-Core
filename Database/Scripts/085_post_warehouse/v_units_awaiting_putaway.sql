USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

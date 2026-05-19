USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW warehouse.v_warehouse_tasks
AS
SELECT
    wt.task_id,
    wt.task_type_code,
    ts.state_desc                                   AS task_state,
    wt.task_state_code,
    ts.is_terminal,

    -- Inventory unit
    iu.inventory_unit_id,
    iu.external_ref                                 AS sscc,
    s.sku_code,
    s.sku_description,
    iu.quantity,
    iu.batch_number,

    -- Bins
    sb.bin_code                                     AS source_bin,
    db.bin_code                                     AS destination_bin,

    -- Assignment
    claimed_usr.username                            AS claimed_by,
    wt.claimed_at,
    wt.expires_at,

    -- Completion
    completed_usr.username                          AS completed_by,
    wt.completed_at,

    -- Audit
    created_usr.username                            AS created_by,
    wt.created_at,
    wt.updated_at

FROM warehouse.warehouse_tasks wt
JOIN warehouse.task_states ts
    ON ts.state_code = wt.task_state_code
JOIN inventory.inventory_units iu
    ON iu.inventory_unit_id = wt.inventory_unit_id
JOIN inventory.skus s
    ON s.sku_id = iu.sku_id
LEFT JOIN locations.bins sb
    ON sb.bin_id = wt.source_bin_id
LEFT JOIN locations.bins db
    ON db.bin_id = wt.destination_bin_id
LEFT JOIN auth.users claimed_usr
    ON claimed_usr.id = wt.claimed_by_user_id
LEFT JOIN auth.users completed_usr
    ON completed_usr.id = wt.completed_by_user_id
LEFT JOIN auth.users created_usr
    ON created_usr.id = wt.created_by;
GO
PRINT 'warehouse.v_warehouse_tasks created.';
GO

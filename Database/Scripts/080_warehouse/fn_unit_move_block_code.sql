USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.fn_unit_move_block_code
   ------------------------------------------------------------
   The single definition of "is this unit free to be moved?".
   Returns NULL when it is; otherwise the ERRMOVE* code saying
   why not. Used by every path that relocates a unit's
   placement (bin-to-bin create/confirm, and count corrections
   later), so the rule cannot drift between them.

   Rules, in order:
     ERRMOVE01  unit does not exist
     ERRMOVE02  state is not one the state machine lets enter MOV
                (inventory.stock_state_transitions drives this, so
                 PTW and RCD today; PKD/LDD/SHP/REV/SCR are out)
     ERRMOVE08  inventory.stock_operation_rules says can_move = 0
                for this state + status. Data-driven: flip the flag in
                the table to change it. No rule row = allowed. No
                seeded rule sets it today - blocked, QC-held and expired
                stock are all deliberately movable (e.g. out to a
                quarantine or scrap area).
     ERRMOVE03  unit has no current placement
     ERRMOVE10  unit has an open (OPN/CLM) task of any type, other
                than @ignore_task_id (the caller's own MOVE task)
   ============================================================ */
CREATE OR ALTER FUNCTION warehouse.fn_unit_move_block_code
(
    @inventory_unit_id INT,
    @ignore_task_id    INT
)
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE
        @state_code  VARCHAR(3),
        @status_code VARCHAR(2);

    SELECT
        @state_code  = stock_state_code,
        @status_code = stock_status_code
    FROM inventory.inventory_units
    WHERE inventory_unit_id = @inventory_unit_id;

    IF @state_code IS NULL
        RETURN N'ERRMOVE01';

    IF NOT EXISTS (
        SELECT 1
        FROM inventory.stock_state_transitions
        WHERE from_state_code = @state_code
          AND to_state_code   = 'MOV'
    )
        RETURN N'ERRMOVE02';

    IF EXISTS (
        SELECT 1
        FROM inventory.stock_operation_rules
        WHERE state_code  = @state_code
          AND status_code = @status_code
          AND can_move    = 0
    )
        RETURN N'ERRMOVE08';

    IF NOT EXISTS (
        SELECT 1
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id
    )
        RETURN N'ERRMOVE03';

    IF EXISTS (
        SELECT 1
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_state_code IN ('OPN', 'CLM')
          AND (@ignore_task_id IS NULL OR task_id <> @ignore_task_id)
    )
        RETURN N'ERRMOVE10';

    RETURN NULL;
END;
GO
PRINT 'warehouse.fn_unit_move_block_code created.';
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   inventory.usp_apply_scrap
   ------------------------------------------------------------
   The single place a unit is scrapped:
     - its placement is removed (it is no longer in any bin)
     - it moves to the terminal SCR state
     - one ADJUSTMENT row is written to the movement ledger, recording the
       bin it left, so the write-off can be reversed later

   Shared by usp_write_off_unit (reference MANUAL) and the stock-count
   adjustment (reference COUNT), so the effect cannot drift between them -
   the same split as warehouse.usp_apply_relocation. The RULES for whether a
   unit may be scrapped are NOT here: callers check them first and call this
   inside their own transaction, holding their own locks. No TRY/CATCH and no
   result set by design: an error propagates to the caller's CATCH and the
   whole transaction rolls back together.

   It refuses by itself, too, if what it is asked to do is not something the
   state machine allows: it THROWs if the unit does not exist, or if
   inventory.stock_state_transitions has no row from its current state to SCR.
   A ledger row claiming a write-off that the state machine forbids is worse
   than an error, so the invariant does not rest on every caller remembering.

   Returns the new ledger row id through @movement_id.
   ============================================================ */
CREATE OR ALTER PROCEDURE inventory.usp_apply_scrap
(
    @inventory_unit_id INT,
    @reference_type    NVARCHAR(30),
    @reference_id      INT,
    @user_id           INT,
    @session_id        UNIQUEIDENTIFIER,
    @movement_id       INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @from_state  VARCHAR(3),
        @status_code VARCHAR(2),
        @sku_id      INT,
        @quantity    INT,
        @from_bin_id INT,
        @now         DATETIME2(3) = SYSUTCDATETIME();

    SELECT
        @from_state  = stock_state_code,
        @status_code = stock_status_code,
        @sku_id      = sku_id,
        @quantity    = quantity
    FROM inventory.inventory_units
    WHERE inventory_unit_id = @inventory_unit_id;

    IF @from_state IS NULL
        THROW 50031, 'usp_apply_scrap: unit not found.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM inventory.stock_state_transitions
        WHERE from_state_code = @from_state
          AND to_state_code   = 'SCR'
    )
        THROW 50032, 'usp_apply_scrap: the stock state machine does not allow this unit to be scrapped from its current state.', 1;

    SELECT @from_bin_id = bin_id
    FROM inventory.inventory_placements
    WHERE inventory_unit_id = @inventory_unit_id;

    DELETE FROM inventory.inventory_placements
    WHERE inventory_unit_id = @inventory_unit_id;

    UPDATE inventory.inventory_units
    SET stock_state_code = 'SCR',
        updated_at       = @now,
        updated_by       = @user_id
    WHERE inventory_unit_id = @inventory_unit_id;

    INSERT INTO inventory.inventory_movements
        (inventory_unit_id, sku_id, moved_qty,
         from_bin_id, to_bin_id,
         from_state_code, to_state_code,
         from_status_code, to_status_code,
         movement_type, reference_type, reference_id,
         moved_at, moved_by_user_id, session_id)
    VALUES
        (@inventory_unit_id, @sku_id, @quantity,
         @from_bin_id, NULL,
         @from_state, 'SCR',
         @status_code, @status_code,
         N'ADJUSTMENT', @reference_type, @reference_id,
         @now, @user_id, @session_id);

    SET @movement_id = SCOPE_IDENTITY();
END;
GO
PRINT 'inventory.usp_apply_scrap created.';
GO

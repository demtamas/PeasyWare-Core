USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_apply_relocation
   ------------------------------------------------------------
   The single place a unit's recorded location actually changes:
     - placement -> destination bin
     - RCD leaving a STAGE bin becomes PTW (a move out of staging
       is a manual putaway, wherever it lands)
     - one inventory_movements ledger row

   Shared by bin-to-bin move confirm and the count correction, so
   the effect cannot drift between them. The RULES for whether a
   relocation is allowed are NOT here - callers check them first
   (warehouse.fn_unit_move_block_code / fn_bin_receive_block_code)
   and call this inside their own transaction, holding their own
   locks. No TRY/CATCH and no result set by design: an error
   propagates to the caller's CATCH (XACT_ABORT is on there) and
   the whole transaction rolls back together.

   Returns the new ledger row id through @movement_id.
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_apply_relocation
(
    @inventory_unit_id  INT,
    @destination_bin_id INT,
    @movement_type      NVARCHAR(30),
    @reference_type     NVARCHAR(30),
    @reference_id       INT,
    @user_id            INT,
    @session_id         UNIQUEIDENTIFIER,
    @movement_id        INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @source_bin_id INT,
        @sku_id        INT,
        @quantity      INT,
        @from_state    VARCHAR(3),
        @to_state      VARCHAR(3),
        @status_code   VARCHAR(2),
        @now           DATETIME2(3) = SYSUTCDATETIME();

    SELECT @source_bin_id = bin_id
    FROM inventory.inventory_placements
    WHERE inventory_unit_id = @inventory_unit_id;

    SELECT
        @sku_id      = sku_id,
        @quantity    = quantity,
        @from_state  = stock_state_code,
        @status_code = stock_status_code
    FROM inventory.inventory_units
    WHERE inventory_unit_id = @inventory_unit_id;

    UPDATE inventory.inventory_placements
    SET bin_id    = @destination_bin_id,
        placed_at = @now,
        placed_by = @user_id
    WHERE inventory_unit_id = @inventory_unit_id;

    SET @to_state = @from_state;

    IF @from_state = 'RCD'
       AND EXISTS (
            SELECT 1
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.bin_id = @source_bin_id
              AND st.storage_type_code = 'STAGE'
       )
    BEGIN
        SET @to_state = 'PTW';

        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;
    END

    INSERT INTO inventory.inventory_movements
        (inventory_unit_id, sku_id, moved_qty,
         from_bin_id, to_bin_id,
         from_state_code, to_state_code,
         from_status_code, to_status_code,
         movement_type, reference_type, reference_id,
         moved_at, moved_by_user_id, session_id)
    VALUES
        (@inventory_unit_id, @sku_id, @quantity,
         @source_bin_id, @destination_bin_id,
         @from_state, @to_state,
         @status_code, @status_code,
         @movement_type, @reference_type, @reference_id,
         @now, @user_id, @session_id);

    SET @movement_id = SCOPE_IDENTITY();
END;
GO
PRINT 'warehouse.usp_apply_relocation created.';
GO

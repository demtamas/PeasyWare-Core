USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.fn_bin_receive_block_code
   ------------------------------------------------------------
   The single definition of "can this bin take one more unit?".
   Returns NULL when it can; otherwise the ERRMOVE* code why not.

   Rules, in order:
     ERRMOVE04  bin does not exist
     ERRMOVE07  bin is inactive or locked
     ERRMOVE09  placements + unexpired reservations >= capacity

   Same occupancy calculation locations.usp_suggest_putaway_bin
   and warehouse.usp_putaway_confirm_task already use.

   A function cannot take locks. Callers that must be race-safe
   (move create/confirm) take UPDLOCK, HOLDLOCK on the bin row
   FIRST, then call this - it reads the committed picture under
   that lock. A caller confirming its own task must release that
   task's reservation before calling, or it counts against itself.
   ============================================================ */
CREATE OR ALTER FUNCTION warehouse.fn_bin_receive_block_code
(
    @bin_id INT
)
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE
        @capacity  INT,
        @is_active BIT,
        @is_locked BIT,
        @occupied  INT;

    SELECT
        @capacity  = capacity,
        @is_active = is_active,
        @is_locked = is_locked
    FROM locations.bins
    WHERE bin_id = @bin_id;

    IF @capacity IS NULL
        RETURN N'ERRMOVE04';

    IF @is_active = 0 OR @is_locked = 1
        RETURN N'ERRMOVE07';

    SET @occupied =
        (SELECT COUNT(*)
         FROM inventory.inventory_placements
         WHERE bin_id = @bin_id)
      + (SELECT COUNT(*)
         FROM locations.bin_reservations
         WHERE bin_id = @bin_id
           AND expires_at > SYSUTCDATETIME());

    IF @occupied >= @capacity
        RETURN N'ERRMOVE09';

    RETURN NULL;
END;
GO
PRINT 'warehouse.fn_bin_receive_block_code created.';
GO

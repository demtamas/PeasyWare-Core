USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   locations.fn_bin_is_being_counted
   ------------------------------------------------------------
   The single definition of "is this bin locked for a count?".
   1 when the bin holds an unexpired COUNT reservation, else 0.

   A COUNT reservation is a hard lock, not a capacity slot: while it
   stands nothing may be put into the bin and nothing may be taken out of
   it. Honoured by:
     warehouse.fn_bin_receive_block_code   (anything going in: move, putaway)
     warehouse.fn_unit_move_block_code     (anything moving out of it)
     locations.usp_suggest_putaway_bin     (never offered as a destination)
     warehouse.usp_putaway_confirm_task    (putaway into it)
     outbound.usp_pick_create / usp_pick_confirm (picking from it)

   The lock expires (warehouse.count_bin_ttl_seconds) so an abandoned count
   cannot pin a bin for ever. It is an optimisation, not the safeguard: the
   count's correctness comes from usp_count_finish_bin, which refuses to
   accept a bin if the movement ledger shows ANY change to it since the
   count opened - so a writer that does not honour the lock (receiving into
   staging, say) cannot corrupt a count, only make it be done again.

   Lives in 050_locations, with the reservations table, so everything built
   after it can call it.
   ============================================================ */
CREATE OR ALTER FUNCTION locations.fn_bin_is_being_counted
(
    @bin_id INT
)
RETURNS BIT
AS
BEGIN
    RETURN CASE
        WHEN EXISTS (
            SELECT 1
            FROM locations.bin_reservations
            WHERE bin_id           = @bin_id
              AND reservation_type = N'COUNT'
              AND expires_at       > SYSUTCDATETIME()
        )
        THEN 1 ELSE 0
    END;
END;
GO
PRINT 'locations.fn_bin_is_being_counted created.';
GO

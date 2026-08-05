USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE locations.usp_suggest_putaway_bin
(
    @inventory_unit_id INT,
    @suggested_bin_id INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @sku_id INT,
        @type_id INT,
        @section_id INT;

    /* --------------------------------------------------------
       1) Resolve SKU storage preferences
    -------------------------------------------------------- */
    SELECT
        @sku_id = iu.sku_id,
        @type_id = s.preferred_storage_type_id,
        @section_id = s.preferred_storage_section_id
    FROM inventory.inventory_units iu
    JOIN inventory.skus s
        ON iu.sku_id = s.sku_id
    WHERE iu.inventory_unit_id = @inventory_unit_id;

    IF @type_id IS NULL
        RETURN;

    /* --------------------------------------------------------
       2) Zone load - count of currently-active putaway tasks
          (OPN/CLM) per zone. Used as a ranking, not a hard
          filter: an empty zone sorts before a busy one, but if
          every eligible zone is equally loaded (e.g. one active
          task each), the tie resolves to the lowest zone_code -
          i.e. "double up in zone 1 again" rather than finding no
          candidate at all. The next task after that correctly
          moves on to zone 2 (now the least-loaded), and so on -
          the same ordering handles the normal case and the
          all-zones-busy case without needing separate logic.
    -------------------------------------------------------- */
    ;WITH zone_task_load AS
    (
        SELECT
            b.zone_id,
            COUNT(DISTINCT t.task_id) AS active_task_count
        FROM locations.bins b
        JOIN warehouse.warehouse_tasks t
            ON t.destination_bin_id = b.bin_id
           AND t.task_state_code IN ('CLM','OPN')
        WHERE b.zone_id IS NOT NULL
        GROUP BY b.zone_id
    ),

    /* --------------------------------------------------------
       3) Candidate bins
    -------------------------------------------------------- */
    bin_candidates AS
    (
        SELECT
            b.bin_id,
            b.zone_id,
            z.zone_code,
            b.capacity,

            /* existing pallets */
            ISNULL(p.placement_count,0) AS placement_count,

            /* active reservations */
            ISNULL(r.reservation_count,0) AS reservation_count,

            /* zone load */
            ISNULL(zl.active_task_count,0) AS zone_task_count

        FROM locations.bins b

        LEFT JOIN locations.zones z
            ON z.zone_id = b.zone_id

        LEFT JOIN zone_task_load zl
            ON zl.zone_id = b.zone_id

        OUTER APPLY
        (
            SELECT COUNT(*) AS placement_count
            FROM inventory.inventory_placements ip
            WHERE ip.bin_id = b.bin_id
        ) p

        OUTER APPLY
        (
            SELECT COUNT(*) AS reservation_count
            FROM locations.bin_reservations br
            WHERE br.bin_id = b.bin_id
              AND br.expires_at > SYSUTCDATETIME()
        ) r

        WHERE
            b.is_active = 1
            AND b.is_locked = 0
            AND b.storage_type_id = @type_id
            AND (@section_id IS NULL OR b.storage_section_id = @section_id)
    )

    /* --------------------------------------------------------
       4) Select best bin - least-loaded zone first, lowest
          zone_code as the tiebreak (covers both "skip the busy
          zone" and "all zones equally busy, start over from the
          first one" with the same ORDER BY), emptiest bin within
          that zone as the next tiebreak.
    -------------------------------------------------------- */
    SELECT TOP (1)
        @suggested_bin_id = bin_id
    FROM bin_candidates
    WHERE (placement_count + reservation_count) < capacity
    ORDER BY
        zone_task_count ASC,                           -- least-loaded zone first
        CASE WHEN zone_id IS NULL THEN 1 ELSE 0 END,   -- unzoned bins last
        TRY_CAST(zone_code AS INT) ASC,                -- numeric zone order among ties
        zone_code ASC,                                 -- fallback for non-numeric codes
        placement_count ASC,                           -- emptier bins preferred
        NEWID();                                        -- random tie break to prevent clustering

END
GO

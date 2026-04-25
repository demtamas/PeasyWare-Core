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
       2) Calculate zone activity (traffic awareness)
    -------------------------------------------------------- */
    ;WITH zone_load AS
    (
        SELECT
            b.zone_id,

            /* active putaway tasks */
            COUNT(DISTINCT t.task_id)

            +

            /* active reservations */
            COUNT(DISTINCT r.reservation_id)

            AS zone_activity

        FROM locations.bins b

        LEFT JOIN warehouse.warehouse_tasks t
            ON t.destination_bin_id = b.bin_id
           AND t.task_state_code IN ('CLM','OPN')

        LEFT JOIN locations.bin_reservations r
            ON r.bin_id = b.bin_id
           AND r.expires_at > SYSUTCDATETIME()

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
            b.capacity,

            /* existing pallets */
            ISNULL(p.placement_count,0) AS placement_count,

            /* active reservations */
            ISNULL(r.reservation_count,0) AS reservation_count,

            /* zone traffic */
            ISNULL(z.zone_activity,0) AS zone_activity

        FROM locations.bins b

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

        LEFT JOIN zone_load z
            ON z.zone_id = b.zone_id

        WHERE
            b.is_active = 1
            AND b.storage_type_id = @type_id
            AND (@section_id IS NULL OR b.storage_section_id = @section_id)
    )

    /* --------------------------------------------------------
       4) Select best bin
    -------------------------------------------------------- */
    SELECT TOP (1)
        @suggested_bin_id = bin_id
    FROM bin_candidates
    WHERE (placement_count + reservation_count) < capacity
    ORDER BY
        zone_activity ASC,       -- least busy zone first
        placement_count ASC,     -- emptier bins preferred
        NEWID();                 -- random tie break to prevent clustering

END
GO

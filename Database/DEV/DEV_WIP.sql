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
           AND t.task_state_code IN ('NEW','CLM','ACT')

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

CREATE OR ALTER PROCEDURE warehouse.usp_create_putaway_task
(
    @inventory_unit_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @sku_id INT,
        @stock_state VARCHAR(3),
        @current_bin_id INT,
        @dest_bin_id INT,
        @ttl_seconds INT,
        @expires_at DATETIME2(3),
        @task_id INT;

    BEGIN TRY
        BEGIN TRAN;

        -- Resolve inventory unit
        SELECT
            @sku_id = sku_id,
            @stock_state = stock_state_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        -- Must be in RECEIVED state
        IF @stock_state <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK02';
            ROLLBACK;
            RETURN;
        END

        -- Resolve current placement
        SELECT @current_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @current_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK03';
            ROLLBACK;
            RETURN;
        END

        -- Prevent duplicate tasks
        IF EXISTS (
            SELECT 1
            FROM warehouse.warehouse_tasks
            WHERE inventory_unit_id = @inventory_unit_id
            AND task_state_code IN ('OPN','CLM')
        )
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK05';
            ROLLBACK;
            RETURN;
        END

        -- Suggest destination bin
        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK04';
            ROLLBACK;
            RETURN;
        END

        -- Load TTL from settings
        SELECT @ttl_seconds =
            TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        -- Create task
        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code,
            inventory_unit_id,
            source_bin_id,
            destination_bin_id,
            task_state_code,
            expires_at,
            created_by
        )
        VALUES
        (
            'PUTAWAY',
            @inventory_unit_id,
            @current_bin_id,
            @dest_bin_id,
            'OPN',
            @expires_at,
            @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT
            CAST(1 AS BIT) AS success,
            'SUCTASK01' AS result_code,
            @task_id AS task_id,
            @dest_bin_id AS destination_bin_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT), 'ERRTASK99';
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_create_task_for_unit
(
    @inventory_unit_id INT,
    @user_id           INT,
    @session_id        UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @task_id INT,
        @dest_bin_id INT,
        @dest_bin_code NVARCHAR(100),
        @source_bin_id INT,
        @ttl_seconds INT,
        @expires_at DATETIME2(3),
        @sku_id INT,
        @state_code VARCHAR(3);

    BEGIN TRY
        BEGIN TRAN;

    ------------------------------------------------------------
    -- 1. Validate inventory unit
    ------------------------------------------------------------
        SELECT
            @sku_id = sku_id,
            @state_code = stock_state_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        IF @state_code <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK02';
            ROLLBACK;
            RETURN;
        END

    ------------------------------------------------------------
    -- 2. Resolve current placement
    ------------------------------------------------------------
        SELECT
            @source_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK03';
            ROLLBACK;
            RETURN;
        END

    ------------------------------------------------------------
    -- 3. Detect existing open task (idempotency)
    ------------------------------------------------------------
        SELECT TOP (1)
            @task_id = task_id,
            @dest_bin_id = destination_bin_id
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
        AND task_state_code IN ('OPN','CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            SELECT @dest_bin_code = bin_code
            FROM locations.bins
            WHERE bin_id = @dest_bin_id;

            COMMIT;

            SELECT
                CAST(1 AS BIT),
                N'SUCTASK01',
                @task_id,
                @dest_bin_code;

            RETURN;
        END

    ------------------------------------------------------------
    -- 4. Suggest destination bin
    ------------------------------------------------------------
        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK04';
            ROLLBACK;
            RETURN;
        END

        SELECT
            @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

    ------------------------------------------------------------
    -- 5. Resolve TTL from settings
    ------------------------------------------------------------
        SELECT
            @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL
            SET @ttl_seconds = 300;

        SET @expires_at =
            DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

    ------------------------------------------------------------
    -- 6. Insert warehouse task
    ------------------------------------------------------------
        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code,
            inventory_unit_id,
            source_bin_id,
            destination_bin_id,
            task_state_code,
            expires_at,
            created_by
        )
        VALUES
        (
            'PUTAWAY',
            @inventory_unit_id,
            @source_bin_id,
            @dest_bin_id,
            'OPN',
            @expires_at,
            @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

    ------------------------------------------------------------
    -- 7. Create bin reservation
    ------------------------------------------------------------
        INSERT INTO locations.bin_reservations
        (
            bin_id,
            reservation_type,
            reserved_by,
            expires_at
        )
        VALUES
        (
            @dest_bin_id,
            'PUTAWAY',
            @user_id,
            @expires_at
        );

    ------------------------------------------------------------
    -- 8. Success
    ------------------------------------------------------------
        COMMIT;

        SELECT
            CAST(1 AS BIT),
            N'SUCTASK01',
            @task_id,
            @dest_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        SELECT
            CAST(0 AS BIT),
            N'ERRTASK99';
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_confirm_task
(
    @task_id    INT,
    @user_id    INT,
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @inventory_unit_id INT,
        @source_bin_id INT,
        @dest_bin_id INT,
        @sku_id INT,
        @quantity INT,
        @task_state VARCHAR(3),
        @now DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

    ------------------------------------------------------------
    -- 1. Lock task
    ------------------------------------------------------------
        SELECT
            @inventory_unit_id = inventory_unit_id,
            @source_bin_id     = source_bin_id,
            @dest_bin_id       = destination_bin_id,
            @task_state        = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id = @task_id;

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        IF @task_state NOT IN ('OPN','CLM')
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK07';
            ROLLBACK;
            RETURN;
        END

    ------------------------------------------------------------
    -- 2. Lock inventory unit
    ------------------------------------------------------------
        SELECT
            @sku_id   = sku_id,
            @quantity = quantity
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

    ------------------------------------------------------------
    -- 3. Move placement
    ------------------------------------------------------------
        UPDATE inventory.inventory_placements
        SET bin_id = @dest_bin_id,
            placed_at = @now,
            placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

    ------------------------------------------------------------
    -- 4. Transition inventory lifecycle
    ------------------------------------------------------------
        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW'
        WHERE inventory_unit_id = @inventory_unit_id
        AND stock_state_code = 'RCD';

    ------------------------------------------------------------
    -- 5. Close warehouse task
    ------------------------------------------------------------
        UPDATE warehouse.warehouse_tasks
        SET task_state_code = 'CNF',
            completed_at    = @now,
            completed_by_user_id    = @user_id
        WHERE task_id = @task_id;

    ------------------------------------------------------------
    -- 6. Remove reservation
    ------------------------------------------------------------
        DELETE FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id
        AND reservation_type = 'PUTAWAY'
        AND expires_at >= @now;

    ------------------------------------------------------------
    -- 7. Inventory movement log
    ------------------------------------------------------------
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id,
            sku_id,
            moved_qty,
            from_bin_id,
            to_bin_id,
            from_status_code,
            to_status_code,
            movement_type,
            reference_type,
            reference_id,
            moved_at,
            moved_by_user_id,
            session_id
        )
        VALUES
        (
            @inventory_unit_id,
            @sku_id,
            @quantity,
            @source_bin_id,
            @dest_bin_id,
            NULL,
            'AV',
            'PUTAWAY',
            'TASK',
            @task_id,
            @now,
            @user_id,
            @session_id
        );

    ------------------------------------------------------------
    -- 8. Success
    ------------------------------------------------------------
        COMMIT;

        SELECT
            CAST(1 AS BIT),
            N'SUCTASK02';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        SELECT
            CAST(0 AS BIT),
            N'ERRTASK99';
    END CATCH
END
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


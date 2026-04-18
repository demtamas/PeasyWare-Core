USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — Outbound stored procedures
    Date: 2026-04-17

    1. outbound.usp_create_order
    2. outbound.usp_allocate_order
    3. outbound.usp_create_shipment
    4. outbound.usp_add_order_to_shipment
    5. outbound.usp_pick_create
    6. outbound.usp_pick_confirm
    7. outbound.usp_ship
********************************************************************************************/


/********************************************************************************************
    1. outbound.usp_create_order
    Creates outbound order header + lines in a single transaction.

    @lines_json — JSON array of line objects:
    [
      { "line_no": 1, "sku_code": "SKU001", "ordered_qty": 2,
        "requested_batch": null, "requested_bbe": null, "notes": null },
      ...
    ]

    Contract: success BIT | result_code NVARCHAR(20) | outbound_order_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_create_order
(
    @order_ref          NVARCHAR(50),
    @customer_party_id  INT,
    @haulier_party_id   INT           = NULL,
    @required_date      DATE          = NULL,
    @order_source       VARCHAR(10)   = 'MANUAL',
    @notes              NVARCHAR(500) = NULL,
    @lines_json         NVARCHAR(MAX),          -- JSON array of lines
    @user_id            INT           = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @outbound_order_id INT;

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order ref uniqueness ── */
        IF EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = @order_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD03' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate customer exists ── */
        IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_id = @customer_party_id AND is_active = 1)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 3. Validate lines JSON not empty ── */
        IF @lines_json IS NULL OR ISJSON(@lines_json) = 0
           OR NOT EXISTS (SELECT 1 FROM OPENJSON(@lines_json))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD04' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 4. Insert order header ── */
        INSERT INTO outbound.outbound_orders
        (
            order_ref, customer_party_id, haulier_party_id,
            order_status_code, order_source,
            required_date, notes,
            created_at, created_by
        )
        VALUES
        (
            @order_ref, @customer_party_id, @haulier_party_id,
            'NEW', @order_source,
            @required_date, @notes,
            SYSUTCDATETIME(), @user_id
        );

        SET @outbound_order_id = SCOPE_IDENTITY();

        /* ── 5. Insert lines from JSON ── */
        INSERT INTO outbound.outbound_lines
        (
            outbound_order_id, line_no, sku_id,
            ordered_qty, requested_batch, requested_bbe,
            line_status_code, notes,
            created_at, created_by
        )
        SELECT
            @outbound_order_id,
            CAST(j.line_no AS INT),
            s.sku_id,
            CAST(j.ordered_qty AS INT),
            NULLIF(j.requested_batch, ''),
            TRY_CAST(NULLIF(j.requested_bbe, '') AS DATE),
            'NEW',
            NULLIF(j.notes, ''),
            SYSUTCDATETIME(),
            @user_id
        FROM OPENJSON(@lines_json)
        WITH (
            line_no         INT            '$.line_no',
            sku_code        NVARCHAR(50)   '$.sku_code',
            ordered_qty     INT            '$.ordered_qty',
            requested_batch NVARCHAR(100)  '$.requested_batch',
            requested_bbe   NVARCHAR(20)   '$.requested_bbe',
            notes           NVARCHAR(500)  '$.notes'
        ) j
        JOIN inventory.skus s
            ON s.sku_code = j.sku_code
           AND s.is_active = 1;

        /* ── 6. Verify all lines resolved (no unknown SKU codes) ── */
        DECLARE @json_line_count   INT = (SELECT COUNT(*) FROM OPENJSON(@lines_json));
        DECLARE @inserted_count    INT = (SELECT COUNT(*) FROM outbound.outbound_lines
                                          WHERE outbound_order_id = @outbound_order_id);

        IF @inserted_count <> @json_line_count
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD04' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code, @outbound_order_id AS outbound_order_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
    END CATCH
END;
GO
PRINT 'outbound.usp_create_order created.';
GO


/********************************************************************************************
    2. outbound.usp_allocate_order
    Allocation engine — reserves stock for every line on an order.

    Strategy (driven by operations.settings 'outbound.allocation_strategy'):
      FEFO  — earliest best_before_date first
      FIFO  — earliest received_at first
      NONE  — FEFO if BBE present on unit, else FIFO (default)

    Rules:
      - Only PUTAWAY + AVAILABLE units
      - Full pallets only (unit quantity must satisfy line qty requirement)
      - Respects requested_batch and requested_bbe on line if set
      - Per-SKU allocation: per-line override on batch/BBE takes priority
      - All lines must be satisfiable — partial allocation rolls back

    Contract: success BIT | result_code NVARCHAR(20) | outbound_order_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_allocate_order
(
    @outbound_order_id  INT,
    @user_id            INT           = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @order_status   VARCHAR(10),
        @strategy       NVARCHAR(20),
        @now            DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order ── */
        SELECT @order_status = order_status_code
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        IF @order_status <> 'NEW'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code, @outbound_order_id AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 2. Read allocation strategy setting ── */
        SELECT @strategy = UPPER(LTRIM(RTRIM(setting_value)))
        FROM operations.settings
        WHERE setting_name = 'outbound.allocation_strategy';

        IF @strategy IS NULL OR @strategy NOT IN ('FEFO','FIFO','LIFO','NONE')
            SET @strategy = 'NONE';

        /* ── 3. Allocate each line ── */
        DECLARE
            @line_id         INT,
            @sku_id          INT,
            @ordered_qty     INT,
            @req_batch       NVARCHAR(100),
            @req_bbe         DATE,
            @unit_id         INT,
            @unit_qty        INT,
            @remaining       INT,
            @allocated_total INT;

        DECLARE line_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT outbound_line_id, sku_id, ordered_qty, requested_batch, requested_bbe
            FROM outbound.outbound_lines
            WHERE outbound_order_id = @outbound_order_id
              AND line_status_code  = 'NEW';

        OPEN line_cursor;
        FETCH NEXT FROM line_cursor INTO @line_id, @sku_id, @ordered_qty, @req_batch, @req_bbe;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @remaining       = @ordered_qty;
            SET @allocated_total = 0;

            /* ── Per line: find eligible units ordered by strategy ── */
            DECLARE unit_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT iu.inventory_unit_id, iu.quantity
                FROM inventory.inventory_units iu WITH (UPDLOCK)
                JOIN inventory.inventory_placements ip
                    ON ip.inventory_unit_id = iu.inventory_unit_id
                JOIN locations.bins b
                    ON b.bin_id = ip.bin_id
                JOIN locations.storage_types st
                    ON st.storage_type_id = b.storage_type_id
                WHERE iu.sku_id           = @sku_id
                  AND iu.stock_state_code = 'PTW'
                  AND iu.stock_status_code = 'AV'
                  -- Respect requested batch / BBE if specified on the line
                  AND (@req_batch IS NULL OR iu.batch_number    = @req_batch)
                  AND (@req_bbe   IS NULL OR iu.best_before_date = @req_bbe)
                  -- Only allocate from storage, not staging
                  AND st.storage_type_code <> 'STAGE'
                  -- Not already allocated
                  AND NOT EXISTS (
                      SELECT 1 FROM outbound.outbound_allocations a
                      WHERE a.inventory_unit_id = iu.inventory_unit_id
                        AND a.allocation_status <> 'CANCELLED'
                  )
                ORDER BY
                    CASE
                        WHEN @strategy = 'FEFO' THEN
                            CASE WHEN iu.best_before_date IS NOT NULL
                                 THEN CAST(iu.best_before_date AS DATETIME2)
                                 ELSE '9999-12-31'
                            END
                        WHEN @strategy = 'FIFO' THEN iu.created_at
                        WHEN @strategy = 'LIFO' THEN CAST('9999-12-31' AS DATETIME2)
                        WHEN @strategy = 'NONE' THEN
                            CASE WHEN iu.best_before_date IS NOT NULL
                                 THEN CAST(iu.best_before_date AS DATETIME2)
                                 ELSE iu.created_at
                            END
                        ELSE iu.created_at
                    END ASC,
                    CASE WHEN @strategy = 'LIFO' THEN iu.created_at END DESC;

            OPEN unit_cursor;
            FETCH NEXT FROM unit_cursor INTO @unit_id, @unit_qty;

            WHILE @@FETCH_STATUS = 0 AND @remaining > 0
            BEGIN
                IF @unit_qty <= @remaining
                BEGIN
                    INSERT INTO outbound.outbound_allocations
                    (
                        outbound_line_id, inventory_unit_id,
                        allocated_qty, allocation_status,
                        allocated_at, allocated_by
                    )
                    VALUES
                    (
                        @line_id, @unit_id,
                        @unit_qty, 'PENDING',
                        @now, @user_id
                    );

                    SET @remaining       -= @unit_qty;
                    SET @allocated_total += @unit_qty;
                END

                FETCH NEXT FROM unit_cursor INTO @unit_id, @unit_qty;
            END

            CLOSE unit_cursor;
            DEALLOCATE unit_cursor;

            /* ── Check line fully allocated ── */
            IF @remaining > 0
            BEGIN
                CLOSE line_cursor;
                DEALLOCATE line_cursor;

                IF @req_batch IS NOT NULL OR @req_bbe IS NOT NULL
                    SELECT CAST(0 AS BIT) AS success, N'ERRALLOC02' AS result_code, @outbound_order_id AS outbound_order_id;
                ELSE
                    SELECT CAST(0 AS BIT) AS success, N'ERRALLOC01' AS result_code, @outbound_order_id AS outbound_order_id;

                ROLLBACK; RETURN;
            END

            /* ── Update line ── */
            UPDATE outbound.outbound_lines
            SET allocated_qty    = @ordered_qty,
                line_status_code = 'ALLOCATED',
                updated_at       = @now,
                updated_by       = @user_id
            WHERE outbound_line_id = @line_id;

            FETCH NEXT FROM line_cursor INTO @line_id, @sku_id, @ordered_qty, @req_batch, @req_bbe;
        END

        CLOSE line_cursor;
        DEALLOCATE line_cursor;

        /* ── Update order header ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'ALLOCATED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD02' AS result_code, @outbound_order_id AS outbound_order_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF CURSOR_STATUS('local','line_cursor') >= 0 BEGIN CLOSE line_cursor; DEALLOCATE line_cursor; END
        IF CURSOR_STATUS('local','unit_cursor') >= 0 BEGIN CLOSE unit_cursor; DEALLOCATE unit_cursor; END
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
    END CATCH
END;
GO
PRINT 'outbound.usp_allocate_order created.';
GO


/********************************************************************************************
    3. outbound.usp_create_shipment
    Contract: success BIT | result_code NVARCHAR(20) | shipment_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_create_shipment
(
    @shipment_ref           NVARCHAR(50),
    @haulier_party_id       INT           = NULL,
    @vehicle_ref            NVARCHAR(50)  = NULL,
    @ship_from_address_id   INT,
    @planned_departure      DATETIME2(3)  = NULL,
    @notes                  NVARCHAR(500) = NULL,
    @user_id                INT           = NULL,
    @session_id             UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @shipment_id INT;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = @shipment_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP03' AS result_code, NULL AS shipment_id;
            ROLLBACK; RETURN;
        END

        INSERT INTO outbound.shipments
        (
            shipment_ref, haulier_party_id, vehicle_ref,
            ship_from_address_id, planned_departure,
            shipment_status, notes,
            created_at, created_by
        )
        VALUES
        (
            @shipment_ref, @haulier_party_id, @vehicle_ref,
            @ship_from_address_id, @planned_departure,
            'OPEN', @notes,
            SYSUTCDATETIME(), @user_id
        );

        SET @shipment_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP01' AS result_code, @shipment_id AS shipment_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code, NULL AS shipment_id;
    END CATCH
END;
GO
PRINT 'outbound.usp_create_shipment created.';
GO


/********************************************************************************************
    4. outbound.usp_add_order_to_shipment
    Links an allocated order to an open shipment.
    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_add_order_to_shipment
(
    @outbound_order_id  INT,
    @shipment_id        INT,
    @user_id            INT           = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @order_status    VARCHAR(10),
        @shipment_status VARCHAR(10);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @order_status = order_status_code
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('ALLOCATED','PICKING','PICKED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        SELECT @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_id = @shipment_id;

        IF @shipment_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @shipment_status NOT IN ('OPEN','LOADING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Link order to shipment
        UPDATE outbound.outbound_orders
        SET shipment_id = @shipment_id,
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        -- Junction row
        IF NOT EXISTS (
            SELECT 1 FROM outbound.shipment_orders
            WHERE shipment_id = @shipment_id
              AND outbound_order_id = @outbound_order_id
        )
        BEGIN
            INSERT INTO outbound.shipment_orders
                (shipment_id, outbound_order_id, added_at, added_by)
            VALUES
                (@shipment_id, @outbound_order_id, SYSUTCDATETIME(), @user_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_add_order_to_shipment created.';
GO


/********************************************************************************************
    5. outbound.usp_pick_create
    Creates a PICK task for an allocation. Transitions unit to PKD.

    Contract:
      success BIT | result_code NVARCHAR(20) | task_id INT
      | inventory_unit_id INT | source_bin_code NVARCHAR(100)
      | destination_bin_code NVARCHAR(100)
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_pick_create
(
    @allocation_id  INT,
    @user_id        INT,
    @session_id     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inventory_unit_id  INT,
        @outbound_line_id   INT,
        @alloc_status       VARCHAR(10),
        @unit_state         VARCHAR(3),
        @source_bin_id      INT,
        @source_bin_code    NVARCHAR(100),
        @staging_bin_id     INT,
        @staging_bin_code   NVARCHAR(100),
        @task_id            INT,
        @ttl_seconds        INT,
        @expires_at         DATETIME2(3),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve allocation ── */
        SELECT
            @inventory_unit_id = a.inventory_unit_id,
            @outbound_line_id  = a.outbound_line_id,
            @alloc_status      = a.allocation_status
        FROM outbound.outbound_allocations a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.allocation_id = @allocation_id;

        IF @inventory_unit_id IS NULL OR @alloc_status <> 'PENDING'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK01' AS result_code,
                   NULL AS task_id, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate unit state ── */
        SELECT @unit_state = stock_state_code
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @unit_state <> 'PTW'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK02' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Get source bin ── */
        SELECT
            @source_bin_id   = b.bin_id,
            @source_bin_code = b.bin_code
        FROM inventory.inventory_placements ip
        JOIN locations.bins b ON b.bin_id = ip.bin_id
        WHERE ip.inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Destination = first active staging bin ── */
        SELECT TOP 1
            @staging_bin_id   = b.bin_id,
            @staging_bin_code = b.bin_code
        FROM locations.bins b
        JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
        WHERE st.storage_type_code = 'STAGE'
          AND b.is_active = 1
        ORDER BY b.bin_code;

        IF @staging_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK04' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   @source_bin_code AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        /* ── 5. Create PICK task ── */
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code, inventory_unit_id,
            source_bin_id, destination_bin_id,
            task_state_code, expires_at, created_by
        )
        VALUES
        (
            'PICK', @inventory_unit_id,
            @source_bin_id, @staging_bin_id,
            'OPN', @expires_at, @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        /* ── 6. Update allocation status ── */
        UPDATE outbound.outbound_allocations
        SET allocation_status = 'CONFIRMED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE allocation_id = @allocation_id;

        /* ── 7. Update order line status → PICKING ── */
        UPDATE outbound.outbound_lines
        SET line_status_code = 'PICKING',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE outbound_line_id = @outbound_line_id
          AND line_status_code = 'ALLOCATED';

        /* ── 8. Update order header → PICKING ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'PICKING',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = (
            SELECT outbound_order_id
            FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id
        )
        AND order_status_code = 'ALLOCATED';

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
               @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
               @source_bin_code AS source_bin_code,
               @staging_bin_code AS destination_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_pick_create created.';
GO


/********************************************************************************************
    6. outbound.usp_pick_confirm
    Operator scans bin then SSCC to confirm physical pick.
    Moves unit placement to staging bin, transitions unit to PKD,
    writes PICK movement record.

    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_pick_confirm
(
    @task_id            INT,
    @scanned_bin_code   NVARCHAR(100),
    @scanned_sscc       NVARCHAR(100),
    @user_id            INT,
    @session_id         UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inventory_unit_id   INT,
        @sku_id              INT,
        @quantity            INT,
        @stock_status_code   VARCHAR(2),
        @source_bin_id       INT,
        @source_bin_code     NVARCHAR(100),
        @dest_bin_id         INT,
        @dest_bin_code       NVARCHAR(100),
        @task_state          VARCHAR(3),
        @unit_external_ref   NVARCHAR(100),
        @outbound_line_id    INT,
        @allocation_id       INT,
        @outbound_order_id   INT,
        @now                 DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Resolve task ── */
        SELECT
            @inventory_unit_id = t.inventory_unit_id,
            @source_bin_id     = t.source_bin_id,
            @dest_bin_id       = t.destination_bin_id,
            @task_state        = t.task_state_code
        FROM warehouse.warehouse_tasks t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.task_id       = @task_id
          AND t.task_type_code = 'PICK';

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @task_state NOT IN ('OPN','CLM')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate scanned bin matches source ── */
        SELECT @source_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @source_bin_id;

        IF LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@source_bin_code))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK03' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Validate scanned SSCC matches allocated unit ── */
        SELECT
            @unit_external_ref = iu.external_ref,
            @sku_id            = iu.sku_id,
            @quantity          = iu.quantity,
            @stock_status_code = iu.stock_status_code
        FROM inventory.inventory_units iu WITH (UPDLOCK, HOLDLOCK)
        WHERE iu.inventory_unit_id = @inventory_unit_id;

        IF LTRIM(RTRIM(@scanned_sscc)) <> LTRIM(RTRIM(@unit_external_ref))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPICK02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Get destination bin code ── */
        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        /* ── 5. Move placement to staging ── */
        UPDATE inventory.inventory_placements
        SET bin_id    = @dest_bin_id,
            placed_at = @now,
            placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        /* ── 6. Transition unit → PKD ── */
        UPDATE inventory.inventory_units
        SET stock_state_code = 'PKD',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        /* ── 7. Complete task ── */
        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        /* ── 8. Write PICK movement ── */
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id
        )
        VALUES
        (
            @inventory_unit_id, @sku_id, @quantity,
            @source_bin_id, @dest_bin_id,
            'PTW', 'PKD',
            @stock_status_code, @stock_status_code,
            'PICK', 'TASK', @task_id,
            @now, @user_id, @session_id
        );

        /* ── 9. Update allocation → PICKED ── */
        SELECT @allocation_id = allocation_id
        FROM outbound.outbound_allocations
        WHERE inventory_unit_id = @inventory_unit_id
          AND allocation_status = 'CONFIRMED';

        IF @allocation_id IS NOT NULL
        BEGIN
            UPDATE outbound.outbound_allocations
            SET allocation_status = 'PICKED',
                updated_at        = @now,
                updated_by        = @user_id
            WHERE allocation_id = @allocation_id;

            /* ── 10. Update line picked_qty and status ── */
            SELECT @outbound_line_id = outbound_line_id
            FROM outbound.outbound_allocations
            WHERE allocation_id = @allocation_id;

            UPDATE outbound.outbound_lines
            SET picked_qty       = picked_qty + @quantity,
                line_status_code = CASE
                    WHEN (picked_qty + @quantity) >= ordered_qty THEN 'PICKED'
                    ELSE 'PICKING'
                END,
                updated_at = @now,
                updated_by = @user_id
            WHERE outbound_line_id = @outbound_line_id;

            /* ── 11. Check if all lines picked → update order ── */
            SELECT @outbound_order_id = outbound_order_id
            FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id;

            IF NOT EXISTS (
                SELECT 1 FROM outbound.outbound_lines
                WHERE outbound_order_id = @outbound_order_id
                  AND line_status_code NOT IN ('PICKED','CNL')
            )
            BEGIN
                UPDATE outbound.outbound_orders
                SET order_status_code = 'PICKED',
                    updated_at        = @now,
                    updated_by        = @user_id
                WHERE outbound_order_id = @outbound_order_id;
            END
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCPICK01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_pick_confirm created.';
GO


/********************************************************************************************
    7. outbound.usp_ship
    Closes a shipment. All orders on the shipment must be PICKED or LOADED.
    Transitions all allocated units to SHP, writes SHIP movement per unit,
    sets actual_departure, closes shipment to DEPARTED.

    Contract: success BIT | result_code NVARCHAR(20) | shipment_id INT
              | units_shipped INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE outbound.usp_ship
(
    @shipment_id    INT,
    @user_id        INT,
    @session_id     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @shipment_status VARCHAR(10),
        @units_shipped   INT = 0,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_id = @shipment_id;

        IF @shipment_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code,
                   NULL AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        IF @shipment_status NOT IN ('OPEN','LOADING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Check all orders are PICKED or LOADED ── */
        IF EXISTS (
            SELECT 1 FROM outbound.outbound_orders
            WHERE shipment_id       = @shipment_id
              AND order_status_code NOT IN ('PICKED','LOADED','CNL')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP04' AS result_code,
                   @shipment_id AS shipment_id, 0 AS units_shipped;
            ROLLBACK; RETURN;
        END

        /* ── Ship each allocated unit ── */
        DECLARE
            @unit_id           INT,
            @sku_id            INT,
            @qty               INT,
            @status_code       VARCHAR(2),
            @from_bin_id       INT;

        DECLARE ship_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                iu.inventory_unit_id,
                iu.sku_id,
                iu.quantity,
                iu.stock_status_code,
                ip.bin_id
            FROM outbound.outbound_orders o
            JOIN outbound.outbound_lines ol
                ON ol.outbound_order_id = o.outbound_order_id
            JOIN outbound.outbound_allocations a
                ON a.outbound_line_id = ol.outbound_line_id
               AND a.allocation_status = 'PICKED'
            JOIN inventory.inventory_units iu WITH (UPDLOCK)
                ON iu.inventory_unit_id = a.inventory_unit_id
            JOIN inventory.inventory_placements ip
                ON ip.inventory_unit_id = iu.inventory_unit_id
            WHERE o.shipment_id = @shipment_id;

        OPEN ship_cursor;
        FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* Transition unit → SHP */
            UPDATE inventory.inventory_units
            SET stock_state_code = 'SHP',
                updated_at       = @now,
                updated_by       = @user_id
            WHERE inventory_unit_id = @unit_id;

            /* Remove placement — unit is no longer in the warehouse */
            DELETE FROM inventory.inventory_placements
            WHERE inventory_unit_id = @unit_id;

            /* Write SHIP movement */
            INSERT INTO inventory.inventory_movements
            (
                inventory_unit_id, sku_id, moved_qty,
                from_bin_id, to_bin_id,
                from_state_code, to_state_code,
                from_status_code, to_status_code,
                movement_type, reference_type, reference_id,
                moved_at, moved_by_user_id, session_id
            )
            VALUES
            (
                @unit_id, @sku_id, @qty,
                @from_bin_id, NULL,
                'PKD', 'SHP',
                @status_code, @status_code,
                'SHIP', 'SHIPMENT', @shipment_id,
                @now, @user_id, @session_id
            );

            SET @units_shipped += 1;

            FETCH NEXT FROM ship_cursor INTO @unit_id, @sku_id, @qty, @status_code, @from_bin_id;
        END

        CLOSE ship_cursor;
        DEALLOCATE ship_cursor;

        /* ── Update all orders on shipment → SHIPPED ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'SHIPPED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE shipment_id       = @shipment_id
          AND order_status_code IN ('PICKED','LOADED');

        /* ── Update all lines on these orders → PICKED (terminal) ── */
        UPDATE ol
        SET ol.line_status_code = 'PICKED',
            ol.updated_at       = @now,
            ol.updated_by       = @user_id
        FROM outbound.outbound_lines ol
        JOIN outbound.outbound_orders o
            ON o.outbound_order_id = ol.outbound_order_id
        WHERE o.shipment_id = @shipment_id
          AND ol.line_status_code <> 'CNL';

        /* ── Close shipment ── */
        UPDATE outbound.shipments
        SET shipment_status  = 'DEPARTED',
            actual_departure = @now,
            updated_at       = @now,
            updated_by       = @user_id
        WHERE shipment_id = @shipment_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP02' AS result_code,
               @shipment_id AS shipment_id, @units_shipped AS units_shipped;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF CURSOR_STATUS('local','ship_cursor') >= 0 BEGIN CLOSE ship_cursor; DEALLOCATE ship_cursor; END
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code,
               NULL AS shipment_id, 0 AS units_shipped;
    END CATCH
END;
GO
PRINT 'outbound.usp_ship created.';
GO


/********************************************************************************************
    Add allocation_strategy setting
********************************************************************************************/
IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'outbound.allocation_strategy')
BEGIN
    INSERT INTO operations.settings
    (
        setting_name, display_name, category, display_order,
        setting_value, data_type, validation_rule, description
    )
    VALUES
    (
        'outbound.allocation_strategy',
        'Allocation strategy',
        'outbound', 10,
        'NONE',
        'string',
        '{"type":"enum","values":["FEFO","FIFO","LIFO","NONE"]}',
        'Stock allocation strategy. NONE = FEFO if BBE present, else FIFO.'
    );
    PRINT 'outbound.allocation_strategy setting added.';
END
GO

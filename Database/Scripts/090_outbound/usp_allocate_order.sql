USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_allocate_order
(
    @outbound_order_id          INT,
    @allow_partial              BIT              = 0,
    @allow_shelf_life_override  BIT              = 0,
    @user_id                    INT              = NULL,
    @session_id                 UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @order_status      VARCHAR(10),
        @customer_party_id INT,
        @required_date     DATE,
        @delivery_date     DATE,
        @strategy          NVARCHAR(20),
        @now               DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order ── */
        SELECT
            @order_status      = order_status_code,
            @customer_party_id = customer_party_id,
            @required_date     = required_date
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        -- Computed here, before validation, so it's available (and
        -- included) on every result set below, not just the success path -
        -- knowing the delivery date used is exactly the context needed to
        -- diagnose a shelf-life-driven shortfall (ERRALLOC01/02).
        SET @delivery_date = COALESCE(@required_date, CAST(@now AS DATE));

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id, @delivery_date AS delivery_date;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('NEW', 'ALLOCATED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code, @outbound_order_id AS outbound_order_id, @delivery_date AS delivery_date;
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
            @line_id              INT,
            @sku_id               INT,
            @ordered_qty          INT,
            @req_batch            NVARCHAR(100),
            @req_bbe              DATE,
            @required_min_days    INT,
            @unit_id              INT,
            @unit_qty             INT,
            @remaining            INT,
            @allocated_total      INT,
            @newly_allocated_qty  INT = 0;

        -- Captures every unit actually allocated in this call, so the caller
        -- can log (and later search) which SSCCs/SKUs were affected, not just
        -- the order ID. required_min_days is backfilled per-line after each
        -- line's unit_cursor completes (OUTPUT can only capture columns
        -- actually being inserted into outbound_allocations, and this isn't
        -- one of them - it's the requirement that applied to the decision,
        -- not something that belongs stored on the allocation row itself).
        DECLARE @new_allocations TABLE
        (
            allocation_id      INT,
            inventory_unit_id  INT,
            outbound_line_id   INT,
            allocated_qty      INT,
            required_min_days  INT NULL
        );

        DECLARE line_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT outbound_line_id, sku_id, ordered_qty, requested_batch, requested_bbe
            FROM outbound.outbound_lines
            WHERE outbound_order_id = @outbound_order_id
              AND line_status_code IN ('NEW', 'ALLOCATED', 'PICKING')
              AND allocated_qty < ordered_qty;

        OPEN line_cursor;
        FETCH NEXT FROM line_cursor INTO @line_id, @sku_id, @ordered_qty, @req_batch, @req_bbe;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Start remaining from what's not yet allocated on this line
            -- so partial re-allocation after deallocation works correctly
            SELECT @allocated_total = ISNULL(SUM(a.allocated_qty), 0)
            FROM outbound.outbound_allocations a
            WHERE a.outbound_line_id  = @line_id
              AND a.allocation_status <> 'CANCELLED';

            SET @remaining = @ordered_qty - @allocated_total;

            IF @remaining <= 0
            BEGIN
                FETCH NEXT FROM line_cursor INTO @line_id, @sku_id, @ordered_qty, @req_batch, @req_bbe;
                CONTINUE;
            END

            SET @allocated_total = 0;

            -- Cascading lookup: customer+SKU override -> SKU default -> 0
            -- (0 is the floor itself - BBE simply must be in the future
            -- relative to delivery date when nothing is configured).
            SET @required_min_days = COALESCE(
                (SELECT csl.minimum_remaining_shelf_life_days
                 FROM inventory.customer_shelf_life_requirements csl
                 WHERE csl.customer_party_id = @customer_party_id
                   AND csl.sku_id            = @sku_id),
                (SELECT sk.minimum_remaining_shelf_life_days
                 FROM inventory.skus sk
                 WHERE sk.sku_id = @sku_id),
                0
            );

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
                  -- Minimum remaining shelf life: exempt entirely for units
                  -- with no BBE at all (non-batch-managed SKUs never carry
                  -- one); otherwise must clear the resolved requirement as
                  -- of delivery date, unless explicitly overridden.
                  AND (
                      @allow_shelf_life_override = 1
                      OR iu.best_before_date IS NULL
                      OR DATEDIFF(day, @delivery_date, iu.best_before_date) >= @required_min_days
                  )
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
                    CASE WHEN @strategy = 'LIFO' THEN iu.created_at END DESC,
                    -- Tiebreak for FEFO/NONE when multiple units share the same BBE -
                    -- without this, which unit wins is whatever order SQL Server
                    -- happens to return matching rows in, not a real rule. FIFO and
                    -- LIFO already have their own deterministic ordering above, so
                    -- this only ever activates for the two strategies that needed it.
                    CASE WHEN @strategy IN ('FEFO','NONE') THEN iu.created_at END ASC;

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
                    OUTPUT
                        inserted.allocation_id, inserted.inventory_unit_id,
                        inserted.outbound_line_id, inserted.allocated_qty
                    INTO @new_allocations (allocation_id, inventory_unit_id, outbound_line_id, allocated_qty)
                    VALUES
                    (
                        @line_id, @unit_id,
                        @unit_qty, 'PENDING',
                        @now, @user_id
                    );

                    SET @remaining            -= @unit_qty;
                    SET @allocated_total      += @unit_qty;
                    SET @newly_allocated_qty  += @unit_qty;
                END

                FETCH NEXT FROM unit_cursor INTO @unit_id, @unit_qty;
            END

            CLOSE unit_cursor;
            DEALLOCATE unit_cursor;

            -- Backfill the requirement that applied to this line's units -
            -- same value for all of them, since it's resolved once per line
            UPDATE @new_allocations
            SET required_min_days = @required_min_days
            WHERE outbound_line_id = @line_id
              AND required_min_days IS NULL;

            /* ── Check line fully allocated ── */
            IF @remaining > 0
            BEGIN
                IF @allow_partial = 0
                BEGIN
                    CLOSE line_cursor;
                    DEALLOCATE line_cursor;
                    IF @req_batch IS NOT NULL OR @req_bbe IS NOT NULL
                        SELECT CAST(0 AS BIT) AS success, N'ERRALLOC02' AS result_code, @outbound_order_id AS outbound_order_id, @delivery_date AS delivery_date;
                    ELSE
                        SELECT CAST(0 AS BIT) AS success, N'ERRALLOC01' AS result_code, @outbound_order_id AS outbound_order_id, @delivery_date AS delivery_date;
                    ROLLBACK; RETURN;
                END
                /* Partial mode: record what was allocated on this line, move to next */
                IF @allocated_total - @remaining > 0 OR @newly_allocated_qty > 0
                BEGIN
                    UPDATE outbound.outbound_lines
                    SET allocated_qty    = @ordered_qty - @remaining,
                        line_status_code = CASE WHEN @ordered_qty - @remaining > 0 THEN 'ALLOCATED' ELSE line_status_code END,
                        updated_at       = @now,
                        updated_by       = @user_id
                    WHERE outbound_line_id = @line_id;
                END
                FETCH NEXT FROM line_cursor INTO @line_id, @sku_id, @ordered_qty, @req_batch, @req_bbe;
                CONTINUE;
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

        SELECT
            CAST(1 AS BIT) AS success,
            CASE WHEN @newly_allocated_qty > 0 THEN N'SUCORD02' ELSE N'WARNORD01' END AS result_code,
            @outbound_order_id AS outbound_order_id,
            @delivery_date      AS delivery_date;

        -- Second result set: exactly which units this call allocated, for logging/search
        SELECT
            na.allocation_id,
            na.inventory_unit_id,
            iu.external_ref      AS sscc,
            sk.sku_code,
            na.outbound_line_id,
            na.allocated_qty,
            iu.best_before_date,
            na.required_min_days
        FROM @new_allocations na
        JOIN inventory.inventory_units iu ON iu.inventory_unit_id = na.inventory_unit_id
        JOIN inventory.skus sk           ON sk.sku_id = iu.sku_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF CURSOR_STATUS('local','line_cursor') >= 0 BEGIN CLOSE line_cursor; DEALLOCATE line_cursor; END
        IF CURSOR_STATUS('local','unit_cursor') >= 0 BEGIN CLOSE unit_cursor; DEALLOCATE unit_cursor; END
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id, @delivery_date AS delivery_date;
    END CATCH
END;

GO



/****** Object:  StoredProcedure [outbound].[usp_create_order]    Script Date: 18/04/2026 09:31:17 ******/


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
GO

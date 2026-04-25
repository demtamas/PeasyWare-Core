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

/****** Object:  StoredProcedure [outbound].[usp_create_shipment]    Script Date: 18/04/2026 09:31:33 ******/



/********************************************************************************************
    3. outbound.usp_create_shipment
    Contract: success BIT | result_code NVARCHAR(20) | shipment_id INT
********************************************************************************************/
GO

PRINT 'outbound.usp_create_order created.';
GO

-- ── 6. outbound.usp_create_shipment (party-code based) ──────────────────
GO

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

CREATE OR ALTER PROCEDURE outbound.usp_create_order
(
    @order_ref           NVARCHAR(50),
    @customer_party_code NVARCHAR(50),
    @haulier_party_code  NVARCHAR(50)     = NULL,
    @required_date       DATE             = NULL,
    @notes               NVARCHAR(500)    = NULL,
    @lines_json          NVARCHAR(MAX)    = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = @order_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code, NULL AS outbound_order_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @customer_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @customer_party_code
        );

        IF @customer_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS outbound_order_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = NULL;
        IF @haulier_party_code IS NOT NULL
            SET @haulier_id = (SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code);

        INSERT INTO outbound.outbound_orders
            (order_ref, customer_party_id, haulier_party_id, required_date,
             order_status_code, order_source, notes, created_at, created_by)
        VALUES
            (@order_ref, @customer_id, @haulier_id, @required_date,
             'NEW', 'API', @notes, SYSUTCDATETIME(), @user_id);

        DECLARE @order_id INT = SCOPE_IDENTITY();

        -- Insert lines from JSON
        IF @lines_json IS NOT NULL
        BEGIN
            INSERT INTO outbound.outbound_lines
                (outbound_order_id, line_no, sku_id, ordered_qty,
                 requested_batch, requested_bbe, notes, created_at, created_by)
            SELECT
                @order_id,
                l.line_no,
                s.sku_id,
                l.ordered_qty,
                l.requested_batch,
                TRY_CAST(l.requested_bbe AS DATE),
                l.notes,
                SYSUTCDATETIME(),
                @user_id
            FROM OPENJSON(@lines_json) WITH (
                line_no        INT            '$.line_no',
                sku_code       NVARCHAR(50)   '$.sku_code',
                ordered_qty    INT            '$.ordered_qty',
                requested_batch NVARCHAR(100) '$.requested_batch',
                requested_bbe  NVARCHAR(20)   '$.requested_bbe',
                notes          NVARCHAR(500)  '$.notes'
            ) l
            JOIN inventory.skus s ON s.sku_code = l.sku_code;
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code, @order_id AS outbound_order_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD99' AS result_code, NULL AS outbound_order_id;
    END CATCH
END;
GO

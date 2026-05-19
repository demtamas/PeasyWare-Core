USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_reallocate_line
(
    @outbound_line_id   INT,
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
        @line_status        VARCHAR(10),
        @sku_id             INT,
        @ordered_qty        INT,
        @allocated_qty      INT,
        @picked_qty         INT,
        @remaining_qty      INT,
        @req_batch          NVARCHAR(100),
        @req_bbe            DATE,
        @strategy           NVARCHAR(20),
        @unit_id            INT,
        @unit_qty           INT,
        @new_allocation_id  INT,
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Lock and read line ── */
        SELECT
            @line_status   = l.line_status_code,
            @sku_id        = l.sku_id,
            @ordered_qty   = l.ordered_qty,
            @allocated_qty = l.allocated_qty,
            @picked_qty    = l.picked_qty,
            @req_batch     = l.requested_batch,
            @req_bbe       = l.requested_bbe
        FROM outbound.outbound_lines l WITH (UPDLOCK, HOLDLOCK)
        WHERE l.outbound_line_id = @outbound_line_id;

        IF @line_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC07' AS result_code, NULL AS allocation_id;
            ROLLBACK; RETURN;
        END

        /* ── 2. Validate line is in a re-allocatable state ── */
        IF @line_status NOT IN ('NEW', 'ALLOCATED', 'PICKING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC07' AS result_code, NULL AS allocation_id;
            ROLLBACK; RETURN;
        END

        /* ── 3. Determine remaining qty needed ── */
        -- remaining = ordered - active (non-cancelled, non-picked) allocations
        -- Do NOT subtract picked_qty: picked units were already deducted from allocated_qty
        -- when pick confirmed, so subtracting both would double-count.
        DECLARE @active_allocated_qty INT;
        SELECT @active_allocated_qty = ISNULL(SUM(a.allocated_qty), 0)
        FROM outbound.outbound_allocations a
        WHERE a.outbound_line_id  = @outbound_line_id
          AND a.allocation_status NOT IN ('CANCELLED', 'PICKED');

        SET @remaining_qty = @ordered_qty - @picked_qty - @active_allocated_qty;

        IF @remaining_qty <= 0
        BEGIN
            -- Already fully allocated (shouldn't be called in this state)
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC07' AS result_code, NULL AS allocation_id;
            ROLLBACK; RETURN;
        END

        /* ── 4. Read allocation strategy ── */
        SELECT @strategy = UPPER(LTRIM(RTRIM(setting_value)))
        FROM operations.settings
        WHERE setting_name = 'outbound.allocation_strategy';

        IF @strategy IS NULL OR @strategy NOT IN ('FEFO','FIFO','LIFO','NONE')
            SET @strategy = 'NONE';

        /* ── 5. Find next eligible unit ── */
        -- Same eligibility rules as usp_allocate_order; exclude already-allocated units
        SELECT TOP 1
            @unit_id  = iu.inventory_unit_id,
            @unit_qty = iu.quantity
        FROM inventory.inventory_units iu WITH (UPDLOCK)
        JOIN inventory.inventory_placements ip
            ON ip.inventory_unit_id = iu.inventory_unit_id
        JOIN locations.bins b
            ON b.bin_id = ip.bin_id
        JOIN locations.storage_types st
            ON st.storage_type_id = b.storage_type_id
        WHERE iu.sku_id            = @sku_id
          AND iu.stock_state_code  = 'PTW'
          AND iu.stock_status_code = 'AV'
          AND (@req_batch IS NULL OR iu.batch_number     = @req_batch)
          AND (@req_bbe   IS NULL OR iu.best_before_date = @req_bbe)
          AND st.storage_type_code <> 'STAGE'
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
                ELSE
                    CASE WHEN iu.best_before_date IS NOT NULL
                         THEN CAST(iu.best_before_date AS DATETIME2)
                         ELSE iu.created_at
                    END
            END ASC,
            CASE WHEN @strategy = 'LIFO' THEN iu.created_at END DESC;

        IF @unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC06' AS result_code, NULL AS allocation_id;
            ROLLBACK; RETURN;
        END

        /* ── 6. Insert new allocation ── */
        INSERT INTO outbound.outbound_allocations
        (
            outbound_line_id, inventory_unit_id,
            allocated_qty, allocation_status,
            allocated_at, allocated_by
        )
        VALUES
        (
            @outbound_line_id, @unit_id,
            @unit_qty, 'PENDING',
            @now, @user_id
        );

        SET @new_allocation_id = SCOPE_IDENTITY();

        /* ── 7. Update line allocated_qty and status ── */
        UPDATE outbound.outbound_lines
        SET allocated_qty    = allocated_qty + @unit_qty,
            line_status_code = CASE
                WHEN (allocated_qty + @unit_qty) >= ordered_qty THEN 'ALLOCATED'
                ELSE 'NEW'
            END,
            updated_at       = @now,
            updated_by       = @user_id
        WHERE outbound_line_id = @outbound_line_id;

        /* ── 8. Reopen order header to ALLOCATED so it shows as pickable ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'ALLOCATED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = (
            SELECT outbound_order_id FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id
        )
          AND order_status_code IN ('NEW', 'ALLOCATED', 'PICKING');

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCALLOC03' AS result_code, @new_allocation_id AS allocation_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRALLOC99' AS result_code, NULL AS allocation_id;
    END CATCH
END;
GO

PRINT 'outbound.usp_reallocate_line created.';
GO

PRINT 'outbound.usp_reallocate_line created.';
GO


-- ══════════════════════════════════════════════════════════════════════════════
-- Deallocation SP + error codes  (merged from WIP_deallocate)
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- NEW ERROR CODES — Deallocation
-- ══════════════════════════════════════════════════════════════════════════════
GO

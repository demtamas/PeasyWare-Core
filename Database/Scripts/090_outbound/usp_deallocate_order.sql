USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_deallocate_order
(
    @outbound_order_id  INT,
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
        @order_status       VARCHAR(10),
        @cancelled_count    INT = 0,
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Lock and validate order ── */
        SELECT @order_status = order_status_code
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD10' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('ALLOCATED', 'PICKING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD11' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Cancel all PENDING and CONFIRMED allocations on this order ──
               PICKED allocations stay — stock is already physically moved.     */
        UPDATE a
        SET a.allocation_status = 'CANCELLED',
            a.updated_at        = @now,
            a.updated_by        = @user_id
        FROM outbound.outbound_allocations a
        JOIN outbound.outbound_lines l
            ON l.outbound_line_id = a.outbound_line_id
        WHERE l.outbound_order_id  = @outbound_order_id
          AND a.allocation_status IN ('PENDING', 'CONFIRMED');

        SET @cancelled_count = @@ROWCOUNT;

        /* ── 3. Recalculate allocated_qty per line and fix line status ──
               allocated_qty = sum of remaining non-cancelled, non-picked allocs.
               If allocated_qty drops to 0 and nothing is picked → NEW.
               If picked_qty > 0 but allocated_qty = 0 → stays PICKING
               (supervisor must deal with partially-picked line).              */
        UPDATE l
        SET l.allocated_qty    = ISNULL(active.total_active_qty, 0),
            l.line_status_code = CASE
                WHEN ISNULL(active.total_active_qty, 0) = 0 AND l.picked_qty = 0 THEN 'NEW'
                WHEN ISNULL(active.total_active_qty, 0) = 0 AND l.picked_qty > 0 THEN 'PICKING'
                ELSE l.line_status_code
            END,
            l.updated_at       = @now,
            l.updated_by       = @user_id
        FROM outbound.outbound_lines l
        LEFT JOIN (
            SELECT a.outbound_line_id,
                   SUM(a.allocated_qty) AS total_active_qty
            FROM outbound.outbound_allocations a
            WHERE a.allocation_status NOT IN ('CANCELLED', 'PICKED')
            GROUP BY a.outbound_line_id
        ) active
            ON active.outbound_line_id = l.outbound_line_id
        WHERE l.outbound_order_id = @outbound_order_id;

        /* ── 4. Reset order header ──
               If no active allocations remain at all, order → NEW.
               If some picked lines exist → PICKING (partial).                 */
        DECLARE @remaining_active INT;

        SELECT @remaining_active = COUNT(*)
        FROM outbound.outbound_allocations a
        JOIN outbound.outbound_lines l
            ON l.outbound_line_id = a.outbound_line_id
        WHERE l.outbound_order_id  = @outbound_order_id
          AND a.allocation_status NOT IN ('CANCELLED', 'PICKED');

        DECLARE @any_picked INT;

        SELECT @any_picked = COUNT(*)
        FROM outbound.outbound_allocations a
        JOIN outbound.outbound_lines l
            ON l.outbound_line_id = a.outbound_line_id
        WHERE l.outbound_order_id  = @outbound_order_id
          AND a.allocation_status  = 'PICKED';

        UPDATE outbound.outbound_orders
        SET order_status_code = CASE
                WHEN @remaining_active = 0 AND @any_picked = 0 THEN 'NEW'
                WHEN @remaining_active = 0 AND @any_picked > 0 THEN 'PICKING'
                ELSE order_status_code
            END,
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD10' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD99' AS result_code;
    END CATCH
END;
GO

PRINT 'outbound.usp_deallocate_order created.';
GO


-- ══════════════════════════════════════════════════════════════════════════════
-- Order cancellation SP + error codes  (merged from WIP_cancel_order)
-- ══════════════════════════════════════════════════════════════════════════════

USE PW_Core_DEV;
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- NEW ERROR CODES — Order cancellation
-- ══════════════════════════════════════════════════════════════════════════════
GO

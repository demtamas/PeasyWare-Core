USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_cancel_allocation
(
    @allocation_id  INT,
    @reason         NVARCHAR(200) = NULL,
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
        @alloc_status       VARCHAR(10),
        @is_terminal        BIT,
        @outbound_line_id   INT,
        @allocated_qty      INT,
        @line_status        VARCHAR(10),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Lock and read allocation ── */
        SELECT
            @alloc_status     = a.allocation_status,
            @outbound_line_id = a.outbound_line_id,
            @allocated_qty    = a.allocated_qty
        FROM outbound.outbound_allocations a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.allocation_id = @allocation_id;

        IF @alloc_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC04' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Check terminal states ── */
        SELECT @is_terminal = is_terminal
        FROM outbound.allocation_statuses
        WHERE status_code = @alloc_status;

        IF @is_terminal = 1
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRALLOC04' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Cancel the allocation ── */
        UPDATE outbound.outbound_allocations
        SET allocation_status = 'CANCELLED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE allocation_id = @allocation_id;

        /* ── 3b. Cancel any open PICK tasks for this unit ── */
        DECLARE @inv_unit_id INT;
        SELECT @inv_unit_id = inventory_unit_id
        FROM outbound.outbound_allocations
        WHERE allocation_id = @allocation_id;

        UPDATE warehouse.warehouse_tasks
        SET task_state_code = 'CNL',
            updated_at      = @now,
            updated_by      = @user_id
        WHERE inventory_unit_id = @inv_unit_id
          AND task_type_code    = 'PICK'
          AND task_state_code   = 'OPN';

        /* ── 4. Roll back line allocated_qty and status ── */
        SELECT @line_status = line_status_code
        FROM outbound.outbound_lines
        WHERE outbound_line_id = @outbound_line_id;

        UPDATE outbound.outbound_lines
        SET allocated_qty    = allocated_qty - @allocated_qty,
            -- If all allocations cancelled, line goes back to NEW; otherwise stays ALLOCATED/PICKING
            line_status_code = CASE
                WHEN (allocated_qty - @allocated_qty) <= 0 THEN 'NEW'
                ELSE line_status_code
            END,
            updated_at       = @now,
            updated_by       = @user_id
        WHERE outbound_line_id = @outbound_line_id;

        /* ── 5. Reopen order header if it was ALLOCATED or PICKING ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'NEW',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = (
            SELECT outbound_order_id FROM outbound.outbound_lines
            WHERE outbound_line_id = @outbound_line_id
        )
          AND order_status_code IN ('ALLOCATED', 'PICKING');

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCALLOC02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRALLOC99' AS result_code;
    END CATCH
END;
GO

PRINT 'outbound.usp_cancel_allocation created.';
GO

PRINT 'outbound.usp_cancel_allocation created.';
GO

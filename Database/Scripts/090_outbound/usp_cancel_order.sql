USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_cancel_order
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
        @order_status   VARCHAR(10),
        @lines_in_flight INT,
        @now            DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Lock and read order ── */
        SELECT @order_status = order_status_code
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD12' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Refuse terminal statuses ── */
        IF @order_status IN ('CANCELLED', 'DEPARTED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD14' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 3. Hard-refuse if any line is beyond NEW ──
               Line statuses beyond NEW: ALLOCATED, PICKING, PICKED, LOADED, CNL
               We only allow cancellation when ALL active lines are NEW.        */
        SELECT @lines_in_flight = COUNT(*)
        FROM outbound.outbound_lines
        WHERE outbound_order_id = @outbound_order_id
          AND line_status_code NOT IN ('NEW', 'CNL');

        IF @lines_in_flight > 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD13' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 4. Cancel all NEW lines ── */
        UPDATE outbound.outbound_lines
        SET line_status_code = 'CNL',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE outbound_order_id = @outbound_order_id
          AND line_status_code  = 'NEW';

        /* ── 5. Cancel the order header ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'CANCELLED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD11' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD99' AS result_code;
    END CATCH
END;
GO

PRINT 'outbound.usp_cancel_order created.';
GO

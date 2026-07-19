USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE warehouse.usp_cancel_task
(
    @task_id    INT,
    @reason     NVARCHAR(200) = NULL,
    @user_id    INT,
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @current_state  VARCHAR(3),
        @is_terminal    BIT,
        @task_type      NVARCHAR(20),
        @dest_bin_id    INT,
        @now            DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @current_state = wt.task_state_code,
            @is_terminal   = ts.is_terminal,
            @task_type     = wt.task_type_code,
            @dest_bin_id   = wt.destination_bin_id
        FROM warehouse.warehouse_tasks wt WITH (UPDLOCK, HOLDLOCK)
        JOIN warehouse.task_states ts ON ts.state_code = wt.task_state_code
        WHERE wt.task_id = @task_id;

        IF @current_state IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @is_terminal = 1
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK06' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Validate transition is allowed
        IF NOT EXISTS (
            SELECT 1 FROM warehouse.task_state_transitions
            WHERE from_state_code = @current_state
              AND to_state_code   = 'CNL'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE warehouse.warehouse_tasks
        SET task_state_code = 'CNL',
            updated_at      = @now,
            updated_by      = @user_id
        WHERE task_id = @task_id;

        -- A cancelled PUTAWAY task's destination-bin reservation (created in
        -- usp_putaway_create_task_for_unit) has no further purpose - release
        -- it now rather than leave the bin needlessly held for the rest of
        -- the TTL window.
        IF @task_type = 'PUTAWAY' AND @dest_bin_id IS NOT NULL
        BEGIN
            DELETE FROM locations.bin_reservations
            WHERE bin_id = @dest_bin_id AND reservation_type = 'PUTAWAY' AND expires_at >= @now;
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK03' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_cancel_task created.';
GO

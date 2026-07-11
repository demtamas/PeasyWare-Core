USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Revoke all active sessions (maintenance / emergency logout)
--
-- Terminates every ACTIVE/IDLE session except the caller's own.
-- Uses REVOKED status to distinguish from a normal user logout.
-- Returns count of sessions terminated.
--
-- Audit logging is handled exclusively by BuildResult (C# side).
-- ============================================================

CREATE OR ALTER PROCEDURE auth.usp_logout_all_sessions
(
    @exclude_session_id  UNIQUEIDENTIFIER = NULL,
    @reason              NVARCHAR(255)    = NULL,
    @admin_user_id       INT              = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL,

    @result_code         NVARCHAR(20)     OUTPUT,
    @friendly_msg        NVARCHAR(400)    OUTPUT,
    @success             BIT              OUTPUT,
    @terminated_count    INT              OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @success          = 0;
    SET @result_code      = NULL;
    SET @friendly_msg     = NULL;
    SET @terminated_count = 0;

    DECLARE @reason_json NVARCHAR(400) = CONCAT(
        N'{"reason":"admin_logout_all","by":', CAST(@admin_user_id AS NVARCHAR(10)),
        CASE WHEN @reason IS NOT NULL
             THEN CONCAT(N',"note":"', REPLACE(@reason, N'"', N'\"'), N'"')
             ELSE N'' END,
        N'}'
    );

    BEGIN TRY

        --------------------------------------------------------
        -- Permission check (Phase 2c)
        --------------------------------------------------------
        IF auth.fn_has_permission(@admin_user_id, 'sessions.terminate_all') = 0
        BEGIN
            SET @result_code  = 'ERRPERM01';
            SET @friendly_msg = 'You do not have permission for this action.';
            SET @success      = 0;
            RETURN;
        END

        -- Collect active sessions (excluding caller)
        IF OBJECT_ID('tempdb..#ToRevoke') IS NOT NULL
            DROP TABLE #ToRevoke;

        SELECT session_id
        INTO   #ToRevoke
        FROM   auth.user_sessions
        WHERE  is_active = 1
          AND  session_status IN ('ACTIVE', 'IDLE')
          AND  (
                   @exclude_session_id IS NULL
                OR session_id <> @exclude_session_id
               );

        SET @terminated_count = (SELECT COUNT(*) FROM #ToRevoke);

        IF @terminated_count = 0
        BEGIN
            SET @result_code  = 'SUCAUTH09';
            SET @friendly_msg = 'No active sessions to terminate.';
            SET @success      = 1;
            RETURN;
        END

        -- Revoke each session via lifecycle SP
        DECLARE @sid  UNIQUEIDENTIFIER;
        DECLARE @code NVARCHAR(20);
        DECLARE @msg  NVARCHAR(400);

        DECLARE revoke_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT session_id FROM #ToRevoke;

        OPEN revoke_cursor;
        FETCH NEXT FROM revoke_cursor INTO @sid;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC auth.usp_session_set_status
                @session_id    = @sid,
                @to_status     = 'REVOKED',
                @source_app    = 'PeasyWare.Desktop',
                @source_client = 'Admin:LogoutAll',
                @source_ip     = NULL,
                @details       = @reason_json,
                @result_code   = @code OUTPUT,
                @friendly_msg  = @msg  OUTPUT;

            FETCH NEXT FROM revoke_cursor INTO @sid;
        END

        CLOSE revoke_cursor;
        DEALLOCATE revoke_cursor;

        SET @result_code  = 'SUCAUTH09';
        SET @friendly_msg = CONCAT(
            CAST(@terminated_count AS NVARCHAR(10)),
            CASE WHEN @terminated_count = 1 THEN N' session' ELSE N' sessions' END,
            N' terminated.'
        );
        SET @success = 1;

    END TRY
    BEGIN CATCH
        SET @result_code  = 'ERRPROC02';
        SET @friendly_msg = ERROR_MESSAGE();
        SET @success      = 0;
    END CATCH;
END;
GO

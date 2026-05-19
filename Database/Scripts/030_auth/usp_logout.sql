USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_logout
(
    @session_id      UNIQUEIDENTIFIER,
    @source_app      NVARCHAR(50),
    @source_client   NVARCHAR(200),
    @source_ip       NVARCHAR(50) = NULL,
    @correlation_id  UNIQUEIDENTIFIER = NULL,

    @result_code     NVARCHAR(20) OUTPUT,
    @friendly_msg    NVARCHAR(400) OUTPUT,
    @success         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @success = 0;
    SET @result_code = NULL;
    SET @friendly_msg = NULL;

    DECLARE
        @actor_id        INT = TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        @ctx_session_id  UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER),
        @corr_id         UNIQUEIDENTIFIER = COALESCE(@correlation_id, TRY_CAST(SESSION_CONTEXT(N'correlation_id') AS UNIQUEIDENTIFIER)),
        @now             DATETIME2(3) = SYSUTCDATETIME(),

        @session_status  NVARCHAR(20),
        @transition_code NVARCHAR(20),
        @transition_msg  NVARCHAR(400),
        @details         NVARCHAR(MAX);

    BEGIN TRY

        --------------------------------------------------------
        -- Fetch current status
        --------------------------------------------------------
        SELECT @session_status = session_status
        FROM auth.user_sessions
        WHERE session_id = @session_id;

        --------------------------------------------------------
        -- Not found
        --------------------------------------------------------
        IF @session_status IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH06';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Idempotent success
        --------------------------------------------------------
        IF @session_status IN ('LOGGED_OUT', 'EXPIRED', 'REVOKED')
        BEGIN
            SET @result_code = 'SUCAUTH03';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            SET @success = 1;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Build details payload (for transition)
        --------------------------------------------------------
        SET @details = (
            SELECT
                @corr_id AS correlation_id,
                'user logout' AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Perform transition
        --------------------------------------------------------
        EXEC auth.usp_session_set_status
            @session_id     = @session_id,
            @to_status      = 'LOGGED_OUT',
            @source_app     = @source_app,
            @source_client  = @source_client,
            @source_ip      = @source_ip,
            @details        = @details,
            @result_code    = @transition_code OUTPUT,
            @friendly_msg   = @transition_msg OUTPUT;

        --------------------------------------------------------
        -- Final response
        --------------------------------------------------------
        IF @transition_code LIKE 'SUC%'
        BEGIN
            SET @result_code = 'SUCAUTH03';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            SET @success = 1;
        END
        ELSE
        BEGIN
            SET @result_code  = @transition_code;
            SET @friendly_msg = @transition_msg;
            SET @success = 0;
        END;

LogAndExit:

        --------------------------------------------------------
        -- Payload
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @actor_id    AS PerformedBy,
                @session_id  AS TargetSessionId,
                @session_status AS PreviousStatus,
                @result_code AS ResultCode
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Mapping
        --------------------------------------------------------
        DECLARE @event_result_code NVARCHAR(50);
        DECLARE @event_success BIT;

        SELECT
            @event_result_code = m.event_result_code,
            @event_success     = m.event_success
        FROM audit.fn_map_user_result(@result_code) m;

        --------------------------------------------------------
        -- Audit
        --------------------------------------------------------
        EXEC audit.usp_log_event
            @correlation_id = @corr_id,
            @user_id        = @actor_id,
            @session_id     = @ctx_session_id,
            @event_name     = 'session.logout',
            @result_code    = @event_result_code,
            @success        = @event_success,
            @payload_json   = @payload_json;

    END TRY
    BEGIN CATCH

        DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();

        DECLARE @payload_json_error NVARCHAR(MAX);

        SET @payload_json_error = (
            SELECT
                @err AS ErrorMessage,
                @session_id AS TargetSessionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @corr_id,
            @user_id        = @actor_id,
            @session_id     = @ctx_session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

        SET @success = 0;

    END CATCH;
END;
GO

/* ============================================================
   9. CHANGE PASSWORD (username-based)
   ============================================================*/
GO

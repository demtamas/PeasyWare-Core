USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_admin_reset_password
(
    @target_user_id    INT,
    @new_password      NVARCHAR(200),

    @result_code       NVARCHAR(20)  OUTPUT,
    @friendly_message  NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @username        NVARCHAR(100),
        @actor_id        INT = TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        @session_id      UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER),
        @correlation_id  UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'correlation_id') AS UNIQUEIDENTIFIER),
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY

        --------------------------------------------------------
        -- Resolve target user
        --------------------------------------------------------
        SELECT @username = u.username
        FROM auth.users u
        WHERE u.id = @target_user_id;

        IF @username IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH02';

            SELECT @friendly_message = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Delegate to core password change
        --------------------------------------------------------
        EXEC auth.usp_change_password
            @username         = @username,
            @new_password     = @new_password,
            @result_code      = @result_code OUTPUT,
            @friendly_message = @friendly_message OUTPUT;

        --------------------------------------------------------
        -- Admin override
        --------------------------------------------------------
        IF @result_code LIKE 'SUC%'
        BEGIN
            UPDATE auth.users
            SET must_change_password = 1
            WHERE id = @target_user_id;
        END;

LogAndExit:

        --------------------------------------------------------
        -- Payload
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @actor_id       AS PerformedBy,
                @target_user_id AS TargetUserId,
                @username       AS Username,
                @result_code    AS ResultCode
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
        -- Audit (single source of truth)
        --------------------------------------------------------
        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @actor_id,
            @session_id     = @session_id,
            @event_name     = 'user.password.reset',
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
                @target_user_id AS TargetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @actor_id,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_message = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

    END CATCH;
END;
GO

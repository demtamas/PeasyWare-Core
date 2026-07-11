USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_set_user_active
(
    @user_id        INT,
    @is_active      BIT,

    @result_code    NVARCHAR(20) OUTPUT,
    @friendly_msg   NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @actor          INT = TRY_CONVERT(INT, SESSION_CONTEXT(N'user_id')),
        @session_id     UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'session_id')),
        @correlation_id UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'correlation_id')),
        @now            DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY

        --------------------------------------------------------
        -- Permission check (Phase 2c)
        --------------------------------------------------------
        IF auth.fn_has_permission(@actor, 'users.manage') = 0
        BEGIN
            SET @result_code = 'ERRPERM01';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Validate target user
        --------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM auth.users
            WHERE id = @user_id
        )
        BEGIN
            SET @result_code = 'ERRUSR01';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Perform update
        --------------------------------------------------------
        UPDATE auth.users
        SET
            is_active   = @is_active,
            updated_at  = @now,
            updated_by  = @actor
        WHERE id = @user_id;

        --------------------------------------------------------
        -- Success
        --------------------------------------------------------
        SET @result_code = 'SUCUSR01';

        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

LogAndExit:

        --------------------------------------------------------
        -- Payload
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @actor       AS PerformedBy,
                @user_id     AS TargetUserId,
                @is_active   AS IsActive,
                @result_code AS ResultCode
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Mapping (CENTRALISED)
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
            @correlation_id = @correlation_id,
            @user_id        = @actor,
            @session_id     = @session_id,
            @event_name     = 'user.status.updated',
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
                @user_id AS TargetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @actor,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

    END CATCH;
END;
GO

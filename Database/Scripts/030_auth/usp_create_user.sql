USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_create_user
(
    @username     NVARCHAR(50),
    @display_name NVARCHAR(100),
    @role_name    NVARCHAR(100),
    @email        NVARCHAR(255),
    @password     NVARCHAR(200),

    @result_code  NVARCHAR(20)  OUTPUT,
    @friendly_msg NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @salt        VARBINARY(256),
        @hash        VARBINARY(512),
        @actor       INT = TRY_CONVERT(INT, SESSION_CONTEXT(N'user_id')),
        @session_id  UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'session_id')),
        @correlation_id UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'correlation_id')),

        @now         DATETIME2(3) = SYSUTCDATETIME(),
        @expiry_days INT,
        @expires_at  DATETIME2(0),
        @role_id     INT,
        @new_user_id INT;

    BEGIN TRY

        --------------------------------------------------------
        -- Permission check (Phase 2c)
        -- Bootstrap escape hatch: while no admin role assignment
        -- exists yet (fresh install — this is how the seed script
        -- creates the first admin/api accounts with no session
        -- context set), this check is skipped. Once any admin exists,
        -- the guard is permanently live.
        --------------------------------------------------------
        IF auth.fn_has_permission(@actor, 'users.manage') = 0
           AND EXISTS (
                SELECT 1
                FROM auth.user_roles ur
                JOIN auth.roles r ON r.id = ur.role_id
                WHERE r.role_name = 'admin'
           )
        BEGIN
            SET @result_code = 'ERRPERM01';
            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Username uniqueness
        --------------------------------------------------------
        IF EXISTS (SELECT 1 FROM auth.users WHERE username = @username)
        BEGIN
            SET @result_code = 'ERRAUTHUSR01';
            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Email uniqueness
        --------------------------------------------------------
        IF EXISTS (SELECT 1 FROM auth.users WHERE email = @email)
        BEGIN
            SET @result_code = 'ERRAUTHUSR04';
            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Role validation
        --------------------------------------------------------
        SELECT @role_id = id
        FROM auth.roles
        WHERE role_name = @role_name;

        IF @role_id IS NULL
        BEGIN
            SET @result_code = 'ERRAUTHUSR02';
            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Password hashing
        --------------------------------------------------------
        EXEC auth.sp_hash_password
             @plain = @password,
             @salt  = @salt OUTPUT,
             @hash  = @hash OUTPUT;

        --------------------------------------------------------
        -- Password expiry
        --------------------------------------------------------
        SELECT @expiry_days =
            TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'auth.password_expiry_days';

        IF @expiry_days IS NULL OR @expiry_days <= 0
            SET @expiry_days = 90;

        SET @expires_at = DATEADD(DAY, @expiry_days, @now);

        --------------------------------------------------------
        -- Insert user
        --------------------------------------------------------
        INSERT INTO auth.users
        (
            username, display_name, email,
            password_hash, salt,
            password_last_changed, password_expires_at,
            must_change_password,
            is_active,
            created_at, created_by
        )
        VALUES
        (
            @username, @display_name, @email,
            @hash, @salt,
            @now, @expires_at,
            1,
            1,
            @now, @actor
        );

        SET @new_user_id = SCOPE_IDENTITY();

        --------------------------------------------------------
        -- Role assignment
        --------------------------------------------------------
        INSERT INTO auth.user_roles (user_id, role_id)
        VALUES (@new_user_id, @role_id);

        --------------------------------------------------------
        -- Success
        --------------------------------------------------------
        SET @result_code = 'SUCAUTHUSR01';
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
                @username     AS Username,
                @role_name    AS Role,
                @actor        AS PerformedBy,
                @new_user_id  AS NewUserId,
                @result_code  AS ResultCode
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
            @event_name     = 'user.created',
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
                @username AS Username
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

        SET @result_code = 'ERRAUTHUSR03';
        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

    END CATCH;
END;
GO


-- Add api user
IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username = 'api')
BEGIN
    EXEC auth.usp_create_user
        @username     = 'api',
        @display_name = 'PeasyWare API',
        @role_name    = 'api',
        @email        = 'api@pw.local',
        @password     = 'ChangeMe123!',
        @result_code  = NULL,
        @friendly_msg = NULL;
    PRINT 'api user created.';
END
ELSE
    PRINT 'api user already exists — skipped.';
GO

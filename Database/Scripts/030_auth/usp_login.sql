USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_login
(
    @username           NVARCHAR(100),
    @password_plain     NVARCHAR(200) = NULL,
    @client_info        NVARCHAR(200) = NULL,
    @ip_address         NVARCHAR(50)  = NULL,
    @client_app         NVARCHAR(50)  = NULL,
    @os_info            NVARCHAR(200) = NULL,
    @force_login        BIT           = 0,
    @correlation_id     UNIQUEIDENTIFIER = NULL,

    -- OUTPUTS
    @result_code        NVARCHAR(20)  OUTPUT,
    @friendly_message   NVARCHAR(400) OUTPUT,
    @user_id_out        INT           OUTPUT,
    @session_id_out     UNIQUEIDENTIFIER OUTPUT,
    @display_name_out   NVARCHAR(200) OUTPUT,
    @last_login_time    DATETIME2(3)  OUTPUT,
    @failed_attempts    INT           OUTPUT,
    @lockout_until_out  DATETIME2(3)  OUTPUT,
    @role_name_out      NVARCHAR(100) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------
    -- HARD GUARDS
    --------------------------------------------------------
    SET @client_app = NULLIF(LTRIM(RTRIM(@client_app)), '');
    IF @client_app IS NULL
        THROW 50001, 'client_app must be supplied', 1;

    --------------------------------------------------------
    -- Init outputs
    --------------------------------------------------------
    SET @result_code = NULL;
    SET @friendly_message = NULL;
    SET @user_id_out = NULL;
    SET @session_id_out = NULL;
    SET @display_name_out = NULL;
    SET @last_login_time = NULL;
    SET @failed_attempts = 0;
    SET @lockout_until_out = NULL;

    EXEC auth.usp_session_cleanup;

    DECLARE
        @user_id INT,
        @is_active BIT,
        @password_hash VARBINARY(512),
        @salt VARBINARY(256),
        @failed INT,
        @lockout_until DATETIME2(3),
        @must_change_password BIT,
        @password_expires_at DATETIME2(3),
        @display_name NVARCHAR(200),
        @role_name NVARCHAR(100),
        @now DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        --------------------------------------------------------
        -- Load user
        --------------------------------------------------------
        SELECT
            @user_id = u.id,
            @is_active = u.is_active,
            @password_hash = u.password_hash,
            @salt = u.salt,
            @failed = u.failed_attempts,
            @lockout_until = u.lockout_until,
            @must_change_password = u.must_change_password,
            @password_expires_at = u.password_expires_at,
            @display_name = u.display_name,
            @role_name            = r.role_name 
        FROM auth.users u
        JOIN auth.user_roles ur ON ur.user_id = u.id
        JOIN auth.roles r       ON r.id = ur.role_id
        WHERE u.username = @username;

        IF @user_id IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH01';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Disabled user guard
        --------------------------------------------------------
        IF @is_active = 0
        BEGIN
            SET @result_code = 'ERRAUTH02';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Lockout check
        --------------------------------------------------------
        IF @lockout_until IS NOT NULL AND @now < @lockout_until
        BEGIN
            SET @result_code = 'ERRAUTH07';
            SET @friendly_message =
                CONCAT('Too many failed attempts. Try again at ',
                       FORMAT(@lockout_until, 'yyyy-MM-dd HH:mm:ss'));
            SET @failed_attempts = @failed;
            SET @lockout_until_out = @lockout_until;
            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Password validation
        --------------------------------------------------------
        DECLARE @calc_hash VARBINARY(512) =
            HASHBYTES('SHA2_512',
                CONVERT(VARBINARY(512), @password_plain) + @salt);

        IF @calc_hash IS NULL OR @calc_hash <> @password_hash
        BEGIN
            SET @failed += 1;

            DECLARE @lock_minutes INT = NULL;
            DECLARE @terminal_lock DATETIME2(3) = '9999-12-31 23:59:59.997';

            IF      @failed = 3 SET @lock_minutes = 1;
            ELSE IF @failed = 4 SET @lock_minutes = 2;
            ELSE IF @failed = 5 SET @lock_minutes = 5;
            ELSE IF @failed = 6 SET @lock_minutes = 10;
            ELSE IF @failed = 7 SET @lock_minutes = 20;
            ELSE IF @failed = 8 SET @lock_minutes = 30;
            ELSE IF @failed = 9 SET @lock_minutes = 60;
            ELSE IF @failed >= 10
            BEGIN
                UPDATE auth.users
                SET failed_attempts = @failed,
                    lockout_until = @terminal_lock
                WHERE id = @user_id;

                SET @result_code = 'ERRAUTH08';
                SET @friendly_message =
                    'Account locked due to repeated failed login attempts. Contact an administrator.';

                SET @failed_attempts = @failed;
                SET @lockout_until_out = @terminal_lock;

                GOTO LogAndExit;
            END;

            UPDATE auth.users
            SET failed_attempts = @failed,
                lockout_until = DATEADD(MINUTE, @lock_minutes, @now)
            WHERE id = @user_id;

            SET @result_code = 'ERRAUTH01';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            SET @failed_attempts = @failed;
            SET @lockout_until_out = DATEADD(MINUTE, @lock_minutes, @now);

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Clear failures
        --------------------------------------------------------
        UPDATE auth.users
        SET failed_attempts = 0,
            lockout_until = NULL
        WHERE id = @user_id;

        --------------------------------------------------------
        -- Password policy
        --------------------------------------------------------
        IF @must_change_password = 1
           OR (@password_expires_at IS NOT NULL AND @now > @password_expires_at)
        BEGIN
            SET @result_code = 'ERRAUTH09';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            SET @user_id_out = @user_id;
            SET @display_name_out = @display_name;
            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Existing session
        --------------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM auth.user_sessions
            WHERE user_id = @user_id
              AND client_app = @client_app
              AND is_active = 1
        )
        BEGIN
            IF @force_login = 0
            BEGIN
                SET @result_code = 'ERRAUTH05';
                SET @friendly_message = operations.fn_get_friendly_message(@result_code);
                GOTO LogAndExit;
            END;

            UPDATE auth.user_sessions
            SET is_active = 0
            WHERE user_id = @user_id
              AND client_app = @client_app;
        END;

        --------------------------------------------------------
        -- Create session
        --------------------------------------------------------
        DECLARE @session_id UNIQUEIDENTIFIER = NEWID();

        INSERT INTO auth.user_sessions
        (session_id, user_id, client_info, client_app, correlation_id)
        VALUES
        (@session_id, @user_id, @client_info, @client_app, @correlation_id);

        SET @result_code = 'SUCAUTH01';
        SET @friendly_message = operations.fn_get_friendly_message(@result_code);
        SET @user_id_out = @user_id;
        SET @session_id_out = @session_id;
        SET @display_name_out = @display_name;
        SET @role_name_out = @role_name;

LogAndExit:

        --------------------------------------------------------
        -- Login attempts
        --------------------------------------------------------
        INSERT INTO auth.login_attempts
        (username, attempt_time, result_code, success,
         session_id, correlation_id, ip_address, client_info, client_app, os_info)
        VALUES
        (@username, @now, @result_code,
         CASE WHEN @result_code = 'SUCAUTH01' THEN 1 ELSE 0 END,
         @session_id_out, @correlation_id,
         @ip_address, @client_info, @client_app, @os_info);

        --------------------------------------------------------
        -- Event logging (STRICT MAPPING)
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @username AS Username,
                @client_app AS ClientApp,
                @ip_address AS IpAddress,
                @result_code AS ResultCode
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        DECLARE @event_result_code NVARCHAR(50);
            DECLARE @event_success BIT;

            SELECT
                @event_result_code = m.event_result_code,
                @event_success = m.event_success
            FROM audit.fn_map_auth_result(@result_code) m;

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id_out,
            @event_name     = 'auth.login',
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
            @user_id        = NULL,
            @session_id     = NULL,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code      = 'ERRAUTH99';
        SET @friendly_message = operations.fn_get_friendly_message('ERRAUTH99');
    END CATCH;
END;
GO

/* ============================================================
   7. SESSION TOUCH
   ============================================================*/
GO

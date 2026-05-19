USE PW_Core_DEV;
GO

CREATE OR ALTER PROCEDURE auth.usp_change_password
(
    @username         NVARCHAR(100),
    @new_password     NVARCHAR(200),
    @result_code      NVARCHAR(20)  OUTPUT,
    @friendly_message NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @user_id       INT,
        @existing_hash VARBINARY(512),
        @existing_salt VARBINARY(256),
        @is_active     BIT,
        @now           DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY

        --------------------------------------------------------
        -- 0. Load user
        --------------------------------------------------------
        SELECT
            @user_id       = u.id,
            @existing_hash = u.password_hash,
            @existing_salt = u.salt,
            @is_active     = u.is_active
        FROM auth.users u
        WHERE u.username = @username;

        IF @user_id IS NULL OR @existing_hash IS NULL OR @existing_salt IS NULL
        BEGIN
            SET @result_code      = 'ERRAUTH02';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            RETURN;
        END;

        IF @is_active = 0
        BEGIN
            SET @result_code      = 'ERRAUTH02';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            RETURN;
        END;

        --------------------------------------------------------
        -- 1. Complexity: min length + upper + lower + digit
        --------------------------------------------------------
        DECLARE @min_len INT =
        (
            SELECT TRY_CONVERT(INT, setting_value)
            FROM operations.settings
            WHERE setting_name = 'auth.password_min_length'
        );

        IF @min_len IS NULL OR @min_len < 1
            SET @min_len = 8;

        IF LEN(@new_password) < @min_len
           OR @new_password NOT LIKE '%[A-Z]%'
           OR @new_password NOT LIKE '%[a-z]%'
           OR @new_password NOT LIKE '%[0-9]%'
        BEGIN
            SET @result_code      = 'ERRAUTH10';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            RETURN;
        END;

        --------------------------------------------------------
        -- 2. History depth
        --------------------------------------------------------
        DECLARE @history_len INT =
        (
            SELECT TRY_CONVERT(INT, setting_value)
            FROM operations.settings
            WHERE setting_name = 'auth.password_history_depth'
        );

        IF @history_len IS NULL OR @history_len < 1
            SET @history_len = 3;

        --------------------------------------------------------
        -- 3. Prevent reuse of last N passwords
        --------------------------------------------------------
        DECLARE @reuse_count INT = 0;

        ;WITH LastN AS
        (
            SELECT TOP (@history_len)
                h.password_hash,
                h.salt
            FROM auth.password_history h
            WHERE h.user_id = @user_id
            ORDER BY h.changed_at DESC
        )
        SELECT @reuse_count = COUNT(*)
        FROM LastN h
        WHERE h.password_hash =
              HASHBYTES('SHA2_512',
                    CONVERT(VARBINARY(512), @new_password) + h.salt);

        IF @reuse_count > 0
        BEGIN
            SET @result_code      = 'ERRAUTH11';
            SET @friendly_message = operations.fn_get_friendly_message(@result_code);
            RETURN;
        END;

        --------------------------------------------------------
        -- 4. Generate new hash/salt
        --------------------------------------------------------
        DECLARE @new_salt VARBINARY(256),
                @new_hash VARBINARY(512);

        EXEC auth.sp_hash_password
             @plain = @new_password,
             @salt  = @new_salt OUTPUT,
             @hash  = @new_hash OUTPUT;

        --------------------------------------------------------
        -- 5. Put OLD password into history
        --------------------------------------------------------
        IF @existing_hash IS NOT NULL AND @existing_salt IS NOT NULL
        BEGIN
            INSERT INTO auth.password_history (user_id, password_hash, salt, changed_at)
            VALUES (@user_id, @existing_hash, @existing_salt, @now);
        END;

        -- Trim to last N
        ;WITH Ranked AS
        (
            SELECT
                id,
                ROW_NUMBER() OVER (ORDER BY changed_at DESC) AS rn
            FROM auth.password_history
            WHERE user_id = @user_id
        )
        DELETE FROM auth.password_history
        WHERE id IN
        (
            SELECT id FROM Ranked WHERE rn > @history_len
        );

        --------------------------------------------------------
        -- 6. Password expiry date
        --------------------------------------------------------
        DECLARE @expiry_days INT =
        (
            SELECT TRY_CONVERT(INT, setting_value)
            FROM operations.settings
            WHERE setting_name = 'auth.password_expiry_days'
        );

        IF @expiry_days IS NULL OR @expiry_days <= 0
            SET @expiry_days = 90;

        DECLARE @expires_at DATETIME2(0) = DATEADD(DAY, @expiry_days, @now);

        --------------------------------------------------------
        -- 7. Update user
        --------------------------------------------------------
        UPDATE auth.users
        SET password_hash         = @new_hash,
            salt                  = @new_salt,
            password_last_changed = @now,
            password_expires_at   = @expires_at,
            must_change_password  = 0,
            failed_attempts       = 0,
            lockout_until         = NULL
        WHERE id = @user_id;

        SET @result_code      = 'SUCAUTH10';
        SET @friendly_message = operations.fn_get_friendly_message(@result_code);

    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ctx NVARCHAR(MAX)  = JSON_OBJECT('username': @username);

        EXEC operations.usp_log_error
            @error_code   = 'ERRAUTH99',
            @module_code  = 'AUTH',
            @message      = 'Unhandled error in usp_change_password.',
            @details      = @err,
            @context_json = @ctx;

        SET @result_code      = 'ERRAUTH99';
        SET @friendly_message = operations.fn_get_friendly_message(@result_code);
    END CATCH;
END;
GO

/* ============================================================
   11. ROLE RESOLUTION VIEW
   ============================================================*/

IF OBJECT_ID('auth.v_user_roles', 'V') IS NULL
BEGIN
    EXEC('CREATE VIEW auth.v_user_roles AS
          SELECT u.id AS user_id,
                 u.username,
                 u.display_name,
                 r.role_name,
                 r.description
          FROM auth.users u
          JOIN auth.user_roles ur ON ur.user_id = u.id
          JOIN auth.roles r       ON r.id = ur.role_id;');
END;
GO

DECLARE @salt VARBINARY(256) = 0x01;
DECLARE @hash VARBINARY(512) = 0x01;

IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username='system')
BEGIN
    INSERT INTO auth.users
        (username, display_name, email, password_hash, salt,
         password_last_changed, is_active, created_by)
    VALUES
        ('system', 'System Account', NULL, @hash, @salt,
         SYSUTCDATETIME(), 1, NULL);

    PRINT 'System user created.';
END
ELSE
    PRINT 'System user already exists.';
GO

IF OBJECT_ID('auth.usp_add_role', 'P') IS NOT NULL
    DROP PROCEDURE auth.usp_add_role;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

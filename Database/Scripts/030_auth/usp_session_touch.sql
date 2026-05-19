USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_session_touch
(
    @session_id     UNIQUEIDENTIFIER,
    @source_app     NVARCHAR(50),
    @source_client  NVARCHAR(200),
    @source_ip      NVARCHAR(50) = NULL,

    @result_code    NVARCHAR(20)  OUTPUT,
    @friendly_msg   NVARCHAR(400) OUTPUT,
    @is_alive       BIT           OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @is_alive = 0;
    SET @result_code = NULL;
    SET @friendly_msg = NULL;

    DECLARE
        @user_id INT,
        @is_active BIT,
        @last_seen DATETIME2(3),
        @now DATETIME2(3) = SYSUTCDATETIME(),
        @timeout_minutes INT,
        @session_status NVARCHAR(20),
        @transition_code NVARCHAR(20),
        @transition_msg NVARCHAR(400),
        @client_app NVARCHAR(100),
        @details NVARCHAR(4000);

    SELECT
        @user_id = s.user_id,
        @is_active = s.is_active,
        @last_seen = s.last_seen,
        @session_status = s.session_status,
        @client_app = s.client_app
    FROM auth.user_sessions s
    WHERE s.session_id = @session_id;

    IF @user_id IS NULL
    BEGIN
        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    IF @session_status IS NULL
    BEGIN
        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    IF @session_status IN ('EXPIRED', 'LOGGED_OUT', 'REVOKED')
    BEGIN
        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    SELECT @timeout_minutes =
        COALESCE(c.session_timeout_minutes,
            TRY_CONVERT(INT, os.setting_value))
    FROM operations.settings os
    LEFT JOIN auth.clients c
        ON c.client_name = @client_app
    WHERE os.setting_name = 'auth.session_timeout_minutes';

    IF @timeout_minutes IS NULL OR @timeout_minutes <= 0
        SET @timeout_minutes = 30;

    IF @last_seen IS NULL
       OR @last_seen < DATEADD(MINUTE, -@timeout_minutes, @now)
    BEGIN
        SET @details =
            N'{"last_seen":"'
            + COALESCE(CONVERT(NVARCHAR(30), @last_seen, 126), N'NULL')
            + N'","reason":"touch timeout"}';

        EXEC auth.usp_session_set_status
            @session_id = @session_id,
            @to_status = 'EXPIRED',
            @source_app = @source_app,
            @source_client = @source_client,
            @source_ip = @source_ip,
            @details = @details,
            @result_code = @transition_code OUTPUT,
            @friendly_msg = @transition_msg OUTPUT;

        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    UPDATE auth.user_sessions
    SET
        last_seen = @now,
        session_status = CASE
            WHEN session_status = 'IDLE' THEN 'ACTIVE'
            ELSE session_status
        END,
        is_active = 1
    WHERE session_id = @session_id;

    SET @result_code = 'SUCAUTH02';
    SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
    SET @is_alive = 1;
END;
GO


/* ============================================================
   8. LOGOUT
   ============================================================*/
GO

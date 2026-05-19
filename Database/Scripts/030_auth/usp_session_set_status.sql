USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_session_set_status
(
    @session_id        UNIQUEIDENTIFIER,
    @to_status         NVARCHAR(20),
    @source_app        NVARCHAR(100) = NULL,
    @source_client     NVARCHAR(200) = NULL,
    @source_ip         NVARCHAR(50)  = NULL,
    @details           NVARCHAR(4000) = NULL,

    @result_code       NVARCHAR(20)  OUTPUT,
    @friendly_msg      NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @from_status NVARCHAR(20),
        @user_id INT,
        @system_user_id INT,
        @event_type NVARCHAR(30);

    --------------------------------------------------
    -- Lock row (prevents race conditions)
    --------------------------------------------------

    SELECT
        @from_status = s.session_status,
        @user_id = s.user_id
    FROM auth.user_sessions s WITH (UPDLOCK, ROWLOCK)
    WHERE s.session_id = @session_id;

    IF @from_status IS NULL
    BEGIN
        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    --------------------------------------------------
    -- Terminal state protection
    --------------------------------------------------

    IF @from_status IN ('EXPIRED', 'LOGGED_OUT', 'REVOKED')
    BEGIN
        SET @result_code = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    --------------------------------------------------
    -- Validate target status
    --------------------------------------------------

    IF NOT EXISTS
    (
        SELECT 1
        FROM auth.session_statuses ss
        WHERE ss.status_code = @to_status
    )
    BEGIN
        SET @result_code = 'ERRPROC02';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    --------------------------------------------------
    -- No-op (same state)
    --------------------------------------------------

    IF @from_status = @to_status
    BEGIN
        SET @result_code = 'SUCAUTH02';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    --------------------------------------------------
    -- Validate transition
    --------------------------------------------------

    IF NOT EXISTS
    (
        SELECT 1
        FROM auth.session_status_transitions t
        WHERE t.from_status = @from_status
          AND t.to_status = @to_status
    )
    BEGIN
        SET @result_code = 'ERRAUTH07';
        SET @friendly_msg = CONCAT(
            'Illegal session transition from ',
            @from_status,
            ' to ',
            @to_status,
            '.');
        RETURN;
    END;

    --------------------------------------------------
    -- Apply transition
    --------------------------------------------------

    UPDATE auth.user_sessions
    SET
        session_status = @to_status,
        is_active =
            CASE
                WHEN @to_status IN ('ACTIVE', 'IDLE') THEN 1
                ELSE 0
            END,
        updated_at = SYSUTCDATETIME()
    WHERE session_id = @session_id;

    --------------------------------------------------
    -- Resolve event type
    --------------------------------------------------

    SET @event_type =
        CASE @to_status
            WHEN 'ACTIVE' THEN 'SESSION_REACTIVATED'
            WHEN 'IDLE' THEN 'SESSION_IDLE'
            WHEN 'EXPIRED' THEN 'LOGOUT_TIMEOUT'
            WHEN 'LOGGED_OUT' THEN 'LOGOUT_USER'
            WHEN 'REVOKED' THEN 'SESSION_KILLED'
            ELSE 'SESSION_STATUS_CHANGED'
        END;

    --------------------------------------------------
    -- System user fallback
    --------------------------------------------------

    SELECT TOP (1)
        @system_user_id = id
    FROM auth.users
    WHERE username = 'system';

    --------------------------------------------------
    -- Log event
    --------------------------------------------------

    INSERT INTO auth.session_events
    (
        session_id,
        user_id,
        event_type,
        source_app,
        source_client,
        source_ip,
        details,
        created_by
    )
    VALUES
    (
        @session_id,
        @user_id,
        @event_type,
        @source_app,
        @source_client,
        @source_ip,
        @details,
        COALESCE(CONVERT(INT, SESSION_CONTEXT(N'user_id')), @system_user_id)
    );

    --------------------------------------------------
    -- Success
    --------------------------------------------------

    SET @result_code = 'SUCAUTH02';
    SET @friendly_msg = operations.fn_get_friendly_message(@result_code);

END;
GO

---------------------------------------------------------------
-- 1.8 SESSION CONFIG TABLE
---------------------------------------------------------------
IF OBJECT_ID('auth.clients', 'U') IS NULL
BEGIN
    CREATE TABLE auth.clients
    (
        client_name NVARCHAR(100) NOT NULL
            CONSTRAINT PK_auth_clients PRIMARY KEY,
            -- Unique identifier of the client application.
            -- Must match the value stored in auth.user_sessions.client_info

        session_timeout_minutes INT NULL,
            -- Optional client-specific timeout override.
            -- NULL = use global timeout from operations.settings

        max_concurrent_sessions INT NULL,
            -- Optional limit for concurrent sessions per user.
            -- NULL = unlimited

        is_active BIT NOT NULL
            CONSTRAINT DF_auth_clients_is_active DEFAULT (1),
            -- Allows disabling a client without deleting it

        description NVARCHAR(255) NULL,

        created_at DATETIME2(3) NOT NULL
            CONSTRAINT DF_auth_clients_created_at DEFAULT SYSUTCDATETIME(),

        created_by INT NULL
            DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'user_id')))
    );
END;
GO

---------------------------------------------------------------
-- 1.9 SESSION CLIENT SEED - Required, do not delete
---------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = 'PeasyWare.Desktop')
BEGIN
    INSERT INTO auth.clients
        (client_name, session_timeout_minutes, max_concurrent_sessions, description, created_by)
    VALUES
        ('PeasyWare.Desktop', 480, NULL, 'PeasyWare desktop application',
            (SELECT id FROM auth.users WHERE username = 'system'));
END;

IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = 'PeasyWare.CLI')
BEGIN
    INSERT INTO auth.clients
        (client_name, session_timeout_minutes, max_concurrent_sessions, description, created_by)
    VALUES
        ('PeasyWare.CLI', 60, NULL, 'PeasyWare terminal application',
            (SELECT id FROM auth.users WHERE username = 'system'));
END;
GO

/* ============================================================
    2.1 HELPER: HASH PASSWORD
   ============================================================*/
GO

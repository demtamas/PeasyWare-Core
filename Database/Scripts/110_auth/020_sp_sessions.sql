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
   6. LOGIN
   ============================================================*/
GO

/* ============================================================
   8. LOGOUT
   ============================================================*/
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

/* ============================================================
    2.1 HELPER: HASH PASSWORD
   ============================================================*/

CREATE OR ALTER PROCEDURE auth.sp_hash_password
(
    @plain NVARCHAR(200),
    @salt  VARBINARY(256) OUTPUT,
    @hash  VARBINARY(512) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @plain IS NULL
    BEGIN
        SET @salt = NULL;
        SET @hash = NULL;
        RETURN;
    END;

    -- 32 bytes of cryptographic salt
    SET @salt = CRYPT_GEN_RANDOM(32);

    SET @hash = HASHBYTES('SHA2_512',
                CONVERT(VARBINARY(512), @plain) + @salt);
END;
GO

/* ============================================================
   3. SESSION CLEANUP
   ============================================================*/

CREATE OR ALTER PROCEDURE auth.usp_session_cleanup
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @default_timeout_minutes INT =
    (
        SELECT TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'auth.session_timeout_minutes'
    );

    IF @default_timeout_minutes IS NULL OR @default_timeout_minutes <= 0
        SET @default_timeout_minutes = 30;

    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @SystemUserId INT =
    (
        SELECT TOP (1) id
        FROM auth.users
        WHERE username = 'system'
    );

    ------------------------------------------------------------------
    -- First: materialise expired rows into a temp table (bulletproof)
    ------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Expired') IS NOT NULL
        DROP TABLE #Expired;

    SELECT
        s.session_id,
        s.user_id,
        s.client_info,
        s.last_seen
    INTO #Expired
    FROM auth.user_sessions s
    LEFT JOIN auth.clients c
        ON c.client_name = s.client_app
    CROSS APPLY
    (
        SELECT COALESCE(c.session_timeout_minutes, @default_timeout_minutes) AS effective_timeout
    ) t
    WHERE
        s.is_active = 1
        AND (
                s.last_seen IS NULL
             OR DATEADD(MINUTE, t.effective_timeout, s.last_seen) <= @now
        );

    ------------------------------------------------------------------
    -- Log timeout events
    ------------------------------------------------------------------
    INSERT INTO auth.session_events
        (session_id, user_id, event_type, source_app, source_client, source_ip, details, created_by)
    SELECT
        e.session_id,
        e.user_id,
        'LOGOUT_TIMEOUT',
        NULL,              -- background process
        e.client_info,
        NULL,
        CONCAT(
            N'{"reason":"cleanup timeout","last_seen":"',
            CONVERT(varchar(30), e.last_seen, 126),
            N'"}'
        ),
        @SystemUserId
    FROM #Expired e;

    ------------------------------------------------------------------
    -- Deactivate expired sessions via lifecycle transition
    ------------------------------------------------------------------
    DECLARE
        @expired_session_id UNIQUEIDENTIFIER,
        @code NVARCHAR(20),
        @msg NVARCHAR(400);

    DECLARE expired_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT e.session_id
        FROM #Expired e;

    OPEN expired_cursor;

    FETCH NEXT FROM expired_cursor INTO @expired_session_id;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC auth.usp_session_set_status
            @session_id = @expired_session_id,
            @to_status = 'EXPIRED',
            @source_app = 'PeasyWare.System',
            @source_client = 'SessionCleanupJob',
            @source_ip = NULL,
            @details = N'{"reason":"cleanup timeout"}',
            @result_code = @code OUTPUT,
            @friendly_msg = @msg OUTPUT;

        FETCH NEXT FROM expired_cursor INTO @expired_session_id;
    END

    CLOSE expired_cursor;
    DEALLOCATE expired_cursor;

END;
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

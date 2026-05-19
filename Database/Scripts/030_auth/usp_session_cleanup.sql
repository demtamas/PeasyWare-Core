USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

/* ============================================================
   6. LOGIN
   ============================================================*/
GO

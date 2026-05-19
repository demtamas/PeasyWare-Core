USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('audit.event_catalog') IS NULL
BEGIN
    CREATE TABLE audit.event_catalog
    (
        event_name NVARCHAR(200) PRIMARY KEY,
        description NVARCHAR(500) NOT NULL,
        is_active BIT NOT NULL DEFAULT 1
    );
END;

----------------------------------------------------------
-- 2. EVENT CATALOG SEED
----------------------------------------------------------
INSERT INTO audit.event_catalog (event_name, description)
SELECT v.event_name, v.description
FROM (VALUES

    ('auth.login', 'User login attempt'),
    ('auth.password.changed', 'User password updated'),

    ('user.created', 'User account created'),
    ('user.status.updated', 'User enabled or disabled'),
    ('user.password.reset', 'Admin password reset'),

    ('session.created', 'Session started'),
    ('session.touched', 'Session activity recorded'),
    ('session.ended', 'Session ended'),
    ('session.logout', 'User logout'),

    ('system.setting.updated', 'System configuration updated'),
    ('system.error.occurred', 'Unhandled system error'),

    ('trace.session', 'Session trace heartbeat'),
    ('trace.action', 'Generic trace action')

) v(event_name, description)
WHERE NOT EXISTS (
    SELECT 1 FROM audit.event_catalog e WHERE e.event_name = v.event_name
);

----------------------------------------------------------
-- 3. RESULT CODE TABLE
----------------------------------------------------------
IF OBJECT_ID('audit.event_result_codes') IS NULL
BEGIN
    CREATE TABLE audit.event_result_codes
    (
        event_name NVARCHAR(200) NOT NULL,
        result_code NVARCHAR(50) NOT NULL,
        PRIMARY KEY (event_name, result_code),
        FOREIGN KEY (event_name) REFERENCES audit.event_catalog(event_name)
    );
END;

----------------------------------------------------------
-- 4. RESULT CODE SEED (ALL DOMAINS)
----------------------------------------------------------
INSERT INTO audit.event_result_codes (event_name, result_code)
SELECT v.event_name, v.result_code
FROM (VALUES

    -- auth.login
    ('auth.login', 'SUCCESS'),
    ('auth.login', 'INVALID_PASSWORD'),
    ('auth.login', 'USER_DISABLED'),
    ('auth.login', 'USER_LOCKED'),
    ('auth.login', 'USER_TERMINAL_LOCK'),
    ('auth.login', 'ALREADY_LOGGED_IN'),
    ('auth.login', 'PASSWORD_CHANGE_REQUIRED'),
    ('auth.login', 'ERROR'),

    -- user.created
    ('user.created', 'SUCCESS'),
    ('user.created', 'DUPLICATE_USERNAME'),
    ('user.created', 'DUPLICATE_EMAIL'),
    ('user.created', 'INVALID_ROLE'),
    ('user.created', 'ERROR'),

    -- user.status.updated
    ('user.status.updated', 'SUCCESS'),
    ('user.status.updated', 'NOT_FOUND'),
    ('user.status.updated', 'ERROR'),

    -- user.password.reset
    ('user.password.reset', 'SUCCESS'),
    ('user.password.reset', 'NOT_FOUND'),
    ('user.password.reset', 'VALIDATION_FAILED'),
    ('user.password.reset', 'ERROR'),

    -- session.logout
    ('session.logout', 'SUCCESS'),
    ('session.logout', 'NOT_FOUND'),
    ('session.logout', 'ALREADY_ENDED'),
    ('session.logout', 'ERROR'),

    -- session.touched
    ('session.touched', 'SUCCESS'),
    ('session.touched', 'SESSION_EXPIRED'),

    -- session.ended
    ('session.ended', 'SUCCESS'),

    -- settings
    ('system.setting.updated', 'SUCCESS'),
    ('system.setting.updated', 'VALIDATION_FAILED'),
    ('system.setting.updated', 'ERROR'),

    -- system error
    ('system.error.occurred', 'UNHANDLED_EXCEPTION')

) v(event_name, result_code)
WHERE NOT EXISTS (
    SELECT 1
    FROM audit.event_result_codes e
    WHERE e.event_name = v.event_name
      AND e.result_code = v.result_code
);

----------------------------------------------------------
-- 5. FK FROM audit_events → catalog
----------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_audit_events_event_name'
)
BEGIN
    ALTER TABLE audit.audit_events
    ADD CONSTRAINT FK_audit_events_event_name
    FOREIGN KEY (event_name)
    REFERENCES audit.event_catalog(event_name);
END;

----------------------------------------------------------
-- 6. VALIDATION FUNCTION
----------------------------------------------------------
IF OBJECT_ID('audit.fn_is_valid_result_code') IS NOT NULL
    DROP FUNCTION audit.fn_is_valid_result_code;
GO

CREATE FUNCTION audit.fn_is_valid_result_code
(
    @event_name NVARCHAR(200),
    @result_code NVARCHAR(50)
)
RETURNS BIT
AS
BEGIN
    RETURN (
        SELECT CASE 
            WHEN EXISTS (
                SELECT 1
                FROM audit.event_result_codes
                WHERE event_name = @event_name
                  AND result_code = @result_code
            )
            THEN 1 ELSE 0 END
    );
END;
GO

----------------------------------------------------------
-- 7. CHECK CONSTRAINT
----------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_audit_events_valid_result_code'
)
BEGIN
    ALTER TABLE audit.audit_events
    ADD CONSTRAINT CK_audit_events_valid_result_code
    CHECK (audit.fn_is_valid_result_code(event_name, result_code) = 1);
END;

----------------------------------------------------------
-- 8. TRACE TABLE
----------------------------------------------------------
IF OBJECT_ID('audit.trace_logs') IS NULL
BEGIN
    CREATE TABLE audit.trace_logs
    (
        trace_id        BIGINT IDENTITY PRIMARY KEY,
        occurred_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        correlation_id  UNIQUEIDENTIFIER NULL,
        user_id         INT NULL,
        session_id      UNIQUEIDENTIFIER NULL,
        level           NVARCHAR(10) NOT NULL,
        action          NVARCHAR(200) NOT NULL,
        payload_json    NVARCHAR(MAX) NULL
    );
END;

----------------------------------------------------------
-- 9. TRACE PROCEDURE
----------------------------------------------------------
IF OBJECT_ID('audit.usp_log_trace') IS NOT NULL
    DROP PROCEDURE audit.usp_log_trace;
GO

CREATE PROCEDURE audit.usp_log_trace
(
    @correlation_id UNIQUEIDENTIFIER = NULL,
    @user_id        INT = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @level          NVARCHAR(10),
    @action         NVARCHAR(200),
    @payload_json   NVARCHAR(MAX) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @level  = UPPER(LTRIM(RTRIM(@level)));
    SET @action = LTRIM(RTRIM(@action));

    IF @level NOT IN ('INFO', 'WARN', 'ERROR')
        THROW 51001, 'audit.usp_log_trace: invalid level.', 1;

    IF @action IS NULL OR @action = ''
        THROW 51002, 'audit.usp_log_trace: action is required.', 1;

    IF @payload_json IS NOT NULL AND ISJSON(@payload_json) <> 1
        THROW 51003, 'audit.usp_log_trace: payload must be valid JSON.', 1;

    INSERT INTO audit.trace_logs
    (
        occurred_at,
        correlation_id,
        user_id,
        session_id,
        level,
        action,
        payload_json
    )
    VALUES
    (
        SYSUTCDATETIME(),
        @correlation_id,
        @user_id,
        @session_id,
        @level,
        @action,
        @payload_json
    );
END;
GO

/* ========================================================
   EVENT RESULT CODES (IDEMPOTENT INSERT)
======================================================== */

/* ========================================================
   EVENT CATALOG TABLE
======================================================== */

IF OBJECT_ID('audit.event_catalog') IS NULL
BEGIN
    CREATE TABLE audit.event_catalog
    (
        event_name NVARCHAR(200) PRIMARY KEY,
        description NVARCHAR(500) NOT NULL,
        is_active BIT NOT NULL DEFAULT 1
    );
END;

/* ========================================================
   AUTH RESULT MAPPING FUNCTION
======================================================== */

IF OBJECT_ID('audit.fn_map_auth_result') IS NOT NULL
    DROP FUNCTION audit.fn_map_auth_result;
GO

CREATE FUNCTION audit.fn_map_auth_result
(
    @result_code NVARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        event_result_code =
            CASE
                WHEN @result_code = 'SUCAUTH01' THEN 'SUCCESS'

                WHEN @result_code = 'ERRAUTH01' THEN 'INVALID_PASSWORD'
                WHEN @result_code = 'ERRAUTH02' THEN 'USER_DISABLED'
                WHEN @result_code = 'ERRAUTH05' THEN 'ALREADY_LOGGED_IN'
                WHEN @result_code = 'ERRAUTH07' THEN 'USER_LOCKED'
                WHEN @result_code = 'ERRAUTH08' THEN 'USER_TERMINAL_LOCK'
                WHEN @result_code = 'ERRAUTH09' THEN 'PASSWORD_CHANGE_REQUIRED'

                ELSE 'ERROR'
            END,

        event_success =
            CASE
                WHEN @result_code = 'SUCAUTH01' THEN 1
                ELSE 0
            END
);
GO


/* ========================================================
   CHECK CONSTRAINT (SAFE ADD)
======================================================== */

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_audit_events_valid_result_code'
)
BEGIN
    ALTER TABLE audit.audit_events
    ADD CONSTRAINT CK_audit_events_valid_result_code
    CHECK (audit.fn_is_valid_result_code(event_name, result_code) = 1);
END;
GO

IF OBJECT_ID('audit.fn_map_user_result') IS NOT NULL
    DROP FUNCTION audit.fn_map_user_result;
GO

CREATE FUNCTION audit.fn_map_user_result
(
    @result_code NVARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        event_result_code =
            CASE
                WHEN @result_code = 'SUCAUTHUSR01' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTHUSR01' THEN 'DUPLICATE_USERNAME'
                WHEN @result_code = 'ERRAUTHUSR04' THEN 'DUPLICATE_EMAIL'
                WHEN @result_code = 'ERRAUTHUSR02' THEN 'INVALID_ROLE'
                WHEN @result_code = 'ERRUSR01' THEN 'NOT_FOUND'
                WHEN @result_code = 'SUCUSR01' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTH02' THEN 'NOT_FOUND'
                WHEN @result_code = 'SUCAUTH10' THEN 'SUCCESS'
                WHEN @result_code LIKE 'ERRAUTH%' THEN 'VALIDATION_FAILED'
                WHEN @result_code = 'SUCAUTH03' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTH06' THEN 'NOT_FOUND'
                ELSE 'ERROR'
            END,

        event_success =
            CASE
                WHEN @result_code = 'SUCAUTHUSR01' THEN 1
                ELSE 0
            END
);
GO

/* ============================================================
   10. CREATE USER (provisioning)
   ============================================================*/
GO

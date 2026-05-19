USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_roles_get
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        role_name   AS RoleName,
        description AS Description
    FROM auth.roles
    WHERE is_active      = 1
      AND is_system_role = 0        -- never show system roles in user-facing dropdowns
    ORDER BY role_name;
END;
GO

---------------------------------------------------------------
-- 1.4 Sessions
---------------------------------------------------------------
IF OBJECT_ID('auth.user_sessions', 'U') IS NULL
BEGIN
    CREATE TABLE auth.user_sessions
    (
        session_id  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
        user_id     INT              NOT NULL,
        login_time  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        last_seen   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        is_active   BIT              NOT NULL DEFAULT 1,
        client_info NVARCHAR(200)    NULL,
        client_app  NVARCHAR(50)     NOT NULL,
        correlation_id uniqueidentifier NULL,
        session_status NVARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        created_at  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at  DATETIME2(3)     

        CONSTRAINT FK_user_sessions_user
        FOREIGN KEY (user_id) REFERENCES auth.users(id)
    );
END;
GO

---------------------------------------------------------------
-- 1.5 Login attempts (audit)
---------------------------------------------------------------
IF OBJECT_ID('auth.login_attempts', 'U') IS NULL
BEGIN
    CREATE TABLE auth.login_attempts
    (
        id           BIGINT IDENTITY(1,1) PRIMARY KEY,
        username     NVARCHAR(100)  NOT NULL,
        attempt_time DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
        result_code  NVARCHAR(20)   NULL,
        success      BIT            NOT NULL DEFAULT 0,
        session_id   UNIQUEIDENTIFIER NULL,
        correlation_id uniqueidentifier NULL,
        ip_address   NVARCHAR(50)   NULL,
        client_info  NVARCHAR(200)  NULL,
        client_app   NVARCHAR(50)   NULL,
        os_info      NVARCHAR(200)  NULL
    );
END;
GO

---------------------------------------------------------------
-- Support trace lookups by correlation
---------------------------------------------------------------

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_login_attempts_correlation_id'
      AND object_id = OBJECT_ID('auth.login_attempts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_login_attempts_correlation_id
        ON auth.login_attempts (correlation_id)
        INCLUDE (attempt_time, username, success, session_id);
END;
GO

---------------------------------------------------------------
-- 1.6 Password history
---------------------------------------------------------------
IF OBJECT_ID('auth.password_history', 'U') IS NULL
BEGIN
    CREATE TABLE auth.password_history
    (
        id            BIGINT IDENTITY(1,1) PRIMARY KEY,
        user_id       INT            NOT NULL,
        password_hash VARBINARY(512) NOT NULL,
        salt          VARBINARY(256) NOT NULL,
        changed_at    DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_password_history_users FOREIGN KEY (user_id)
            REFERENCES auth.users(id)
    );
END;
GO

---------------------------------------------------------------
-- 1.7 SESSION EVENTS TABLE
---------------------------------------------------------------
IF OBJECT_ID('auth.session_events', 'U') IS NULL
BEGIN
    CREATE TABLE auth.session_events
    (
        id             BIGINT IDENTITY(1,1) PRIMARY KEY,

        session_id     UNIQUEIDENTIFIER NOT NULL,
        user_id        INT              NOT NULL,

        event_type     NVARCHAR(30)     NOT NULL,
        -- LOGIN_CREATED | LOGOUT_USER | LOGOUT_FORCED | LOGOUT_TIMEOUT | SESSION_KILLED

        event_time     DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),

        source_app     NVARCHAR(100)    NULL,
        source_client  NVARCHAR(200)    NULL,
        source_ip      NVARCHAR(50)     NULL,

        details        NVARCHAR(4000)   NULL,   -- Optional JSON

        created_at     DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        created_by     INT              NULL 
                             DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'user_id')))
    );
END;
GO

---------------------------------------------------------------
-- 1.7.1 SESSION STATUS MASTER
---------------------------------------------------------------
IF OBJECT_ID('auth.session_statuses', 'U') IS NULL
BEGIN
    CREATE TABLE auth.session_statuses
    (
        status_code NVARCHAR(20) NOT NULL
            CONSTRAINT PK_auth_session_statuses PRIMARY KEY,

        description NVARCHAR(200) NOT NULL,

        is_terminal BIT NOT NULL DEFAULT 0,
        -- 1 = cannot transition out (EXPIRED, LOGGED_OUT, REVOKED)

        created_at DATETIME2(3) NOT NULL
            CONSTRAINT DF_auth_session_statuses_created_at DEFAULT SYSUTCDATETIME()
    );
END;
GO

---------------------------------------------------------------
-- SEED SESSION STATUSES
---------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'ACTIVE')
INSERT INTO auth.session_statuses VALUES ('ACTIVE', 'Session is active', 0, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'IDLE')
INSERT INTO auth.session_statuses VALUES ('IDLE', 'Session is idle', 0, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'EXPIRED')
INSERT INTO auth.session_statuses VALUES ('EXPIRED', 'Session expired due to timeout', 1, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'LOGGED_OUT')
INSERT INTO auth.session_statuses VALUES ('LOGGED_OUT', 'User logged out', 1, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'REVOKED')
INSERT INTO auth.session_statuses VALUES ('REVOKED', 'Session revoked by system/admin', 1, SYSUTCDATETIME());
GO

---------------------------------------------------------------
-- 1.7.1 SESSION STATUS MASTER
---------------------------------------------------------------
IF OBJECT_ID('auth.session_statuses', 'U') IS NULL
BEGIN
    CREATE TABLE auth.session_statuses
    (
        status_code NVARCHAR(20) NOT NULL
            CONSTRAINT PK_auth_session_statuses PRIMARY KEY,

        description NVARCHAR(200) NOT NULL,

        is_terminal BIT NOT NULL DEFAULT 0,
        -- 1 = cannot transition out (EXPIRED, LOGGED_OUT, REVOKED)

        created_at DATETIME2(3) NOT NULL
            CONSTRAINT DF_auth_session_statuses_created_at DEFAULT SYSUTCDATETIME()
    );
END;
GO

---------------------------------------------------------------
-- SEED SESSION STATUSES
---------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'ACTIVE')
INSERT INTO auth.session_statuses VALUES ('ACTIVE', 'Session is active', 0, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'IDLE')
INSERT INTO auth.session_statuses VALUES ('IDLE', 'Session is idle', 0, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'EXPIRED')
INSERT INTO auth.session_statuses VALUES ('EXPIRED', 'Session expired due to timeout', 1, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'LOGGED_OUT')
INSERT INTO auth.session_statuses VALUES ('LOGGED_OUT', 'User logged out', 1, SYSUTCDATETIME());

IF NOT EXISTS (SELECT 1 FROM auth.session_statuses WHERE status_code = 'REVOKED')
INSERT INTO auth.session_statuses VALUES ('REVOKED', 'Session revoked by system/admin', 1, SYSUTCDATETIME());
GO

---------------------------------------------------------------
-- 1.7.2 SESSION STATUS TRANSITIONS
---------------------------------------------------------------
IF OBJECT_ID('auth.session_status_transitions', 'U') IS NULL
BEGIN
    CREATE TABLE auth.session_status_transitions
    (
        from_status NVARCHAR(20) NOT NULL,
        to_status   NVARCHAR(20) NOT NULL,

        CONSTRAINT PK_auth_session_status_transitions
            PRIMARY KEY (from_status, to_status),

        CONSTRAINT FK_auth_sst_from
            FOREIGN KEY (from_status)
            REFERENCES auth.session_statuses(status_code),

        CONSTRAINT FK_auth_sst_to
            FOREIGN KEY (to_status)
            REFERENCES auth.session_statuses(status_code)
    );
END;
GO

---------------------------------------------------------------
-- ALLOWED TRANSITIONS
---------------------------------------------------------------

-- ACTIVE transitions
INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'ACTIVE', 'IDLE'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='ACTIVE' AND to_status='IDLE');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'ACTIVE', 'EXPIRED'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='ACTIVE' AND to_status='EXPIRED');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'ACTIVE', 'LOGGED_OUT'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='ACTIVE' AND to_status='LOGGED_OUT');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'ACTIVE', 'REVOKED'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='ACTIVE' AND to_status='REVOKED');


-- IDLE transitions
INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'IDLE', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='IDLE' AND to_status='ACTIVE');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'IDLE', 'EXPIRED'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='IDLE' AND to_status='EXPIRED');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'IDLE', 'LOGGED_OUT'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='IDLE' AND to_status='LOGGED_OUT');

INSERT INTO auth.session_status_transitions (from_status, to_status)
SELECT 'IDLE', 'REVOKED'
WHERE NOT EXISTS (SELECT 1 FROM auth.session_status_transitions WHERE from_status='IDLE' AND to_status='REVOKED');

GO

---------------------------------------------------------------
-- 1.7.3 ADD STATUS TO USER SESSIONS
---------------------------------------------------------------
IF COL_LENGTH('auth.user_sessions', 'session_status') IS NULL
BEGIN
    ALTER TABLE auth.user_sessions
    ADD session_status NVARCHAR(20) NOT NULL
        CONSTRAINT DF_auth_user_sessions_status DEFAULT 'ACTIVE';
END;
GO

---------------------------------------------------------------
-- ADD FK TO STATUS MASTER
---------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_auth_user_sessions_status'
)
BEGIN
    ALTER TABLE auth.user_sessions
    ADD CONSTRAINT FK_auth_user_sessions_status
        FOREIGN KEY (session_status)
        REFERENCES auth.session_statuses(status_code);
END;
GO

---------------------------------------------------------------
-- ADD FK TO SESSION
---------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_auth_session_events_session'
)
BEGIN
    ALTER TABLE auth.session_events
    ADD CONSTRAINT FK_auth_session_events_session
        FOREIGN KEY (session_id)
        REFERENCES auth.user_sessions(session_id);
END;
GO

---------------------------------------------------------------
-- ADD FK TO USER
---------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_auth_session_events_user'
)
BEGIN
    ALTER TABLE auth.session_events
    ADD CONSTRAINT FK_auth_session_events_user
        FOREIGN KEY (user_id)
        REFERENCES auth.users(id);
END;
GO

---------------------------------------------------------------
-- 1.7.4 SESSION STATUS TRANSITION PROCEDURE
---------------------------------------------------------------
GO

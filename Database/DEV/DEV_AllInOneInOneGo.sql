------------------------------------------------------------
-- Detect environment
------------------------------------------------------------
USE master;
GO

DECLARE @db sysname       = N'PW_Core_DEV';
DECLARE @os NVARCHAR(200) = LOWER(@@VERSION);
DECLARE @backupPath NVARCHAR(500);

IF @os LIKE '%windows%'
    SET @backupPath = 'C:\SQL_Backups\PW_Core_DEV.bak';
ELSE
    SET @backupPath = '/var/opt/mssql/backups/PW_Core_DEV.bak';

PRINT 'Environment: ' + @os;
PRINT 'Backup Path: ' + @backupPath;
PRINT '------------------------------------------------------------';


------------------------------------------------------------
-- Backup & Drop Existing DB
------------------------------------------------------------
IF DB_ID(@db) IS NOT NULL
BEGIN
    PRINT 'Backing up existing database [' + @db + ']...';

    BACKUP DATABASE [PW_Core_DEV]
        TO DISK = @backupPath
        WITH FORMAT, INIT, NAME = 'PW_Core_DEV Backup';

    PRINT 'Backup done. Dropping database...';

    ALTER DATABASE [PW_Core_DEV] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PW_Core_DEV];

    PRINT 'Existing PW_Core_DEV dropped.';
END
ELSE
BEGIN
    PRINT 'No existing PW_Core_DEV found. Creating fresh database.';
END
PRINT '------------------------------------------------------------';
GO


/********************************************************************************************
    PeasyWare WMS - Core Database Schema
    Version:        1.0.0
    Database:       PW_Core_DEV
    Description:    Single-file core schema + operational seed data
                    - Schemas
                    - Core tables
                    - Status & error lookup data
                    - Core stored procedures & helper functions

    Notes:
      - Intended for development and pre-production.
      - Test data (sample inbound, inventory, etc.) belongs in a SEPARATE script.
      - When production-ready, switch to migrations for structural changes.

********************************************************************************************/

-------------------------------------------
-- 1. Create / select database
-------------------------------------------
IF DB_ID('PW_Core_DEV') IS NULL
BEGIN
    CREATE DATABASE [PW_Core_DEV];
END;
GO

USE [PW_Core_DEV];
GO

-------------------------------------------
-- 2. Create schemas
-------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'auth')
    EXEC('CREATE SCHEMA auth');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC('CREATE SCHEMA audit');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inventory')
    EXEC('CREATE SCHEMA inventory');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'deliveries')
    EXEC('CREATE SCHEMA deliveries');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'locations')
    EXEC('CREATE SCHEMA locations');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'operations')
    EXEC('CREATE SCHEMA operations');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'core')
    EXEC('CREATE SCHEMA core');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'suppliers')
    EXEC('CREATE SCHEMA suppliers');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'customers')
    EXEC('CREATE SCHEMA customers');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'logistics')
    EXEC('CREATE SCHEMA logistics');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'warehouse')
    EXEC('CREATE SCHEMA warehouse');
GO

/********************************************************************************************
    3. OPERATIONS SCHEMA
    - Global settings
    - Friendly error messages
    - Error log
    - Core helpers (session user, friendly message lookup)
********************************************************************************************/

-------------------------------------------
-- 3.1 Settings table
-- Stores configuration values (environment, toggles, etc.)
-------------------------------------------
IF OBJECT_ID('operations.settings', 'U') IS NULL
BEGIN
    CREATE TABLE operations.settings
    (
        setting_name    sysname          NOT NULL PRIMARY KEY,
        setting_value   nvarchar(4000)   NULL,
        data_type       nvarchar(50)     NOT NULL DEFAULT ('string'), -- string/int/bool/json/etc.
        description     nvarchar(500)    NULL,
        is_sensitive    bit              NOT NULL DEFAULT (0),

        created_at      datetime2(3)     NOT NULL CONSTRAINT DF_operations_settings_created_at DEFAULT (sysutcdatetime()),
        created_by      int              NULL     CONSTRAINT DF_operations_settings_created_by DEFAULT (CONVERT(int, SESSION_CONTEXT(N'user_id'))),
        updated_at      datetime2(3)     NULL,
        updated_by      int              NULL
    );
END;
GO

-------------------------------------------
-- 3.2 EVENTS TABLE
-- Audit trail.
-------------------------------------------
CREATE TABLE audit.audit_events
(
    audit_id        BIGINT IDENTITY PRIMARY KEY,
    occurred_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    correlation_id  UNIQUEIDENTIFIER NULL,
    user_id         INT NULL,
    session_id      UNIQUEIDENTIFIER NULL,
    event_name      NVARCHAR(1000) NOT NULL,
    result_code     NVARCHAR(20) NOT NULL,
    success         BIT NOT NULL,
    payload_json    NVARCHAR(MAX) NULL
);

CREATE NONCLUSTERED INDEX IX_audit_events_correlation
ON audit.audit_events (correlation_id);

CREATE NONCLUSTERED INDEX IX_audit_events_session
ON audit.audit_events (session_id);

CREATE NONCLUSTERED INDEX IX_audit_events_user_time
ON audit.audit_events (user_id, occurred_at DESC);

CREATE NONCLUSTERED INDEX IX_audit_events_event_time
ON audit.audit_events (event_name, occurred_at DESC);

-- Helper macro style: Update if exists, otherwise insert.
-- Pattern used across all settings.

-------------------------------------------
-- CORE
-------------------------------------------

-- core.version
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'core.version')
    UPDATE operations.settings SET setting_value = '1.0.0' 
    WHERE setting_name = 'core.version';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('core.version', '1.0.0', 'string', 'PeasyWare Core DB schema version');

-- core.environment
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'core.environment')
    UPDATE operations.settings SET setting_value = 'dev' 
    WHERE setting_name = 'core.environment';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('core.environment', 'dev', 'string', 'Environment (dev/test/prod)');

-- inbound.auto_complete_on_full_receipt
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'inbound.auto_complete_on_full_receipt')
    UPDATE operations.settings SET setting_value = 'false'
    WHERE setting_name = 'inbound.auto_complete_on_full_receipt';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('inbound.auto_complete_on_full_receipt', 'false', 'bool',
            'Auto-complete inbound header when all rows fully received');


-------------------------------------------
-- AUTHENTICATION SETTINGS
-------------------------------------------

IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.login_enabled')
    UPDATE operations.settings
    SET setting_value = 'true', data_type = 'bool',
        description = 'Master switch to disable all user logins',
        updated_at = SYSUTCDATETIME(),
        updated_by = CONVERT(int, SESSION_CONTEXT(N'user_id'))
    WHERE setting_name = 'auth.login_enabled';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.login_enabled', 'true', 'bool',
            'Master switch to disable all user logins');

-- Hard session expiry (server-side)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.session_timeout_minutes')
    UPDATE operations.settings SET setting_value = '30'
    WHERE setting_name = 'auth.session_timeout_minutes';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.session_timeout_minutes', '30', 'int',
            'Minutes before a session is force-closed by server inactivity');

-- Client-side inactivity lock
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.app_lock_minutes')
    UPDATE operations.settings SET setting_value = '15'
    WHERE setting_name = 'auth.app_lock_minutes';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.app_lock_minutes', '15', 'int',
            'Minutes of UI inactivity before client lockscreen');

-- Max failed login attempts before lockout
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.max_login_attempts')
    UPDATE operations.settings SET setting_value = '5'
    WHERE setting_name = 'auth.max_login_attempts';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.max_login_attempts', '5', 'int',
            'Maximum failed attempts before lockout escalation');

-- Password minimum length
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_min_length')
    UPDATE operations.settings SET setting_value = '8'
    WHERE setting_name = 'auth.password_min_length';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.password_min_length', '8', 'int',
            'Minimum password length enforced by policy');

-- Password expiry (days)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_expiry_days')
    UPDATE operations.settings SET setting_value = '90'
    WHERE setting_name = 'auth.password_expiry_days';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.password_expiry_days', '90', 'int',
            'Password validity duration before required rotation');

-- Password history depth
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_history_depth')
    UPDATE operations.settings SET setting_value = '3'
    WHERE setting_name = 'auth.password_history_depth';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.password_history_depth', '3', 'int',
            'How many previous passwords are blocked from reuse');

-- Global login on/off
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.enable_login')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'auth.enable_login';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('auth.enable_login', 'true', 'bool',
            'Master switch to disable all user logins');

-- Auto-login enable
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'EnableAutoLogin')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'EnableAutoLogin';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('EnableAutoLogin', 'true', 'bool',
            'Allow client-side auto-login based on stored token');

-- Legacy session expiry (kept for compatibility)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'SessionExpiryMinutes')
    UPDATE operations.settings SET setting_value = '60'
    WHERE setting_name = 'SessionExpiryMinutes';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('SessionExpiryMinutes', '60', 'int',
            'Legacy session timeout (deprecated)');

-- SSCC claim TTL (seconds) for inbound receiving double-scan window
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'inbound.sscc_claim_ttl_seconds')
    UPDATE operations.settings 
    SET setting_value = '60'
    WHERE setting_name = 'inbound.sscc_claim_ttl_seconds';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES (
        'inbound.sscc_claim_ttl_seconds',
        '60',
        'int',
        'Time-to-live (seconds) for SSCC claim during inbound receive confirmation window.'
    );

-- Putaway task TTL (seconds) for reserved putaway task lifetime
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'warehouse.putaway_task_ttl_seconds')
    UPDATE operations.settings 
    SET setting_value = '600'
    WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES (
        'warehouse.putaway_task_ttl_seconds',
        '600',
        'int',
        'Time-to-live (seconds) for putaway task reservations before they expire and become available again.'
    );

-------------------------------------------
-- LOGGING SETTINGS
-------------------------------------------

-- Master logging enable switch
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.enabled')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'logging.enabled';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('logging.enabled', 'true', 'bool',
            'Global master switch for all logging');

-- Console logging (runtime visibility)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.console.enabled')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'logging.console.enabled';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('logging.console.enabled', 'true', 'bool',
            'When enabled, logs are written to console output');

-- Minimum log level
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.min_level')
    UPDATE operations.settings SET setting_value = 'INFO'
    WHERE setting_name = 'logging.min_level';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('logging.min_level', 'INFO', 'string',
            'Minimum log level to emit (INFO/WARN/ERROR)');

-- Persist logs to database
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.db.enabled')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'logging.db.enabled';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('logging.db.enabled', 'true', 'bool',
            'When enabled, logs are persisted to database');

-- Include sensitive data in logs (never enable in prod)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.include_sensitive')
    UPDATE operations.settings SET setting_value = 'false'
    WHERE setting_name = 'logging.include_sensitive';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('logging.include_sensitive', 'false', 'bool',
            'Allows sensitive fields to be logged (DEV ONLY)');

IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'receiving.ui_mode')
    UPDATE operations.settings 
    SET setting_value = 'TRACEL',
        data_type = 'string',
        description = 'Receiving UI mode (MINIMAL / TRACE)',
        updated_at = SYSUTCDATETIME(),
        updated_by = CONVERT(int, SESSION_CONTEXT(N'user_id'))
    WHERE setting_name = 'receiving.ui_mode';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('receiving.ui_mode', 'TRACE', 'string',
            'Receiving UI mode (MINIMAL / TRACE)');
GO

-------------------------------------------
-- AUDIT SETTINGS
-------------------------------------------

-- Master audit enable switch (persistent state transition tracking)
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'audit.enabled')
    UPDATE operations.settings SET setting_value = 'true'
    WHERE setting_name = 'audit.enabled';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('audit.enabled', 'true', 'bool',
            'When enabled, critical state transitions are persisted to audit.audit_events');

-------------------------------------------
-- PW CLIENT SETTINGS
-------------------------------------------

-- Warehouse code
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'pw.warehouse_code')
    UPDATE operations.settings SET setting_value = 'MAIN'
    WHERE setting_name = 'pw.warehouse_code';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('pw.warehouse_code', 'MAIN', 'string',
            'Warehouse code used by client runtime');

-- Site code
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'pw.site_code')
    UPDATE operations.settings SET setting_value = 'RUGBY'
    WHERE setting_name = 'pw.site_code';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('pw.site_code', 'RUGBY', 'string',
            'Logical site identifier');

-- Site name
IF EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'pw.site_name')
    UPDATE operations.settings SET setting_value = 'Test Warehouse 001'
    WHERE setting_name = 'pw.site_name';
ELSE
    INSERT INTO operations.settings (setting_name, setting_value, data_type, description)
    VALUES ('pw.site_name', 'Test Warehouse 001', 'string',
            'Human-readable site name');

GO



-------------------------------------------
-- 3.2 Error messages (friendly messages)
-- Core place for human-friendly messages by error_code & module
-------------------------------------------
IF OBJECT_ID('operations.error_messages', 'U') IS NULL
BEGIN
    CREATE TABLE operations.error_messages
    (
        error_code        nvarchar(20)    NOT NULL PRIMARY KEY,   -- e.g. ERRINB01, SUCINB01
        module_code       nvarchar(20)    NOT NULL,               -- e.g. INB, INV, SYS
        severity          nvarchar(10)    NOT NULL,               -- INFO/WARN/ERROR/CRIT
        message_template  nvarchar(400)   NOT NULL,               -- Friendly text (with optional {placeholders})
        is_active         bit             NOT NULL DEFAULT (1),

        tech_messege      nvarchar(400)    NULL,                   -- optional technical message for logs
        created_at        datetime2(3)    NOT NULL CONSTRAINT DF_operations_error_messages_created_at DEFAULT (sysutcdatetime()),
        created_by        int             NULL     CONSTRAINT DF_operations_error_messages_created_by DEFAULT (CONVERT(int, SESSION_CONTEXT(N'user_id'))),
        updated_at        datetime2(3)    NULL,
        updated_by        int             NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRAUTH01')
BEGIN
    INSERT INTO operations.error_messages
        (error_code, module_code, severity, message_template, tech_messege)
    VALUES
        (N'ERRAUTH01', N'AUTH', N'ERROR',
            N'Invalid username or password.',
            N'Auth: Credentials invalid'),

        (N'ERRAUTH02', N'AUTH', N'ERROR',
            N'Your account is blocked. Please contact your system administrator.',
            N'Auth: Account inactive or blocked'),

        (N'ERRAUTH03', N'AUTH', N'ERROR', 
            N'Login is currently disabled for this site.',
            N'Auth: Global login disabled'),

        (N'ERRAUTH04', N'AUTH', N'ERROR',
            N'Your password has expired. Please reset your password.',
            N'Auth: Password expired'),

        (N'ERRAUTH05', N'AUTH', N'ERROR',
            N'You are already logged in on another session.',
            N'Auth: Concurrent session exists'),

        (N'ERRAUTH06', N'AUTH', N'ERROR',
            N'Your session is no longer active. Please log in again.',
            N'Auth: Session inactive/expired'),

        (N'ERRAUTH07', N'AUTH', N'ERROR',
            N'Too many failed attempts. Please try again later.',
            N'Auth: Lockout threshold reached'),

        (N'ERRAUTH08', N'AUTH', N'ERROR',
            N'Invalid credentials. Login temporarily locked.',
            N'Auth: Progressive lockout'),

        (N'ERRAUTH09', N'AUTH', N'WARN',
            N'Your password has expired. You must change it.',
            N'Auth: Mandatory password change'),

        (N'ERRAUTH10', N'AUTH', N'WARN',
            N'New password does not meet complexity requirements.',
            N'Auth: Complexity rules failed'),

        (N'ERRAUTH11', N'AUTH', N'WARN',
            N'New password must differ from your recent passwords.',
            N'Auth: Password reuse detected'),

        (N'SUCAUTH01', N'AUTH', N'INFO',
            N'Login successful. Welcome back!',
            N'Auth: Login OK'),

        (N'SUCAUTH02', N'AUTH', N'INFO',
            N'Session refreshed successfully.',
            N'Auth: Session heartbeat OK'),

        (N'SUCAUTH03', N'AUTH', N'INFO',
            N'Logout successful.',
            N'Auth: Session closed'),

        (N'SUCAUTH10', N'AUTH', N'INFO',
            N'Password changed successfully.',
            N'Auth: Password updated'),

        (N'ERRAUTHUSR01', N'AUTH', N'ERROR',
            N'A user with this username already exists.',
            N'Auth.CreateUser: Duplicate username'),

        (N'ERRAUTHUSR02', N'AUTH', N'ERROR',
            N'The selected role does not exist.',
            N'Auth.CreateUser: Invalid role'),

        (N'ERRAUTHUSR03', N'AUTH', N'ERROR',
            N'User creation failed due to a system error.',
            N'Auth.CreateUser: Insert failed'),

        (N'WARAUTHUSR01', N'AUTH', N'WARN',
            N'The password is valid but considered weak.',
            N'Auth.CreateUser: Weak password'),

        (N'ERRAUTHUSR04', N'AUTH', N'ERROR',
            N'A user with this email address already exists.',
            N'Auth.CreateUser: Duplicate email'),

        (N'SUCAUTHUSR01', N'AUTH', N'INFO',
            N'User account created successfully.',
            N'Auth.CreateUser: Success'),

        (N'ERRINB01', N'INB', N'ERROR',
            N'Inbound delivery not found.',
            N'Inbound.Activate: inbound_id not found'),

        (N'ERRINB02', N'INB', N'ERROR',
            N'Inbound delivery is already activated.',
            N'Inbound.Activate: already ACTIVATED'),

        (N'ERRINB03', N'INB', N'ERROR',
            N'Inbound delivery has no lines and cannot be activated.',
            N'Inbound.Activate: no inbound_lines exist'),

        (N'ERRINB04', N'INB', N'ERROR',
            N'Inbound delivery is cancelled and cannot be activated.',
            N'Inbound.Activate: inbound_status = CANCELLED'),

        (N'ERRINB05', N'INB', N'ERROR',
            N'Inbound delivery is not in a valid state for this operation.',
            N'Inbound: invalid inbound_status transition'),

        (N'SUCINB01', N'INB', N'INFO',
            N'Inbound delivery activated successfully.',
            N'Inbound.Activate: success'),

        (N'ERRINBL01', N'INB', N'ERROR',
            N'Inbound line not found.',
            N'Inbound.Line: inbound_line_id not found'),

        (N'ERRINBL03', N'INB', N'ERROR',
            N'Inbound line is already fully received.',
            N'Inbound.Line: already RECEIVED'),

        (N'SUCINBL01', N'INB', N'INFO',
            N'Inbound line received successfully.',
            N'Inbound.Line: receipt success'),

        (N'ERRINBL02', N'INB', N'ERROR',
            N'Receiving quantity must be greater than zero.',
            N'Inbound.Line: invalid quantity <= 0'),

        (N'ERRINBL04', N'INB', N'ERROR',
            N'Inbound is not in a receivable state.',
            N'Inbound.Header: not ACTIVATED or RECEIVING'),

        (N'ERRINBL05', N'INB', N'ERROR',
            N'Invalid or inactive staging bin.',
            N'Inbound.Line: staging bin invalid'),

        (N'ERRINBL99', N'INB', N'ERROR',
            N'Unexpected error while receiving inbound line.',
            N'Inbound.Line: unhandled exception'),

        (N'ERRSSCC01', N'SSCC', N'ERROR',
            N'SSCC not recognised. Please verify the barcode and try again.',
            N'SSCC.Validate: SSCC not found'),

        (N'ERRSSCC02', N'SSCC', N'ERROR',
            N'SSCC already exists and is currently active.',
            N'SSCC.Validate: duplicate active SSCC'),

        (N'ERRSSCC03', N'SSCC', N'ERROR',
            N'SSCC is already linked to another inbound delivery.',
            N'SSCC.Validate: linked to different inbound'),

        (N'ERRSSCC04', N'SSCC', N'ERROR',
            N'SSCC cannot be reused while active. Complete or cancel the previous transaction first.',
            N'SSCC.Validate: reuse blocked - active record exists'),

        (N'ERRSSCC05', N'SSCC', N'WARN',
            N'SSCC reuse is allowed only for returned units. Please confirm return process.',
            N'SSCC.Validate: reuse requires return context'),

        (N'ERRQTY01', N'INB', N'ERROR',
            N'Received quantity exceeds expected quantity for this inbound line.',
            N'Inbound.Line: quantity > expected'),

        (N'ERRQTY03', N'INB', N'ERROR',
            N'Unit of measure mismatch. Please use the expected UOM for this material.',
            N'Inbound.Line: UOM mismatch'),

        (N'ERRQTY04', N'INB', N'ERROR',
            N'Full handling unit quantity required for this SSCC.',
            N'Inbound.Line: partial HU not allowed'),

        (N'ERRMAT01', N'INB', N'ERROR',
            N'Material could not be resolved from the scanned GTIN.',
            N'Inbound.Line: GTIN resolution failed'),

        (N'ERRMAT02', N'INB', N'ERROR',
            N'Material is not expected on this inbound delivery.',
            N'Inbound.Line: material not on inbound'),

        (N'ERRMAT03', N'INB', N'ERROR',
            N'Multiple materials match this GTIN. Manual selection required.',
            N'Inbound.Line: ambiguous GTIN mapping'),

        (N'ERRMAT04', N'INB', N'ERROR',
            N'Material master data incomplete. Please contact master data team.',
            N'Inbound.Line: material master incomplete'),

        (N'ERRPROC01', N'CORE', N'ERROR',
            N'Operation not allowed in current document status.',
            N'Process.Validate: invalid status transition'),

        (N'ERRPROC02', N'CORE', N'ERROR',
            N'Transaction validation failed. Please review the scanned data.',
            N'Process.Validate: business rule failure'),

        (N'ERRPROC03', N'CORE', N'ERROR',
            N'Another user is currently processing this document.',
            N'Process.Locking: record locked'),

        (N'ERRPROC04', N'CORE', N'INFO',
            N'Process cancelled. No changes were saved.',
            N'Process: user cancelled transaction'),

        (N'ERRSSCC06', N'SSCC', N'ERROR',
            N'SSCC has already been received for this inbound delivery.',
            N'SSCC.Validate: already received on same inbound'),

        (N'ERRINB06', N'INB', N'ERROR',
            N'Inbound delivery is already fully received and closed.',
            N'Inbound.Receive: attempt after CLOSED'),

        (N'SUCSSCC01', N'SSCC', N'INFO',
            N'SSCC validated successfully. Please scan again to confirm receipt.',
            N'SSCC.Validate: claim acquired'),

        (N'ERRSSCC07', N'SSCC', N'ERROR',
             N'SSCC is currently being processed by another user.',
             N'SSCC.Receive: active claim held by different session'),

        (N'ERRSSCC08', N'SSCC', N'ERROR',
             N'SSCC confirmation window expired. Please rescan to validate again.',
             N'SSCC.Receive: claim expired'),

        (N'ERRSSCC09', N'SSCC', N'ERROR',
             N'SSCC confirmation token invalid. Please rescan to validate again.',
             N'SSCC.Receive: claim token mismatch'),

        (N'ERRSSCC99', N'SSCC', N'ERROR',
             N'SSCC validation failed. Please rescan. If it persists, contact a supervisor.',
             N'SSCC.Preview: unexpected system error'),

        (N'ERRINBHYB01', N'INBOUND', N'ERROR',
            N'Inbound structure invalid. Please contact warehouse supervisor',
            N'Inbound.Activate: hybrid SSCC + manual structure detected'),

        (N'ERRINBMODE01', N'INBOUND', N'ERROR',
            N'Inbound mode already determined and cannot be changed.',
            N'Inbound.Activate: attempted mode overwrite'),

        (N'ERRINBSTRUCT01', N'INBOUND', N'ERROR',
             N'Inbound structure cannot be modified after activation.',
             N'Inbound.Structure: modification attempted after activation'),

        (N'ERRINBSTRUCT02', N'INBOUND', N'ERROR',
             N'Expected handling units cannot be modified after activation.',
             N'Inbound.Structure: expected units modification attempted after activation'),

        (N'ERRTASK01', N'TASK', N'ERROR',
             N'Inventory unit not recognised.',
             N'Task.Create: inventory unit not found'),

        (N'ERRTASK02', N'TASK', N'ERROR',
             N'Inventory unit not eligible for putaway.',
             N'Task.Create: inventory unit state invalid for putaway'),

        (N'ERRTASK03', N'TASK', N'ERROR',
             N'Inventory unit is not located in a staging bin.',
             N'Task.Create: staging placement not found'),

        (N'ERRTASK04', N'TASK', N'ERROR',
             N'No suitable storage location found. Please contact a supervisor.',
             N'Task.Create: destination bin suggestion failed'),

        (N'ERRTASK05', N'TASK', N'ERROR',
             N'A warehouse task already exists for this unit.',
             N'Task.Create: duplicate active task detected'),

        (N'ERRTASK06', N'TASK', N'ERROR',
             N'Task claim is no longer valid. Please rescan.',
             N'Task.Claim: claim expired or invalid'),

        (N'ERRTASK07', N'TASK', N'ERROR',
             N'Task cannot be confirmed in its current state.',
             N'Task.Confirm: invalid state transition'),

        (N'ERRTASK99', N'TASK', N'ERROR',
             N'Warehouse task operation failed. Please retry. If the problem persists, contact a supervisor.',
             N'Task.Engine: unexpected system error'),

        (N'SUCTASK02', N'TASK', N'SUCCESS',
            N'Putaway completed successfully.',
            N'Task.Confirm: putaway confirmed')
;

END;
GO

-------------------------------------------
-- 3.3 Error log
-- Captures errors with context for troubleshooting
-------------------------------------------
IF OBJECT_ID('operations.error_log', 'U') IS NULL
BEGIN
    CREATE TABLE operations.error_log
    (
        id               bigint           IDENTITY(1,1) PRIMARY KEY,
        error_code       nvarchar(20)     NULL,          -- may be null for unknown errors
        module_code      nvarchar(20)     NULL,
        message          nvarchar(400)    NULL,
        details          nvarchar(max)    NULL,          -- stack, inner exceptions, etc.
        context_json     nvarchar(max)    NULL,          -- optional JSON context payload
        correlation_id   uniqueidentifier NOT NULL CONSTRAINT DF_operations_error_log_corrid DEFAULT (NEWSEQUENTIALID()),
        occurred_at      datetime2(3)     NOT NULL CONSTRAINT DF_operations_error_log_occurred_at DEFAULT (sysutcdatetime()),
        user_id          int              NULL           -- from SESSION_CONTEXT('user_id') if available
    );
END;
GO

-------------------------------------------
-- 3.4 Helper: set session user
-- Use from the app before running business procs:
--   EXEC operations.usp_set_session_user @user_id = 1;
-------------------------------------------
IF OBJECT_ID('operations.usp_set_session_user', 'P') IS NULL
    EXEC('CREATE PROCEDURE operations.usp_set_session_user AS RETURN 0;');
GO

ALTER PROCEDURE operations.usp_set_session_user
    @user_id int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sys.sp_set_session_context @key = N'user_id', @value = @user_id;
END;
GO

-------------------------------------------
-- 3.5 Helper: get session user id
-------------------------------------------
IF OBJECT_ID('operations.fn_get_session_user_id', 'FN') IS NULL
    EXEC('CREATE FUNCTION operations.fn_get_session_user_id() RETURNS int AS BEGIN RETURN NULL; END;');
GO

ALTER FUNCTION operations.fn_get_session_user_id()
RETURNS int
AS
BEGIN
    DECLARE @uid_sql_variant sql_variant;
    DECLARE @uid int;

    SELECT @uid_sql_variant = SESSION_CONTEXT(N'user_id');
    IF @uid_sql_variant IS NOT NULL
    BEGIN
        SET @uid = TRY_CONVERT(int, @uid_sql_variant);
    END

    RETURN @uid;
END;
GO

-------------------------------------------
-- 3.6 Helper: get friendly message by error_code
-- Returns a human-friendly message or the error_code if not found
-------------------------------------------
IF OBJECT_ID('operations.fn_get_friendly_message', 'FN') IS NULL
    EXEC('CREATE FUNCTION operations.fn_get_friendly_message(@error_code nvarchar(20)) RETURNS nvarchar(400) AS BEGIN RETURN @error_code; END;');
GO

ALTER FUNCTION operations.fn_get_friendly_message
(
    @error_code nvarchar(20)
)
RETURNS nvarchar(400)
AS
BEGIN
    DECLARE @msg nvarchar(400);

    SELECT @msg = em.message_template
    FROM operations.error_messages em
    WHERE em.error_code = @error_code
      AND em.is_active = 1;
    RETURN ISNULL(@msg, @error_code);
END;
GO

-------------------------------------------
-- 3.7 Helper: simple error logging proc
-------------------------------------------
IF OBJECT_ID('operations.usp_log_error', 'P') IS NULL
    EXEC('CREATE PROCEDURE operations.usp_log_error AS RETURN 0;');
GO

ALTER PROCEDURE operations.usp_log_error
(
    @error_code     nvarchar(20) = NULL,
    @module_code    nvarchar(20) = NULL,
    @message        nvarchar(400) = NULL,
    @details        nvarchar(max) = NULL,
    @context_json   nvarchar(max) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @user_id int = operations.fn_get_session_user_id();

    INSERT INTO operations.error_log
        (error_code, module_code, message, details, context_json, user_id)
    VALUES
        (@error_code, @module_code, @message, @details, @context_json, @user_id);
END;
GO


/* ============================================================
   AUTHENTICATION LAYER v1.0
   Schemas, tables, settings, helper procs, auth SPs
   ============================================================*/

---------------------------------------------------------------
-- 0. Ensure db
---------------------------------------------------------------
USE [PW_Core_DEV];
GO

/* ============================================================
   1. TABLES
   ============================================================*/

---------------------------------------------------------------
-- 1.1 Users
---------------------------------------------------------------
IF OBJECT_ID('auth.users', 'U') IS NULL
BEGIN
    CREATE TABLE auth.users
    (
        id                   INT IDENTITY(1,1) PRIMARY KEY,
        username             NVARCHAR(100)  NOT NULL UNIQUE,
        display_name         NVARCHAR(200)  NOT NULL,
        email                NVARCHAR(255)  NULL UNIQUE,
        is_active            BIT            NOT NULL DEFAULT (1),

        password_hash        VARBINARY(512) NULL,
        salt                 VARBINARY(256) NOT NULL,
        password_last_changed DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
        password_expires_at   DATETIME2(0)  NOT NULL DEFAULT '9999-12-31T00:00:00',
        must_change_password  BIT           NOT NULL DEFAULT 0,

        failed_attempts      INT            NOT NULL DEFAULT 0,
        lockout_until        DATETIME2(3)   NULL,

        is_2fa_enabled       BIT            NOT NULL DEFAULT 0,
        twofa_secret         VARBINARY(512) NULL,

        created_at           DATETIME2(3)   NOT NULL CONSTRAINT DF_auth_users_created_at DEFAULT (SYSUTCDATETIME()),
        created_by           INT            NULL     CONSTRAINT DF_auth_users_created_by DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'user_id'))),
        updated_at           DATETIME2(3)   NULL,
        updated_by           INT            NULL
    );
END;
GO

---------------------------------------------------------------
-- 1.2 Roles
---------------------------------------------------------------
IF OBJECT_ID('auth.roles', 'U') IS NULL
BEGIN
    CREATE TABLE auth.roles
    (
        id          INT IDENTITY(1,1) PRIMARY KEY,
        role_name   NVARCHAR(100) NOT NULL UNIQUE,
        description NVARCHAR(255) NULL,
        is_active   BIT DEFAULT 1,
        created_by  INT,
        created_at  DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_by  INT FOREIGN KEY REFERENCES auth.users(id),
        updated_at  DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

---------------------------------------------------------------
-- 1.3 User → Roles
---------------------------------------------------------------
IF OBJECT_ID('auth.user_roles', 'U') IS NULL
BEGIN
    CREATE TABLE auth.user_roles
    (
        user_id INT NOT NULL,
        role_id INT NOT NULL,
        PRIMARY KEY (user_id, role_id),

        CONSTRAINT FK_user_roles_user FOREIGN KEY (user_id)
            REFERENCES auth.users(id),

        CONSTRAINT FK_user_roles_role FOREIGN KEY (role_id)
            REFERENCES auth.roles(id)
    );
END;
GO

---------------------------------------------------------------
-- 1.4 Get Roles
---------------------------------------------------------------
CREATE OR ALTER PROCEDURE auth.usp_roles_get
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        role_name   AS RoleName,
        description AS Description
    FROM auth.roles
    WHERE is_active = 1
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
        correlation_id VARCHAR(32)   NULL,
        created_at  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME()
    );

    ALTER TABLE auth.user_sessions
        ADD CONSTRAINT FK_user_sessions_user
        FOREIGN KEY (user_id) REFERENCES auth.users(id);
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
        correlation_id VARCHAR(32)  NULL,
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

    DECLARE @timeout_minutes INT =
    (
        SELECT TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'auth.session_timeout_minutes'
    );

    IF @timeout_minutes IS NULL OR @timeout_minutes <= 0
        SET @timeout_minutes = 30;

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
    WHERE s.is_active = 1
      AND (
            s.last_seen IS NULL
         OR DATEDIFF(MINUTE, s.last_seen, @now) >= @timeout_minutes
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
    -- Deactivate expired sessions
    ------------------------------------------------------------------
    UPDATE s
    SET is_active = 0
    FROM auth.user_sessions s
    JOIN #Expired e ON s.session_id = e.session_id;
END;
GO


/* ============================================================
   6. LOGIN
   ============================================================*/

CREATE OR ALTER PROCEDURE auth.usp_login
(
    @username           NVARCHAR(100),
    @password_plain     NVARCHAR(200) = NULL,
    @client_info        NVARCHAR(200) = NULL,
    @ip_address         NVARCHAR(50)  = NULL,
    @client_app         NVARCHAR(50)  = NULL,
    @os_info            NVARCHAR(200) = NULL,
    @force_login        BIT           = 0,
    @correlation_id     VARCHAR(32)   = NULL,

    -- OUTPUTS
    @result_code        NVARCHAR(20)  OUTPUT,
    @friendly_message   NVARCHAR(400) OUTPUT,
    @user_id_out        INT           OUTPUT,
    @session_id_out     UNIQUEIDENTIFIER OUTPUT,
    @display_name_out   NVARCHAR(200) OUTPUT,
    @last_login_time    DATETIME2(3)  OUTPUT,
    @failed_attempts    INT           OUTPUT,
    @lockout_until_out  DATETIME2(3)  OUTPUT
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
            @display_name = u.display_name
        FROM auth.users u
        WHERE u.username = @username;

        IF @user_id IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH01';
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
        -- Password validation (MANDATORY)
        --------------------------------------------------------
        DECLARE @calc_hash VARBINARY(512) =
            HASHBYTES('SHA2_512',
                CONVERT(VARBINARY(512), @password_plain) + @salt);

        IF @calc_hash IS NULL OR @calc_hash <> @password_hash
        BEGIN
            SET @failed += 1;

            DECLARE @lock_minutes INT = NULL;
            DECLARE @terminal_lock DATETIME2(3) = '9999-12-31 23:59:59.997';

            -- Progressive lockout policy
            IF      @failed = 3 SET @lock_minutes = 1;
            ELSE IF @failed = 4 SET @lock_minutes = 2;
            ELSE IF @failed = 5 SET @lock_minutes = 5;
            ELSE IF @failed = 6 SET @lock_minutes = 10;
            ELSE IF @failed = 7 SET @lock_minutes = 20;
            ELSE IF @failed = 8 SET @lock_minutes = 30;
            ELSE IF @failed = 9 SET @lock_minutes = 60;
            ELSE IF @failed >= 10
            BEGIN
                -- Terminal lockout (admin / password reset only)
                UPDATE auth.users
                SET
                    failed_attempts = @failed,
                    lockout_until = @terminal_lock
                WHERE id = @user_id;

                SET @result_code = 'ERRAUTH08'; -- e.g. "Account locked"
                SET @friendly_message =
                    'Account locked due to repeated failed login attempts. Contact an administrator.';

                SET @failed_attempts = @failed;
                SET @lockout_until_out = @terminal_lock;

                GOTO LogAndExit;
            END;

            -- Time-based lockout
            UPDATE auth.users
            SET
                failed_attempts = @failed,
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
        -- Must change / expiry AFTER validation
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
        -- Existing active session (same app)
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

LogAndExit:
        INSERT INTO auth.login_attempts
        (username, attempt_time, result_code, success,
         session_id, correlation_id, ip_address, client_info, client_app, os_info)
        VALUES
        (@username, @now, @result_code,
         CASE WHEN @result_code LIKE 'SUC%' THEN 1 ELSE 0 END,
         @session_id_out, @correlation_id,
         @ip_address, @client_info, @client_app, @os_info);

    END TRY
    BEGIN CATCH
    DECLARE @err NVARCHAR(4000);
    DECLARE @ctx NVARCHAR(MAX);

    SET @err = ERROR_MESSAGE();

    SET @ctx =
        CONCAT(
            '{',
            '"username":"',     ISNULL(@username, ''),     '",',
            '"client_app":"',   ISNULL(@client_app, ''),   '",',
            '"client_info":"',  ISNULL(@client_info, ''),  '",',
            '"ip_address":"',   ISNULL(@ip_address, ''),   '"',
            '}'
        );

    EXEC operations.usp_log_error
        @error_code     = 'ERRAUTH99',
        @module_code    = 'AUTH',
        @message        = 'Unhandled authentication error in auth.usp_login.',
        @details        = @err,
        @context_json   = @ctx,
        @correlation_id = @correlation_id;

    SET @result_code      = 'ERRAUTH99';
    SET @friendly_message = operations.fn_get_friendly_message('ERRAUTH99');
END CATCH;
END;
GO

/* ============================================================
   7. SESSION TOUCH
   ============================================================*/
CREATE OR ALTER PROCEDURE auth.usp_session_touch
(
    @session_id    UNIQUEIDENTIFIER,
    @result_code   NVARCHAR(20)  OUTPUT,
    @friendly_msg  NVARCHAR(400) OUTPUT,
    @is_alive      BIT           OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @is_alive = 0;
    SET @result_code = NULL;
    SET @friendly_msg = NULL;

    DECLARE
        @user_id        INT,
        @is_active      BIT,
        @last_seen      DATETIME2(3),
        @now            DATETIME2(3) = SYSUTCDATETIME(),
        @timeout_minutes INT;

    SELECT
        @user_id   = s.user_id,
        @is_active = s.is_active,
        @last_seen = s.last_seen
    FROM auth.user_sessions s
    WHERE s.session_id = @session_id;

    IF @user_id IS NULL
    BEGIN
        SET @result_code  = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    IF @is_active = 0
    BEGIN
        SET @result_code  = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    SELECT @timeout_minutes =
        TRY_CONVERT(INT, setting_value)
    FROM operations.settings
    WHERE setting_name = 'auth.session_timeout_minutes';

    IF @timeout_minutes IS NULL OR @timeout_minutes <= 0
        SET @timeout_minutes = 30;

    IF DATEDIFF(MINUTE, @last_seen, @now) >= @timeout_minutes
    BEGIN
        UPDATE auth.user_sessions
        SET is_active = 0
        WHERE session_id = @session_id;

        DECLARE @client_info_db NVARCHAR(200);

        SELECT @client_info_db = client_info
        FROM auth.user_sessions
        WHERE session_id = @session_id;

        DECLARE @SystemUserId INT =
        (
            SELECT TOP (1) id 
            FROM auth.users 
            WHERE username = 'system'
        );

        INSERT INTO auth.session_events
        (session_id, user_id, event_type, source_app, source_client, source_ip, details, created_by)
        VALUES
        (
            @session_id,
            @user_id,
            'LOGOUT_TIMEOUT',
            'CLI',
            @client_info_db,
            NULL,
            CONCAT('{"last_seen":"', CONVERT(varchar(30), @last_seen, 126), '"}'),
            @SystemUserId
        );

        SET @result_code  = 'ERRAUTH06';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    UPDATE auth.user_sessions
    SET 
        last_seen = @now,
        is_active = 1
    WHERE session_id = @session_id;

    SET @result_code  = 'SUCAUTH02';
    SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
    SET @is_alive     = 1;
END;
GO


/* ============================================================
   8. LOGOUT
   ============================================================*/

CREATE OR ALTER PROCEDURE auth.usp_logout
(
    @session_id      UNIQUEIDENTIFIER,
    @source_app      NVARCHAR(50),
    @source_client   NVARCHAR(200),
    @source_ip       NVARCHAR(50) = NULL,
    @correlation_id  VARCHAR(32) = NULL,
    @result_code     NVARCHAR(20) OUTPUT,
    @friendly_msg    NVARCHAR(400) OUTPUT,
    @success         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @user_id INT;

    SELECT @user_id = user_id
    FROM auth.user_sessions
    WHERE session_id = @session_id
      AND is_active = 1;

    -- Already logged out → idempotent success
    IF @user_id IS NULL
    BEGIN
        SET @result_code  = 'SUCAUTH03';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
        SET @success = 1;
        RETURN;
    END;

    UPDATE auth.user_sessions
    SET
        is_active = 0,
        last_seen = SYSUTCDATETIME()
    WHERE session_id = @session_id;

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
        'LOGOUT_USER',
        @source_app,
        @source_client,
        @source_ip,
        CONCAT('{"correlation_id":"', @correlation_id, '"}'),
        @user_id
    );

    SET @result_code  = 'SUCAUTH03';
    SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
    SET @success = 1;
END;
GO

/* ============================================================
   9. CHANGE PASSWORD (username-based)
   ============================================================*/

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
   10. CREATE USER (provisioning)
   ============================================================*/

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
        @now         DATETIME2(3) = SYSUTCDATETIME(),
        @expiry_days INT,
        @expires_at  DATETIME2(0),
        @role_id     INT;

    -- --------------------------------------------------
    -- Username uniqueness
    -- --------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM auth.users
        WHERE username = @username
    )
    BEGIN
        SELECT
            @result_code  = em.error_code,
            @friendly_msg = em.message_template
        FROM operations.error_messages em
        WHERE em.error_code = N'ERRAUTHUSR01'
          AND em.is_active = 1;

        RETURN;
    END;

    -- --------------------------------------------------
    -- Email uniqueness
    -- --------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM auth.users
        WHERE email = @email
    )
    BEGIN
        SELECT
            @result_code  = em.error_code,
            @friendly_msg = em.message_template
        FROM operations.error_messages em
        WHERE em.error_code = N'ERRAUTHUSR04'
          AND em.is_active = 1;

        RETURN;
    END;

    -- --------------------------------------------------
    -- Role validation
    -- --------------------------------------------------
    SELECT @role_id = id
    FROM auth.roles
    WHERE role_name = @role_name;

    IF @role_id IS NULL
    BEGIN
        SELECT
            @result_code  = em.error_code,
            @friendly_msg = em.message_template
        FROM operations.error_messages em
        WHERE em.error_code = N'ERRAUTHUSR02'
          AND em.is_active = 1;

        RETURN;
    END;

    -- --------------------------------------------------
    -- Password hashing
    -- --------------------------------------------------
    EXEC auth.sp_hash_password
         @plain = @password,
         @salt  = @salt OUTPUT,
         @hash  = @hash OUTPUT;

    -- --------------------------------------------------
    -- Password expiry
    -- --------------------------------------------------
    SELECT @expiry_days =
        TRY_CONVERT(INT, setting_value)
    FROM operations.settings
    WHERE setting_name = 'auth.password_expiry_days';

    IF @expiry_days IS NULL OR @expiry_days <= 0
        SET @expiry_days = 90;

    SET @expires_at = DATEADD(DAY, @expiry_days, @now);

    -- --------------------------------------------------
    -- User insert
    -- --------------------------------------------------
    INSERT INTO auth.users
        (username, display_name, email,
         password_hash, salt,
         password_last_changed, password_expires_at,
         must_change_password,
         is_active,
         created_at, created_by)
    VALUES
        (@username, @display_name, @email,
         @hash, @salt,
         @now, @expires_at,
         1,        -- must change password on first login
         1,        -- active by default
         @now, @actor);

    DECLARE @new_user_id INT = SCOPE_IDENTITY();

    -- --------------------------------------------------
    -- Role assignment
    -- --------------------------------------------------
    INSERT INTO auth.user_roles (user_id, role_id)
    VALUES (@new_user_id, @role_id);

    -- --------------------------------------------------
    -- Success
    -- --------------------------------------------------
    SELECT
        @result_code  = em.error_code,
        @friendly_msg = em.message_template
    FROM operations.error_messages em
    WHERE em.error_code = N'SUCAUTHUSR01'
      AND em.is_active = 1;
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

CREATE OR ALTER PROCEDURE auth.usp_add_role
    @RoleName    NVARCHAR(100),
    @Description NVARCHAR(200) = NULL,
    @CreatedBy   INT,
    @NewRoleId   INT OUTPUT -- Returns the new ID to the caller
AS
BEGIN
    SET NOCOUNT ON;

    -- Basic Validation
    IF EXISTS (SELECT 1 FROM auth.roles WHERE role_name = @RoleName)
    BEGIN
        -- Option A: Throw an error
        THROW 51000, 'The role name already exists.', 1;
        
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO auth.roles (role_name, description, is_active, created_by)
        VALUES (@RoleName, @Description, DEFAULT, @CreatedBy);

        -- Capture the new Identity ID
        SET @NewRoleId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Re-throw the error
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @OutputId INT;

EXEC auth.usp_add_role 
    @RoleName = 'system', 
    @Description = 'Under the hood functions and seed data', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;
GO

IF OBJECT_ID('auth.usp_update_role_by_name', 'P') IS NOT NULL
    DROP PROCEDURE auth.usp_update_role_by_name;
GO

---------------------------------------------------------------
-- 3. Ensure SYSTEM user is assigned to SYSTEM role
---------------------------------------------------------------
DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SystemRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'system');

IF @SystemUserId IS NULL OR @SystemRoleId IS NULL
BEGIN
    PRINT 'ERROR: System user or role missing – cannot assign.';
END
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM auth.user_roles
        WHERE user_id = @SystemUserId
          AND role_id = @SystemRoleId
    )
    BEGIN
        INSERT INTO auth.user_roles (user_id, role_id)
        VALUES (@SystemUserId, @SystemRoleId);

        PRINT 'System user assigned to system role.';
    END
    ELSE
    BEGIN
        PRINT 'System user already assigned to system role.';
    END
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE auth.usp_update_role_by_name
    @RoleName       NVARCHAR(100),        -- The specific role to find
    @NewDescription NVARCHAR(200) = NULL, -- Pass NULL to keep existing description
    @NewRoleName    NVARCHAR(100) = NULL, -- Pass NULL to keep existing name
    @UpdatedBy      INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Identity Check: Ensure the role exists
    DECLARE @RoleId INT = (SELECT id FROM auth.roles WHERE role_name = @RoleName);
    
    IF @RoleId IS NULL
    BEGIN
        THROW 51000, 'The role specified for update does not exist.', 1;
    END

    -- 2. Collision Check: If renaming, ensure the NEW name isn't taken
    IF @NewRoleName IS NOT NULL AND @NewRoleName <> @RoleName
    BEGIN
        IF EXISTS (SELECT 1 FROM auth.roles WHERE role_name = @NewRoleName)
        BEGIN
             THROW 51000, 'The new role name is already taken by another role.', 1;
        END
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE auth.roles
        SET 
            -- If @NewRoleName is NULL, keep the old name
            role_name   = COALESCE(@NewRoleName, role_name),
            
            -- If @NewDescription is NULL, keep the old description
            description = COALESCE(@NewDescription, description),
            
            -- Audit fields
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @UpdatedBy
        WHERE 
            id = @RoleId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

IF OBJECT_ID('auth.fn_is_session_expired', 'FN') IS NULL
    EXEC('CREATE FUNCTION auth.fn_is_session_expired() RETURNS bit AS BEGIN RETURN 0; END');
GO

ALTER FUNCTION auth.fn_is_session_expired
(
    @last_seen       datetime2(3),
    @timeout_minutes int
)
RETURNS bit
AS
BEGIN
    IF @last_seen IS NULL OR @timeout_minutes IS NULL OR @timeout_minutes <= 0
        RETURN 1;

    IF DATEDIFF(MINUTE, @last_seen, SYSUTCDATETIME()) >= @timeout_minutes
        RETURN 1;

    RETURN 0;
END;
GO

CREATE OR ALTER VIEW auth.v_active_sessions
AS
SELECT
    s.session_id,
    u.username,
    s.client_app,
    s.client_info,
    s.last_seen,
    s.is_active
FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id
WHERE s.is_active = 1;
GO

CREATE OR ALTER VIEW auth.vw_session_forensic
AS
SELECT
    s.session_id,
    s.is_active,
    s.login_time,
    s.last_seen,

    u.id            AS user_id,
    u.username,
    u.display_name,

    s.client_app,
    s.client_info,

    la.ip_address,
    la.os_info,
    la.correlation_id

FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id

OUTER APPLY
(
    SELECT TOP (1)
        a.ip_address,
        a.os_info,
        a.correlation_id
    FROM auth.login_attempts a
    WHERE a.session_id = s.session_id
      AND a.success = 1
    ORDER BY a.attempt_time DESC
) la;
GO

CREATE OR ALTER PROCEDURE auth.usp_get_session_details
(
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM auth.vw_session_forensic
    WHERE session_id = @session_id;
END;
GO

USE msdb;
GO

--------------------------------------------------------------------------------
-- 1. Remove existing job if it exists (idempotent)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Session Cleanup Job')
BEGIN
EXEC msdb.dbo.sp_delete_job
@job_name = N'DEV PW Session Cleanup Job',
@delete_unused_schedule = 1;

DECLARE @schedule_id INT;

WHILE 1 = 1
BEGIN
    SELECT TOP (1) @schedule_id = schedule_id
    FROM msdb.dbo.sysschedules
    WHERE name = N'DEV PW Cleanup – Every 10 Minutes';

    IF @schedule_id IS NULL BREAK;

    EXEC msdb.dbo.sp_delete_schedule
        @schedule_id = @schedule_id;

    PRINT 'Deleted schedule_id = ' + CAST(@schedule_id AS NVARCHAR(20));

    SET @schedule_id = NULL;
END;
END
GO

--------------------------------------------------------------------------------
-- 2. Create Job
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name = N'DEV PW Session Cleanup Job',
    @enabled = 1,
    @description = N'Automatically clears timed-out PW_Core_DEV sessions.',
    @start_step_id = 1,
    @job_id = @job_id OUTPUT;

PRINT 'Job created. ID = ' + CONVERT(NVARCHAR(50), @job_id);
GO

--------------------------------------------------------------------------------
-- 3. Add Job Step
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Session Cleanup Job'
);

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @job_id,
    @step_id = 1,
    @step_name = N'Run Session Cleanup',
    @subsystem = N'TSQL',
    @command = N'EXEC PW_Core_DEV.auth.usp_session_cleanup;',
    @database_name = N'PW_Core_DEV',
    @on_success_action = 1,
    @on_fail_action = 2;
GO

--------------------------------------------------------------------------------
-- 4. Create Schedule (Every 10 minutes)
--------------------------------------------------------------------------------
DECLARE @schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'PW Cleanup – Every 10 Minutes',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 10,
    @active_start_time = 000000,
    @schedule_id = @schedule_id OUTPUT;

PRINT 'Schedule created. ID = ' + CONVERT(NVARCHAR(20), @schedule_id);

--------------------------------------------------------------------------------
-- 5. Attach schedule to job
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id 
    FROM msdb.dbo.sysjobs 
    WHERE name = N'DEV PW Session Cleanup Job'
);

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @job_id,
    @schedule_id = @schedule_id;

--------------------------------------------------------------------------------
-- 6. Enable job for this server
--------------------------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'DEV PW Session Cleanup Job',
    @server_name = @@SERVERNAME;

PRINT 'DEV PW Session Cleanup Job successfully installed + enabled.';
GO

USE PW_Core_DEV;
GO
--------------------------------------------------------------------------------
-- User lookup view
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Protect the system user
--------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION auth.fn_is_system_user
(
    @user_id INT
)
RETURNS BIT
AS
BEGIN
    DECLARE @is_system BIT = 0;

    SELECT @is_system = 1
    FROM auth.users
    WHERE id = @user_id
      AND username = 'system';

    RETURN @is_system;
END;
GO

CREATE OR ALTER VIEW auth.v_users_admin
AS

SELECT
    u.id,
    u.username,
    u.display_name,

    -- Role (defensive)
    COALESCE(r.role_name, '[MISSING ROLE]') AS role_name,

    u.email,

    -- ONLINE if at least one active session exists
    CAST(
        CASE
            WHEN MAX(CASE WHEN s.is_active = 1 THEN 1 ELSE 0 END) = 1
                THEN 1
            ELSE 0
        END
    AS bit) AS is_online,

    -- Most recent last_seen across ALL sessions
    MAX(s.last_seen) AS last_last_seen,

    u.is_active,
    u.must_change_password,
    u.failed_attempts,
    u.lockout_until,
    u.password_expires_at,

    u.created_at,
    u.created_by,
    u.updated_at,
    u.updated_by

FROM auth.users u

-- users may exist without a role (temporarily or due to config drift)
LEFT JOIN auth.user_roles ur
    ON u.id = ur.user_id

LEFT JOIN auth.roles r
    ON ur.role_id = r.id

LEFT JOIN auth.user_sessions s
    ON u.id = s.user_id

WHERE auth.fn_is_system_user(u.id) = 0

GROUP BY
    u.id,
    u.username,
    u.display_name,
    COALESCE(r.role_name, '[MISSING ROLE]'),
    u.email,
    u.is_active,
    u.must_change_password,
    u.failed_attempts,
    u.lockout_until,
    u.password_expires_at,
    u.created_at,
    u.created_by,
    u.updated_at,
    u.updated_by;
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

    -- -----------------------------------------
    -- Validate target user
    -- -----------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users
        WHERE id = @user_id
    )
    BEGIN
        SET @result_code  = 'ERRUSR01';
        SET @friendly_msg = 'User not found.';
        RETURN;
    END

    -- -----------------------------------------
    -- Perform update
    -- -----------------------------------------
    UPDATE auth.users
    SET
        is_active   = @is_active,
        updated_at = SYSUTCDATETIME(),
        updated_by = TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT)
    WHERE id = @user_id;

    -- -----------------------------------------
    -- Success
    -- -----------------------------------------
    SET @result_code = 'SUCUSR01';

    SET @friendly_msg =
        CASE
            WHEN @is_active = 1 THEN 'User has been enabled.'
            ELSE 'User has been disabled.'
        END;
END;
GO


CREATE TABLE audit.user_changes
(
    audit_id        BIGINT IDENTITY PRIMARY KEY,
    user_id         INT NOT NULL,
    action          NVARCHAR(50) NOT NULL,

    old_is_active   BIT NULL,
    new_is_active   BIT NULL,

    details         NVARCHAR(1000),

    changed_at      DATETIME2 NOT NULL,
    changed_by      INT NULL,

    session_id      UNIQUEIDENTIFIER NULL
);
GO

CREATE OR ALTER TRIGGER auth.tr_users_audit
ON auth.users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        old_is_active,
        new_is_active,
        changed_at,
        changed_by,
        session_id
    )
    SELECT
        i.id,
        'SET_ACTIVE',
        d.is_active,
        i.is_active,
        SYSUTCDATETIME(),
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.is_active, -1) <> ISNULL(i.is_active, -1);
END;
GO

CREATE OR ALTER PROCEDURE auth.usp_admin_reset_password
(
    @target_user_id    INT,
    @new_password      NVARCHAR(200),

    @result_code       NVARCHAR(20)  OUTPUT,
    @friendly_message  NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @username   NVARCHAR(100),
        @now        DATETIME2(3) = SYSUTCDATETIME(),
        @actor_id   INT =
            TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        @session_id UNIQUEIDENTIFIER =
            TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER);

    --------------------------------------------------------
    -- 0. Resolve target user
    --------------------------------------------------------
    SELECT @username = u.username
    FROM auth.users u
    WHERE u.id = @target_user_id;

    IF @username IS NULL
    BEGIN
        SET @result_code      = 'ERRAUTH02';
        SET @friendly_message = operations.fn_get_friendly_message(@result_code);
        RETURN;
    END;

    --------------------------------------------------------
    -- 1. Reuse standard password rules + unlock behaviour
    --------------------------------------------------------
    EXEC auth.usp_change_password
        @username         = @username,
        @new_password     = @new_password,
        @result_code      = @result_code OUTPUT,
        @friendly_message = @friendly_message OUTPUT;

    --------------------------------------------------------
    -- 2. Admin override: force password change on next login
    --    + explicit audit trail
    --------------------------------------------------------
    IF @result_code LIKE 'SUC%'
    BEGIN
        UPDATE auth.users
        SET must_change_password = 1
        WHERE id = @target_user_id;

        INSERT INTO audit.user_changes
        (
            user_id,
            action,
            details,
            changed_at,
            changed_by,
            session_id
        )
        VALUES
        (
            @target_user_id,
            'ADMIN_PASSWORD_RESET',
            'Password reset by administrator; must_change_password enforced',
            SYSUTCDATETIME(),
            TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
            TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)
        );
    END;
END;
GO

CREATE OR ALTER TRIGGER auth.tr_users_security_audit
ON auth.users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @actor INT =
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT);
    DECLARE @session UNIQUEIDENTIFIER =
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER);

    -- Terminal lock triggered
    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        changed_at,
        changed_by,
        session_id,
        details
    )
    SELECT
        i.id,
        'TERMINAL_LOCK',
        @now,
        @actor,
        @session,
        CONCAT('failed_attempts=', i.failed_attempts)
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE d.must_change_password = 0
      AND i.must_change_password = 1;

    -- Failed attempts increment
    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        changed_at,
        changed_by,
        session_id,
        details
    )
    SELECT
        i.id,
        'FAILED_LOGIN_ATTEMPT',
        @now,
        @actor,
        @session,
        CONCAT(
            'attempts=', i.failed_attempts,
            ', lockout_until=',
            COALESCE(CONVERT(NVARCHAR(30), i.lockout_until, 126), 'NULL')
        )
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.failed_attempts, 0) <> ISNULL(i.failed_attempts, 0);
END;
GO


-- --------------------------------------------------
-- Initial role & user
-- --------------------------------------------------
DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @OutputId INT;

EXEC auth.usp_add_role 
    @RoleName = 'admin', 
    @Description = 'Administrator with full access', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;

EXEC auth.usp_create_user
    @username = 'admin',
    @display_name = 'Warehouse Administrator',
    @role_name = 'operator',
    @email = 'warehouse.admin@pw.local',
    @password = 'Operator0',
    @result_code = NULL,
    @friendly_msg = NULL;
GO

USE PW_Core_DEV;
GO

/* ============================================================
   Schema: locations
   Purpose: Physical warehouse structure & storage modelling
   ============================================================ */

/* ============================================================
   locations.storage_types
   ------------------------------------------------------------
   High-level storage category.
   Defines the physical and operational nature of storage.
   ============================================================ */
CREATE TABLE locations.storage_types
(
    storage_type_id   INT IDENTITY(1,1) PRIMARY KEY,

    -- Stable code used by SKU preferences & logic (e.g. RACK, BULK)
    storage_type_code NVARCHAR(50) NOT NULL,

    -- Human-friendly name
    storage_type_name NVARCHAR(100) NOT NULL,

    -- Optional operational description
    description       NVARCHAR(255) NULL,

    is_active         BIT NOT NULL DEFAULT (1),

    created_at        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by        INT NULL,

    CONSTRAINT uq_storage_types_code
        UNIQUE (storage_type_code)
);

/* ============================================================
   locations.storage_sections
   ------------------------------------------------------------
   Sub-division within a storage type.
   Sections are scoped to a single storage type.
   ============================================================ */
CREATE TABLE locations.storage_sections
(
    storage_section_id INT IDENTITY(1,1) PRIMARY KEY,

    --storage_type_id    INT NOT NULL,

    -- Section identifier (FLOOR, MID, TOP, LEFT, RIGHT, etc.)
    section_code       NVARCHAR(50) NOT NULL,

    section_name       NVARCHAR(100) NOT NULL,

    description        NVARCHAR(255) NULL,

    is_active          BIT NOT NULL DEFAULT (1),

    created_at         DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by         INT NULL,

    --CONSTRAINT fk_storage_sections_type
    --    FOREIGN KEY (storage_type_id)
    --    REFERENCES locations.storage_types(storage_type_id),

    --CONSTRAINT uq_storage_sections_type_code
    --    UNIQUE (storage_type_id, section_code)
);


/* ============================================================
   locations.zones
   ------------------------------------------------------------
   Operational grouping for travel paths, load balancing,
   and putaway optimisation (e.g. AISLE_01, BULK_ZONE_A).
   ============================================================ */
CREATE TABLE locations.zones
(
    zone_id        INT IDENTITY(1,1) PRIMARY KEY,

    zone_code      NVARCHAR(50) NOT NULL,
    zone_name      NVARCHAR(100) NOT NULL,

    description    NVARCHAR(255) NULL,

    is_active      BIT NOT NULL DEFAULT (1),

    created_at     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by     INT NULL,

    CONSTRAINT uq_zones_code
        UNIQUE (zone_code)
);

/* ============================================================
   locations.bins
   ------------------------------------------------------------
   Physical storage units.
   This is the ONLY place inventory can reside.
   ============================================================ */
CREATE TABLE locations.bins
(
    bin_id              INT IDENTITY(1,1) PRIMARY KEY,

    -- Human-readable warehouse identifier (A1-01-01, BAY03, etc.)
    bin_code            NVARCHAR(100) NOT NULL,

    storage_type_id     INT NOT NULL,
    storage_section_id  INT NULL,
    zone_id             INT NULL,

    -- Capacity expressed in logical units (pallets for now)
    capacity            INT NOT NULL DEFAULT (1),

    is_active           BIT NOT NULL DEFAULT (1),

    notes               NVARCHAR(255) NULL,

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,
    updated_at          DATETIME2(3) NULL,
    updated_by          INT NULL,

    CONSTRAINT uq_bins_code
        UNIQUE (bin_code),

    CONSTRAINT fk_bins_storage_type
        FOREIGN KEY (storage_type_id)
        REFERENCES locations.storage_types(storage_type_id),

    CONSTRAINT fk_bins_storage_section
        FOREIGN KEY (storage_section_id)
        REFERENCES locations.storage_sections(storage_section_id),

    CONSTRAINT fk_bins_zone
        FOREIGN KEY (zone_id)
        REFERENCES locations.zones(zone_id)
);

CREATE INDEX IX_bins_storage_lookup
ON locations.bins (storage_type_id, storage_section_id, zone_id)
INCLUDE (capacity, is_active);

/* ============================================================
   locations.bin_reservations
   ------------------------------------------------------------
   Temporary claims on bins for putaway / movement planning.
   ============================================================ */
CREATE TABLE locations.bin_reservations
(
    reservation_id   INT IDENTITY(1,1) PRIMARY KEY,

    bin_id           INT NOT NULL,

    reservation_type NVARCHAR(50) NOT NULL, -- PUTAWAY, MOVE, PICK

    reserved_by      INT NOT NULL,
    reserved_at      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    expires_at       DATETIME2(3) NOT NULL,

    CONSTRAINT fk_bin_reservations_bin
        FOREIGN KEY (bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_bin_reservations_bin_expiry
ON locations.bin_reservations (bin_id, expires_at);

/* ============================================================
   inventory.skus
   ------------------------------------------------------------
   Canonical product master.
   Defines physical characteristics and storage intent.
   ============================================================ */
CREATE TABLE inventory.skus
(
    sku_id                  INT IDENTITY(1,1) PRIMARY KEY,

    -- External / business identifier (SAP material, item code)
    sku_code                NVARCHAR(50) NOT NULL,

    sku_description         NVARCHAR(255) NOT NULL,

    ean NVARCHAR(20) NULL UNIQUE, -- Barcode for easy scanning.

    uom_code                NVARCHAR(10) NOT NULL,  -- EA, PAL, KG, etc.

    -- Physical characteristics (used later for rules & capacity)
    weight_per_unit         DECIMAL(10,3) NULL,
    standard_hu_quantity INT NULL,
    is_full_hu_required BIT NOT NULL DEFAULT(0),


    -- Storage intent (THIS is what putaway reads)
    preferred_storage_type_id   INT NOT NULL,
    preferred_storage_section_id INT NULL,

    is_hazardous            BIT NOT NULL DEFAULT (0),
    is_active               BIT NOT NULL DEFAULT (1),

    created_at              DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by              INT NULL,
    updated_at              DATETIME2(3) NULL,
    updated_by              INT NULL,

    CONSTRAINT uq_skus_code
        UNIQUE (sku_code),

    CONSTRAINT fk_skus_storage_type
        FOREIGN KEY (preferred_storage_type_id)
        REFERENCES locations.storage_types(storage_type_id),

    CONSTRAINT fk_skus_storage_section
        FOREIGN KEY (preferred_storage_section_id)
        REFERENCES locations.storage_sections(storage_section_id)
);
GO

/* ============================================================
   inventory.stock_states & statuses
   ------------------------------------------------------------
   Canonical state / status master.
   Defines allowed movements and transitions.
   ============================================================ */
CREATE TABLE inventory.stock_states
(
    state_code        VARCHAR(3)   NOT NULL PRIMARY KEY, -- RCD
    state_code_desc   NVARCHAR(30) NOT NULL,             -- RECEIVED
    is_terminal       BIT NOT NULL DEFAULT 0
);

INSERT INTO inventory.stock_states (state_code, state_code_desc, is_terminal)
VALUES
('EXP', 'EXPECTED', 0),
('RCD', 'RECEIVED', 0),
('PTW', 'PUTAWAY', 0),
('PKD', 'PICKED', 0),
('SHP', 'SHIPPED', 1);

CREATE TABLE inventory.stock_statuses
(
    status_code       VARCHAR(2)   NOT NULL PRIMARY KEY, -- AV
    status_desc       NVARCHAR(30) NOT NULL              -- AVAILABLE
);

INSERT INTO inventory.stock_statuses (status_code, status_desc)
VALUES
('AV', 'AVAILABLE'),
('QC', 'QC HOLD'),
('BL', 'BLOCKED'),
('DM', 'DAMAGED');

CREATE TABLE inventory.stock_state_transitions
(
    from_state_code    VARCHAR(3) NOT NULL,
    to_state_code      VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT 0,
    notes              NVARCHAR(200),

    PRIMARY KEY (from_state_code, to_state_code),

    FOREIGN KEY (from_state_code) REFERENCES inventory.stock_states(state_code),
    FOREIGN KEY (to_state_code)   REFERENCES inventory.stock_states(state_code)
);

INSERT INTO inventory.stock_state_transitions
VALUES
('RCD','PTW',0,'Putaway complete'),
('PTW','PKD',0,'Picked'),
('PKD','SHP',0,'Shipped');

CREATE TABLE inventory.stock_operation_rules
(
    state_code     VARCHAR(3) NOT NULL,
    status_code    VARCHAR(2) NOT NULL,

    can_move       BIT NOT NULL DEFAULT 1,
    can_allocate   BIT NOT NULL DEFAULT 1,
    can_ship       BIT NOT NULL DEFAULT 1,
    can_adjust     BIT NOT NULL DEFAULT 1,
    requires_override BIT NOT NULL DEFAULT 0,

    PRIMARY KEY (state_code, status_code),

    FOREIGN KEY (state_code)  REFERENCES inventory.stock_states(state_code),
    FOREIGN KEY (status_code) REFERENCES inventory.stock_statuses(status_code)
);

-- Normal usable stock
INSERT INTO inventory.stock_operation_rules
VALUES
('PTW','AV',1,1,1,1,0),

-- QC Hold
('PTW','QC',1,0,0,1,1),

-- Blocked
('PTW','BL',0,0,0,0,1);
GO

/* ============================================================
   inventory.inventory_units
   ------------------------------------------------------------
   Physical inventory units (pallets, handling units).
   One row = one traceable unit.
   ============================================================ */
/* ============================================================
   inventory.inventory_units
   ------------------------------------------------------------
   Physical inventory units (pallets, handling units).
   One row = one traceable unit.
   ============================================================ */
CREATE TABLE inventory.inventory_units
(
    inventory_unit_id   INT IDENTITY(1,1) PRIMARY KEY,

    sku_id              INT NOT NULL,

    -- External identifier (SSCC, pallet ID, HU)
    external_ref        NVARCHAR(100) NULL,

    batch_number        NVARCHAR(100) NULL,
    best_before_date    DATE NULL,

    quantity            INT NOT NULL,

    -- Lifecycle axis (RCD, PTW, PKD, SHP)
    stock_state_code    VARCHAR(3) NOT NULL,

    -- Restriction axis (AV, QC, BL, DM)
    stock_status_code   VARCHAR(2) NOT NULL,

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,

    CONSTRAINT fk_inventory_units_sku
        FOREIGN KEY (sku_id)
        REFERENCES inventory.skus(sku_id),

    CONSTRAINT fk_inventory_units_state
        FOREIGN KEY (stock_state_code)
        REFERENCES inventory.stock_states(state_code),

    CONSTRAINT fk_inventory_units_status
        FOREIGN KEY (stock_status_code)
        REFERENCES inventory.stock_statuses(status_code)
);
GO

/* ============================================================
   Indexes
   ============================================================ */

-- 1. Unique SSCC (only when provided)
CREATE UNIQUE INDEX ux_inventory_units_external_ref
ON inventory.inventory_units (external_ref)
WHERE external_ref IS NOT NULL;
GO

-- 2. Fast lookup by SKU (stock aggregation, joins)
CREATE INDEX ix_inventory_units_sku_id
ON inventory.inventory_units (sku_id);
GO

-- 3. Optimised availability queries (SKU + status filtering)
CREATE INDEX ix_inventory_units_sku_state_status
ON inventory.inventory_units (sku_id, stock_state_code, stock_status_code);
GO

CREATE INDEX IX_inventory_units_state
ON inventory.inventory_units (stock_state_code);

/* ============================================================
   inventory.inventory_placements
   ------------------------------------------------------------
   Current physical placement of inventory units.
   One active placement per inventory unit.
   ============================================================ */
CREATE TABLE inventory.inventory_placements
(
    inventory_unit_id   INT PRIMARY KEY,

    bin_id              INT NOT NULL,

    placed_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    placed_by           INT NULL,

    CONSTRAINT fk_inventory_placements_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT fk_inventory_placements_bin
        FOREIGN KEY (bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_inventory_placements_bin
ON inventory.inventory_placements (bin_id);

/* ============================================================
   inventory.inventory_movements
   ------------------------------------------------------------
   Immutable event log of all stock movements.

   One row = one atomic inventory movement event.
   Never updated. Only inserted.
   ============================================================ */
IF OBJECT_ID('inventory.inventory_movements','U') IS NOT NULL
    DROP TABLE inventory.inventory_movements;
GO

CREATE TABLE inventory.inventory_movements
(
    movement_id            INT IDENTITY(1,1)
                           CONSTRAINT PK_inventory_movements
                           PRIMARY KEY,

    /* --------------------------------------------------------
       What moved
       -------------------------------------------------------- */

    inventory_unit_id      INT NOT NULL
                           CONSTRAINT FK_inventory_movements_unit
                           REFERENCES inventory.inventory_units(inventory_unit_id),

    sku_id                 INT NOT NULL
                           CONSTRAINT FK_inventory_movements_sku
                           REFERENCES inventory.skus(sku_id),

    moved_qty              INT NOT NULL
                           CHECK (moved_qty > 0),

    /* --------------------------------------------------------
       Location transition
       -------------------------------------------------------- */

    from_bin_id            INT NULL
                           CONSTRAINT FK_inventory_movements_from_bin
                           REFERENCES locations.bins(bin_id),

    to_bin_id              INT NULL
                           CONSTRAINT FK_inventory_movements_to_bin
                           REFERENCES locations.bins(bin_id),

    /* --------------------------------------------------------
       Lifecycle transition (NEW)
       -------------------------------------------------------- */

    from_state_code        VARCHAR(3) NULL
                           CONSTRAINT FK_inventory_movements_from_state
                           REFERENCES inventory.stock_states(state_code),

    to_state_code          VARCHAR(3) NULL
                           CONSTRAINT FK_inventory_movements_to_state
                           REFERENCES inventory.stock_states(state_code),

    /* --------------------------------------------------------
       Restriction transition (NEW)
       -------------------------------------------------------- */

    from_status_code       VARCHAR(2) NULL
                           CONSTRAINT FK_inventory_movements_from_status
                           REFERENCES inventory.stock_statuses(status_code),

    to_status_code         VARCHAR(2) NULL
                           CONSTRAINT FK_inventory_movements_to_status
                           REFERENCES inventory.stock_statuses(status_code),

    /* --------------------------------------------------------
       Business context
       -------------------------------------------------------- */

    movement_type          NVARCHAR(30) NOT NULL,
    -- RECEIVE
    -- PUTAWAY
    -- BIN_MOVE
    -- ALLOCATE
    -- DEALLOCATE
    -- PICK
    -- LOAD
    -- SHIP
    -- ADJUSTMENT
    -- STATUS_CHANGE
    -- STATE_CHANGE
    -- REVERSAL

    reference_type         NVARCHAR(30) NULL,
    -- INBOUND
    -- OUTBOUND
    -- ADJUSTMENT
    -- MANUAL

    reference_id           INT NULL,

    /* --------------------------------------------------------
       Operational metadata
       -------------------------------------------------------- */

    moved_at               DATETIME2(3) NOT NULL
                           CONSTRAINT DF_inventory_movements_moved_at
                           DEFAULT SYSUTCDATETIME(),

    moved_by_user_id       INT NOT NULL
                           CONSTRAINT FK_inventory_movements_user
                           REFERENCES auth.users(id),

    session_id             UNIQUEIDENTIFIER NULL,

    /* --------------------------------------------------------
       Reversal control
       -------------------------------------------------------- */

    is_reversal            BIT NOT NULL DEFAULT(0),

    reversed_movement_id   INT NULL
                           CONSTRAINT FK_inventory_movements_reversal
                           REFERENCES inventory.inventory_movements(movement_id)
);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_unit
ON inventory.inventory_movements(inventory_unit_id, moved_at DESC);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_reference
ON inventory.inventory_movements(reference_type, reference_id);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_bin
ON inventory.inventory_movements(to_bin_id, moved_at DESC);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_state_status
ON inventory.inventory_movements(to_state_code, to_status_code, moved_at DESC);
GO

/* ============================================================
   core.parties
   ------------------------------------------------------------
   Canonical table for all external business entities
   (suppliers, customers, hauliers, owners, etc.).

   One row = one real-world legal entity.
   Roles are assigned separately via core.party_roles.

   This table is intentionally role-agnostic.
   ============================================================ */
CREATE TABLE core.parties
(
    party_id        INT IDENTITY(1,1) PRIMARY KEY,

    -- Stable external reference (e.g. SAP BP / Vendor / Customer code)
    party_code      NVARCHAR(50)  NOT NULL,

    -- Legal registered name (finance / compliance)
    legal_name      NVARCHAR(200) NOT NULL,

    -- Friendly operational name (what users see)
    display_name    NVARCHAR(200) NOT NULL,

    -- ISO country code (e.g. GB, HU)
    country_code    CHAR(2)       NULL,

    -- Tax / VAT identifier if applicable
    tax_id          NVARCHAR(50)  NULL,

    -- Soft-enable flag (do not delete historical parties)
    is_active       BIT           NOT NULL DEFAULT (1),

    -- Audit
    created_at      DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by      INT           NULL,
    updated_at      DATETIME2(3)  NULL,
    updated_by      INT           NULL,

    CONSTRAINT uq_parties_code UNIQUE (party_code)
);

/* ============================================================
   core.party_roles
   ------------------------------------------------------------
   Assigns functional roles to parties.

   A party may have multiple roles simultaneously
   (e.g. SUPPLIER + HAULIER).

   Role codes are intentionally free-text for now.
   ============================================================ */
CREATE TABLE core.party_roles
(
    party_id    INT          NOT NULL,
    role_code   NVARCHAR(50) NOT NULL, -- SUPPLIER, CUSTOMER, HAULIER, OWNER

    assigned_at DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    assigned_by      INT           NULL,
    updated_at      DATETIME2(3)  NULL,
    updated_by      INT           NULL,

    CONSTRAINT pk_party_roles
        PRIMARY KEY (party_id, role_code),

    CONSTRAINT fk_party_roles_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);

/* ============================================================
   core.party_addresses
   ------------------------------------------------------------
   Physical or logical addresses associated with a party.
   Can be reused across inbound, outbound, billing, etc.
   ============================================================ */
CREATE TABLE core.party_addresses
(
    address_id        INT IDENTITY(1,1) PRIMARY KEY,

    -- Owning party
    party_id          INT NOT NULL,

    -- Address usage / intent
    -- e.g. SHIP_FROM, SHIP_TO, BILL_TO, HQ, YARD
    address_type      NVARCHAR(50) NOT NULL,

    -- Free-text address fields (intentionally simple)
    line_1            NVARCHAR(200) NOT NULL,
    line_2            NVARCHAR(200) NULL,
    city              NVARCHAR(100) NULL,
    region            NVARCHAR(100) NULL,
    postal_code       NVARCHAR(50)  NULL,
    country_code      CHAR(2)       NOT NULL,

    -- Optional operational hints
    dock_info         NVARCHAR(200) NULL, -- gate, dock, yard notes
    instructions      NVARCHAR(400) NULL, -- receiving notes, access rules

    -- Flags
    is_primary        BIT NOT NULL DEFAULT (0),
    is_active         BIT NOT NULL DEFAULT (1),

    -- Audit
    created_at        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by        INT          NULL,
    updated_at        DATETIME2(3) NULL,
    updated_by        INT          NULL,

    CONSTRAINT fk_party_addresses_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);

/* ============================================================
   suppliers.suppliers
   ------------------------------------------------------------
   Supplier-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE suppliers.suppliers
(
    party_id             INT PRIMARY KEY,
    supplier_type        NVARCHAR(50) NULL,  -- RAW, PACKAGING, 3PL
    default_lead_days    INT          NULL,
    preferred_haulier_id INT          NULL,

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_suppliers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT fk_suppliers_haulier
        FOREIGN KEY (preferred_haulier_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   customers.customers
   ------------------------------------------------------------
   Customer-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE customers.customers
(
    party_id               INT PRIMARY KEY,
    customer_type          NVARCHAR(50) NULL, -- RETAIL, WHOLESALE, EXPORT
    default_delivery_days  INT          NULL,
    preferred_haulier_id   INT          NULL,
    allow_crossdock        BIT NOT NULL DEFAULT (0),

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_customers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT fk_customers_haulier
        FOREIGN KEY (preferred_haulier_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   logistics.hauliers
   ------------------------------------------------------------
   Haulier-specific attributes extending core.parties.
   ============================================================ */
CREATE TABLE logistics.hauliers
(
    party_id              INT PRIMARY KEY,
    haulier_type          NVARCHAR(50) NULL, -- INTERNAL, CONTRACTED
    default_vehicle_type  NVARCHAR(50) NULL, -- CURTAIN, BOX, FRIDGE
    requires_timeslot     BIT NOT NULL DEFAULT (0),
    notes                 NVARCHAR(500) NULL,

    CONSTRAINT fk_hauliers_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   core.party_contacts
   ============================================================ */
CREATE TABLE core.party_contacts
(
    contact_id    INT IDENTITY(1,1) PRIMARY KEY,
    party_id      INT NOT NULL,

    contact_role  NVARCHAR(50) NULL,
    contact_name  NVARCHAR(200) NULL,
    email         NVARCHAR(200) NULL,
    phone         NVARCHAR(50)  NULL,

    is_primary    BIT NOT NULL DEFAULT (0),
    is_active     BIT NOT NULL DEFAULT (1),

    created_at    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by    INT          NULL,
    updated_at    DATETIME2(3) NULL,
    updated_by    INT          NULL,

    CONSTRAINT fk_party_contacts_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);


/* ============================================================
   audit.party_changes
   ============================================================ */
CREATE TABLE audit.party_changes
(
    audit_id     BIGINT IDENTITY PRIMARY KEY,
    party_id     INT NOT NULL,

    action       NVARCHAR(50) NOT NULL,
    details      NVARCHAR(500) NULL,

    changed_at   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    changed_by   INT NULL,
    session_id   UNIQUEIDENTIFIER NULL,

    CONSTRAINT fk_party_changes_party
        FOREIGN KEY (party_id)
        REFERENCES core.parties(party_id)
);
GO

CREATE OR ALTER TRIGGER core.tr_parties_audit
ON core.parties
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.party_changes
    (
        party_id,
        action,
        details,
        changed_by,
        session_id
    )
    SELECT
        COALESCE(i.party_id, d.party_id),

        CASE
            WHEN d.party_id IS NULL THEN 'CREATE_PARTY'
            WHEN i.party_id IS NULL THEN 'DELETE_PARTY'
            WHEN d.is_active <> i.is_active THEN 'SET_ACTIVE'
            ELSE 'UPDATE_PARTY'
        END,

        CONCAT(
            'code=', COALESCE(i.party_code, d.party_code),
            '; name=', COALESCE(i.display_name, d.display_name)
        ),

        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)

    FROM inserted i
    FULL JOIN deleted d
        ON d.party_id = i.party_id;
END;
GO

CREATE TABLE deliveries.inbound_statuses
(
    status_code VARCHAR(3) PRIMARY KEY,   -- EXP, ACT, RCV, CLS, CNL
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT NOT NULL DEFAULT(0)
);

INSERT INTO deliveries.inbound_statuses VALUES
('EXP', 'Expected', 0),
('ACT', 'Activated', 0),
('RCV', 'Receiving', 0),
('CLS', 'Closed', 1),
('CNL', 'Cancelled', 1);

CREATE TABLE deliveries.inbound_status_transitions
(
    from_status_code VARCHAR(3) NOT NULL,
    to_status_code   VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT(0),

    CONSTRAINT PK_inbound_status_transitions
        PRIMARY KEY (from_status_code, to_status_code),

    CONSTRAINT FK_inbound_transition_from
        FOREIGN KEY (from_status_code)
        REFERENCES deliveries.inbound_statuses(status_code),

    CONSTRAINT FK_inbound_transition_to
        FOREIGN KEY (to_status_code)
        REFERENCES deliveries.inbound_statuses(status_code)
);

INSERT INTO deliveries.inbound_status_transitions VALUES
('EXP','ACT',0),
('ACT','RCV',0),
('RCV','CLS',0),
('EXP','CNL',0),
('ACT','CNL',1);



/* ============================================================
   deliveries.inbound_deliveries
   ------------------------------------------------------------
   Canonical inbound advice header table.

   One row = one advised inbound document (ASN / delivery note).

   This table represents INTENT, not execution.
   No stock, no pallets, no quantities live here.

   Purpose:
   - Planning
   - Visibility
   - Status progression
   - Linking parties before warehouse activity begins
   ============================================================ */
   /********************************************************************************************
    Table: deliveries.inbound_modes
    Purpose: Reference table defining structural inbound receiving modes
             - SSCC   : Fully pre-advised handling units
             - MANUAL : Loose / quantity-based receiving
    ********************************************************************************************/
    IF NOT EXISTS (
        SELECT 1
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.name = 'inbound_modes'
          AND s.name = 'deliveries'
    )
    BEGIN
        CREATE TABLE deliveries.inbound_modes
        (
            mode_code   VARCHAR(6)  NOT NULL PRIMARY KEY,
            mode_name   NVARCHAR(50) NOT NULL,
            description NVARCHAR(200) NULL,
            is_active   BIT NOT NULL DEFAULT 1
        );
    END;
    GO

    /* --------------------------------------------------------
       Seed inbound mode reference data
    -------------------------------------------------------- */

    IF NOT EXISTS (
        SELECT 1 FROM deliveries.inbound_modes WHERE mode_code = 'SSCC'
    )
    BEGIN
        INSERT INTO deliveries.inbound_modes (mode_code, mode_name, description)
        VALUES ('SSCC', 'SSCC Controlled', 'Fully pre-advised handling units');
    END;

    IF NOT EXISTS (
        SELECT 1 FROM deliveries.inbound_modes WHERE mode_code = 'MANUAL'
    )
    BEGIN
        INSERT INTO deliveries.inbound_modes (mode_code, mode_name, description)
        VALUES ('MANUAL', 'Manual Quantity', 'Loose or bulk quantity receiving');
    END;
    GO

    CREATE TABLE deliveries.inbound_deliveries
    (
        inbound_id           INT IDENTITY(1,1) PRIMARY KEY,

        inbound_ref          NVARCHAR(50) NOT NULL UNIQUE,

        supplier_party_id    INT NOT NULL,
        owner_party_id       INT NOT NULL,
        haulier_party_id     INT NULL,

        ship_to_address_id   INT NOT NULL,

        expected_arrival_at  DATETIME2(3) NULL,

        inbound_status_code  VARCHAR(3) NOT NULL DEFAULT 'EXP',

        -- Structural mode (set on activation, immutable afterwards)
        inbound_mode_code    VARCHAR(6) NULL,

        created_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        created_by           INT NULL,

        updated_at           DATETIME2(3) NULL,
        updated_by           INT NULL,

        CONSTRAINT FK_inbound_status
            FOREIGN KEY (inbound_status_code)
            REFERENCES deliveries.inbound_statuses(status_code),

        CONSTRAINT FK_inbound_mode
            FOREIGN KEY (inbound_mode_code)
            REFERENCES deliveries.inbound_modes(mode_code),

        CONSTRAINT fk_inbound_supplier
            FOREIGN KEY (supplier_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_owner
            FOREIGN KEY (owner_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_haulier
            FOREIGN KEY (haulier_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT fk_inbound_ship_to
            FOREIGN KEY (ship_to_address_id)
            REFERENCES core.party_addresses(address_id)
    );
    GO

    CREATE INDEX IX_inbound_status_mode
    ON deliveries.inbound_deliveries (inbound_status_code, inbound_mode_code);
    GO

/* ============================================================
   View: deliveries.vw_inbound_overview
   ------------------------------------------------------------
   Operational overview of inbound advice.

   Used by:
   - CLI "View expected deliveries"
   - Desktop inbound list
   - Reporting / dashboards
   ============================================================ */
CREATE OR ALTER VIEW deliveries.vw_inbound_overview
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.inbound_status_code,
    d.expected_arrival_at,

    s.display_name   AS supplier_name,
    o.display_name   AS owner_name,
    h.display_name   AS haulier_name,

    a.city,
    a.postal_code,
    a.country_code

FROM deliveries.inbound_deliveries d
JOIN core.parties s ON s.party_id = d.supplier_party_id
JOIN core.parties o ON o.party_id = d.owner_party_id
LEFT JOIN core.parties h ON h.party_id = d.haulier_party_id
JOIN core.party_addresses a ON a.address_id = d.ship_to_address_id;
GO

/* ============================================================
   View: deliveries.vw_inbound_by_supplier
   ------------------------------------------------------------
   Supplier-centric workload view.

   Used for:
   - Planning
   - Supplier performance insight
   ============================================================ */
CREATE OR ALTER VIEW deliveries.vw_inbound_by_supplier
AS
SELECT
    s.party_code     AS supplier_code,
    s.display_name   AS supplier_name,
    COUNT(*)         AS open_inbounds
FROM deliveries.inbound_deliveries d
JOIN core.parties s ON s.party_id = d.supplier_party_id
WHERE d.inbound_status_code IN ('EXP','ACT','REC')
GROUP BY s.party_code, s.display_name;
GO

/* ============================================================
   logistics.vw_inbound_by_haulier
   ============================================================ */
CREATE OR ALTER VIEW logistics.vw_inbound_by_haulier
AS
SELECT
    h.display_name AS haulier_name,
    COUNT(*)       AS scheduled_deliveries,
    MIN(d.expected_arrival_at) AS next_eta
FROM deliveries.inbound_deliveries d
JOIN core.parties h ON h.party_id = d.haulier_party_id
WHERE d.inbound_status_code IN ('EXP','ACT','REC')
GROUP BY h.display_name;
GO

/* ============================================================
   Trigger: audit inbound advice changes
   ------------------------------------------------------------
   Records meaningful lifecycle and header changes
   to inbound advice documents.

   Mirrors audit.party_changes pattern.
   ============================================================ */
/*
CREATE OR ALTER TRIGGER deliveries.tr_inbound_deliveries_audit
ON deliveries.inbound_deliveries
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.party_changes
    (
        party_id,
        action,
        details,
        changed_at,
        changed_by,
        session_id
    )
    SELECT
        -- Owner is the most stable auditing anchor
        COALESCE(i.owner_party_id, d.owner_party_id),

        CASE
            WHEN d.inbound_id IS NULL THEN 'CREATE_INBOUND'
            WHEN i.inbound_id IS NULL THEN 'DELETE_INBOUND'
            WHEN d.inbound_status <> i.inbound_status THEN 'INBOUND_STATUS_CHANGE'
            ELSE 'UPDATE_INBOUND_HEADER'
        END,

        CONCAT(
            'inbound_ref=', COALESCE(i.inbound_ref, d.inbound_ref),
            '; status=', COALESCE(i.inbound_status, d.inbound_status)
        ),

        SYSUTCDATETIME(),
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)

    FROM inserted i
    FULL JOIN deleted d
        ON d.inbound_id = i.inbound_id;
END;
GO
*/
CREATE TABLE deliveries.inbound_line_states
(
    state_code      VARCHAR(3) PRIMARY KEY, -- EXP, PRC, RCV, CNL
    state_desc      NVARCHAR(30) NOT NULL,
    is_terminal     BIT NOT NULL DEFAULT 0
);

INSERT INTO deliveries.inbound_line_states
VALUES
('EXP','EXPECTED',0),
('PRC','PARTIALLY_RECEIVED',0),
('RCV','RECEIVED',1),
('CNL','CANCELLED',1);

CREATE TABLE deliveries.inbound_line_state_transitions
(
    from_state_code VARCHAR(3) NOT NULL,
    to_state_code   VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT(0),

    CONSTRAINT PK_inbound_line_transitions
        PRIMARY KEY (from_state_code, to_state_code),

    CONSTRAINT FK_inbound_line_transition_from
        FOREIGN KEY (from_state_code)
        REFERENCES deliveries.inbound_line_states(state_code),

    CONSTRAINT FK_inbound_line_transition_to
        FOREIGN KEY (to_state_code)
        REFERENCES deliveries.inbound_line_states(state_code)
);
GO

INSERT INTO deliveries.inbound_line_state_transitions VALUES
('EXP','PRC',0),
('PRC','PRC',0),  -- multiple partial receipts
('PRC','RCV',0),
('EXP','RCV',0),
('EXP','CNL',1),
('PRC','CNL',1);
GO

CREATE TABLE deliveries.inbound_lines
(
    inbound_line_id     INT IDENTITY(1,1) PRIMARY KEY,
    inbound_id          INT NOT NULL,
    line_no             INT NOT NULL,

    sku_id              INT NOT NULL,
    expected_qty        INT NOT NULL CHECK (expected_qty > 0),
    received_qty        INT NOT NULL DEFAULT (0),

    batch_number        NVARCHAR(100) NULL,
    best_before_date    DATE NULL,

    line_state_code     VARCHAR(3) NOT NULL DEFAULT 'EXP',

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,
    updated_at                  DATETIME2(3) NULL,
    updated_by                  INT NULL,

    CONSTRAINT FK_inbound_lines_header
        FOREIGN KEY (inbound_id)
        REFERENCES deliveries.inbound_deliveries(inbound_id),

    CONSTRAINT FK_inbound_lines_sku
        FOREIGN KEY (sku_id)
        REFERENCES inventory.skus(sku_id),

    CONSTRAINT FK_inbound_line_state
        FOREIGN KEY (line_state_code)
        REFERENCES deliveries.inbound_line_states(state_code),

    CONSTRAINT UQ_inbound_line
        UNIQUE (inbound_id, line_no),

    CONSTRAINT CK_received_qty_valid
        CHECK (received_qty <= expected_qty)
);

/* ============================================================
   deliveries.inbound_expected_units
   ------------------------------------------------------------
   Pre-advised handling units (SSCC-level expectations).
   One row = one expected handling unit for an inbound line.
   ============================================================ */
   CREATE TABLE deliveries.inbound_expected_unit_states
    (
        state_code VARCHAR(3) PRIMARY KEY,
        description NVARCHAR(50) NOT NULL
    );

    INSERT INTO deliveries.inbound_expected_unit_states VALUES
        ('EXP', 'EXPECTED'),
        ('CLM', 'CLAIMED'),
        ('RCV', 'RECEIVED'),
        ('CNL', 'CANCELLED');

/* =========================================================================================
   TABLE: deliveries.inbound_expected_unit_state_transitions
   Purpose: Allowed state changes for SSCC expected units (EXP/CLM/RCV/...)
========================================================================================= */
IF OBJECT_ID('deliveries.inbound_expected_unit_state_transitions', 'U') IS NULL
BEGIN
    CREATE TABLE deliveries.inbound_expected_unit_state_transitions
    (
        from_state_code     VARCHAR(3) NOT NULL,
        to_state_code       VARCHAR(3) NOT NULL,
        requires_authority  BIT NOT NULL DEFAULT(0),

        CONSTRAINT PK_inbound_expected_unit_state_transitions
            PRIMARY KEY (from_state_code, to_state_code)
    );
END;
GO

/* Seed transitions (idempotent) */
MERGE deliveries.inbound_expected_unit_state_transitions AS tgt
USING (VALUES
    ('EXP','CLM',0),  -- preview claim
    ('CLM','EXP',0),  -- auto-expire / release claim
    ('CLM','RCV',0),  -- confirm receive
    ('EXP','RCV',1)   -- optional: admin force receive without claim (usually NO; keep as 1)
) AS src(from_state_code, to_state_code, requires_authority)
ON  tgt.from_state_code = src.from_state_code
AND tgt.to_state_code   = src.to_state_code
WHEN NOT MATCHED THEN
    INSERT (from_state_code, to_state_code, requires_authority)
    VALUES (src.from_state_code, src.to_state_code, src.requires_authority);
GO

/* ============================================================
   deliveries.inbound_expected_units (WITH CLAIM FIELDS)
   Includes optional updated_at / updated_by
   ============================================================ */

    IF OBJECT_ID('deliveries.inbound_expected_units', 'U') IS NULL
    BEGIN
        CREATE TABLE deliveries.inbound_expected_units
        (
            inbound_expected_unit_id    INT IDENTITY(1,1) PRIMARY KEY,

            inbound_line_id             INT NOT NULL,

            -- Expected SSCC from ASN / EDI
            expected_external_ref       NVARCHAR(100) NOT NULL,

            expected_quantity           INT NOT NULL CHECK (expected_quantity > 0),

            batch_number                NVARCHAR(100) NULL,
            best_before_date            DATE NULL,

            expected_unit_state_code    VARCHAR(3) NOT NULL
                CONSTRAINT DF_inbexp_state_code DEFAULT ('EXP'),

            received_inventory_unit_id  INT NULL,

            -- Claim / lock fields (two-scan confirm hardening)
            claimed_session_id          UNIQUEIDENTIFIER NULL,
            claimed_by_user_id          INT NULL,
            claimed_at                  DATETIME2(3) NULL,
            claim_expires_at            DATETIME2(3) NULL,
            claim_token                 UNIQUEIDENTIFIER NULL,

            created_at                  DATETIME2(3) NOT NULL
                CONSTRAINT DF_inbexp_created_at DEFAULT (SYSUTCDATETIME()),

            created_by                  INT NULL,

            updated_at                  DATETIME2(3) NULL,
            updated_by                  INT NULL,

            CONSTRAINT FK_inbexp_line
                FOREIGN KEY (inbound_line_id)
                REFERENCES deliveries.inbound_lines(inbound_line_id),

            CONSTRAINT FK_inbexp_inventory_unit
                FOREIGN KEY (received_inventory_unit_id)
                REFERENCES inventory.inventory_units(inventory_unit_id),

            CONSTRAINT FK_inbexp_state
                FOREIGN KEY (expected_unit_state_code)
                REFERENCES deliveries.inbound_expected_unit_states(state_code),

            CONSTRAINT UQ_inbexp_external_ref
                UNIQUE (expected_external_ref),

            CONSTRAINT CK_inbexp_quantity
                CHECK (expected_quantity > 0)
        );

        CREATE INDEX IX_inbexp_line
        ON deliveries.inbound_expected_units(inbound_line_id);

        CREATE INDEX IX_inbexp_claim_session 
        ON deliveries.inbound_expected_units(claimed_session_id, claim_expires_at);

        CREATE INDEX IX_inbexp_units_claim
        ON deliveries.inbound_expected_units (expected_external_ref)
        INCLUDE (received_inventory_unit_id, claimed_session_id, claim_expires_at);

        /* OPTIONAL (recommended): helps clean up / find expiring claims fast */
        CREATE INDEX IX_inbexp_claim_expires
        ON deliveries.inbound_expected_units (claim_expires_at)
        INCLUDE (expected_external_ref, claimed_session_id, received_inventory_unit_id);

    END;
    GO

/* ============================================================
   
   ============================================================ */
    IF OBJECT_ID('deliveries.inbound_expected_units', 'U') IS NOT NULL
    AND NOT EXISTS
    (
        SELECT 1
        FROM sys.default_constraints dc
        JOIN sys.columns c
            ON c.object_id = dc.parent_object_id
           AND c.column_id = dc.parent_column_id
        WHERE dc.parent_object_id = OBJECT_ID('deliveries.inbound_expected_units')
          AND c.name = 'created_by'
    )
    BEGIN
        ALTER TABLE deliveries.inbound_expected_units
        ADD CONSTRAINT DF_inbexp_created_by
        DEFAULT (CONVERT(int, SESSION_CONTEXT(N'user_id')))
        FOR created_by;
    END;
    GO

/* ============================================================
   deliveries.inbound_receipts
   ------------------------------------------------------------
   Physical receipt events against inbound lines.

   One row = one receive transaction.
   Immutable business event.
   ============================================================ */
   IF OBJECT_ID('deliveries.inbound_receipts','U') IS NOT NULL
    DROP TABLE deliveries.inbound_receipts;
GO

CREATE TABLE deliveries.inbound_receipts
(
    receipt_id              INT IDENTITY(1,1)
                            CONSTRAINT PK_inbound_receipts
                            PRIMARY KEY,

    inbound_line_id         INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_line
                            REFERENCES deliveries.inbound_lines(inbound_line_id),

    inbound_expected_unit_id INT NULL
                            CONSTRAINT FK_inbound_receipts_expected_unit
                            REFERENCES deliveries.inbound_expected_units(inbound_expected_unit_id),

    inventory_unit_id       INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_inventory
                            REFERENCES inventory.inventory_units(inventory_unit_id),

    received_qty            INT NOT NULL CHECK (received_qty > 0),

    received_by_user_id     INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_user
                            REFERENCES auth.users(id),

    session_id              UNIQUEIDENTIFIER NULL,

    received_at             DATETIME2(3) NOT NULL
                            CONSTRAINT DF_inbound_receipts_received_at
                            DEFAULT SYSUTCDATETIME(),

    is_reversal             BIT NOT NULL DEFAULT(0),
    reversed_receipt_id     INT NULL
                            CONSTRAINT FK_inbound_receipts_reversal
                            REFERENCES deliveries.inbound_receipts(receipt_id)
);
GO

CREATE NONCLUSTERED INDEX IX_inbound_receipts_line
ON deliveries.inbound_receipts(inbound_line_id)
INCLUDE (received_qty, received_at);
GO

CREATE OR ALTER VIEW deliveries.vw_inbound_lines_receivable
AS
SELECT
    l.inbound_line_id,
    d.inbound_ref,
    l.line_no,
    s.sku_code,
    s.sku_description,
    l.expected_qty,
    l.received_qty,
    (l.expected_qty - l.received_qty) AS outstanding_qty,
    l.line_state_code
FROM deliveries.inbound_lines l
JOIN deliveries.inbound_deliveries d
    ON d.inbound_id = l.inbound_id
JOIN inventory.skus s
    ON s.sku_id = l.sku_id
WHERE
    d.inbound_status_code IN ('ACT','RCV')
    AND l.line_state_code NOT IN ('RCV','CNL')
    AND (l.expected_qty - l.received_qty) > 0;
GO

/********************************************************************************************
    Procedure: deliveries.usp_activate_inbound
    Purpose  : Activates inbound delivery (EXP → ACT)
               - Validates transition rules
               - Enforces structural consistency (no mixed SSCC / Manual lines)
               - Determines and persists inbound_mode_code (SSCC / MANUAL)
               - Locks header during activation
********************************************************************************************/
CREATE OR ALTER PROCEDURE deliveries.usp_activate_inbound
(
    @inbound_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE 
        @current_status      VARCHAR(3),
        @existing_mode       VARCHAR(6),
        @sscc_line_count     INT,
        @manual_line_count   INT,
        @mode_code           VARCHAR(6);

    BEGIN TRY
        BEGIN TRAN;

        /* --------------------------------------------------------
           1️⃣ Lock header and validate existence
        -------------------------------------------------------- */

        SELECT 
            @current_status = inbound_status_code,
            @existing_mode  = inbound_mode_code
        FROM deliveries.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        IF @current_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINB01';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           2️⃣ Validate transition allowed (EXP → ACT)
        -------------------------------------------------------- */

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_status_transitions
            WHERE from_status_code = @current_status
              AND to_status_code   = 'ACT'
        )
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINB05';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           3️⃣ Must have at least one active line
        -------------------------------------------------------- */

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code <> 'CNL'
        )
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINB03';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           4️⃣ Validate inbound structural consistency
               (No mixed SSCC + Manual lines)
        -------------------------------------------------------- */

        SELECT
            @sscc_line_count = COUNT(DISTINCT l.inbound_line_id)
        FROM deliveries.inbound_lines l
        JOIN deliveries.inbound_expected_units eu
            ON eu.inbound_line_id = l.inbound_line_id
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL';

        SELECT
            @manual_line_count = COUNT(*)
        FROM deliveries.inbound_lines l
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL'
          AND NOT EXISTS (
                SELECT 1
                FROM deliveries.inbound_expected_units eu
                WHERE eu.inbound_line_id = l.inbound_line_id
          );

        IF @sscc_line_count > 0 AND @manual_line_count > 0
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBHYB01';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           5️⃣ Determine inbound mode
        -------------------------------------------------------- */

        IF @sscc_line_count > 0
            SET @mode_code = 'SSCC';
        ELSE
            SET @mode_code = 'MANUAL';

        /* --------------------------------------------------------
           6️⃣ Prevent mode overwrite (immutability guard)
        -------------------------------------------------------- */

        IF @existing_mode IS NOT NULL AND @existing_mode <> @mode_code
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBMODE01';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           7️⃣ Perform activation
        -------------------------------------------------------- */

        EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
        EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

        UPDATE deliveries.inbound_deliveries
        SET inbound_status_code = 'ACT',
            inbound_mode_code   = @mode_code,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        COMMIT;

        SELECT CAST(1 AS BIT), N'SUCINB01';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT), N'ERRINB99';
    END CATCH
END;
GO

CREATE OR ALTER VIEW deliveries.vw_inbounds_activatable
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at,
    d.inbound_status_code,
    COUNT(l.inbound_line_id) AS line_count
FROM deliveries.inbound_deliveries d
JOIN deliveries.inbound_lines l
    ON l.inbound_id = d.inbound_id
WHERE
    d.inbound_status_code = 'EXP'
    AND l.line_state_code <> 'CNL'
GROUP BY
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at,
    d.inbound_status_code;
GO

/* ============================================================
   deliveries.usp_receive_inbound_line
   ------------------------------------------------------------
   SSCC-aware receiving procedure.

   Supports:
   - SSCC-based receiving (pre-advised)  => no split
   - Manual quantity receiving (non-SSCC)

   Returns a single row:
       success_bit  BIT
       error_code   NVARCHAR(20)
   ============================================================ */
CREATE OR ALTER PROCEDURE deliveries.usp_receive_inbound_line
(
    -- Manual mode
    @inbound_line_id            INT = NULL,
    @received_qty               INT = NULL,

    @staging_bin_code           NVARCHAR(100),

    -- SSCC mode (authoritative)
    @inbound_expected_unit_id   INT = NULL,
    @claim_token                UNIQUEIDENTIFIER = NULL,

    -- Optional fields (manual mode can supply; SSCC resolves from expected unit)
    @external_ref               NVARCHAR(100) = NULL,
    @batch_number               NVARCHAR(100) = NULL,
    @best_before_date           DATE = NULL,

    @user_id                    INT = NULL,
    @session_id                 UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    BEGIN TRY
        BEGIN TRAN;

        /* --------------------------------------------------------
           1) Validate staging bin input
        -------------------------------------------------------- */
        IF NULLIF(LTRIM(RTRIM(@staging_bin_code)), N'') IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL07';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           2) Determine mode
        -------------------------------------------------------- */
        DECLARE @is_sscc_mode BIT =
            CASE WHEN @inbound_expected_unit_id IS NOT NULL THEN 1 ELSE 0 END;

        DECLARE
            @resolved_line_id      INT = NULL,
            @sku_id                INT = NULL,
            @inbound_id            INT = NULL,
            @expected_qty          INT = NULL,
            @already_received      INT = NULL,
            @line_state            VARCHAR(3) = NULL,
            @header_status         VARCHAR(3) = NULL,
            @expected_unit_qty     INT = NULL,
            @existing_received_id  INT = NULL,
            @now                   DATETIME2(3) = SYSUTCDATETIME(),
            @claim_expires_at      DATETIME2(3) = NULL,
            @db_claim_token        UNIQUEIDENTIFIER = NULL,
            @claimed_session_id    UNIQUEIDENTIFIER = NULL;

        /* ========================================================
           SSCC MODE
        ======================================================== */
        IF @is_sscc_mode = 1
        BEGIN
            -- 1) Protocol guards (cheap checks first)
            IF @session_id IS NULL OR @claim_token IS NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRPROC02';
                ROLLBACK;
                RETURN;
            END

            -- 2) Lock and load the expected unit row (single source of truth)
            SELECT
                @resolved_line_id     = eu.inbound_line_id,
                @expected_unit_qty    = eu.expected_quantity,
                @external_ref         = eu.expected_external_ref,
                @batch_number         = eu.batch_number,
                @best_before_date     = eu.best_before_date,
                @existing_received_id = eu.received_inventory_unit_id,
                @claim_expires_at     = eu.claim_expires_at,
                @db_claim_token       = eu.claim_token,
                @claimed_session_id   = eu.claimed_session_id
            FROM deliveries.inbound_expected_units eu WITH (UPDLOCK, HOLDLOCK)
            WHERE eu.inbound_expected_unit_id = @inbound_expected_unit_id;

            IF @resolved_line_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC01';
                ROLLBACK;
                RETURN;
            END

            IF @existing_received_id IS NOT NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC06';
                ROLLBACK;
                RETURN;
            END

            -- 3) Self-heal expired claims (under the same lock)
            IF @claim_expires_at IS NOT NULL
               AND @claim_expires_at <= @now
            BEGIN
                UPDATE deliveries.inbound_expected_units
                SET expected_unit_state_code = 'EXP',
                    claimed_session_id = NULL,
                    claimed_by_user_id = NULL,
                    claimed_at = NULL,
                    claim_expires_at = NULL,
                    claim_token = NULL
                WHERE inbound_expected_unit_id = @inbound_expected_unit_id
                  AND received_inventory_unit_id IS NULL;

                -- After self-heal, the confirm must fail (force re-preview).
                -- This is the correct UX: "claim expired, rescan".
                SELECT CAST(0 AS BIT), N'ERRSSCC08';
                ROLLBACK;
                RETURN;
            END

            -- 4) Claim must match this session + token and be unexpired
            IF @claimed_session_id IS NULL
               OR @claim_expires_at IS NULL
               OR @claimed_session_id <> @session_id
               OR @db_claim_token <> @claim_token
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC08';
                ROLLBACK;
                RETURN;
            END

            -- 5) Force HU quantity
            SET @received_qty = @expected_unit_qty;
        END
        ELSE
        BEGIN
            /* ========================================================
               MANUAL MODE
            ======================================================== */

            SET @resolved_line_id = @inbound_line_id;

            IF @resolved_line_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRINBL01';
                ROLLBACK;
                RETURN;
            END

            IF @received_qty IS NULL OR @received_qty <= 0
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRINBL06';
                ROLLBACK;
                RETURN;
            END
        END

        /* --------------------------------------------------------
           4) Lock and resolve line
        -------------------------------------------------------- */
        SELECT
            @sku_id           = l.sku_id,
            @inbound_id       = l.inbound_id,
            @expected_qty     = l.expected_qty,
            @already_received = ISNULL(l.received_qty, 0),
            @line_state       = l.line_state_code
        FROM deliveries.inbound_lines l WITH (UPDLOCK, HOLDLOCK)
        WHERE l.inbound_line_id = @resolved_line_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL01';
            ROLLBACK;
            RETURN;
        END

        IF @line_state = 'CNL'
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL08';
            ROLLBACK;
            RETURN;
        END

        IF (@already_received + @received_qty) > @expected_qty
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL02';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           5) Validate header
        -------------------------------------------------------- */
        SELECT @header_status = d.inbound_status_code
        FROM deliveries.inbound_deliveries d WITH (UPDLOCK, HOLDLOCK)
        WHERE d.inbound_id = @inbound_id;

        IF @header_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINB01';
            ROLLBACK;
            RETURN;
        END

        IF @header_status NOT IN ('ACT','RCV')
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL04';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           6) Resolve bin
        -------------------------------------------------------- */
        DECLARE @staging_bin_id INT;

        SELECT @staging_bin_id = b.bin_id
        FROM locations.bins b
        WHERE b.bin_code = @staging_bin_code
          AND b.is_active = 1;

        IF @staging_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL05';
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           7) Create inventory unit
        -------------------------------------------------------- */
        DECLARE @inventory_unit_id INT;

        INSERT INTO inventory.inventory_units
        (
            sku_id,
            external_ref,
            batch_number,
            best_before_date,
            quantity,
            stock_state_code,
            stock_status_code,
            created_at,
            created_by
        )
        VALUES
        (
            @sku_id,
            @external_ref,
            @batch_number,
            @best_before_date,
            @received_qty,
            'RCD',
            'AV',
            SYSUTCDATETIME(),
            @user_id
        );

        SET @inventory_unit_id = SCOPE_IDENTITY();

        /* --------------------------------------------------------
           8) Mark expected unit received (SSCC mode)
        -------------------------------------------------------- */
        IF @is_sscc_mode = 1
        BEGIN
            UPDATE deliveries.inbound_expected_units
            SET received_inventory_unit_id = @inventory_unit_id,
                expected_unit_state_code   = 'RCV',
                claimed_session_id         = NULL,
                claimed_by_user_id         = NULL,
                claimed_at                 = NULL,
                claim_expires_at           = NULL,
                claim_token                = NULL
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id
              AND received_inventory_unit_id IS NULL
              AND claimed_session_id = @session_id
              AND claim_token = @claim_token
              AND claim_expires_at > @now;

            IF @@ROWCOUNT = 0
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC08';
                ROLLBACK;
                RETURN;
            END
        END

        /* --------------------------------------------------------
           9) Placement
        -------------------------------------------------------- */
        INSERT INTO inventory.inventory_placements
        (
            inventory_unit_id,
            bin_id,
            placed_at,
            placed_by
        )
        VALUES
        (
            @inventory_unit_id,
            @staging_bin_id,
            SYSUTCDATETIME(),
            @user_id
        );

        /* --------------------------------------------------------
           10) Receipt record
        -------------------------------------------------------- */
        INSERT INTO deliveries.inbound_receipts
        (
            inbound_line_id,
            inbound_expected_unit_id,
            inventory_unit_id,
            received_qty,
            received_at,
            received_by_user_id,
            session_id
        )
        VALUES
        (
            @resolved_line_id,
            @inbound_expected_unit_id,
            @inventory_unit_id,
            @received_qty,
            SYSUTCDATETIME(),
            @user_id,
            @session_id
        );

        /* --------------------------------------------------------
           11) Inventory movement
        -------------------------------------------------------- */
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id,
            sku_id,
            moved_qty,
            from_bin_id,
            to_bin_id,
            from_status_code,
            to_status_code,
            movement_type,
            reference_type,
            reference_id,
            moved_at,
            moved_by_user_id,
            session_id
        )
        VALUES
        (
            @inventory_unit_id,
            @sku_id,
            @received_qty,
            NULL,
            @staging_bin_id,
            NULL,
            'AV',
            'RECEIVE',
            'INBOUND',
            @inbound_id,
            SYSUTCDATETIME(),
            @user_id,
            @session_id
        );

        /* --------------------------------------------------------
           12) Update line
        -------------------------------------------------------- */
        DECLARE @new_received_qty INT = @already_received + @received_qty;
        DECLARE @new_line_state VARCHAR(3);

        SET @new_line_state =
            CASE
                WHEN @new_received_qty < @expected_qty THEN 'PRC'
                ELSE 'RCV'
            END;

        UPDATE deliveries.inbound_lines
        SET received_qty    = @new_received_qty,
            line_state_code = @new_line_state,
            updated_at      = SYSUTCDATETIME(),
            updated_by      = @user_id
        WHERE inbound_line_id = @resolved_line_id;

        /* --------------------------------------------------------
           13) Update header
        -------------------------------------------------------- */
        IF @header_status = 'ACT'
        BEGIN
            UPDATE deliveries.inbound_deliveries
            SET inbound_status_code = 'RCV',
                updated_at          = SYSUTCDATETIME(),
                updated_by          = @user_id
            WHERE inbound_id = @inbound_id;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code NOT IN ('RCV','CNL')
        )
        BEGIN
            UPDATE deliveries.inbound_deliveries
            SET inbound_status_code = 'CLS',
                updated_at          = SYSUTCDATETIME(),
                updated_by          = @user_id
            WHERE inbound_id = @inbound_id;
        END

        COMMIT;

        SELECT CAST(1 AS BIT), N'SUCINBL01';
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;

            DECLARE @err_no INT = ERROR_NUMBER();
            DECLARE @err_msg NVARCHAR(2048) = ERROR_MESSAGE();

            -- Pass-through our domain THROWs (guards etc.)
            IF @err_no = 50001 AND @err_msg LIKE N'ERR%'
            BEGIN
                SELECT CAST(0 AS BIT), @err_msg;
                RETURN;
            END

            SELECT CAST(0 AS BIT), N'ERRINBL99';
        END CATCH
    END;
    GO

CREATE OR ALTER PROCEDURE deliveries.usp_get_inbound_summary
(
    @inbound_ref NVARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CAST(
            CASE WHEN d.inbound_id IS NULL THEN 0 ELSE 1 END
        AS BIT) AS ExistsFlag,

        CAST(
            CASE WHEN d.inbound_status_code IN ('ACT','RCV')
                 THEN 1 ELSE 0 END
        AS BIT) AS IsReceivable,

        CAST(
            CASE WHEN EXISTS (
                SELECT 1
                FROM deliveries.inbound_expected_units eu
                JOIN deliveries.inbound_lines l
                    ON eu.inbound_line_id = l.inbound_line_id
                WHERE l.inbound_id = d.inbound_id
                  AND eu.expected_unit_state_code = 'EXP'
            )
            THEN 1 ELSE 0 END
        AS BIT) AS HasExpectedUnits
    FROM deliveries.inbound_deliveries d
    WHERE d.inbound_ref = @inbound_ref;
END
GO

/********************************************************************************************
    PROCEDURE: deliveries.usp_validate_sscc_for_receive
    Purpose  : Preview + claim an expected SSCC unit for receiving (CLM window)
               Enforces expected-unit state transitions via deliveries.inbound_expected_unit_state_transitions
               Keeps output contract columns 0-19 stable for C# reader mapping
********************************************************************************************/
CREATE OR ALTER PROCEDURE deliveries.usp_validate_sscc_for_receive
(
    @external_ref        NVARCHAR(100),
    @staging_bin_code    NVARCHAR(100),
    @user_id             INT = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @success                  BIT              = 0,
        @result_code              NVARCHAR(20)     = NULL,
        @inbound_expected_unit_id INT              = NULL,  -- claim key
        @inbound_line_id          INT              = NULL,
        @inbound_ref              NVARCHAR(50)     = NULL,
        @header_status            VARCHAR(3)       = NULL,
        @line_state               VARCHAR(3)       = NULL,
        @sku_code                 NVARCHAR(50)     = NULL,
        @sku_description          NVARCHAR(200)    = NULL,
        @expected_unit_qty        INT              = NULL,
        @line_expected_qty        INT              = NULL,
        @line_received_qty        INT              = NULL,
        @batch_number             NVARCHAR(100)    = NULL,
        @best_before_date         DATE             = NULL,
        @received_inventory_id    INT              = NULL,

        -- expected unit state (NEW)
        @expected_unit_state      VARCHAR(3)       = NULL,

        -- claim fields
        @claimed_session_id       UNIQUEIDENTIFIER = NULL,
        @claimed_by_user_id       INT              = NULL,
        @claim_expires_at         DATETIME2(3)     = NULL,
        @claim_token              UNIQUEIDENTIFIER = NULL,

        @ttl_seconds              INT              = NULL;

    ----------------------------------------------------------------------
    -- TTL seconds (operations.settings)
    ----------------------------------------------------------------------
    SELECT @ttl_seconds = TRY_CONVERT(INT, s.setting_value)
    FROM operations.settings s
    WHERE s.setting_name = 'inbound.sscc_claim_ttl_seconds';

    IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
        SET @ttl_seconds = 30; -- safe default for DEV

    ----------------------------------------------------------------------
    -- 0) Cleanup expired claims (CLM → EXP)
    --    NOTE: This update will be blocked by guards if they disallow it.
    --          Your trigger should allow CLM->EXP operational updates.
    ----------------------------------------------------------------------
    UPDATE deliveries.inbound_expected_units
    SET expected_unit_state_code = 'EXP',
        claimed_session_id       = NULL,
        claimed_by_user_id       = NULL,
        claimed_at               = NULL,
        claim_expires_at         = NULL,
        claim_token              = NULL
    WHERE claim_expires_at <= SYSUTCDATETIME()
      AND received_inventory_unit_id IS NULL
      AND expected_unit_state_code = 'CLM';

    ----------------------------------------------------------------------
    -- 1) Resolve + LOCK expected unit row (preview is where we claim)
    ----------------------------------------------------------------------
    BEGIN TRY
        BEGIN TRAN;

        SELECT TOP (1)
            @inbound_line_id          = l.inbound_line_id,
            @inbound_ref              = d.inbound_ref,
            @header_status            = d.inbound_status_code,
            @line_state               = l.line_state_code,
            @sku_code                 = s.sku_code,
            @sku_description          = s.sku_description,
            @expected_unit_qty        = eu.expected_quantity,
            @line_expected_qty        = l.expected_qty,
            @line_received_qty        = ISNULL(l.received_qty, 0),
            @batch_number             = eu.batch_number,
            @best_before_date         = eu.best_before_date,
            @received_inventory_id    = eu.received_inventory_unit_id,

            @expected_unit_state      = eu.expected_unit_state_code,    -- ✅ NEW

            @inbound_expected_unit_id = eu.inbound_expected_unit_id,
            @claimed_session_id       = eu.claimed_session_id,
            @claimed_by_user_id       = eu.claimed_by_user_id,
            @claim_expires_at         = eu.claim_expires_at,
            @claim_token              = eu.claim_token
        FROM deliveries.inbound_expected_units eu WITH (UPDLOCK, ROWLOCK)
        JOIN deliveries.inbound_lines l
            ON eu.inbound_line_id = l.inbound_line_id
        JOIN deliveries.inbound_deliveries d
            ON l.inbound_id = d.inbound_id
        JOIN inventory.skus s
            ON l.sku_id = s.sku_id
        WHERE eu.expected_external_ref = LTRIM(RTRIM(@external_ref));

        IF @inbound_line_id IS NULL
        BEGIN
            ROLLBACK;
            SELECT CAST(0 AS BIT), N'ERRSSCC01',
                   NULL,
                   NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
                   NULL,NULL,NULL,NULL;
            RETURN;
        END

        ------------------------------------------------------------------
        -- 2) Already received?
        ------------------------------------------------------------------
        IF @received_inventory_id IS NOT NULL
        BEGIN
            ROLLBACK;
            SELECT CAST(0 AS BIT), N'ERRSSCC06',
                   @inbound_expected_unit_id,
                   @inbound_line_id,
                   @inbound_ref,
                   @header_status,
                   @line_state,
                   @sku_code,
                   @sku_description,
                   @expected_unit_qty,
                   @line_expected_qty,
                   @line_received_qty,
                   (@line_expected_qty - @line_received_qty),
                   (@line_expected_qty - @line_received_qty),
                   @batch_number,
                   @best_before_date,
                   NULL,NULL,NULL,NULL;
            RETURN;
        END

        ------------------------------------------------------------------
        -- 3) Header lifecycle check
        ------------------------------------------------------------------
        IF @header_status NOT IN ('ACT','RCV')
        BEGIN
            ROLLBACK;
            SELECT CAST(0 AS BIT), N'ERRINBL04',
                   @inbound_expected_unit_id,
                   @inbound_line_id,
                   @inbound_ref,
                   @header_status,
                   @line_state,
                   @sku_code,
                   @sku_description,
                   @expected_unit_qty,
                   @line_expected_qty,
                   @line_received_qty,
                   (@line_expected_qty - @line_received_qty),
                   (@line_expected_qty - @line_received_qty),
                   @batch_number,
                   @best_before_date,
                   NULL,NULL,NULL,NULL;
            RETURN;
        END

        ------------------------------------------------------------------
        -- 4) Claim logic
        ------------------------------------------------------------------
        DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

        -- Another-session active claim?
        IF @claimed_session_id IS NOT NULL
           AND @claim_expires_at IS NOT NULL
           AND @claim_expires_at > @now
           AND (@session_id IS NULL OR @claimed_session_id <> @session_id)
        BEGIN
            ROLLBACK;
            SELECT CAST(0 AS BIT), N'ERRSSCC07',
                   @inbound_expected_unit_id,
                   @inbound_line_id,
                   @inbound_ref,
                   @header_status,
                   @line_state,
                   @sku_code,
                   @sku_description,
                   @expected_unit_qty,
                   @line_expected_qty,
                   @line_received_qty,
                   (@line_expected_qty - @line_received_qty),
                   (@line_expected_qty - @line_received_qty - @expected_unit_qty),
                   @batch_number,
                   @best_before_date,
                   @claimed_session_id, @claimed_by_user_id, @claim_expires_at, @claim_token;
            RETURN;
        END

        -- Same-session active claim already valid? Treat as success; no rewrite required.
        IF @session_id IS NOT NULL
           AND @claimed_session_id = @session_id
           AND @claim_expires_at IS NOT NULL
           AND @claim_expires_at > @now
           AND @claim_token IS NOT NULL
        BEGIN
            COMMIT;

            SET @success = 1;
            SET @result_code = N'SUCSSCC01';

            SELECT
                @success,
                @result_code,
                @inbound_expected_unit_id,
                @inbound_line_id,
                @inbound_ref,
                @header_status,
                @line_state,
                @sku_code,
                @sku_description,
                @expected_unit_qty,
                @line_expected_qty,
                @line_received_qty,
                (@line_expected_qty - @line_received_qty),
                (@line_expected_qty - @line_received_qty - @expected_unit_qty),
                @batch_number,
                @best_before_date,
                @claimed_session_id,
                @claimed_by_user_id,
                @claim_expires_at,
                @claim_token;
            RETURN;
        END

        -- (re)claim for this session if we have one
        IF @session_id IS NOT NULL
        BEGIN
            -- ✅ Transition check: current expected unit state -> CLM must be allowed
            IF NOT EXISTS
            (
                SELECT 1
                FROM deliveries.inbound_expected_unit_state_transitions t
                WHERE t.from_state_code = @expected_unit_state
                  AND t.to_state_code   = 'CLM'
            )
            BEGIN
                ROLLBACK;
                SELECT CAST(0 AS BIT), N'ERRSSCCSTATE01',
                       @inbound_expected_unit_id,
                       @inbound_line_id,
                       @inbound_ref,
                       @header_status,
                       @line_state,
                       @sku_code,
                       @sku_description,
                       @expected_unit_qty,
                       @line_expected_qty,
                       @line_received_qty,
                       (@line_expected_qty - @line_received_qty),
                       (@line_expected_qty - @line_received_qty),
                       @batch_number,
                       @best_before_date,
                       NULL,NULL,NULL,NULL;
                RETURN;
            END

            SET @claim_token      = NEWID();
            SET @claim_expires_at = DATEADD(SECOND, @ttl_seconds, @now);

            UPDATE deliveries.inbound_expected_units
            SET expected_unit_state_code = 'CLM',
                claimed_session_id       = @session_id,
                claimed_by_user_id       = @user_id,
                claimed_at               = @now,
                claim_expires_at         = @claim_expires_at,
                claim_token              = @claim_token
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id
              AND received_inventory_unit_id IS NULL;
        END

        COMMIT;

        ------------------------------------------------------------------
        -- 5) Valid preview
        ------------------------------------------------------------------
        SET @success = 1;
        SET @result_code = N'SUCSSCC01';

        SELECT
            @success,
            @result_code,
            @inbound_expected_unit_id,
            @inbound_line_id,
            @inbound_ref,
            @header_status,
            @line_state,
            @sku_code,
            @sku_description,
            @expected_unit_qty,
            @line_expected_qty,
            @line_received_qty,
            (@line_expected_qty - @line_received_qty),
            (@line_expected_qty - @line_received_qty - @expected_unit_qty),
            @batch_number,
            @best_before_date,
            @session_id AS claimed_session_id,
            @user_id    AS claimed_by_user_id,
            @claim_expires_at,
            @claim_token;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @err_no   INT = ERROR_NUMBER();
        DECLARE @err_line INT = ERROR_LINE();
        DECLARE @err_msg  NVARCHAR(2048) = ERROR_MESSAGE();

        -- Contract columns 0-19 unchanged; debug extras start at 20+
        SELECT
            CAST(0 AS BIT)      AS success,
            N'ERRSSCC99'        AS result_code,

            NULL AS inbound_expected_unit_id,
            NULL AS inbound_line_id,
            NULL AS inbound_ref,
            NULL AS header_status,
            NULL AS line_state,
            NULL AS sku_code,
            NULL AS sku_description,
            NULL AS expected_unit_qty,
            NULL AS line_expected_qty,
            NULL AS line_received_qty,
            NULL AS outstanding_before,
            NULL AS outstanding_after,
            NULL AS batch_number,
            NULL AS best_before_date,
            NULL AS claimed_session_id,
            NULL AS claimed_by_user_id,
            NULL AS claim_expires_at,
            NULL AS claim_token,

            @err_no   AS debug_error_number,
            @err_line AS debug_error_line,
            @err_msg  AS debug_error_message;
    END CATCH
END;
GO

/********************************************************************************************
    SECTION: Inbound Structural Guards
    Purpose : Prevent structural modification after activation
              - Inbound lines cannot be inserted/updated/deleted once ACT+
              - Expected units cannot be inserted/updated/deleted once ACT+
              - Inbound mode cannot be changed once set
********************************************************************************************/
GO


/* =========================================================================================
   Trigger: deliveries.trg_inbound_lines_guard
   Blocks modification of inbound lines after activation
========================================================================================= */
CREATE OR ALTER TRIGGER deliveries.trg_inbound_lines_guard
ON deliveries.inbound_lines
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM deliveries.inbound_deliveries d
        JOIN (
            SELECT inbound_id FROM inserted
            UNION
            SELECT inbound_id FROM deleted
        ) x ON x.inbound_id = d.inbound_id
        WHERE d.inbound_status_code <> 'EXP'
    )
    BEGIN
        THROW 50001, 'ERRINBSTRUCT01', 1;
    END
END;
GO


/********************************************************************************************
    SECTION: Inbound Structural Guards (Operationally-aware)
    Purpose : Prevent structural modification after activation while allowing operational flow
              - Inbound lines:
                    * Block INSERT/DELETE once ACT+
                    * Allow UPDATE only for receiving progression (received_qty, line_state_code, updated_*)
              - Expected units:
                    * Block INSERT/DELETE once ACT+
                    * Allow UPDATE only for claim/receive fields + expected_unit_state_code transitions
              - Inbound mode:
                    * Prevent inbound_mode_code from being changed once set
********************************************************************************************/
GO

/* =========================================================================================
   Trigger: deliveries.trg_inbound_lines_guard
   Blocks structural modification of inbound lines after activation.
   Allows operational updates (receiving progression) in ACT/RCV.
========================================================================================= */
CREATE OR ALTER TRIGGER deliveries.trg_inbound_lines_guard
ON deliveries.inbound_lines
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------
    -- 1) Block INSERT or DELETE after activation
    ---------------------------------------------------------------------
    IF (
           (EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted))
        OR (EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted))
       )
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_deliveries d
            JOIN deliveries.inbound_lines l
                ON l.inbound_id = d.inbound_id
            WHERE l.inbound_line_id IN
            (
                SELECT inbound_line_id FROM inserted
                UNION
                SELECT inbound_line_id FROM deleted
            )
              AND d.inbound_status_code <> 'EXP'
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END

        RETURN;
    END

    ---------------------------------------------------------------------
    -- 2) UPDATE case – allow operational fields only
    ---------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM deliveries.inbound_deliveries d
        JOIN deliveries.inbound_lines l
            ON l.inbound_id = d.inbound_id
        WHERE l.inbound_line_id IN
        (
            SELECT inbound_line_id FROM inserted
            UNION
            SELECT inbound_line_id FROM deleted
        )
          AND d.inbound_status_code <> 'EXP'
    )
    BEGIN
        -- Block structural changes
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_line_id = i.inbound_line_id
            WHERE
                ISNULL(i.inbound_id,0) <> ISNULL(d.inbound_id,0)
             OR ISNULL(i.line_no,0) <> ISNULL(d.line_no,0)
             OR ISNULL(i.sku_id,0) <> ISNULL(d.sku_id,0)
             OR ISNULL(i.expected_qty,0) <> ISNULL(d.expected_qty,0)
             OR ISNULL(i.batch_number,'') <> ISNULL(d.batch_number,'')
             OR ISNULL(i.best_before_date,'19000101') <> ISNULL(d.best_before_date,'19000101')
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END

        -- Enforce allowed line state transitions
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_line_id = i.inbound_line_id
            WHERE ISNULL(i.line_state_code,'') <> ISNULL(d.line_state_code,'')
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM deliveries.inbound_line_state_transitions t
                  WHERE t.from_state_code = d.line_state_code
                    AND t.to_state_code   = i.line_state_code
              )
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END
    END
END;
GO

/* =========================================================================================
   Trigger: deliveries.trg_inbound_expected_units_guard
   Blocks structural modification of expected units after activation.
   Allows operational claim/receive updates in ACT/RCV/CLS, enforcing allowed transitions.
========================================================================================= */
CREATE OR ALTER TRIGGER deliveries.trg_inbound_expected_units_guard
ON deliveries.inbound_expected_units
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------
    -- 1) Block INSERT or DELETE after activation
    ---------------------------------------------------------------------
    IF (
           (EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted))
        OR (EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted))
       )
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_deliveries d
            JOIN deliveries.inbound_lines l
                ON l.inbound_id = d.inbound_id
            WHERE l.inbound_line_id IN
            (
                SELECT inbound_line_id FROM inserted
                UNION
                SELECT inbound_line_id FROM deleted
            )
              AND d.inbound_status_code <> 'EXP'
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END

        RETURN;
    END

    ---------------------------------------------------------------------
    -- 2) UPDATE case – allow claim/receive fields only
    ---------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM deliveries.inbound_deliveries d
        JOIN deliveries.inbound_lines l
            ON l.inbound_id = d.inbound_id
        WHERE l.inbound_line_id IN
        (
            SELECT inbound_line_id FROM inserted
            UNION
            SELECT inbound_line_id FROM deleted
        )
          AND d.inbound_status_code <> 'EXP'
    )
    BEGIN
        -- Block structural column changes
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_expected_unit_id = i.inbound_expected_unit_id
            WHERE
                ISNULL(i.inbound_line_id,0) <> ISNULL(d.inbound_line_id,0)
             OR ISNULL(i.expected_external_ref,'') <> ISNULL(d.expected_external_ref,'')
             OR ISNULL(i.expected_quantity,0) <> ISNULL(d.expected_quantity,0)
             OR ISNULL(i.batch_number,'') <> ISNULL(d.batch_number,'')
             OR ISNULL(i.best_before_date,'19000101') <> ISNULL(d.best_before_date,'19000101')
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END

        -- Enforce allowed expected unit state transitions
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_expected_unit_id = i.inbound_expected_unit_id
            WHERE ISNULL(i.expected_unit_state_code,'') <> ISNULL(d.expected_unit_state_code,'')
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM deliveries.inbound_expected_unit_state_transitions t
                  WHERE t.from_state_code = d.expected_unit_state_code
                    AND t.to_state_code   = i.expected_unit_state_code
              )
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END
    END
END;
GO


/* =========================================================================================
   Trigger: deliveries.trg_inbound_mode_guard
   Prevents inbound_mode_code from being changed once set
========================================================================================= */
CREATE OR ALTER TRIGGER deliveries.trg_inbound_mode_guard
ON deliveries.inbound_deliveries
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.inbound_id = i.inbound_id
        WHERE d.inbound_mode_code IS NOT NULL
          AND i.inbound_mode_code <> d.inbound_mode_code
    )
    BEGIN
        THROW 50001, 'ERRINBMODE01', 1;
    END
END;
GO

CREATE INDEX IX_inbexp_outstanding
ON deliveries.inbound_expected_units(expected_external_ref)
WHERE received_inventory_unit_id IS NULL;


/* ============================================================
   warehouse.warehouse_tasks
   ------------------------------------------------------------
   Operational work instructions for warehouse movements.
   One row = one actionable task for an operator.
   ============================================================ */

CREATE TABLE warehouse.warehouse_tasks
(
    task_id                 INT IDENTITY(1,1) PRIMARY KEY,

    -- Task classification
    task_type_code          NVARCHAR(20) NOT NULL,   -- PUTAWAY, MOVE, PICK

    -- Object being moved
    inventory_unit_id       INT NOT NULL,

    -- Movement context
    source_bin_id           INT NULL,
    destination_bin_id      INT NULL,

    -- Task lifecycle
    task_state_code         VARCHAR(3) NOT NULL DEFAULT 'OPN', -- OPN, CLM, CNF, CNL, EXP

    -- Assignment
    claimed_by_user_id      INT NULL,
    claimed_session_id      UNIQUEIDENTIFIER NULL,

    claimed_at              DATETIME2(3) NULL,
    expires_at              DATETIME2(3) NULL,

    -- Completion
    completed_at            DATETIME2(3) NULL,
    completed_by_user_id    INT NULL,

    -- Audit
    created_at              DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by              INT NULL,
    updated_at              DATETIME2(3) NULL,
    updated_by              INT NULL,

    CONSTRAINT fk_tasks_inventory_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT fk_tasks_source_bin
        FOREIGN KEY (source_bin_id)
        REFERENCES locations.bins(bin_id),

    CONSTRAINT fk_tasks_destination_bin
        FOREIGN KEY (destination_bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_tasks_state
ON warehouse.warehouse_tasks (task_state_code);

CREATE INDEX IX_tasks_inventory
ON warehouse.warehouse_tasks (inventory_unit_id);

CREATE INDEX IX_tasks_expiry
ON warehouse.warehouse_tasks (expires_at);

/* ============================================================
   warehouse.task_states
   ------------------------------------------------------------
   Canonical lifecycle states for warehouse tasks.
   ============================================================ */
CREATE TABLE warehouse.task_states
(
    state_code      VARCHAR(3) NOT NULL PRIMARY KEY,
    state_desc      NVARCHAR(30) NOT NULL,
    is_terminal     BIT NOT NULL DEFAULT 0
);

INSERT INTO warehouse.task_states (state_code, state_desc, is_terminal)
VALUES
('OPN','OPEN',0),
('CLM','CLAIMED',0),
('CNF','CONFIRMED',1),
('EXP','EXPIRED',1),
('CNL','CANCELLED',1);

/* ============================================================
   warehouse.task_state_transitions
   ------------------------------------------------------------
   Defines legal transitions between task lifecycle states.
   ============================================================ */
CREATE TABLE warehouse.task_state_transitions
(
    from_state_code    VARCHAR(3) NOT NULL,
    to_state_code      VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT 0,
    notes              NVARCHAR(200) NULL,

    PRIMARY KEY (from_state_code, to_state_code),

    FOREIGN KEY (from_state_code)
        REFERENCES warehouse.task_states(state_code),

    FOREIGN KEY (to_state_code)
        REFERENCES warehouse.task_states(state_code)
);

INSERT INTO warehouse.task_state_transitions
VALUES
('OPN','CLM',0,'Operator claims task'),
('OPN','CNL',1,'Task cancelled before claim'),

('CLM','CNF',0,'Task completed'),
('CLM','EXP',0,'Task expired due to TTL'),
('CLM','CNL',1,'Supervisor cancels task');

ALTER TABLE warehouse.warehouse_tasks
ADD CONSTRAINT fk_tasks_state
FOREIGN KEY (task_state_code)
REFERENCES warehouse.task_states(state_code);

CREATE UNIQUE INDEX UX_tasks_open_unit
ON warehouse.warehouse_tasks (inventory_unit_id)
WHERE task_state_code IN ('OPN','CLM');


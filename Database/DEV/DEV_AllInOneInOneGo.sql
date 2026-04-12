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
-- 3.1 Settings categories table
-- Central runtime configuration registry
-------------------------------------------
CREATE TABLE operations.setting_categories
(
    category        sysname        NOT NULL PRIMARY KEY,
    display_name    nvarchar(100)  NOT NULL,
    display_order   int            NOT NULL
);

INSERT INTO operations.setting_categories (category, display_name, display_order)
VALUES
('core','Core',10),
('auth','Authentication',20),
('inbound','Inbound',30),
('warehouse','Warehouse',40),
('logging','Logging',50),
('audit','Audit',60),
('client','Client',70);

-------------------------------------------
-- 3.2 Settings table
-- Central runtime configuration registry
-------------------------------------------
IF OBJECT_ID('operations.settings', 'U') IS NULL
BEGIN
    CREATE TABLE operations.settings
    (
        --------------------------------------------------
        -- Identity
        --------------------------------------------------

        setting_name        sysname            NOT NULL
            CONSTRAINT PK_operations_settings PRIMARY KEY,
        -- Internal key used by the application

        display_name        nvarchar(200)      NOT NULL,
        -- Human-readable label used in UI

        category            varchar(50)        NOT NULL
            CONSTRAINT DF_operations_settings_category DEFAULT ('general'),
        -- Logical grouping (auth, logging, inbound, pw, etc.)

        display_order       int                NOT NULL
            CONSTRAINT DF_operations_settings_display_order DEFAULT (100),
        -- Determines ordering within category in the UI

        --------------------------------------------------
        -- Value
        --------------------------------------------------

        setting_value       nvarchar(4000)     NULL,

        data_type           varchar(20)        NOT NULL
            CONSTRAINT CK_operations_settings_data_type
            CHECK (data_type IN ('string','int','bool','decimal','json')),

        --------------------------------------------------
        -- Validation rules (JSON metadata)
        --------------------------------------------------

        validation_rule     nvarchar(max)      NULL,
        /*
            JSON rule describing allowed values.

            Examples:

            {"type":"bool"}

            {"type":"enum","values":["TRACE","DEBUG","INFO","WARN","ERROR"]}

            {"type":"range","min":5,"max":240}

            {"type":"regex","pattern":"^[A-Z]{3}$"}
        */

        --------------------------------------------------
        -- Metadata
        --------------------------------------------------

        description         nvarchar(500)      NULL,

        is_sensitive        bit                NOT NULL
            CONSTRAINT DF_operations_settings_is_sensitive DEFAULT (0),
        -- Prevents displaying actual values in UI

        requires_restart    bit                NOT NULL
            CONSTRAINT DF_operations_settings_requires_restart DEFAULT (0),
        -- Indicates application restart is required

        --------------------------------------------------
        -- Audit fields
        --------------------------------------------------

        created_at          datetime2(3)       NOT NULL
            CONSTRAINT DF_operations_settings_created_at
            DEFAULT sysutcdatetime(),

        created_by          int                NULL
            CONSTRAINT DF_operations_settings_created_by
            DEFAULT CONVERT(int, SESSION_CONTEXT(N'user_id')),

        updated_at          datetime2(3)       NULL,

        updated_by          int                NULL
    );
END;
GO

-------------------------------------------
-- 3.3 EVENTS TABLE
-- Audit trail.
-------------------------------------------
CREATE TABLE audit.audit_events
(
    audit_id        BIGINT IDENTITY PRIMARY KEY,
    occurred_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    correlation_id  UNIQUEIDENTIFIER NULL,
    user_id         INT NULL,
    session_id      UNIQUEIDENTIFIER NULL,
    event_name      NVARCHAR(200) NOT NULL,
    result_code     NVARCHAR(50) NOT NULL,
    success         BIT NOT NULL,
    payload_json    NVARCHAR(MAX) NULL
);

-- JSON integrity
ALTER TABLE audit.audit_events
ADD CONSTRAINT CK_audit_events_payload_json_valid
CHECK (payload_json IS NULL OR ISJSON(payload_json) = 1);

-- Prevent blanks
ALTER TABLE audit.audit_events
ADD CONSTRAINT CK_audit_events_event_name_not_blank
CHECK (LTRIM(RTRIM(event_name)) <> '');

ALTER TABLE audit.audit_events
ADD CONSTRAINT CK_audit_events_result_code_not_blank
CHECK (LTRIM(RTRIM(result_code)) <> '');

-- Indexes
CREATE NONCLUSTERED INDEX IX_audit_events_occurred_at
ON audit.audit_events (occurred_at DESC);

CREATE NONCLUSTERED INDEX IX_audit_events_correlation_time
ON audit.audit_events (correlation_id, occurred_at ASC);

CREATE NONCLUSTERED INDEX IX_audit_events_session_time
ON audit.audit_events (session_id, occurred_at ASC);

CREATE NONCLUSTERED INDEX IX_audit_events_user_time
ON audit.audit_events (user_id, occurred_at DESC);

CREATE NONCLUSTERED INDEX IX_audit_events_event_time
ON audit.audit_events (event_name, occurred_at DESC);



-- Helper macro style: Update if exists, otherwise insert.
-- Pattern used across all settings.

INSERT INTO operations.settings
(
    setting_name,
    display_name,
    category,
    display_order,
    setting_value,
    data_type,
    validation_rule,
    description
)
VALUES

--------------------------------------------------
-- CORE
--------------------------------------------------

('core.version','Core schema version','core',10,'1.0.0','string',
 NULL,
 'PeasyWare Core DB schema version'),

('core.environment','Environment','core',20,'dev','string',
 '{"type":"enum","values":["dev","test","prod"]}',
 'Environment type'),

('inbound.auto_complete_on_full_receipt','Auto-complete inbound','inbound',10,'false','bool',
 '{"type":"bool"}',
 'Auto-complete inbound header when all rows fully received'),

--------------------------------------------------
-- AUTHENTICATION
--------------------------------------------------

('auth.login_enabled','Login enabled','auth',10,'true','bool',
 '{"type":"bool"}',
 'Master switch to disable all user logins'),

('auth.session_timeout_minutes','Session timeout (minutes)','auth',20,'30','int',
 '{"type":"range","min":5,"max":240}',
 'Minutes before a session is force-closed by server inactivity'),

('auth.app_lock_minutes','Application lock timeout (minutes)','auth',30,'15','int',
 '{"type":"range","min":1,"max":120}',
 'Minutes of UI inactivity before client lockscreen'),

('auth.max_login_attempts','Maximum login attempts','auth',40,'5','int',
 '{"type":"range","min":3,"max":20}',
 'Maximum failed attempts before lockout escalation'),

('auth.password_min_length','Minimum password length','auth',50,'8','int',
 '{"type":"range","min":6,"max":64}',
 'Minimum password length enforced by policy'),

('auth.password_expiry_days','Password expiry (days)','auth',60,'90','int',
 '{"type":"range","min":30,"max":365}',
 'Password validity duration before required rotation'),

('auth.password_history_depth','Password history depth','auth',70,'3','int',
 '{"type":"range","min":0,"max":20}',
 'How many previous passwords are blocked from reuse'),

('auth.enable_login','Enable login','auth',80,'true','bool',
 '{"type":"bool"}',
 'Master switch to disable all user logins'),

('EnableAutoLogin','Enable auto login','auth',90,'true','bool',
 '{"type":"bool"}',
 'Allow client-side auto-login based on stored token'),

('SessionExpiryMinutes','Legacy session expiry (minutes)','auth',100,'60','int',
 '{"type":"range","min":10,"max":240}',
 'Legacy session timeout (deprecated)'),

--------------------------------------------------
-- INBOUND / WAREHOUSE
--------------------------------------------------

('inbound.sscc_claim_ttl_seconds','SSCC claim TTL (seconds)','inbound',20,'60','int',
 '{"type":"range","min":10,"max":300}',
 'Time-to-live (seconds) for SSCC claim during inbound receive confirmation window'),

('warehouse.putaway_task_ttl_seconds','Putaway task TTL (seconds)','warehouse',10,'600','int',
 '{"type":"range","min":60,"max":3600}',
 'Time-to-live (seconds) for putaway task reservations before they expire'),

--------------------------------------------------
-- LOGGING
--------------------------------------------------

('logging.enabled','Logging enabled','logging',10,'true','bool',
 '{"type":"bool"}',
 'Global master switch for all logging'),

('logging.console.enabled','Console logging enabled','logging',20,'true','bool',
 '{"type":"bool"}',
 'When enabled, logs are written to console output'),

('logging.min_level','Minimum log level','logging',30,'INFO','string',
 '{"type":"enum","values":["INFO","WARN","ERROR"]}',
 'Minimum log level to emit'),

('logging.db.enabled','Database logging enabled','logging',40,'true','bool',
 '{"type":"bool"}',
 'When enabled, logs are persisted to database'),

('logging.include_sensitive','Log sensitive fields','logging',50,'false','bool',
 '{"type":"bool"}',
 'Allows sensitive fields to be logged (DEV ONLY)'),

('receiving.ui_mode','Receiving UI mode','inbound',30,'TRACE','string',
 '{"type":"enum","values":["MINIMAL","TRACE"]}',
 'Receiving UI mode'),

--------------------------------------------------
-- AUDIT
--------------------------------------------------

('audit.enabled','Audit logging enabled','audit',10,'true','bool',
 '{"type":"bool"}',
 'When enabled, critical state transitions are persisted to audit.audit_events'),

--------------------------------------------------
-- CLIENT SETTINGS
--------------------------------------------------

('pw.warehouse_code','Warehouse code','client',10,'MAIN','string',
 NULL,
 'Warehouse code used by client runtime'),

('pw.site_code','Site code','client',20,'RUGBY','string',
 NULL,
 'Logical site identifier'),

('pw.site_name','Site name','client',30,'Test Warehouse 001','string',
 NULL,
 'Human-readable site name');

---------------------------------------------------------------
-- AUDIT: SETTINGS CHANGE LOG
---------------------------------------------------------------
IF OBJECT_ID('audit.setting_changes', 'U') IS NULL
BEGIN
    CREATE TABLE audit.setting_changes
    (
        change_id      BIGINT IDENTITY(1,1)
            CONSTRAINT PK_audit_setting_changes PRIMARY KEY,

        setting_name   NVARCHAR(200) NOT NULL,

        old_value      NVARCHAR(MAX) NULL,
        new_value      NVARCHAR(MAX) NULL,

        changed_at     DATETIME2(3) NOT NULL
            CONSTRAINT DF_audit_setting_changes_changed_at DEFAULT SYSUTCDATETIME(),

        changed_by     INT NULL,

        source_app     NVARCHAR(100) NULL,
        source_client  NVARCHAR(200) NULL,
        source_ip      NVARCHAR(50) NULL,

        correlation_id uniqueidentifier NULL,

        details        NVARCHAR(4000) NULL
    );

    CREATE INDEX IX_audit_setting_changes_setting_name
        ON audit.setting_changes(setting_name, changed_at DESC);
END;
GO

CREATE OR ALTER PROCEDURE audit.usp_log_event
(
    @correlation_id UNIQUEIDENTIFIER = NULL,
    @user_id        INT = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @event_name     NVARCHAR(200),
    @result_code    NVARCHAR(50),
    @success        BIT,
    @payload_json   NVARCHAR(MAX) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------
    -- Normalize input (trim only, no magic)
    --------------------------------------------------------

    SET @event_name  = LTRIM(RTRIM(@event_name));
    SET @result_code = LTRIM(RTRIM(@result_code));

    --------------------------------------------------------
    -- Validation
    --------------------------------------------------------

    IF @event_name IS NULL OR @event_name = ''
        THROW 50001, 'audit.usp_log_event: @event_name is required.', 1;

    IF @result_code IS NULL OR @result_code = ''
        THROW 50002, 'audit.usp_log_event: @result_code is required.', 1;

    IF @payload_json IS NOT NULL AND ISJSON(@payload_json) <> 1
        THROW 50003, 'audit.usp_log_event: @payload_json must be valid JSON.', 1;

    --------------------------------------------------------
    -- Insert (constraints enforce correctness)
    --------------------------------------------------------

    INSERT INTO audit.audit_events
    (
        occurred_at,
        correlation_id,
        user_id,
        session_id,
        event_name,
        result_code,
        success,
        payload_json
    )
    VALUES
    (
        SYSUTCDATETIME(),
        @correlation_id,
        @user_id,
        @session_id,
        @event_name,
        @result_code,
        @success,
        @payload_json
    );
END;
GO

CREATE OR ALTER PROCEDURE operations.usp_setting_update
(
    @setting_name  sysname,
    @setting_value nvarchar(4000),

    @result_code   nvarchar(20) OUTPUT,
    @friendly_msg  nvarchar(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @data_type nvarchar(50),
        @validation_rule nvarchar(max),

        -- audit
        @old_value nvarchar(4000),
        @user_id int,
        @session_id uniqueidentifier,
        @correlation_id uniqueidentifier,
        @source_app nvarchar(100),
        @source_client nvarchar(200),
        @source_ip nvarchar(50),

        -- raw context (defensive parsing)
        @session_id_raw nvarchar(100),
        @correlation_id_raw nvarchar(100);

    BEGIN TRY
        BEGIN TRANSACTION;

        --------------------------------------------------------
        -- Resolve metadata
        --------------------------------------------------------

        SELECT
            @data_type = data_type,
            @validation_rule = validation_rule,
            @old_value = setting_value
        FROM operations.settings
        WHERE setting_name = @setting_name;

        IF @data_type IS NULL
        BEGIN
            SET @result_code = 'ERRSET01';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Validation
        --------------------------------------------------------

        IF @data_type = 'int'
           AND TRY_CONVERT(int, @setting_value) IS NULL
        BEGIN
            SET @result_code = 'ERRSET02';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- SAFE session context resolution
        --------------------------------------------------------

        SELECT
            @session_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'session_id')),

            @correlation_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'correlation_id')),

            @user_id =
                TRY_CONVERT(int, SESSION_CONTEXT(N'user_id')),

            @source_app =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'source_app')),

            @source_client =
                TRY_CONVERT(nvarchar(200), SESSION_CONTEXT(N'source_client')),

            @source_ip =
                TRY_CONVERT(nvarchar(50), SESSION_CONTEXT(N'source_ip'));

        SET @session_id =
            TRY_CONVERT(uniqueidentifier, @session_id_raw);

        SET @correlation_id =
            TRY_CONVERT(uniqueidentifier, @correlation_id_raw);

        --------------------------------------------------------
        -- HARD GUARD
        --------------------------------------------------------

        IF @session_id IS NULL OR @user_id IS NULL
        BEGIN
            SET @result_code = 'ERRCTX01';
            SET @friendly_msg = 'Invalid or missing session context';
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Update
        --------------------------------------------------------

        UPDATE operations.settings
        SET
            setting_value = @setting_value,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        WHERE setting_name = @setting_name;

        --------------------------------------------------------
        -- Structured audit
        --------------------------------------------------------

        INSERT INTO audit.setting_changes
        (
            setting_name,
            old_value,
            new_value,
            changed_at,
            changed_by,
            source_app,
            source_client,
            source_ip,
            correlation_id
        )
        VALUES
        (
            @setting_name,
            @old_value,
            @setting_value,
            SYSUTCDATETIME(),
            @user_id,
            @source_app,
            @source_client,
            @source_ip,
            @correlation_id
        );

        --------------------------------------------------------
        -- Event audit
        --------------------------------------------------------

        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @setting_name  AS SettingName,
                @old_value     AS OldValue,
                @setting_value AS NewValue
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.setting.updated',
            @result_code    = 'SUCCESS',
            @success        = 1,
            @payload_json   = @payload_json;

        COMMIT;

        SET @result_code = 'SUCSET01';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        --------------------------------------------------------
        -- Capture error FIRST (this was missing)
        --------------------------------------------------------

        DECLARE @error nvarchar(4000) = ERROR_MESSAGE();

        DECLARE @payload_json_error NVARCHAR(MAX);

        SET @payload_json_error = (
            SELECT
                @error AS ErrorMessage,
                ERROR_NUMBER() AS ErrorNumber,
                ERROR_LINE() AS ErrorLine
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRSET99';
        SET @friendly_msg = 'Unexpected error occurred while updating setting.';
    END CATCH
END
GO

-------------------------------------------
-- 3.4 Error messages (friendly messages)
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
            N'Task.Confirm: putaway confirmed'),

        (N'ERRSET01', N'SET', N'ERROR',
            N'Setting not found.',
            N'Settings.Update: requested setting does not exist'),

        (N'ERRSET02', N'SET', N'ERROR',
            N'The provided value is not valid for this setting type.',
            N'Settings.Update: data type validation failed'),

        (N'ERRSET03', N'SET', N'ERROR',
            N'The value is not allowed for this setting.',
            N'Settings.Update: value not in allowed_values list'),

        (N'ERRSET04', N'SET', N'ERROR',
            N'The value is outside the permitted range.',
            N'Settings.Update: numeric range validation failed'),

        (N'SUCSET01', N'SET', N'SUCCESS',
            N'Setting updated successfully.',
            N'Settings.Update: value persisted'),

        (N'SUCTASK01', N'TASK', N'SUCCESS',
        N'Putaway task created. Please move stock to the suggested location.',
        N'Task.Create: task created and destination bin reserved'),

        (N'ERRTASK08', N'TASK', N'ERROR',
            N'Wrong location. Please move the stock to {0}.',
            N'Task.Confirm: scanned bin does not match reserved destination'),

        (N'ERRTASK09', N'TASK', N'ERROR',
            N'The suggested location is no longer available. Please request a new suggestion.',
            N'Task.Confirm: destination bin capacity exceeded or bin inactive at confirm time');

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
    @correlation_id     UNIQUEIDENTIFIER = NULL,

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

CREATE OR ALTER PROCEDURE auth.usp_logout
(
    @session_id      UNIQUEIDENTIFIER,
    @source_app      NVARCHAR(50),
    @source_client   NVARCHAR(200),
    @source_ip       NVARCHAR(50) = NULL,
    @correlation_id  UNIQUEIDENTIFIER = NULL,

    @result_code     NVARCHAR(20) OUTPUT,
    @friendly_msg    NVARCHAR(400) OUTPUT,
    @success         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @success = 0;
    SET @result_code = NULL;
    SET @friendly_msg = NULL;

    DECLARE
        @actor_id        INT = TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        @ctx_session_id  UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER),
        @corr_id         UNIQUEIDENTIFIER = COALESCE(@correlation_id, TRY_CAST(SESSION_CONTEXT(N'correlation_id') AS UNIQUEIDENTIFIER)),
        @now             DATETIME2(3) = SYSUTCDATETIME(),

        @session_status  NVARCHAR(20),
        @transition_code NVARCHAR(20),
        @transition_msg  NVARCHAR(400),
        @details         NVARCHAR(MAX);

    BEGIN TRY

        --------------------------------------------------------
        -- Fetch current status
        --------------------------------------------------------
        SELECT @session_status = session_status
        FROM auth.user_sessions
        WHERE session_id = @session_id;

        --------------------------------------------------------
        -- Not found
        --------------------------------------------------------
        IF @session_status IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH06';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Idempotent success
        --------------------------------------------------------
        IF @session_status IN ('LOGGED_OUT', 'EXPIRED', 'REVOKED')
        BEGIN
            SET @result_code = 'SUCAUTH03';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            SET @success = 1;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Build details payload (for transition)
        --------------------------------------------------------
        SET @details = (
            SELECT
                @corr_id AS correlation_id,
                'user logout' AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Perform transition
        --------------------------------------------------------
        EXEC auth.usp_session_set_status
            @session_id     = @session_id,
            @to_status      = 'LOGGED_OUT',
            @source_app     = @source_app,
            @source_client  = @source_client,
            @source_ip      = @source_ip,
            @details        = @details,
            @result_code    = @transition_code OUTPUT,
            @friendly_msg   = @transition_msg OUTPUT;

        --------------------------------------------------------
        -- Final response
        --------------------------------------------------------
        IF @transition_code LIKE 'SUC%'
        BEGIN
            SET @result_code = 'SUCAUTH03';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            SET @success = 1;
        END
        ELSE
        BEGIN
            SET @result_code  = @transition_code;
            SET @friendly_msg = @transition_msg;
            SET @success = 0;
        END;

LogAndExit:

        --------------------------------------------------------
        -- Payload
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @actor_id    AS PerformedBy,
                @session_id  AS TargetSessionId,
                @session_status AS PreviousStatus,
                @result_code AS ResultCode
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Mapping
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
            @correlation_id = @corr_id,
            @user_id        = @actor_id,
            @session_id     = @ctx_session_id,
            @event_name     = 'session.logout',
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
                @session_id AS TargetSessionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @corr_id,
            @user_id        = @actor_id,
            @session_id     = @ctx_session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

        SET @success = 0;

    END CATCH;
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

CREATE OR ALTER VIEW operations.v_settings
AS
SELECT
    s.setting_name,
    s.display_name,
    s.category,
    c.display_name AS category_name,
    c.display_order AS category_order,
    s.display_order,

    s.setting_value,
    s.data_type,
    s.validation_rule,
    s.description,
    s.is_sensitive,
    s.requires_restart,

    s.created_at,
    s.created_by,
    s.updated_at,
    s.updated_by,
    u.username AS updated_by_username,

    CASE WHEN s.data_type = 'bool' THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS is_boolean,

    CASE WHEN JSON_VALUE(s.validation_rule,'$.type') = 'enum'
         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS is_enum,

    CASE WHEN JSON_VALUE(s.validation_rule,'$.type') = 'range'
         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS is_range,

    TRY_CONVERT(int, JSON_VALUE(s.validation_rule,'$.min')) AS range_min,
    TRY_CONVERT(int, JSON_VALUE(s.validation_rule,'$.max')) AS range_max

FROM operations.settings s
LEFT JOIN operations.setting_categories c
    ON s.category = c.category
LEFT JOIN auth.users u
    ON s.updated_by = u.id;

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

    DECLARE
        @actor          INT = TRY_CONVERT(INT, SESSION_CONTEXT(N'user_id')),
        @session_id     UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'session_id')),
        @correlation_id UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'correlation_id')),
        @now            DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY

        --------------------------------------------------------
        -- Validate target user
        --------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM auth.users
            WHERE id = @user_id
        )
        BEGIN
            SET @result_code = 'ERRUSR01';

            SELECT @friendly_msg = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Perform update
        --------------------------------------------------------
        UPDATE auth.users
        SET
            is_active   = @is_active,
            updated_at  = @now,
            updated_by  = @actor
        WHERE id = @user_id;

        --------------------------------------------------------
        -- Success
        --------------------------------------------------------
        SET @result_code = 'SUCUSR01';

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
                @actor       AS PerformedBy,
                @user_id     AS TargetUserId,
                @is_active   AS IsActive,
                @result_code AS ResultCode
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
            @event_name     = 'user.status.updated',
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
                @user_id AS TargetUserId
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

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_msg = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

    END CATCH;
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
        @username        NVARCHAR(100),
        @actor_id        INT = TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        @session_id      UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER),
        @correlation_id  UNIQUEIDENTIFIER = TRY_CAST(SESSION_CONTEXT(N'correlation_id') AS UNIQUEIDENTIFIER),
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY

        --------------------------------------------------------
        -- Resolve target user
        --------------------------------------------------------
        SELECT @username = u.username
        FROM auth.users u
        WHERE u.id = @target_user_id;

        IF @username IS NULL
        BEGIN
            SET @result_code = 'ERRAUTH02';

            SELECT @friendly_message = message_template
            FROM operations.error_messages
            WHERE error_code = @result_code;

            GOTO LogAndExit;
        END;

        --------------------------------------------------------
        -- Delegate to core password change
        --------------------------------------------------------
        EXEC auth.usp_change_password
            @username         = @username,
            @new_password     = @new_password,
            @result_code      = @result_code OUTPUT,
            @friendly_message = @friendly_message OUTPUT;

        --------------------------------------------------------
        -- Admin override
        --------------------------------------------------------
        IF @result_code LIKE 'SUC%'
        BEGIN
            UPDATE auth.users
            SET must_change_password = 1
            WHERE id = @target_user_id;
        END;

LogAndExit:

        --------------------------------------------------------
        -- Payload
        --------------------------------------------------------
        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @actor_id       AS PerformedBy,
                @target_user_id AS TargetUserId,
                @username       AS Username,
                @result_code    AS ResultCode
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        --------------------------------------------------------
        -- Mapping
        --------------------------------------------------------
        DECLARE @event_result_code NVARCHAR(50);
        DECLARE @event_success BIT;

        SELECT
            @event_result_code = m.event_result_code,
            @event_success     = m.event_success
        FROM audit.fn_map_user_result(@result_code) m;

        --------------------------------------------------------
        -- Audit (single source of truth)
        --------------------------------------------------------
        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @actor_id,
            @session_id     = @session_id,
            @event_name     = 'user.password.reset',
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
                @target_user_id AS TargetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @actor_id,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRPROC02';

        SELECT @friendly_message = message_template
        FROM operations.error_messages
        WHERE error_code = @result_code;

    END CATCH;
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
    updated_at          DATETIME2(3) NULL,
    updated_by          INT NULL,

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
('ACT','CNL',1),
('CLS', 'RCV', 1);



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
WHERE d.inbound_status_code IN ('EXP','ACT','RCV')
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
WHERE d.inbound_status_code IN ('EXP','ACT','RCV')
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
('PRC','CNL',1),
('RCV', 'PRC', 1),
('RCV', 'EXP', 1);
GO

CREATE TABLE deliveries.inbound_lines
(
    inbound_line_id     INT IDENTITY(1,1) PRIMARY KEY,
    inbound_id          INT NOT NULL,
    line_no             INT NOT NULL,

    sku_id              INT NOT NULL,
    expected_qty        INT NOT NULL CHECK (expected_qty > 0),
    received_qty        INT NOT NULL DEFAULT (0),

    arrival_stock_status_code VARCHAR(2) NOT NULL DEFAULT 'AV',
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
        CHECK (received_qty <= expected_qty),

    CONSTRAINT FK_inbound_lines_arrival_status
        FOREIGN KEY (arrival_stock_status_code)
        REFERENCES inventory.stock_statuses(status_code)
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
    ('EXP','RCV',1),  -- optional: admin force receive without claim (usually NO; keep as 1)
    ('RCV', 'EXP', 1)
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

USE PW_Core_DEV;
GO

/* ============================================================
   View: deliveries.vw_inbounds_activatable
   ------------------------------------------------------------
   Returns inbound deliveries eligible for activation.

   Criteria:
   - Status = 'EXP' (Expected — not yet activated)
   - Has at least one inbound line
   
   Used by:
   - CLI: ActivateInboundScreen.RenderList()
   - Application: IInboundQueryRepository.GetActivatableInbounds()

   Columns match SqlInboundQueryRepository.GetActivatableInbounds()
   ordinal read: inbound_id(0), inbound_ref(1),
                 expected_arrival_at(2), line_count(3)
   ============================================================ */
CREATE OR ALTER VIEW deliveries.vw_inbounds_activatable
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at,
    COUNT(l.inbound_line_id)  AS line_count

FROM deliveries.inbound_deliveries d
JOIN deliveries.inbound_lines l
    ON l.inbound_id = d.inbound_id

WHERE d.inbound_status_code = 'EXP'

GROUP BY
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at;
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

CREATE OR ALTER PROCEDURE deliveries.usp_receive_inbound_line
(
    -- Manual mode
    @inbound_line_id            INT = NULL,
    @received_qty               INT = NULL,

    @staging_bin_code           NVARCHAR(100),

    -- SSCC mode
    @inbound_expected_unit_id   INT = NULL,
    @claim_token                UNIQUEIDENTIFIER = NULL,

    -- Optional fields
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

    DECLARE @is_closed BIT = 0;

    BEGIN TRY
        BEGIN TRAN;

        /* -------------------------------------------------------- */
        /* 1) Validate staging bin                                  */
        /* -------------------------------------------------------- */
        IF NULLIF(LTRIM(RTRIM(@staging_bin_code)), N'') IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL07', NULL, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

        /* -------------------------------------------------------- */
        /* 2) Determine mode                                        */
        /* -------------------------------------------------------- */
        DECLARE @is_sscc_mode BIT =
            CASE WHEN @inbound_expected_unit_id IS NOT NULL THEN 1 ELSE 0 END;

        DECLARE
            @resolved_line_id      INT = NULL,
            @sku_id                INT = NULL,
            @inbound_id            INT = NULL,
            @expected_qty          INT = NULL,
            @already_received      INT = NULL,
            @line_state            VARCHAR(3),
            @header_status         VARCHAR(3),
            @expected_unit_qty     INT,
            @existing_received_id  INT,
            @now                   DATETIME2(3) = SYSUTCDATETIME(),
            @claim_expires_at      DATETIME2(3),
            @db_claim_token        UNIQUEIDENTIFIER,
            @claimed_session_id    UNIQUEIDENTIFIER,
            @new_received_qty      INT,
            @new_line_state        VARCHAR(3),
            @receipt_id            INT,
            @arrival_status_code   VARCHAR(2); 

        /* ======================================================== */
        /* SSCC MODE                                                */
        /* ======================================================== */
        IF @is_sscc_mode = 1
        BEGIN
            IF @session_id IS NULL OR @claim_token IS NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRPROC02', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

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
                SELECT CAST(0 AS BIT), N'ERRSSCC01', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

            IF @existing_received_id IS NOT NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC06', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

            IF @claim_expires_at IS NOT NULL AND @claim_expires_at <= @now
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC08', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

            IF @claimed_session_id <> @session_id
               OR @db_claim_token <> @claim_token
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRSSCC08', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

            SET @received_qty = @expected_unit_qty;
        END
        ELSE
        BEGIN
            SET @resolved_line_id = @inbound_line_id;

            IF @resolved_line_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRINBL01', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END

            IF @received_qty IS NULL OR @received_qty <= 0
            BEGIN
                SELECT CAST(0 AS BIT), N'ERRINBL06', NULL, NULL, NULL;
                ROLLBACK;
                RETURN;
            END
        END

        /* -------------------------------------------------------- */
        /* 3) Resolve line                                          */
        /* -------------------------------------------------------- */
        SELECT
            @sku_id           = l.sku_id,
            @inbound_id       = l.inbound_id,
            @expected_qty     = l.expected_qty,
            @already_received = ISNULL(l.received_qty, 0),
            @line_state       = l.line_state_code,
            @arrival_status_code  = l.arrival_stock_status_code 
        FROM deliveries.inbound_lines l WITH (UPDLOCK, HOLDLOCK)
        WHERE l.inbound_line_id = @resolved_line_id;

        IF (@already_received + @received_qty) > @expected_qty
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL02', NULL, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

        /* -------------------------------------------------------- */
        /* 4) Create inventory unit                                 */
        /* -------------------------------------------------------- */
        DECLARE @inventory_unit_id INT;

        INSERT INTO inventory.inventory_units
        (
            sku_id, external_ref, batch_number, best_before_date,
            quantity, stock_state_code, stock_status_code,
            created_at, created_by
        )
        VALUES
        (
            @sku_id, @external_ref, @batch_number, @best_before_date,
            @received_qty, 'RCD', @arrival_status_code,
            SYSUTCDATETIME(), @user_id
        );

        SET @inventory_unit_id = SCOPE_IDENTITY();

        /* -------------------------------------------------------- */
        /* 4b) Place unit in staging bin                            */
        /* -------------------------------------------------------- */
        DECLARE @staging_bin_id INT;

        SELECT @staging_bin_id = bin_id
        FROM locations.bins
        WHERE bin_code = @staging_bin_code
          AND is_active = 1;

        IF @staging_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL08', NULL, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

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

        /* -------------------------------------------------------- */
        /* 5) Update expected unit                                  */
        /* -------------------------------------------------------- */
        IF @is_sscc_mode = 1
        BEGIN
            UPDATE deliveries.inbound_expected_units
            SET received_inventory_unit_id = @inventory_unit_id,
                expected_unit_state_code   = 'RCV'
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id;
        END

        /* -------------------------------------------------------- */
        /* 6) Update line                                           */
        /* -------------------------------------------------------- */
        SET @new_received_qty = @already_received + @received_qty;

        SET @new_line_state =
            CASE
                WHEN @new_received_qty < @expected_qty THEN 'PRC'
                ELSE 'RCV'
            END;

        UPDATE deliveries.inbound_lines
        SET
            received_qty    = @new_received_qty,
            line_state_code = @new_line_state,
            updated_at      = SYSUTCDATETIME(),
            updated_by      = @user_id
        WHERE inbound_line_id = @resolved_line_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBL_UPDATE_MISS', @resolved_line_id, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

        /* -------------------------------------------------------- */
        /* 6.5) Receipt record (CRITICAL TRACEABILITY)              */
        /* -------------------------------------------------------- */
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

        SET @receipt_id = SCOPE_IDENTITY();

        /* -------------------------------------------------------- */
        /* 6.6) Movement log — inbound receipt                      */
        /* -------------------------------------------------------- */
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id,
            sku_id,
            moved_qty,
            from_bin_id,
            to_bin_id,
            from_state_code,
            to_state_code,
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
            NULL,           -- no origin bin on first receipt
            @staging_bin_id,
            NULL,           -- no prior state
            'RCD',
            NULL,           -- no prior status
            @arrival_status_code,
            'INBOUND',
            'RECEIPT',
            @receipt_id,    -- ← captured from SCOPE_IDENTITY() after receipts insert
            SYSUTCDATETIME(),
            @user_id,
            @session_id
        );

        /* -------------------------------------------------------- */
        /* 7) Close inbound if fully received                       */
        /* -------------------------------------------------------- */
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

            SET @is_closed = 1;
        END

        COMMIT;

        /* -------------------------------------------------------- */
        /* FINAL RESULT                                             */
        /* -------------------------------------------------------- */
        SELECT
            CAST(1 AS BIT),
            N'SUCINBL01',
            @resolved_line_id,
            @inbound_id,
            @is_closed;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT),
            N'ERRINBL99',
            NULL,
            NULL,
            NULL;
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
        @inbound_expected_unit_id INT              = NULL,
        @inbound_line_id          INT              = NULL,
        @inbound_ref              NVARCHAR(50)     = NULL,
        @header_status            VARCHAR(3)       = NULL,
        @line_state               VARCHAR(3)       = NULL,
        @sku_code                 NVARCHAR(50)     = NULL,
        @sku_description          NVARCHAR(200)    = NULL,
        @expected_unit_qty        INT              = NULL,
        @line_expected_qty        INT              = NULL,
        @line_received_qty        INT              = NULL,
        @arrival_status_code      VARCHAR(2)       = NULL,
        @batch_number             NVARCHAR(100)    = NULL,
        @best_before_date         DATE             = NULL,
        @received_inventory_id    INT              = NULL,

        @expected_unit_state      VARCHAR(3)       = NULL,

        @claimed_session_id       UNIQUEIDENTIFIER = NULL,
        @claimed_by_user_id       INT              = NULL,
        @claim_expires_at         DATETIME2(3)     = NULL,
        @claim_token              UNIQUEIDENTIFIER = NULL,

        @ttl_seconds              INT              = NULL,
        @now                      DATETIME2(3)     = SYSUTCDATETIME();

    ----------------------------------------------------------------------
    -- TTL seconds
    ----------------------------------------------------------------------
    SELECT @ttl_seconds = TRY_CONVERT(INT, s.setting_value)
    FROM operations.settings s
    WHERE s.setting_name = 'inbound.sscc_claim_ttl_seconds';

    IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
        SET @ttl_seconds = 30;

    ----------------------------------------------------------------------
    -- 0) Cleanup expired claims (short update, no explicit transaction)
    ----------------------------------------------------------------------
    UPDATE deliveries.inbound_expected_units
    SET expected_unit_state_code = 'EXP',
        claimed_session_id       = NULL,
        claimed_by_user_id       = NULL,
        claimed_at               = NULL,
        claim_expires_at         = NULL,
        claim_token              = NULL
    WHERE claim_expires_at IS NOT NULL
      AND claim_expires_at < @now
      AND received_inventory_unit_id IS NULL
      AND expected_unit_state_code = 'CLM';

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1) Resolve expected unit (read-only preview lookup)
        ------------------------------------------------------------------
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
            @expected_unit_state      = eu.expected_unit_state_code,
            @inbound_expected_unit_id = eu.inbound_expected_unit_id,
            @claimed_session_id       = eu.claimed_session_id,
            @claimed_by_user_id       = eu.claimed_by_user_id,
            @claim_expires_at         = eu.claim_expires_at,
            @claim_token              = eu.claim_token,
            @arrival_status_code      = l.arrival_stock_status_code
        FROM deliveries.inbound_expected_units eu
        JOIN deliveries.inbound_lines l
            ON eu.inbound_line_id = l.inbound_line_id
        JOIN deliveries.inbound_deliveries d
            ON l.inbound_id = d.inbound_id
        JOIN inventory.skus s
            ON l.sku_id = s.sku_id
        WHERE eu.expected_external_ref = LTRIM(RTRIM(@external_ref));

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRSSCC01',
                   NULL,
                   NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
                   NULL,NULL,NULL,NULL;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 2) Already received?
        ------------------------------------------------------------------
        IF @received_inventory_id IS NOT NULL
        BEGIN
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
                   NULL,NULL,NULL,NULL, NULL;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 3) Header lifecycle check
        ------------------------------------------------------------------
        IF @header_status NOT IN ('ACT','RCV')
        BEGIN
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
                   NULL,NULL,NULL,NULL, NULL;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4) Claim logic (STRICT MODE)
        ------------------------------------------------------------------

        -- 4.1 Active claim exists (any session) -> reject
        IF @claimed_session_id IS NOT NULL
           AND @claim_expires_at IS NOT NULL
           AND @claim_expires_at >= DATEADD(SECOND, -1, @now)
        BEGIN
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
        END;

        -- 4.2 Transition validation (EXP -> CLM)
        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_expected_unit_state_transitions t
            WHERE t.from_state_code = @expected_unit_state
              AND t.to_state_code   = 'CLM'
        )
        BEGIN
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
                   NULL,NULL,NULL,NULL, NULL;
            RETURN;
        END;

        -- 4.3 Create NEW claim (no reuse)
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
          AND received_inventory_unit_id IS NULL
          AND (
                claimed_session_id IS NULL
                OR claim_expires_at < @now
              );

        -- 4.4 Race protection
        IF @@ROWCOUNT = 0
        BEGIN
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
                   (@line_expected_qty - @line_received_qty),
                   @batch_number,
                   @best_before_date,
                   NULL,NULL,NULL,NULL, NULL;
            RETURN;
        END;

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
            @claim_token,
            @arrival_status_code;

    END TRY
    BEGIN CATCH
        DECLARE @err_no   INT = ERROR_NUMBER();
        DECLARE @err_line INT = ERROR_LINE();
        DECLARE @err_msg  NVARCHAR(2048) = ERROR_MESSAGE();

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
GO

CREATE OR ALTER PROCEDURE deliveries.usp_reverse_inbound_receipt
(
    @receipt_id      INT,
    @reason_code     NVARCHAR(50) = NULL,
    @reason_text     NVARCHAR(400) = NULL,
    @user_id         INT = NULL,
    @session_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inbound_id               INT,
        @inbound_line_id          INT,
        @inbound_expected_unit_id INT,
        @inventory_unit_id        INT,
        @received_qty             INT,
        @reversal_receipt_id      INT,
        @header_reopened          BIT = 0,
        @old_header_status        VARCHAR(3),
        @new_header_status        VARCHAR(3);

    BEGIN TRY
        BEGIN TRAN;

        /* --------------------------------------------------------
           1) Lock + resolve original receipt
        -------------------------------------------------------- */
        SELECT
            @inbound_line_id          = r.inbound_line_id,
            @inbound_expected_unit_id = r.inbound_expected_unit_id,
            @inventory_unit_id        = r.inventory_unit_id,
            @received_qty             = r.received_qty
        FROM deliveries.inbound_receipts r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.receipt_id = @receipt_id
          AND r.is_reversal = 0;

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBREV01', NULL, NULL, NULL, NULL, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_receipts
            WHERE receipt_id = @receipt_id
              AND reversed_receipt_id IS NOT NULL
        )
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBREV02', NULL, NULL, @receipt_id, NULL, NULL, NULL;
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           2) Resolve inbound + header
        -------------------------------------------------------- */
        SELECT @inbound_id = inbound_id
        FROM deliveries.inbound_lines
        WHERE inbound_line_id = @inbound_line_id;

        SELECT @old_header_status = inbound_status_code
        FROM deliveries.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        /* --------------------------------------------------------
           3) Reverse inventory unit
        -------------------------------------------------------- */
        UPDATE inventory.inventory_units
        SET stock_state_code = 'EXP',
            updated_at       = SYSUTCDATETIME(),
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRINBREV03', @inbound_id, @inbound_line_id, @receipt_id, NULL, @inventory_unit_id, NULL;
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           4) Restore expected unit (SSCC mode)
        -------------------------------------------------------- */
        IF @inbound_expected_unit_id IS NOT NULL
        BEGIN
            UPDATE deliveries.inbound_expected_units
            SET received_inventory_unit_id = NULL,
                expected_unit_state_code   = 'EXP',
                claimed_session_id         = NULL,
                claimed_by_user_id         = NULL,
                claimed_at                 = NULL,
                claim_expires_at           = NULL,
                claim_token                = NULL,
                updated_at                 = SYSUTCDATETIME(),
                updated_by                 = @user_id
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id;
        END

        /* --------------------------------------------------------
           5) Insert reversal receipt
        -------------------------------------------------------- */
        INSERT INTO deliveries.inbound_receipts
        (
            inbound_line_id,
            inbound_expected_unit_id,
            inventory_unit_id,
            received_qty,
            received_by_user_id,
            session_id,
            received_at,
            is_reversal,
            reversed_receipt_id
        )
        VALUES
        (
            @inbound_line_id,
            @inbound_expected_unit_id,
            @inventory_unit_id,
            @received_qty,
            @user_id,
            @session_id,
            SYSUTCDATETIME(),
            1,
            @receipt_id
        );

        SET @reversal_receipt_id = SCOPE_IDENTITY();

        /* --------------------------------------------------------
           6) Mark original receipt reversed
        -------------------------------------------------------- */
        UPDATE deliveries.inbound_receipts
        SET reversed_receipt_id = @reversal_receipt_id
        WHERE receipt_id = @receipt_id;

        /* --------------------------------------------------------
           7) Recompute line (🔥 correct aggregation)
        -------------------------------------------------------- */
        UPDATE l
        SET
            received_qty =
            (
                SELECT ISNULL(SUM(
                    CASE 
                        WHEN r.is_reversal = 0 THEN r.received_qty
                        ELSE -r.received_qty
                    END), 0)
                FROM deliveries.inbound_receipts r
                WHERE r.inbound_line_id = l.inbound_line_id
            ),
            line_state_code =
            CASE
                WHEN (
                    SELECT ISNULL(SUM(
                        CASE 
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM deliveries.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) = 0 THEN 'EXP'

                WHEN (
                    SELECT ISNULL(SUM(
                        CASE 
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM deliveries.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) < l.expected_qty THEN 'PRC'

                ELSE 'RCV'
            END,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        FROM deliveries.inbound_lines l
        WHERE l.inbound_line_id = @inbound_line_id;

        /* --------------------------------------------------------
           8) Recompute header
        -------------------------------------------------------- */

        -- Default
        SET @new_header_status = 'ACT';

        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code IN ('PRC','RCV')
        )
            SET @new_header_status = 'RCV';

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code NOT IN ('RCV','CNL')
        )
            SET @new_header_status = 'CLS';

        UPDATE deliveries.inbound_deliveries
        SET inbound_status_code = @new_header_status,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        IF @old_header_status = 'CLS' AND @new_header_status <> 'CLS'
            SET @header_reopened = 1;

        COMMIT;

        /* --------------------------------------------------------
           FINAL RESULT (STRICT CONTRACT)
        -------------------------------------------------------- */
        SELECT
            CAST(1 AS BIT),
            N'SUCINBREV01',
            @inbound_id,
            @inbound_line_id,
            @receipt_id,
            @reversal_receipt_id,
            @inventory_unit_id,
            @header_reopened;

    END TRY
    BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    DECLARE @err_no INT = ERROR_NUMBER();
    DECLARE @err_msg NVARCHAR(2048) = ERROR_MESSAGE();

    SELECT 
        CAST(0 AS BIT),
        N'ERRINBREV99',
        @err_no, 
        @err_msg,
        @receipt_id;

    RETURN;
END CATCH
END;
GO

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @OutputId INT;
/* ========================================================
   AUDIT FOUNDATION (CLEAN BOOTSTRAP)
======================================================== */

----------------------------------------------------------
-- 1. EVENT CATALOG
----------------------------------------------------------
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

CREATE OR ALTER PROCEDURE locations.usp_suggest_putaway_bin
(
    @inventory_unit_id INT,
    @suggested_bin_id INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @sku_id INT,
        @type_id INT,
        @section_id INT;

    /* --------------------------------------------------------
       1) Resolve SKU storage preferences
    -------------------------------------------------------- */
    SELECT
        @sku_id = iu.sku_id,
        @type_id = s.preferred_storage_type_id,
        @section_id = s.preferred_storage_section_id
    FROM inventory.inventory_units iu
    JOIN inventory.skus s
        ON iu.sku_id = s.sku_id
    WHERE iu.inventory_unit_id = @inventory_unit_id;

    IF @type_id IS NULL
        RETURN;

    /* --------------------------------------------------------
       2) Calculate zone activity (traffic awareness)
    -------------------------------------------------------- */
    ;WITH zone_load AS
    (
        SELECT
            b.zone_id,

            /* active putaway tasks */
            COUNT(DISTINCT t.task_id)

            +

            /* active reservations */
            COUNT(DISTINCT r.reservation_id)

            AS zone_activity

        FROM locations.bins b

        LEFT JOIN warehouse.warehouse_tasks t
            ON t.destination_bin_id = b.bin_id
           AND t.task_state_code IN ('NEW','CLM','ACT')

        LEFT JOIN locations.bin_reservations r
            ON r.bin_id = b.bin_id
           AND r.expires_at > SYSUTCDATETIME()

        WHERE b.zone_id IS NOT NULL

        GROUP BY b.zone_id
    ),

    /* --------------------------------------------------------
       3) Candidate bins
    -------------------------------------------------------- */
    bin_candidates AS
    (
        SELECT
            b.bin_id,
            b.zone_id,
            b.capacity,

            /* existing pallets */
            ISNULL(p.placement_count,0) AS placement_count,

            /* active reservations */
            ISNULL(r.reservation_count,0) AS reservation_count,

            /* zone traffic */
            ISNULL(z.zone_activity,0) AS zone_activity

        FROM locations.bins b

        OUTER APPLY
        (
            SELECT COUNT(*) AS placement_count
            FROM inventory.inventory_placements ip
            WHERE ip.bin_id = b.bin_id
        ) p

        OUTER APPLY
        (
            SELECT COUNT(*) AS reservation_count
            FROM locations.bin_reservations br
            WHERE br.bin_id = b.bin_id
              AND br.expires_at > SYSUTCDATETIME()
        ) r

        LEFT JOIN zone_load z
            ON z.zone_id = b.zone_id

        WHERE
            b.is_active = 1
            AND b.storage_type_id = @type_id
            AND (@section_id IS NULL OR b.storage_section_id = @section_id)
    )

    /* --------------------------------------------------------
       4) Select best bin
    -------------------------------------------------------- */
    SELECT TOP (1)
        @suggested_bin_id = bin_id
    FROM bin_candidates
    WHERE (placement_count + reservation_count) < capacity
    ORDER BY
        zone_activity ASC,       -- least busy zone first
        placement_count ASC,     -- emptier bins preferred
        NEWID();                 -- random tie break to prevent clustering

END
GO

CREATE OR ALTER PROCEDURE warehouse.usp_create_putaway_task
(
    @inventory_unit_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @sku_id INT,
        @stock_state VARCHAR(3),
        @current_bin_id INT,
        @dest_bin_id INT,
        @ttl_seconds INT,
        @expires_at DATETIME2(3),
        @task_id INT;

    BEGIN TRY
        BEGIN TRAN;

        -- Resolve inventory unit
        SELECT
            @sku_id = sku_id,
            @stock_state = stock_state_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        -- Must be in RECEIVED state
        IF @stock_state <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK02';
            ROLLBACK;
            RETURN;
        END

        -- Resolve current placement
        SELECT @current_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @current_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK03';
            ROLLBACK;
            RETURN;
        END

        -- Prevent duplicate tasks
        IF EXISTS (
            SELECT 1
            FROM warehouse.warehouse_tasks
            WHERE inventory_unit_id = @inventory_unit_id
            AND task_state_code IN ('OPN','CLM')
        )
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK05';
            ROLLBACK;
            RETURN;
        END

        -- Suggest destination bin
        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), 'ERRTASK04';
            ROLLBACK;
            RETURN;
        END

        -- Load TTL from settings
        SELECT @ttl_seconds =
            TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        -- Create task
        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code,
            inventory_unit_id,
            source_bin_id,
            destination_bin_id,
            task_state_code,
            expires_at,
            created_by
        )
        VALUES
        (
            'PUTAWAY',
            @inventory_unit_id,
            @current_bin_id,
            @dest_bin_id,
            'OPN',
            @expires_at,
            @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT
            CAST(1 AS BIT) AS success,
            'SUCTASK01' AS result_code,
            @task_id AS task_id,
            @dest_bin_id AS destination_bin_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT), 'ERRTASK99';
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_create_task_for_unit
(
    @inventory_unit_id INT,
    @user_id           INT,
    @session_id        UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @task_id INT,
        @dest_bin_id INT,
        @dest_bin_code NVARCHAR(100),
        @source_bin_id INT,
        @ttl_seconds INT,
        @expires_at DATETIME2(3),
        @sku_id INT,
        @state_code VARCHAR(3),
        @stock_status_code  VARCHAR(2),
        @source_bin_code    NVARCHAR(100),
        @zone_code          NVARCHAR(50);

    BEGIN TRY
        BEGIN TRAN;

    ------------------------------------------------------------
    -- 1. Validate inventory unit
    ------------------------------------------------------------
        SELECT
            @sku_id = sku_id,
            @state_code = stock_state_code,
            @stock_status_code = stock_status_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        IF @state_code <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK02';
            ROLLBACK;
            RETURN;
        END

    ------------------------------------------------------------
    -- 2. Resolve current placement
    ------------------------------------------------------------
        SELECT
            @source_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK03';
            ROLLBACK;
            RETURN;
        END

    ------------------------------------------------------------
    -- 2b. Resolve source bin code and zone
    ------------------------------------------------------------
        SELECT
            @source_bin_code = b.bin_code,
            @zone_code       = z.zone_code
        FROM locations.bins b
        LEFT JOIN locations.zones z
            ON z.zone_id = b.zone_id
        WHERE b.bin_id = @source_bin_id;

    ------------------------------------------------------------
    -- 3. Detect existing open task (idempotency)
    ------------------------------------------------------------
        SELECT TOP (1)
            @task_id = task_id,
            @dest_bin_id = destination_bin_id
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
        AND task_state_code IN ('OPN','CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            SELECT @dest_bin_code = bin_code
            FROM locations.bins
            WHERE bin_id = @dest_bin_id;

            COMMIT;

            SELECT
            CAST(1 AS BIT),
            N'SUCTASK01',
            @task_id,
            @dest_bin_code,
            @inventory_unit_id,     -- col 4
            @source_bin_code,       -- col 5
            @state_code,            -- col 6
            @stock_status_code,     -- col 7
            @expires_at,            -- col 8
            @zone_code;             -- col 9

            RETURN;
        END

    ------------------------------------------------------------
    -- 4. Suggest destination bin
    ------------------------------------------------------------
        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK04';
            ROLLBACK;
            RETURN;
        END

        SELECT
            @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

    ------------------------------------------------------------
    -- 5. Resolve TTL from settings
    ------------------------------------------------------------
        SELECT
            @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL
            SET @ttl_seconds = 300;

        SET @expires_at =
            DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

    ------------------------------------------------------------
    -- 6. Insert warehouse task
    ------------------------------------------------------------
        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code,
            inventory_unit_id,
            source_bin_id,
            destination_bin_id,
            task_state_code,
            expires_at,
            created_by
        )
        VALUES
        (
            'PUTAWAY',
            @inventory_unit_id,
            @source_bin_id,
            @dest_bin_id,
            'OPN',
            @expires_at,
            @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

    ------------------------------------------------------------
    -- 7. Create bin reservation
    ------------------------------------------------------------
        INSERT INTO locations.bin_reservations
        (
            bin_id,
            reservation_type,
            reserved_by,
            expires_at
        )
        VALUES
        (
            @dest_bin_id,
            'PUTAWAY',
            @user_id,
            @expires_at
        );

    ------------------------------------------------------------
    -- 8. Success
    ------------------------------------------------------------
        COMMIT;

        SELECT
            CAST(1 AS BIT),
            N'SUCTASK01',
            @task_id,
            @dest_bin_code,
            @inventory_unit_id,     -- col 4
            @source_bin_code,       -- col 5
            @state_code,            -- col 6
            @stock_status_code,     -- col 7
            @expires_at,            -- col 8
            @zone_code;             -- col 9

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        SELECT
            CAST(0 AS BIT),
            N'ERRTASK99';
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE warehouse.usp_putaway_confirm_task
(
    @task_id         INT,
    @scanned_bin_code NVARCHAR(100),   -- ← new: what the operator actually scanned
    @user_id         INT,
    @session_id      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @inventory_unit_id  INT,
        @source_bin_id      INT,
        @dest_bin_id        INT,
        @dest_bin_code      NVARCHAR(100),
        @sku_id             INT,
        @quantity           INT,
        @task_state         VARCHAR(3),
        @scanned_bin_id     INT,
        @bin_capacity       INT,
        @bin_active         BIT,
        @current_placements INT,
        @active_reservations INT,
        @current_status_code VARCHAR(2),
        @now                DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        ------------------------------------------------------------
        -- 1. Lock and resolve task
        ------------------------------------------------------------
        SELECT
            @inventory_unit_id = inventory_unit_id,
            @source_bin_id     = source_bin_id,
            @dest_bin_id       = destination_bin_id,
            @task_state        = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id = @task_id;

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK01';
            ROLLBACK;
            RETURN;
        END

        IF @task_state NOT IN ('OPN', 'CLM')
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK07';
            ROLLBACK;
            RETURN;
        END

        ------------------------------------------------------------
        -- 2. Resolve destination bin code (for comparison)
        ------------------------------------------------------------
        SELECT
            @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        ------------------------------------------------------------
        -- 3. Check scanned bin matches reserved destination
        ------------------------------------------------------------
        IF LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK08';
            ROLLBACK;
            RETURN;
        END

        ------------------------------------------------------------
        -- 4. Re-validate destination bin still available
        --    (capacity check at confirm time)
        ------------------------------------------------------------
        SELECT
            @scanned_bin_id      = bin_id,
            @bin_capacity        = capacity,
            @bin_active          = is_active
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        IF @bin_active = 0
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK09';
            ROLLBACK;
            RETURN;
        END

        SELECT @current_placements = COUNT(*)
        FROM inventory.inventory_placements
        WHERE bin_id = @dest_bin_id;

        SELECT @active_reservations = COUNT(*)
        FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id
          AND expires_at > @now;

        -- Subtract 1 from reservations: this unit's own reservation
        -- is still active at confirm time, so it shouldn't count against capacity
        IF (@current_placements + @active_reservations - 1) >= @bin_capacity
        BEGIN
            SELECT CAST(0 AS BIT), N'ERRTASK09';
            ROLLBACK;
            RETURN;
        END

        ------------------------------------------------------------
        -- 5. Lock inventory unit
        ------------------------------------------------------------
        SELECT
            @sku_id   = sku_id,
            @quantity = quantity,
            @current_status_code = stock_status_code 
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

        ------------------------------------------------------------
        -- 6. Move placement
        ------------------------------------------------------------
        UPDATE inventory.inventory_placements
        SET bin_id    = @dest_bin_id,
            placed_at = @now,
            placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        ------------------------------------------------------------
        -- 7. Transition inventory state
        ------------------------------------------------------------
        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id
          AND stock_state_code = 'RCD';

        ------------------------------------------------------------
        -- 8. Close warehouse task
        ------------------------------------------------------------
        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        ------------------------------------------------------------
        -- 9. Remove bin reservation
        ------------------------------------------------------------
        DELETE FROM locations.bin_reservations
        WHERE bin_id          = @dest_bin_id
          AND reservation_type = 'PUTAWAY'
          AND expires_at      >= @now;

        ------------------------------------------------------------
        -- 10. Movement log
        ------------------------------------------------------------
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id,
            sku_id,
            moved_qty,
            from_bin_id,
            to_bin_id,
            from_state_code,
            to_state_code,
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
            @quantity,
            @source_bin_id,
            @dest_bin_id,
            'RCD',
            'PTW',
            @current_status_code,
            @current_status_code,
            'PUTAWAY',
            'TASK',
            @task_id,
            @now,
            @user_id,
            @session_id
        );

        COMMIT;

        SELECT CAST(1 AS BIT), N'SUCTASK02';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT), N'ERRTASK99';
    END CATCH
END;
GO

CREATE OR ALTER VIEW inventory.v_units_awaiting_putaway
AS
SELECT
    iu.inventory_unit_id,
    iu.external_ref,
    iu.sku_id,
    iu.quantity,
    iu.created_at
FROM inventory.inventory_units iu
WHERE
    iu.stock_state_code = 'RCD'
    AND NOT EXISTS
    (
        SELECT 1
        FROM warehouse.warehouse_tasks wt
        WHERE wt.inventory_unit_id = iu.inventory_unit_id
          AND wt.task_type_code = 'PUTAWAY'
          AND wt.task_state_code IN ('OPN','CLM')
    );
GO

CREATE OR ALTER VIEW inventory.v_units_awaiting_putaway
AS
SELECT
    iu.inventory_unit_id,
    iu.external_ref,
    iu.sku_id,
    iu.quantity,
    iu.created_at
FROM inventory.inventory_units iu
WHERE
    iu.stock_state_code = 'RCD'
    AND NOT EXISTS
    (
        SELECT 1
        FROM warehouse.warehouse_tasks wt
        WHERE wt.inventory_unit_id = iu.inventory_unit_id
          AND wt.task_type_code = 'PUTAWAY'
          AND wt.task_state_code IN ('OPN','CLM')
    );
GO


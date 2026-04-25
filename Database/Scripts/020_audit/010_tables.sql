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

('core.default_ui_mode','Default UI mode','core',30,'TRACE','string',
 '{"type":"enum","values":["Minimal","Standard","Trace"]}',
 'Diagnostic UI mode'),

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

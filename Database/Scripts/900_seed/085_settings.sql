USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

-- ============================================================
-- Seed: operations.settings
-- Idempotent — safe to re-run. Uses IF NOT EXISTS per row.
-- ============================================================

-- ── Cleanup: remove legacy / duplicate settings ────────────────────────
--    auth.enable_login   → duplicate of auth.login_enabled (different name, same purpose)
--    EnableAutoLogin     → renamed to auth.auto_login_enabled
--    SessionExpiryMinutes → legacy duplicate of auth.session_timeout_minutes

DELETE FROM operations.settings WHERE setting_name IN (
    'auth.enable_login',
    'EnableAutoLogin',
    'SessionExpiryMinutes'
);
GO

-- ── Core ───────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'core.version')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('core.version', 'Core schema version', 'core', 10, '1.0.0', 'string', NULL, 'PeasyWare Core DB schema version');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'core.environment')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('core.environment', 'Environment', 'core', 20, 'dev', 'string', '{"type":"enum","values":["dev","test","prod"]}', 'Environment type');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'core.default_ui_mode')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('core.default_ui_mode', 'Default UI mode', 'core', 30, 'TRACE', 'string', '{"type":"enum","values":["Minimal","Standard","Trace"]}', 'Diagnostic UI verbosity for operator screens');

GO

-- ── Authentication ─────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.login_enabled')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.login_enabled', 'Login enabled', 'auth', 10, 'true', 'bool', '{"type":"bool"}', 'Master switch — set to false to block all logins during maintenance');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.session_timeout_minutes')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.session_timeout_minutes', 'Session timeout (minutes)', 'auth', 20, '30', 'int', '{"type":"range","min":5,"max":240}', 'Minutes before an idle session is force-expired by the server');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.app_lock_minutes')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.app_lock_minutes', 'Application lock (minutes)', 'auth', 30, '15', 'int', '{"type":"range","min":1,"max":120}', 'Minutes of UI inactivity before the client lockscreen activates');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.max_login_attempts')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.max_login_attempts', 'Max login attempts', 'auth', 40, '5', 'int', '{"type":"range","min":3,"max":20}', 'Failed attempts before progressive lockout escalates');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_min_length')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.password_min_length', 'Min password length', 'auth', 50, '8', 'int', '{"type":"range","min":6,"max":64}', 'Minimum character length enforced on new passwords');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_expiry_days')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.password_expiry_days', 'Password expiry (days)', 'auth', 60, '90', 'int', '{"type":"range","min":30,"max":365}', 'Days before a password must be rotated');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.password_history_depth')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.password_history_depth', 'Password history depth', 'auth', 70, '3', 'int', '{"type":"range","min":0,"max":20}', 'Number of previous passwords blocked from reuse');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'auth.auto_login_enabled')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('auth.auto_login_enabled', 'Auto-login enabled', 'auth', 80, 'true', 'bool', '{"type":"bool"}', 'Allow client-side auto-login from a stored token');

GO

-- ── Inbound ────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'inbound.auto_complete_on_full_receipt')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('inbound.auto_complete_on_full_receipt', 'Auto-complete inbound', 'inbound', 10, 'false', 'bool', '{"type":"bool"}', 'Automatically close an inbound header when all lines are fully received');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'inbound.sscc_claim_ttl_seconds')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('inbound.sscc_claim_ttl_seconds', 'SSCC claim TTL (seconds)', 'inbound', 20, '60', 'int', '{"type":"range","min":10,"max":300}', 'Seconds an SSCC claim is held open during the receive confirmation window');

GO

-- ── Warehouse ──────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'warehouse.putaway_task_ttl_seconds')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('warehouse.putaway_task_ttl_seconds', 'Putaway task TTL (seconds)', 'warehouse', 10, '600', 'int', '{"type":"range","min":60,"max":3600}', 'Seconds a putaway task reservation remains valid before expiring');

GO

-- ── Logging ────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.enabled')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('logging.enabled', 'Logging enabled', 'logging', 10, 'true', 'bool', '{"type":"bool"}', 'Global master switch for all logging output');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.min_level')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('logging.min_level', 'Minimum log level', 'logging', 20, 'INFO', 'string', '{"type":"enum","values":["INFO","WARN","ERROR"]}', 'Minimum severity level emitted to all log sinks');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.db.enabled')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('logging.db.enabled', 'Database logging enabled', 'logging', 30, 'true', 'bool', '{"type":"bool"}', 'Persist log entries to the audit.trace_logs table');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.console.enabled')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('logging.console.enabled', 'Console logging enabled', 'logging', 40, 'true', 'bool', '{"type":"bool"}', 'Write log entries to console output (CLI and debug)');

IF NOT EXISTS (SELECT 1 FROM operations.settings WHERE setting_name = 'logging.include_sensitive')
    INSERT INTO operations.settings (setting_name, display_name, category, display_order, setting_value, data_type, validation_rule, description)
    VALUES ('logging.include_sensitive', 'Log sensitive fields', 'logging', 50, 'false', 'bool', '{"type":"bool"}', 'Include sensitive field values in log output — DEV environments only');

GO

SET NOCOUNT OFF;
GO

PRINT 'Settings seeded.';
GO

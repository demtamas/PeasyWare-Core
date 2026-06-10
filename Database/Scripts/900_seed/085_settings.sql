USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Seed: operations.settings
-- Idempotent — skips any setting that already exists.
-- ============================================================

INSERT INTO operations.settings
(
    setting_name, display_name, category, display_order,
    setting_value, data_type, validation_rule, description
)
SELECT v.setting_name, v.display_name, v.category, v.display_order,
       v.setting_value, v.data_type, v.validation_rule, v.description
FROM (VALUES

    -- ── Core ───────────────────────────────────────────────────────────────
    ('core.version',       'Core schema version', 'core', 10, '1.0.0', 'string',
     NULL,
     'PeasyWare Core DB schema version'),

    ('core.environment',   'Environment',         'core', 20, 'dev',   'string',
     '{"type":"enum","values":["dev","test","prod"]}',
     'Environment type'),

    -- ── Authentication ─────────────────────────────────────────────────────
    ('auth.login_enabled',          'Login enabled',               'auth', 10, 'true', 'bool',
     '{"type":"bool"}',
     'Master switch to disable all user logins'),

    ('auth.session_timeout_minutes','Session timeout (minutes)',   'auth', 20, '30',   'int',
     '{"type":"range","min":5,"max":240}',
     'Minutes before a session is force-closed by server inactivity'),

    ('auth.app_lock_minutes',       'Application lock (minutes)', 'auth', 30, '15',   'int',
     '{"type":"range","min":1,"max":120}',
     'Minutes of UI inactivity before client lockscreen'),

    ('auth.max_login_attempts',     'Max login attempts',         'auth', 40, '5',    'int',
     '{"type":"range","min":3,"max":20}',
     'Maximum failed attempts before lockout escalation'),

    ('auth.password_min_length',    'Min password length',        'auth', 50, '8',    'int',
     '{"type":"range","min":6,"max":64}',
     'Minimum password length enforced by policy'),

    ('auth.password_expiry_days',   'Password expiry (days)',     'auth', 60, '90',   'int',
     '{"type":"range","min":30,"max":365}',
     'Password validity duration before required rotation'),

    ('auth.password_history_depth', 'Password history depth',    'auth', 70, '3',    'int',
     '{"type":"range","min":0,"max":20}',
     'How many previous passwords are blocked from reuse'),

    -- ── Inbound ────────────────────────────────────────────────────────────
    ('inbound.auto_complete_on_full_receipt', 'Auto-complete inbound', 'inbound', 10, 'false', 'bool',
     '{"type":"bool"}',
     'Auto-complete inbound header when all rows fully received'),

    ('inbound.sscc_claim_ttl_seconds', 'SSCC claim TTL (seconds)', 'inbound', 20, '60', 'int',
     '{"type":"range","min":10,"max":300}',
     'Time-to-live for SSCC claim during receive confirmation window')

) AS v(setting_name, display_name, category, display_order,
       setting_value, data_type, validation_rule, description)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.settings s
    WHERE s.setting_name = v.setting_name
);

PRINT 'Settings seeded.';
GO

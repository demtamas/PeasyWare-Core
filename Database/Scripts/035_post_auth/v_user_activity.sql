USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW audit.v_user_activity
AS
-- ── Source 1: Trigger-based user_changes ──────────────────────────────────
SELECT
    CAST(uc.audit_id AS BIGINT)             AS event_id,
    uc.changed_at                           AS occurred_at,
    'TRIGGER'                               AS source,
    uc.action                               AS event_type,
    -- Subject: the user who was changed
    uc.user_id                              AS subject_user_id,
    subject.username                        AS subject_username,
    -- Actor: who made the change
    uc.changed_by                           AS actor_user_id,
    actor.username                          AS actor_username,
    uc.session_id,
    -- Detail
    CASE uc.action
        WHEN 'SET_ACTIVE'
            THEN CONCAT('is_active: ', CAST(uc.old_is_active AS NVARCHAR(1)),
                        ' → ', CAST(uc.new_is_active AS NVARCHAR(1)))
        ELSE ISNULL(uc.details, '')
    END                                     AS detail,
    NULL                                    AS result_code,
    NULL                                    AS source_app
FROM audit.user_changes uc
JOIN auth.users subject ON subject.id = uc.user_id
LEFT JOIN auth.users actor   ON actor.id   = uc.changed_by

UNION ALL

-- ── Source 2: Trace log user events ───────────────────────────────────────
SELECT
    CAST(t.trace_id AS BIGINT)              AS event_id,
    t.occurred_at,
    'TRACE'                                 AS source,
    t.action                                AS event_type,
    -- Subject: the user the action is about
    t.user_id                               AS subject_user_id,
    u.username                              AS subject_username,
    -- Actor: same as subject for self-service events
    t.user_id                               AS actor_user_id,
    u.username                              AS actor_username,
    t.session_id,
    -- Detail from JSON
    ISNULL(
        JSON_VALUE(t.payload_json, '$.Data.ResultCode'),
        ''
    )                                       AS detail,
    JSON_VALUE(t.payload_json, '$.Data.ResultCode') AS result_code,
    JSON_VALUE(t.payload_json, '$.Session.SourceApp') AS source_app
FROM audit.trace_logs t
LEFT JOIN auth.users u ON u.id = t.user_id
WHERE t.action IN (
    'user.created',
    'user.password.changed',
    'AuthService.PasswordChange.Start',
    'AuthService.PasswordChange.Result',
    'AuthService.Login.Start',
    'AuthService.Login.Result',
    'Session.Start',
    'Session.Logout'
);
GO
PRINT 'audit.v_user_activity created.';
GO

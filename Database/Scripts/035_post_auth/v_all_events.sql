USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   audit.v_all_events
   ------------------------------------------------------------
   Unions audit.trace_logs (everything, high-volume, general
   operational tracing) with audit.audit_events (narrower,
   "critical state transitions" - login, logout, user changes,
   settings changes). Deliberately does NOT include
   auth.session_events, which stays a specialised, validated
   session-state-machine log queried directly when investigating
   a specific session, not browsed alongside everything else.

   Same shape/convention as audit.v_user_activity: BIGINT ids
   cast for cross-source safety, a source column to distinguish
   origin, JSON_VALUE used to surface common fields from each
   source's own payload shape (trace_logs: {Session:{...},
   Data:{...}}; audit_events: flat, and inconsistent row to row -
   source_app/source_client are therefore best-effort here, not
   guaranteed present, same as the underlying data itself.
   ============================================================ */
CREATE OR ALTER VIEW audit.v_all_events
AS
-- ── Source 1: trace_logs - everything ──────────────────────────
SELECT
    CAST(t.trace_id AS BIGINT)                            AS event_id,
    t.occurred_at,
    N'TRACE'                                              AS source,
    t.action                                              AS event_name,
    t.level                                               AS level,
    t.user_id,
    u1.username                                           AS username,
    t.session_id,
    t.correlation_id,
    JSON_VALUE(t.payload_json, '$.Session.SourceApp')     AS source_app,
    JSON_VALUE(t.payload_json, '$.Session.SourceClient')  AS source_client,
    JSON_VALUE(t.payload_json, '$.Data.ResultCode')       AS result_code,
    JSON_VALUE(t.payload_json, '$.Data.Success')          AS success,
    t.payload_json
FROM audit.trace_logs t
LEFT JOIN auth.users u1 ON u1.id = t.user_id

UNION ALL

-- ── Source 2: audit_events - critical state transitions ────────
SELECT
    CAST(a.audit_id AS BIGINT)                            AS event_id,
    a.occurred_at,
    N'AUDIT'                                              AS source,
    a.event_name,
    CASE WHEN a.success = 1 THEN N'INFO' ELSE N'WARN' END AS level,
    a.user_id,
    u2.username                                           AS username,
    a.session_id,
    a.correlation_id,
    JSON_VALUE(a.payload_json, '$.ClientApp')             AS source_app,
    NULL                                                   AS source_client,
    COALESCE(JSON_VALUE(a.payload_json, '$.ResultCode'), a.result_code) AS result_code,
    CASE WHEN a.success = 1 THEN N'true' ELSE N'false' END AS success,
    a.payload_json
FROM audit.audit_events a
LEFT JOIN auth.users u2 ON u2.id = a.user_id;
GO
PRINT 'audit.v_all_events created.';
GO

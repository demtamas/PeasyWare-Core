USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW audit.v_event_log
AS
SELECT
    t.trace_id,
    t.occurred_at,
    t.level,
    t.action,
    -- Session context
    t.user_id,
    u.username,
    t.session_id,
    t.correlation_id,
    -- Parsed from JSON payload
    JSON_VALUE(t.payload_json, '$.Session.SourceApp')    AS source_app,
    JSON_VALUE(t.payload_json, '$.Session.SourceClient') AS source_client,
    -- Common outcome fields
    JSON_VALUE(t.payload_json, '$.Data.ResultCode')      AS result_code,
    JSON_VALUE(t.payload_json, '$.Data.Success')         AS success,
    -- Full payload for detail view
    t.payload_json
FROM audit.trace_logs t
LEFT JOIN auth.users u ON u.id = t.user_id;
GO
PRINT 'audit.v_event_log created.';
GO

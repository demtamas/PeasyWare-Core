USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW audit.v_location_changes
AS
SELECT
    t.trace_id,
    t.occurred_at,
    u.username,
    -- Normalise action to a friendly label
    CASE t.action
        WHEN 'Location.Create'     THEN 'CREATE'
        WHEN 'Location.Update'     THEN 'UPDATE'
        WHEN 'Location.Lock'       THEN 'LOCK'
        WHEN 'Location.Unlock'     THEN 'UNLOCK'
        WHEN 'Location.Deactivate' THEN 'DEACTIVATE'
        WHEN 'Location.Reactivate' THEN 'REACTIVATE'
        ELSE t.action
    END                                                                     AS action_type,

    -- Bin code (after for create/update, current for others)
    COALESCE(
        JSON_VALUE(t.payload_json, '$.Data.Outcome.BinCode'),
        JSON_VALUE(t.payload_json, '$.Data.Outcome.After.BinCode')
    )                                                                       AS bin_code,

    -- Before state (only meaningful on UPDATE)
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.BinCode')            AS bin_code_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.StorageTypeCode')    AS type_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.SectionCode')        AS section_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.ZoneCode')           AS zone_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.Capacity')  AS INT) AS capacity_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsActive')  AS BIT) AS active_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsLocked')  AS BIT) AS locked_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.Notes')              AS notes_before,

    -- After state (only meaningful on UPDATE)
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.BinCode')             AS bin_code_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.StorageTypeCode')     AS type_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.SectionCode')         AS section_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.ZoneCode')            AS zone_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.Capacity')   AS INT) AS capacity_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.Notes')               AS notes_after,

    -- Lock/deactivate reason
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Reason')                    AS reason

FROM audit.trace_logs t
LEFT JOIN auth.users u ON u.id = t.user_id
WHERE t.action IN (
    'Location.Create',
    'Location.Update',
    'Location.Lock',
    'Location.Unlock',
    'Location.Deactivate',
    'Location.Reactivate'
)
-- Only include the rich C# BuildResult rows (have $.Timestamp)
-- The SP-level rows are minimal duplicates without session context
AND JSON_VALUE(t.payload_json, '$.Timestamp') IS NOT NULL;
GO
PRINT 'audit.v_location_changes created.';
GO

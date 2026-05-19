USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW audit.v_sku_changes
AS
SELECT
    t.trace_id,
    t.occurred_at,
    u.username,
    CASE t.action
        WHEN 'Sku.Create' THEN 'INSERT'
        WHEN 'Sku.Update' THEN 'UPDATE'
    END                                                                       AS action_type,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.SkuCode')                     AS sku_code,

    -- Before state (NULL on INSERT)
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.SkuDescription')       AS desc_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.Ean')                  AS ean_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.UomCode')              AS uom_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.WeightPerUnit')      AS DECIMAL(10,3)) AS weight_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.StandardHuQuantity') AS INT)           AS hu_qty_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsBatchRequired')    AS BIT)           AS batch_req_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsFullHuRequired')   AS BIT)           AS full_hu_req_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsHazardous')        AS BIT)           AS hazardous_before,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.IsActive')           AS BIT)           AS active_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.StorageTypeCode')      AS storage_before,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.Before.SectionCode')          AS section_before,

    -- After state
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.SkuDescription')        AS desc_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.Ean')                   AS ean_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.UomCode')               AS uom_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.WeightPerUnit')       AS DECIMAL(10,3)) AS weight_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.StandardHuQuantity')  AS INT)           AS hu_qty_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.IsBatchRequired')     AS BIT)           AS batch_req_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.IsFullHuRequired')    AS BIT)           AS full_hu_req_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.IsHazardous')         AS BIT)           AS hazardous_after,
    TRY_CAST(JSON_VALUE(t.payload_json, '$.Data.Outcome.After.IsActive')            AS BIT)           AS active_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.StorageTypeCode')       AS storage_after,
    JSON_VALUE(t.payload_json, '$.Data.Outcome.After.SectionCode')           AS section_after

FROM audit.trace_logs t
LEFT JOIN auth.users u ON u.id = t.user_id
WHERE t.action IN ('Sku.Create', 'Sku.Update');
GO
PRINT 'audit.v_sku_changes: updated JSON paths to $.Data.Outcome.*';
GO

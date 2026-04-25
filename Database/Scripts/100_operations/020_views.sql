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

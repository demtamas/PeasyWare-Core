USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW auth.vw_session_forensic
AS
SELECT
    s.session_id,
    s.is_active,
    s.login_time,
    s.last_seen,

    u.id            AS user_id,
    u.username,
    u.display_name,

    s.client_app,
    s.client_info,

    la.ip_address,
    la.os_info,
    la.correlation_id

FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id

OUTER APPLY
(
    SELECT TOP (1)
        a.ip_address,
        a.os_info,
        a.correlation_id
    FROM auth.login_attempts a
    WHERE a.session_id = s.session_id
      AND a.success = 1
    ORDER BY a.attempt_time DESC
) la;
GO

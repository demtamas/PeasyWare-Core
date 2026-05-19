USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW auth.v_active_sessions
AS
SELECT
    s.session_id,
    u.username,
    s.client_app,
    s.client_info,
    s.last_seen,
    s.is_active
FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id
WHERE s.is_active = 1;
GO

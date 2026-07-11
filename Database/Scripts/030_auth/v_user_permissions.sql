USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-------------------------------------------------------------------------
-- auth.v_user_permissions
-- Flattened user -> permission list, one query at login (2b step 3).
-- Only active users, active roles, active permissions are surfaced.
-------------------------------------------------------------------------
CREATE OR ALTER VIEW auth.v_user_permissions
AS

SELECT
    u.id    AS user_id,
    u.username,
    p.permission_key

FROM auth.users u

JOIN auth.user_roles ur
    ON ur.user_id = u.id

JOIN auth.roles r
    ON r.id = ur.role_id
    AND r.is_active = 1

JOIN auth.role_permissions rp
    ON rp.role_id = r.id

JOIN auth.permissions p
    ON p.id = rp.permission_id
    AND p.is_active = 1

WHERE u.is_active = 1;
GO

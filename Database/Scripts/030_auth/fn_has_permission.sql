USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-------------------------------------------------------------------------
-- auth.fn_has_permission
-- RBAC guard primitive (Phase 2c). Returns 1 if the user holds the given
-- permission via any active role, 0 otherwise (NULL user_id -> 0).
--
-- System/API integration accounts (auth.roles.is_system_role = 1, e.g.
-- 'system', 'api') always pass — they're trusted automation identities,
-- not human operators bound by menu-level RBAC. This also matches how
-- the Tests/*.sql suite runs everything under the seeded api account.
--
-- Queries the base tables directly (not auth.v_user_permissions) so this
-- file has no cross-file ordering dependency — everything it needs lives
-- in 030_auth/010_tables.sql, same as auth.fn_is_system_user.
-------------------------------------------------------------------------
CREATE OR ALTER FUNCTION auth.fn_has_permission
(
    @user_id        INT,
    @permission_key NVARCHAR(100)
)
RETURNS BIT
AS
BEGIN
    DECLARE @has_permission BIT = 0;

    IF @user_id IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM auth.users u
            JOIN auth.user_roles ur ON ur.user_id = u.id
            JOIN auth.roles r       ON r.id = ur.role_id
            WHERE u.id = @user_id
              AND r.is_system_role = 1
        )
            RETURN 1;

        SELECT @has_permission = 1
        FROM auth.users u
        JOIN auth.user_roles ur       ON ur.user_id = u.id
        JOIN auth.roles r             ON r.id = ur.role_id AND r.is_active = 1
        JOIN auth.role_permissions rp ON rp.role_id = r.id
        JOIN auth.permissions p       ON p.id = rp.permission_id AND p.is_active = 1
        WHERE u.id = @user_id
          AND u.is_active = 1
          AND p.permission_key = @permission_key;
    END;

    RETURN ISNULL(@has_permission, 0);
END;
GO

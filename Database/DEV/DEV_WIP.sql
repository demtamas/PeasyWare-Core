USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — is_system_role on auth.roles + api role + api user
    Date: 2026-04-24

    1. Add is_system_role BIT column to auth.roles
    2. Mark existing 'system' role as system
    3. Insert 'api' role (is_system_role = 1)
    4. Insert 'api' user with api role
    5. Update usp_roles_get — exclude system roles from dropdown
    6. Update fn_is_system_user — role-based check instead of username hardcode
       (covers both 'system' and 'api' users automatically)
    7. v_users_admin already uses fn_is_system_user — no change needed
       (api user will be hidden from Desktop users list automatically)
********************************************************************************************/

-- ── 1. Add is_system_role column ────────────────────────────────────────

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('auth.roles')
      AND name = 'is_system_role'
)
BEGIN
    ALTER TABLE auth.roles
    ADD is_system_role BIT NOT NULL DEFAULT 0;
    PRINT 'auth.roles.is_system_role column added.';
END
ELSE
    PRINT 'auth.roles.is_system_role already exists — skipped.';
GO

-- ── 2. Mark system role ──────────────────────────────────────────────────

UPDATE auth.roles
SET is_system_role = 1
WHERE role_name = 'system';
PRINT 'system role marked as is_system_role = 1.';
GO

-- ── 3. Insert api role ───────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'api')
BEGIN
    INSERT INTO auth.roles (role_name, description, is_active, is_system_role, created_by)
    VALUES ('api', 'API integration role — system use only', 1, 1, @SystemUserId);
    PRINT 'api role created.';
END
ELSE
BEGIN
    -- Ensure existing api role is flagged correctly
    UPDATE auth.roles SET is_system_role = 1 WHERE role_name = 'api';
    PRINT 'api role already exists — is_system_role ensured.';
END
GO

-- ── 4. Insert api user ───────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username = 'api')
BEGIN
    EXEC auth.usp_create_user
        @username     = 'api',
        @display_name = 'PeasyWare API',
        @role_name    = 'api',
        @email        = 'api@pw.local',
        @password     = 'ChangeMe123!',
        @result_code  = NULL,
        @friendly_msg = NULL;
    PRINT 'api user created.';
END
ELSE
    PRINT 'api user already exists — skipped.';
GO

-- ── 5. usp_roles_get — exclude system roles ──────────────────────────────

CREATE OR ALTER PROCEDURE auth.usp_roles_get
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        role_name   AS RoleName,
        description AS Description
    FROM auth.roles
    WHERE is_active      = 1
      AND is_system_role = 0        -- never show system roles in user-facing dropdowns
    ORDER BY role_name;
END;
GO
PRINT 'auth.usp_roles_get updated — system roles excluded.';
GO

-- ── 6. fn_is_system_user — role-based check ──────────────────────────────
-- Previously hardcoded username = 'system'.
-- Now checks is_system_role on the user's assigned role.
-- Covers both 'system' and 'api' users (and any future system roles).

CREATE OR ALTER FUNCTION auth.fn_is_system_user
(
    @user_id INT
)
RETURNS BIT
AS
BEGIN
    DECLARE @is_system BIT = 0;

    SELECT @is_system = 1
    FROM auth.users u
    JOIN auth.user_roles ur ON ur.user_id = u.id
    JOIN auth.roles r       ON r.id = ur.role_id
    WHERE u.id = @user_id
      AND r.is_system_role = 1;

    RETURN @is_system;
END;
GO
PRINT 'auth.fn_is_system_user updated — role-based check.';
GO

PRINT '------------------------------------------------------------';
PRINT 'is_system_role patch complete.';
PRINT '------------------------------------------------------------';
GO

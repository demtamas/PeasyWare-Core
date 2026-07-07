USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Core reference data required for ALL environments.
-- Roles + admin user. Idempotent — safe to re-run.
-- Always included in reset-db.
--
-- NOTE: storage_types / storage_sections / zones / bins are NOT here —
-- they're all fully editable via the Warehouse menu, and a real
-- PeasyWare install starts with none of them defined. The operator
-- builds their own warehouse structure from scratch via the Storage
-- Types / Zones / Sections / Locations views. A demo version of all
-- four lives in 082_demo_locations.sql.
-- ============================================================

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

-- ── Roles ─────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'admin')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('admin', 'System administrator', @SystemUserId);
    PRINT 'Role admin created.';
END
ELSE PRINT 'Role admin already exists.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'manager')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('manager', 'Manager with elevated access', @SystemUserId);
    PRINT 'Role manager created.';
END
ELSE PRINT 'Role manager already exists.';

IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'operator')
BEGIN
    INSERT INTO auth.roles (role_name, description, created_by)
    VALUES ('operator', 'Operator with basic access', @SystemUserId);
    PRINT 'Role operator created.';
END
ELSE PRINT 'Role operator already exists.';
GO

-- ── Admin user ────────────────────────────────────────────────────────────

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

IF NOT EXISTS (SELECT 1 FROM auth.users WHERE username = 'admin')
BEGIN
    EXEC auth.usp_create_user
        @username     = 'admin',
        @display_name = 'Wannabee WMS Engineer',
        @role_name    = 'admin',
        @email        = 'tamas.demjen@pw.local',
        @password     = 'admin0',
        @result_code  = NULL,
        @friendly_msg = NULL;
    PRINT 'User admin created.';
END
ELSE PRINT 'User admin already exists.';
GO

-- ── System user role assignment ───────────────────────────────────────────
-- Must run after both system user and system role exist.

DECLARE @SysUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SysRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'system');

IF @SysUserId IS NOT NULL AND @SysRoleId IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.user_roles WHERE user_id = @SysUserId AND role_id = @SysRoleId)
BEGIN
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@SysUserId, @SysRoleId);
    PRINT 'System user assigned to system role.';
END

PRINT 'Core reference data complete.';
GO

-- ── Client application registrations ───────────────────────────────
-- Required for login to work correctly. session_timeout_minutes
-- overrides the global auth.session_timeout_minutes setting.

IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = 'PeasyWare.Desktop')
    INSERT INTO auth.clients (client_name, session_timeout_minutes, max_concurrent_sessions, description)
    VALUES ('PeasyWare.Desktop', 480, NULL, 'PeasyWare WMS desktop application');

IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = 'PeasyWare.CLI')
    INSERT INTO auth.clients (client_name, session_timeout_minutes, max_concurrent_sessions, description)
    VALUES ('PeasyWare.CLI', 60, NULL, 'PeasyWare WMS terminal / CLI application');

IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = 'PeasyWare.API')
    INSERT INTO auth.clients (client_name, session_timeout_minutes, max_concurrent_sessions, description)
    VALUES ('PeasyWare.API', NULL, NULL, 'PeasyWare API — uses global timeout');

PRINT 'Client app registrations done.';
GO

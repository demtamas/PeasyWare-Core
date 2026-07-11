USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Core reference data required for ALL environments.
-- Roles + admin user + client app registrations.
-- Idempotent — safe to re-run. Always included in reset-db.
--
-- NOT here (all in demo files, skipped by --no-demo):
--   storage_types, storage_sections, zones, bins  → 082_demo_locations.sql
--   parties, addresses, customers, suppliers      → 081_demo_parties.sql
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

-- ── Permissions ───────────────────────────────────────────────────────────
-- Verb-on-resource keys covering the current menu/flow surface (Phase 2a).
-- Core, not demo: RBAC must exist on a blank install.

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');

;WITH perms (permission_key, description) AS
(
    SELECT 'users.manage',           'Create, edit, enable/disable users'                   UNION ALL
    SELECT 'sessions.terminate_all', 'Force logout / revoke sessions'                       UNION ALL
    SELECT 'settings.write',         'Edit system-wide settings'                            UNION ALL
    SELECT 'materials.manage',       'Create/edit/disable materials (SKU master data)'      UNION ALL
    SELECT 'zones.manage',           'Create/edit zones and sections'                       UNION ALL
    SELECT 'storage_types.manage',   'Create/edit storage types'                            UNION ALL
    SELECT 'bins.manage',            'Bulk bin creation and maintenance'                    UNION ALL
    SELECT 'clients.manage',         'Create/edit client apps and session overrides'        UNION ALL
    SELECT 'inventory.adjust',       'Manual stock corrections'                             UNION ALL
    SELECT 'stock.status_change',    'Quarantine / hold / release / write-off'              UNION ALL
    SELECT 'sku_audit.view',         'View SKU audit / trace views'                         UNION ALL
    SELECT 'inbound.receive',        'Execute goods receipt'                                UNION ALL
    SELECT 'inbound.reverse',        'Reverse a receipt'                                    UNION ALL
    SELECT 'putaway.execute',        'Confirm putaway tasks'                                UNION ALL
    SELECT 'pick.execute',           'Create/confirm picks'                                 UNION ALL
    SELECT 'pick.reallocate',        'Cancel allocation / reallocate line'                  UNION ALL
    SELECT 'ship.execute',           'Confirm shipment'
)
INSERT INTO auth.permissions (permission_key, description, created_by)
SELECT p.permission_key, p.description, @SystemUserId
FROM perms p
WHERE NOT EXISTS (SELECT 1 FROM auth.permissions ap WHERE ap.permission_key = p.permission_key);

PRINT 'Permissions seeded.';
GO

-- ── Role → Permission mappings ─────────────────────────────────────────────
-- Operator: execution flows only.
-- Manager: operator set + corrections, reversals, status changes.
-- Admin: everything (dynamic — picks up any permission that exists).

;WITH role_perms (role_name, permission_key) AS
(
    SELECT 'operator', 'inbound.receive'      UNION ALL
    SELECT 'operator', 'putaway.execute'      UNION ALL
    SELECT 'operator', 'pick.execute'         UNION ALL
    SELECT 'operator', 'ship.execute'         UNION ALL

    SELECT 'manager',  'inbound.receive'      UNION ALL
    SELECT 'manager',  'putaway.execute'      UNION ALL
    SELECT 'manager',  'pick.execute'         UNION ALL
    SELECT 'manager',  'ship.execute'         UNION ALL
    SELECT 'manager',  'inventory.adjust'     UNION ALL
    SELECT 'manager',  'stock.status_change'  UNION ALL
    SELECT 'manager',  'inbound.reverse'      UNION ALL
    SELECT 'manager',  'pick.reallocate'      UNION ALL
    SELECT 'manager',  'sku_audit.view'       UNION ALL

    SELECT 'admin', permission_key FROM auth.permissions
)
INSERT INTO auth.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM role_perms rp
JOIN auth.roles r       ON r.role_name = rp.role_name
JOIN auth.permissions p ON p.permission_key = rp.permission_key
WHERE NOT EXISTS (
    SELECT 1 FROM auth.role_permissions existing
    WHERE existing.role_id = r.id AND existing.permission_id = p.id
);

PRINT 'Role permission mappings seeded.';
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

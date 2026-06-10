USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Error messages: Locations (Bin · Zone · Section) + Auth
-- ============================================================

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES

    -- ── Bin ────────────────────────────────────────────────────────────────
    (N'ERRBIN01', N'BIN', N'ERROR',
        N'Location not found.',
        N'usp_lock/unlock_bin: bin_code not found'),

    (N'ERRBIN02', N'BIN', N'ERROR',
        N'Location is already locked.',
        N'usp_lock_bin: is_locked = 1'),

    (N'ERRBIN03', N'BIN', N'ERROR',
        N'Location is not locked.',
        N'usp_unlock_bin: is_locked = 0'),

    (N'ERRBIN04', N'BIN', N'ERROR',
        N'A location with that code already exists.',
        N'usp_create_bin: duplicate bin_code'),

    (N'ERRBIN05', N'BIN', N'ERROR',
        N'Storage type not found.',
        N'usp_create_bin: storage_type_code not found'),

    (N'ERRBIN06', N'BIN', N'ERROR',
        N'Cannot rename a location that contains stock. Move or remove stock first.',
        N'usp_update_bin: rename blocked, unit_count > 0'),

    (N'ERRBIN07', N'BIN', N'ERROR',
        N'Cannot change storage type on a location that contains stock. Move or remove stock first.',
        N'usp_update_bin: type change blocked, unit_count > 0'),

    (N'ERRBIN08', N'BIN', N'ERROR',
        N'Location is already inactive.',
        N'usp_deactivate_bin: is_active = 0'),

    (N'ERRBIN09', N'BIN', N'ERROR',
        N'Cannot deactivate a location that contains stock. Move the stock first.',
        N'usp_deactivate_bin: stock present'),

    (N'ERRBIN10', N'BIN', N'ERROR',
        N'Cannot deactivate a location with open warehouse tasks. Complete or cancel the tasks first.',
        N'usp_deactivate_bin: open tasks present'),

    (N'ERRBIN11', N'BIN', N'ERROR',
        N'Location is already active.',
        N'usp_reactivate_bin: is_active = 1'),

    (N'ERRBIN12', N'BIN', N'ERROR',
        N'Location must be deactivated before it can be deleted.',
        N'usp_delete_bin: is_active = 1'),

    (N'ERRBIN13', N'BIN', N'ERROR',
        N'Cannot delete — this location has operational history (movements, placements or tasks). Deactivate instead.',
        N'usp_delete_bin: referenced in movements/placements/tasks'),

    (N'ERRBIN99', N'BIN', N'ERROR',
        N'An unexpected error occurred.',
        N'usp_*_bin: unhandled exception'),

    (N'SUCBIN01', N'BIN', N'SUCCESS', N'Location locked.',       N'usp_lock_bin: success'),
    (N'SUCBIN02', N'BIN', N'SUCCESS', N'Location unlocked.',     N'usp_unlock_bin: success'),
    (N'SUCBIN03', N'BIN', N'SUCCESS', N'Location created.',      N'usp_create_bin: success'),
    (N'SUCBIN04', N'BIN', N'SUCCESS', N'Locations created.',     N'usp_create_bins_bulk: success'),
    (N'SUCBIN05', N'BIN', N'SUCCESS', N'Location updated.',      N'usp_update_bin: success'),
    (N'SUCBIN06', N'BIN', N'SUCCESS', N'Location deactivated.',  N'usp_deactivate_bin: success'),
    (N'SUCBIN07', N'BIN', N'SUCCESS', N'Location reactivated.',  N'usp_reactivate_bin: success'),
    (N'SUCBIN08', N'BIN', N'SUCCESS', N'Locations activated.',   N'usp_activate_bins: success'),
    (N'SUCBIN09', N'BIN', N'SUCCESS', N'Location deleted.',      N'usp_delete_bin: success'),

    -- ── Zone ───────────────────────────────────────────────────────────────
    (N'ERRZON01', N'ZONE', N'ERROR',
        N'A zone with that code already exists.',
        N'usp_create_zone: duplicate zone_code'),

    (N'ERRZON02', N'ZONE', N'ERROR',
        N'Zone not found.',
        N'usp_update/deactivate/reactivate_zone: zone_code not found'),

    (N'ERRZON03', N'ZONE', N'ERROR',
        N'Cannot delete — bins are assigned to this zone. Reassign them first.',
        N'usp_delete_zone: bins exist with zone_id'),

    (N'ERRZON99', N'ZONE', N'ERROR',
        N'An unexpected error occurred.',
        N'usp_*_zone: unhandled exception'),

    (N'SUCZON01', N'ZONE', N'SUCCESS', N'Zone created.',               N'usp_create_zone: success'),
    (N'SUCZON02', N'ZONE', N'SUCCESS', N'Zone updated.',               N'usp_update_zone: success'),
    (N'SUCZON03', N'ZONE', N'SUCCESS', N'Zone deactivated.',           N'usp_deactivate_zone: success'),
    (N'SUCZON04', N'ZONE', N'SUCCESS', N'Zone reactivated.',           N'usp_reactivate_zone: success'),
    (N'SUCZON05', N'ZONE', N'SUCCESS', N'Bins assigned to zone.',      N'usp_assign_bins_to_zone: success'),
    (N'SUCZON06', N'ZONE', N'SUCCESS', N'Zone deleted.',               N'usp_delete_zone: success'),

    -- ── Section ────────────────────────────────────────────────────────────
    (N'ERRSEC01', N'SEC', N'ERROR',
        N'A section with that code already exists.',
        N'usp_create_section: duplicate section_code'),

    (N'ERRSEC02', N'SEC', N'ERROR',
        N'Section not found.',
        N'usp_update/deactivate/reactivate_section: section_code not found'),

    (N'ERRSEC03', N'SEC', N'ERROR',
        N'Cannot delete — bins are assigned to this section. Reassign them first.',
        N'usp_delete_section: bins exist with storage_section_id'),

    (N'ERRSEC99', N'SEC', N'ERROR',
        N'An unexpected error occurred.',
        N'usp_*_section: unhandled exception'),

    (N'SUCSEC01', N'SEC', N'SUCCESS', N'Section created.',             N'usp_create_section: success'),
    (N'SUCSEC02', N'SEC', N'SUCCESS', N'Section updated.',             N'usp_update_section: success'),
    (N'SUCSEC03', N'SEC', N'SUCCESS', N'Section deactivated.',         N'usp_deactivate_section: success'),
    (N'SUCSEC04', N'SEC', N'SUCCESS', N'Section reactivated.',         N'usp_reactivate_section: success'),
    (N'SUCSEC05', N'SEC', N'SUCCESS', N'Bins assigned to section.',    N'usp_assign_bins_to_section: success'),
    (N'SUCSEC06', N'SEC', N'SUCCESS', N'Section deleted.',             N'usp_delete_section: success'),

    -- ── Auth — user management ─────────────────────────────────────────────
    (N'SUCAUTH08',    N'AUTH', N'SUCCESS',
        N'User updated.',
        N'usp_update_user: success'),

    (N'SUCAUTH09',    N'AUTH', N'SUCCESS',
        N'Sessions terminated.',
        N'usp_logout_all_sessions: success'),

    (N'ERRAUTHUSR05', N'AUTH', N'ERROR',
        N'User not found.',
        N'usp_update_user: user_id not found'),

    (N'ERRAUTHUSR06', N'AUTH', N'ERROR',
        N'Role not found.',
        N'usp_update_user: role_name not found in auth.roles')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO
PRINT 'Location / Zone / Section / Auth error codes seeded.';
GO

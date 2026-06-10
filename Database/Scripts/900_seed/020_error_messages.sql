USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCLOAD01', N'LOAD', N'INFO',
    N'Order loaded onto vehicle successfully.',
    N'Load.Confirm: order status LOADED, shipment LOADING'
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCLOAD01'
);
GO
PRINT 'SUCLOAD01 message inserted.';
GO
GO

-- ============================================================
-- API creation error codes and stored procedures
-- Merged from WIP: 2026-04-24
-- ============================================================
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU01', N'SKU', N'ERROR', N'SKU not found.', N'inventory.usp_create_sku: sku_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU02', N'SKU', N'ERROR', N'A SKU with this code already exists.', N'inventory.usp_create_sku: duplicate sku_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSKU01', N'SKU', N'SUCCESS', N'SKU created successfully.', N'inventory.usp_create_sku: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB02', N'INB', N'ERROR', N'An inbound delivery with this reference already exists.', N'inbound.usp_create_inbound: duplicate inbound_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINB02', N'INB', N'SUCCESS', N'Inbound delivery created successfully.', N'inbound.usp_create_inbound: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBL02', N'INB', N'SUCCESS', N'Inbound line created successfully.', N'inbound.usp_create_inbound_line: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBL02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBU01', N'INB', N'SUCCESS', N'Expected unit created successfully.', N'inbound.usp_create_expected_unit: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINBU01', N'INB', N'ERROR', N'This SSCC is already registered on this inbound delivery.', N'inbound.usp_create_expected_unit: duplicate sscc on inbound'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINBU01');

-- SUCINB03: inbound cancelled
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINB03', N'INB', N'SUCCESS', N'Inbound delivery cancelled.', N'inbound.usp_cancel_inbound: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINB03');

-- ERRINB03: inbound not found
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB03', N'INB', N'ERROR', N'Inbound delivery not found.', N'inbound.usp_cancel_inbound: inbound_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB03');

-- ERRINB04: already terminal
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB04', N'INB', N'ERROR', N'This inbound is already closed or cancelled.', N'inbound.usp_cancel_inbound: status is CLS or CNL'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB04');

-- ERRINB05: receiving in progress
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB05', N'INB', N'ERROR', N'Cannot cancel — receiving is in progress on this delivery.', N'inbound.usp_cancel_inbound: status is RCV'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB05');

-- ERRINB06: receipts exist
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB06', N'INB', N'ERROR', N'Cannot cancel — units have already been received against this delivery. Reverse all receipts first.', N'inbound.usp_cancel_inbound: receipts exist on activated inbound'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD02', N'ORD', N'ERROR', N'An order with this reference already exists.', N'outbound.usp_create_order: duplicate order_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCORD01', N'ORD', N'SUCCESS', N'Order created successfully.', N'outbound.usp_create_order: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCORD01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP02', N'SHIP', N'ERROR', N'A shipment with this reference already exists.', N'outbound.usp_create_shipment: duplicate shipment_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP01', N'SHIP', N'SUCCESS', N'Shipment created successfully.', N'outbound.usp_create_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP03', N'SHIP', N'ERROR', N'Shipment not found.', N'outbound.usp_add_order_to_shipment: shipment_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD03', N'ORD', N'ERROR', N'Order not found.', N'outbound.usp_add_order_to_shipment: order_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP03', N'SHIP', N'SUCCESS', N'Order added to shipment successfully.', N'outbound.usp_add_order_to_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP03');

GO
-- ── 1. inventory.usp_create_sku ─────────────────────────────────────────
GO

-- ERRSHIP05: vehicle ref required at departure
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP05', N'OUTBOUND', N'ERROR', N'Vehicle registration is required before departure.', N'outbound.usp_ship: @vehicle_ref is null or empty'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP05');

-- SUCSHIP04: shipment cancelled
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP04', N'SHIP', N'SUCCESS', N'Shipment cancelled.', N'outbound.usp_cancel_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP04');

-- ERRSHIP06: shipment not found
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP06', N'SHIP', N'ERROR', N'Shipment not found.', N'outbound.usp_cancel_shipment: shipment_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP06');

-- ERRSHIP07: shipment already terminal
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP07', N'SHIP', N'ERROR', N'This shipment has already departed or been cancelled.', N'outbound.usp_cancel_shipment: status is DEPARTED or CNL'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP07');

-- ERRSHIP08: orders in progress
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP08', N'SHIP', N'ERROR', N'Cannot cancel — orders on this shipment are being picked or have been loaded. Reverse picks first.', N'outbound.usp_cancel_shipment: orders in PICKING/PICKED/LOADED state'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP08');

-- ERRSKU03: owner party not found
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU03', N'SKU', N'ERROR', N'Owner party not found or inactive.', N'inventory.usp_create_sku: @owner_party_code not found in core.parties'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU03');

-- ERRSKU04: owner required in multi-owner mode
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU04', N'SKU', N'ERROR', N'Owner is required when multi-owner mode is enabled.', N'inventory.usp_create_sku: @owner_party_code is null but inventory.enable_multi_owner = true'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU04');

-- ERRPARTY01: party code already exists
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRPARTY01', N'PARTY', N'ERROR', N'A party with this code already exists.', N'core.usp_create_party: duplicate party_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRPARTY01');

-- ERRPARTY02: party not found
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRPARTY02', N'PARTY', N'ERROR', N'Party not found.', N'core.usp_update_party: party_id not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRPARTY02');

-- ERRPARTY99: unexpected error
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRPARTY99', N'PARTY', N'ERROR', N'Unexpected error processing party.', N'core.usp_create_party/usp_update_party: unhandled exception'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRPARTY99');

-- ── BIN / LOCATION ────────────────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN01', N'BIN', N'ERROR', N'Location not found.', N'usp_lock/unlock_bin: bin_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN02', N'BIN', N'ERROR', N'Location is already locked.', N'usp_lock_bin: is_locked = 1'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN03', N'BIN', N'ERROR', N'Location is not locked.', N'usp_unlock_bin: is_locked = 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN04', N'BIN', N'ERROR', N'A location with that code already exists.', N'usp_create_bin: duplicate bin_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN04');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN05', N'BIN', N'ERROR', N'Storage type not found.', N'usp_create_bin: storage_type_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN99', N'BIN', N'ERROR', N'An unexpected error occurred.', N'usp_*_bin: unhandled exception'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN99');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN01', N'BIN', N'SUCCESS', N'Location locked.', N'usp_lock_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN02', N'BIN', N'SUCCESS', N'Location unlocked.', N'usp_unlock_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN03', N'BIN', N'SUCCESS', N'Location created.', N'usp_create_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN04', N'BIN', N'SUCCESS', N'Locations created.', N'usp_create_bins_bulk: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN04');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN05', N'BIN', N'SUCCESS', N'Location updated.', N'usp_update_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN06', N'BIN', N'ERROR', N'Cannot rename a location that contains stock. Move or remove stock first.', N'usp_update_bin: rename blocked, unit_count > 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN07', N'BIN', N'ERROR', N'Cannot change storage type on a location that contains stock. Move or remove stock first.', N'usp_update_bin: type change blocked, unit_count > 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN07');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN08', N'BIN', N'ERROR', N'Location is already inactive.', N'usp_deactivate_bin: is_active = 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN08');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN09', N'BIN', N'ERROR', N'Cannot deactivate a location that contains stock. Move the stock first.', N'usp_deactivate_bin: stock present'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN09');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN10', N'BIN', N'ERROR', N'Cannot deactivate a location with open warehouse tasks. Complete or cancel the tasks first.', N'usp_deactivate_bin: open tasks present'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN10');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN11', N'BIN', N'ERROR', N'Location is already active.', N'usp_reactivate_bin: is_active = 1'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN11');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN06', N'BIN', N'SUCCESS', N'Location deactivated.', N'usp_deactivate_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN07', N'BIN', N'SUCCESS', N'Location reactivated.', N'usp_reactivate_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN07');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN08', N'BIN', N'SUCCESS', N'Locations activated.', N'usp_activate_bins: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN08');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCBIN09', N'BIN', N'SUCCESS', N'Location deleted.', N'usp_delete_bin: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCBIN09');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN12', N'BIN', N'ERROR', N'Location must be deactivated before it can be deleted.', N'usp_delete_bin: is_active = 1'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN12');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN13', N'BIN', N'ERROR', N'Cannot delete — this location has operational history (movements, placements or tasks). Deactivate instead.', N'usp_delete_bin: referenced in movements/placements/tasks'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN13');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRZON03', N'ZONE', N'ERROR', N'Cannot delete — bins are assigned to this zone. Reassign them first.', N'usp_delete_zone: bins exist with zone_id'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRZON03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON06', N'ZONE', N'SUCCESS', N'Zone deleted.', N'usp_delete_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSEC03', N'SEC', N'ERROR', N'Cannot delete — bins are assigned to this section. Reassign them first.', N'usp_delete_section: bins exist with storage_section_id'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSEC03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC06', N'SEC', N'SUCCESS', N'Section deleted.', N'usp_delete_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC06');

-- ── ZONES ─────────────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRZON01', N'ZONE', N'ERROR', N'A zone with that code already exists.', N'usp_create_zone: duplicate zone_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRZON01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRZON02', N'ZONE', N'ERROR', N'Zone not found.', N'usp_update/deactivate/reactivate_zone: zone_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRZON02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRZON99', N'ZONE', N'ERROR', N'An unexpected error occurred.', N'usp_*_zone: unhandled exception'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRZON99');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON01', N'ZONE', N'SUCCESS', N'Zone created.', N'usp_create_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON02', N'ZONE', N'SUCCESS', N'Zone updated.', N'usp_update_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON03', N'ZONE', N'SUCCESS', N'Zone deactivated.', N'usp_deactivate_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON04', N'ZONE', N'SUCCESS', N'Zone reactivated.', N'usp_reactivate_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON04');

-- ── SECTIONS ──────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSEC01', N'SEC', N'ERROR', N'A section with that code already exists.', N'usp_create_section: duplicate section_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSEC01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSEC02', N'SEC', N'ERROR', N'Section not found.', N'usp_update/deactivate/reactivate_section: section_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSEC02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSEC99', N'SEC', N'ERROR', N'An unexpected error occurred.', N'usp_*_section: unhandled exception'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSEC99');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC01', N'SEC', N'SUCCESS', N'Section created.', N'usp_create_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC02', N'SEC', N'SUCCESS', N'Section updated.', N'usp_update_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC03', N'SEC', N'SUCCESS', N'Section deactivated.', N'usp_deactivate_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC04', N'SEC', N'SUCCESS', N'Section reactivated.', N'usp_reactivate_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC04');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSEC05', N'SEC', N'SUCCESS', N'Bins assigned to section.', N'usp_assign_bins_to_section: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSEC05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCZON05', N'ZONE', N'SUCCESS', N'Bins assigned to zone.', N'usp_assign_bins_to_zone: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCZON05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCAUTH08', N'AUTH', N'SUCCESS', N'User updated.', N'usp_update_user: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCAUTH08');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCAUTH09', N'AUTH', N'SUCCESS', N'Sessions terminated.', N'usp_logout_all_sessions: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCAUTH09');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRAUTHUSR05', N'AUTH', N'ERROR', N'User not found.', N'usp_update_user: user_id not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRAUTHUSR05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRAUTHUSR06', N'AUTH', N'ERROR', N'Role not found.', N'usp_update_user: role_name not found in auth.roles'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRAUTHUSR06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN06', N'BIN', N'ERROR', N'Cannot rename a location that contains stock. Move or remove stock first.', N'usp_update_bin: rename blocked, unit_count > 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRBIN07', N'BIN', N'ERROR', N'Cannot change storage type on a location that contains stock. Move or remove stock first.', N'usp_update_bin: type change blocked, unit_count > 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRBIN07');

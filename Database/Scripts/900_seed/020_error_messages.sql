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

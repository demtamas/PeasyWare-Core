USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Error messages: Inbound · SKU · Inventory · Party
-- ============================================================

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES

    -- ── Inbound ────────────────────────────────────────────────────────────
    (N'ERRINB02',  N'INB', N'ERROR',
        N'An inbound delivery with this reference already exists.',
        N'inbound.usp_create_inbound: duplicate inbound_ref'),

    (N'ERRINB03',  N'INB', N'ERROR',
        N'Inbound delivery not found.',
        N'inbound.usp_cancel_inbound: inbound_ref not found'),

    (N'ERRINB04',  N'INB', N'ERROR',
        N'This inbound is already closed or cancelled.',
        N'inbound.usp_cancel_inbound: status is CLS or CNL'),

    (N'ERRINB05',  N'INB', N'ERROR',
        N'Cannot cancel — receiving is in progress on this delivery.',
        N'inbound.usp_cancel_inbound: status is RCV'),

    (N'ERRINB06',  N'INB', N'ERROR',
        N'Cannot cancel — units have already been received against this delivery. Reverse all receipts first.',
        N'inbound.usp_cancel_inbound: receipts exist on activated inbound'),

    (N'SUCINB02',  N'INB', N'SUCCESS',
        N'Inbound delivery created successfully.',
        N'inbound.usp_create_inbound: success'),

    (N'SUCINB03',  N'INB', N'SUCCESS',
        N'Inbound delivery cancelled.',
        N'inbound.usp_cancel_inbound: success'),

    (N'SUCINBL02', N'INB', N'SUCCESS',
        N'Inbound line created successfully.',
        N'inbound.usp_create_inbound_line: success'),

    (N'SUCINBU01', N'INB', N'SUCCESS',
        N'Expected unit created successfully.',
        N'inbound.usp_create_expected_unit: success'),

    (N'ERRINBU01', N'INB', N'ERROR',
        N'This SSCC is already registered on this inbound delivery.',
        N'inbound.usp_create_expected_unit: duplicate sscc on inbound'),

    -- ── SKU ────────────────────────────────────────────────────────────────
    (N'ERRSKU01',  N'SKU', N'ERROR',
        N'SKU not found.',
        N'inventory.usp_create_sku: sku_code not found'),

    (N'ERRSKU02',  N'SKU', N'ERROR',
        N'A SKU with this code already exists.',
        N'inventory.usp_create_sku: duplicate sku_code'),

    (N'ERRSKU03',  N'SKU', N'ERROR',
        N'Owner party not found or inactive.',
        N'inventory.usp_create_sku: @owner_party_code not found in core.parties'),

    (N'ERRSKU04',  N'SKU', N'ERROR',
        N'Owner is required when multi-owner mode is enabled.',
        N'inventory.usp_create_sku: @owner_party_code is null but inventory.enable_multi_owner = true'),

    (N'SUCSKU01',  N'SKU', N'SUCCESS',
        N'SKU created successfully.',
        N'inventory.usp_create_sku: success'),

    (N'SUCSKU02',  N'SKU', N'SUCCESS',
        N'SKU updated successfully.',
        N'inventory.usp_update_sku: success'),

    -- ── Inventory ──────────────────────────────────────────────────────────
    (N'SUCINV01',  N'INVENTORY', N'INFO',
        N'Stock status updated successfully.',
        N'inventory.usp_update_stock_status: OK'),

    (N'ERRINV02',  N'INVENTORY', N'ERROR',
        N'Invalid stock status code.',
        N'inventory.usp_update_stock_status: status not found'),

    (N'ERRINV99',  N'INVENTORY', N'ERROR',
        N'Unexpected error updating stock status.',
        N'inventory.usp_update_stock_status: CATCH block'),

    -- ── Party ──────────────────────────────────────────────────────────────
    (N'ERRPARTY01', N'PARTY', N'ERROR',
        N'A party with this code already exists.',
        N'core.usp_create_party: duplicate party_code'),

    (N'ERRPARTY02', N'PARTY', N'ERROR',
        N'Party not found.',
        N'core.usp_update_party: party_id not found'),

    (N'ERRPARTY99', N'PARTY', N'ERROR',
        N'Unexpected error processing party.',
        N'core.usp_create_party/usp_update_party: unhandled exception')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO
PRINT 'Inbound / SKU / Inventory / Party error codes seeded.';
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSKU02', N'SKU', N'SUCCESS', N'SKU updated successfully.', N'inventory.usp_update_sku: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSKU02');
GO

-- ── usp_update_sku ─────────────────────────────────────────────────────────────
GO

-- Inventory status update
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINV01', N'INVENTORY', N'INFO', N'Stock status updated successfully.', N'inventory.usp_update_stock_status: OK'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINV01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINV02', N'INVENTORY', N'ERROR', N'Invalid stock status code.', N'inventory.usp_update_stock_status: status not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINV02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINV99', N'INVENTORY', N'ERROR', N'Unexpected error updating stock status.', N'inventory.usp_update_stock_status: CATCH block'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINV99');

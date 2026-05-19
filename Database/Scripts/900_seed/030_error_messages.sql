USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE01', N'MOVE', N'ERROR', N'Unit not found. Please check the SSCC and try again.', N'usp_bin_to_bin_move_create: external_ref not found in inventory_units'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE02', N'MOVE', N'ERROR', N'This unit is not in a moveable state.', N'usp_bin_to_bin_move_create: stock_state_code not PUT or RCD'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE03', N'MOVE', N'ERROR', N'Unit has no current location. Cannot create a move task.', N'usp_bin_to_bin_move_create: no placement record found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE04', N'MOVE', N'ERROR', N'Destination bin not found. Please check the bin code.', N'usp_bin_to_bin_move_create: destination_bin_code not found in locations.bins'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE04');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE05', N'MOVE', N'ERROR', N'Move task not found or no longer active.', N'usp_bin_to_bin_move_confirm: task_id not found or not OPN/CLM'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE05');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRMOVE06', N'MOVE', N'ERROR', N'Wrong location. Please scan the correct destination bin.', N'usp_bin_to_bin_move_confirm: scanned_bin_code does not match task destination_bin_id'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRMOVE06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCMOVE01', N'MOVE', N'SUCCESS', N'Move task created.', N'usp_bin_to_bin_move_create: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCMOVE01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCMOVE02', N'MOVE', N'SUCCESS', N'Unit moved successfully.', N'usp_bin_to_bin_move_confirm: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCMOVE02');

GO
PRINT 'Move error messages inserted.';
GO

-- ── warehouse.usp_bin_to_bin_move_create ─────────────────────────────────────
GO

-- Task cancel codes
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCTASK03', N'WAREHOUSE', N'INFO', N'Task cancelled successfully.', N'warehouse.usp_cancel_task: OK'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCTASK03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRTASK06', N'WAREHOUSE', N'ERROR', N'Task is already in a terminal state and cannot be cancelled.', N'warehouse.usp_cancel_task: is_terminal = 1'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRTASK06');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRTASK07', N'WAREHOUSE', N'ERROR', N'Task cancellation is not permitted from its current state.', N'warehouse.usp_cancel_task: invalid transition'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRTASK07');

IF NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRAUTH01')
BEGIN
    INSERT INTO operations.error_messages
        (error_code, module_code, severity, message_template, tech_messege)
    VALUES
        (N'ERRAUTH01', N'AUTH', N'ERROR',
            N'Invalid username or password.',
            N'Auth: Credentials invalid'),

        (N'ERRAUTH02', N'AUTH', N'ERROR',
            N'Your account is blocked. Please contact your system administrator.',
            N'Auth: Account inactive or blocked'),

        (N'ERRAUTH03', N'AUTH', N'ERROR', 
            N'Login is currently disabled for this site.',
            N'Auth: Global login disabled'),

        (N'ERRAUTH04', N'AUTH', N'ERROR',
            N'Your password has expired. Please reset your password.',
            N'Auth: Password expired'),

        (N'ERRAUTH05', N'AUTH', N'ERROR',
            N'You are already logged in on another session.',
            N'Auth: Concurrent session exists'),

        (N'ERRAUTH06', N'AUTH', N'ERROR',
            N'Your session is no longer active. Please log in again.',
            N'Auth: Session inactive/expired'),

        (N'ERRAUTH07', N'AUTH', N'ERROR',
            N'Too many failed attempts. Please try again later.',
            N'Auth: Lockout threshold reached'),

        (N'ERRAUTH08', N'AUTH', N'ERROR',
            N'Invalid credentials. Login temporarily locked.',
            N'Auth: Progressive lockout'),

        (N'ERRAUTH09', N'AUTH', N'WARN',
            N'Your password has expired. You must change it.',
            N'Auth: Mandatory password change'),

        (N'ERRAUTH10', N'AUTH', N'WARN',
            N'New password does not meet complexity requirements.',
            N'Auth: Complexity rules failed'),

        (N'ERRAUTH11', N'AUTH', N'WARN',
            N'New password must differ from your recent passwords.',
            N'Auth: Password reuse detected'),

        (N'SUCAUTH01', N'AUTH', N'INFO',
            N'Login successful. Welcome back!',
            N'Auth: Login OK'),

        (N'SUCAUTH02', N'AUTH', N'INFO',
            N'Session refreshed successfully.',
            N'Auth: Session heartbeat OK'),

        (N'SUCAUTH03', N'AUTH', N'INFO',
            N'Logout successful.',
            N'Auth: Session closed'),

        (N'SUCAUTH10', N'AUTH', N'INFO',
            N'Password changed successfully.',
            N'Auth: Password updated'),

        (N'ERRAUTHUSR01', N'AUTH', N'ERROR',
            N'A user with this username already exists.',
            N'Auth.CreateUser: Duplicate username'),

        (N'ERRAUTHUSR02', N'AUTH', N'ERROR',
            N'The selected role does not exist.',
            N'Auth.CreateUser: Invalid role'),

        (N'ERRAUTHUSR03', N'AUTH', N'ERROR',
            N'User creation failed due to a system error.',
            N'Auth.CreateUser: Insert failed'),

        (N'WARAUTHUSR01', N'AUTH', N'WARN',
            N'The password is valid but considered weak.',
            N'Auth.CreateUser: Weak password'),

        (N'ERRAUTHUSR04', N'AUTH', N'ERROR',
            N'A user with this email address already exists.',
            N'Auth.CreateUser: Duplicate email'),

        (N'SUCAUTHUSR01', N'AUTH', N'INFO',
            N'User account created successfully.',
            N'Auth.CreateUser: Success'),

        (N'ERRINB01', N'INB', N'ERROR',
            N'Inbound delivery not found.',
            N'Inbound.Activate: inbound_id not found'),

        (N'ERRINB02', N'INB', N'ERROR',
            N'Inbound delivery is already activated.',
            N'Inbound.Activate: already ACTIVATED'),

        (N'ERRINB03', N'INB', N'ERROR',
            N'Inbound delivery has no lines and cannot be activated.',
            N'Inbound.Activate: no inbound_lines exist'),

        (N'ERRINB04', N'INB', N'ERROR',
            N'Inbound delivery is cancelled and cannot be activated.',
            N'Inbound.Activate: inbound_status = CANCELLED'),

        (N'ERRINB05', N'INB', N'ERROR',
            N'Inbound delivery is not in a valid state for this operation.',
            N'Inbound: invalid inbound_status transition'),

        (N'SUCINB01', N'INB', N'INFO',
            N'Inbound delivery activated successfully.',
            N'Inbound.Activate: success'),

        (N'SUCINBCLS01',     N'INB', N'INFO',
            N'Inbound delivery fully received and closed.',
            N'Inbound.Header: auto-closed after final receipt'),

        (N'SUCINBREOPEN01',  N'INB', N'INFO',
            N'Inbound delivery reopened following receipt reversal.',
            N'Inbound.Header: reopened after reversal'),

        (N'ERRINBL01', N'INB', N'ERROR',
            N'Inbound line not found.',
            N'Inbound.Line: inbound_line_id not found'),

        (N'ERRINBL03', N'INB', N'ERROR',
            N'Inbound line is already fully received.',
            N'Inbound.Line: already RECEIVED'),

        (N'SUCINBL01', N'INB', N'INFO',
            N'Inbound line received successfully.',
            N'Inbound.Line: receipt success'),

        (N'ERRINBL02', N'INB', N'ERROR',
            N'Receiving quantity must be greater than zero.',
            N'Inbound.Line: invalid quantity <= 0'),

        (N'ERRINBL04', N'INB', N'ERROR',
            N'Inbound is not in a receivable state.',
            N'Inbound.Header: not ACTIVATED or RECEIVING'),

        (N'ERRINBL05', N'INB', N'ERROR',
            N'Invalid or inactive staging bin.',
            N'Inbound.Line: staging bin invalid'),

        (N'ERRINBL99', N'INB', N'ERROR',
            N'Unexpected error while receiving inbound line.',
            N'Inbound.Line: unhandled exception'),

        (N'ERRSSCC01', N'SSCC', N'ERROR',
            N'SSCC not recognised. Please verify the barcode and try again.',
            N'SSCC.Validate: SSCC not found'),

        (N'ERRSSCC02', N'SSCC', N'ERROR',
            N'SSCC already exists and is currently active.',
            N'SSCC.Validate: duplicate active SSCC'),

        (N'ERRSSCC03', N'SSCC', N'ERROR',
            N'SSCC is already linked to another inbound delivery.',
            N'SSCC.Validate: linked to different inbound'),

        (N'ERRSSCC04', N'SSCC', N'ERROR',
            N'SSCC cannot be reused while active. Complete or cancel the previous transaction first.',
            N'SSCC.Validate: reuse blocked - active record exists'),

        (N'ERRSSCC05', N'SSCC', N'WARN',
            N'SSCC reuse is allowed only for returned units. Please confirm return process.',
            N'SSCC.Validate: reuse requires return context'),

        (N'ERRQTY01', N'INB', N'ERROR',
            N'Received quantity exceeds expected quantity for this inbound line.',
            N'Inbound.Line: quantity > expected'),

        (N'ERRQTY03', N'INB', N'ERROR',
            N'Unit of measure mismatch. Please use the expected UOM for this material.',
            N'Inbound.Line: UOM mismatch'),

        (N'ERRQTY04', N'INB', N'ERROR',
            N'Full handling unit quantity required for this SSCC.',
            N'Inbound.Line: partial HU not allowed'),

        (N'ERRMAT01', N'INB', N'ERROR',
            N'Material could not be resolved from the scanned GTIN.',
            N'Inbound.Line: GTIN resolution failed'),

        (N'ERRMAT02', N'INB', N'ERROR',
            N'Material is not expected on this inbound delivery.',
            N'Inbound.Line: material not on inbound'),

        (N'ERRMAT03', N'INB', N'ERROR',
            N'Multiple materials match this GTIN. Manual selection required.',
            N'Inbound.Line: ambiguous GTIN mapping'),

        (N'ERRMAT04', N'INB', N'ERROR',
            N'Material master data incomplete. Please contact master data team.',
            N'Inbound.Line: material master incomplete'),

        (N'ERRPROC01', N'CORE', N'ERROR',
            N'Operation not allowed in current document status.',
            N'Process.Validate: invalid status transition'),

        (N'ERRPROC02', N'CORE', N'ERROR',
            N'Transaction validation failed. Please review the scanned data.',
            N'Process.Validate: business rule failure'),

        (N'ERRPROC03', N'CORE', N'ERROR',
            N'Another user is currently processing this document.',
            N'Process.Locking: record locked'),

        (N'ERRPROC04', N'CORE', N'INFO',
            N'Process cancelled. No changes were saved.',
            N'Process: user cancelled transaction'),

        (N'ERRSSCC06', N'SSCC', N'ERROR',
            N'SSCC has already been received for this inbound delivery.',
            N'SSCC.Validate: already received on same inbound'),

        (N'ERRINB06', N'INB', N'ERROR',
            N'Inbound delivery is already fully received and closed.',
            N'Inbound.Receive: attempt after CLOSED'),

        (N'SUCSSCC01', N'SSCC', N'INFO',
            N'SSCC validated successfully. Please scan again to confirm receipt.',
            N'SSCC.Validate: claim acquired'),

        (N'ERRSSCC07', N'SSCC', N'ERROR',
             N'SSCC is currently being processed by another user.',
             N'SSCC.Receive: active claim held by different session'),

        (N'ERRSSCC08', N'SSCC', N'ERROR',
             N'SSCC confirmation window expired. Please rescan to validate again.',
             N'SSCC.Receive: claim expired'),

        (N'ERRSSCC09', N'SSCC', N'ERROR',
             N'SSCC confirmation token invalid. Please rescan to validate again.',
             N'SSCC.Receive: claim token mismatch'),

        (N'ERRSSCC99', N'SSCC', N'ERROR',
             N'SSCC validation failed. Please rescan. If it persists, contact a supervisor.',
             N'SSCC.Preview: unexpected system error'),

        (N'ERRINBHYB01', N'INBOUND', N'ERROR',
            N'Inbound structure invalid. Please contact warehouse supervisor',
            N'Inbound.Activate: hybrid SSCC + manual structure detected'),

        (N'ERRINBMODE01', N'INBOUND', N'ERROR',
            N'Inbound mode already determined and cannot be changed.',
            N'Inbound.Activate: attempted mode overwrite'),

        (N'ERRINBSTRUCT01', N'INBOUND', N'ERROR',
             N'Inbound structure cannot be modified after activation.',
             N'Inbound.Structure: modification attempted after activation'),

        (N'ERRINBSTRUCT02', N'INBOUND', N'ERROR',
             N'Expected handling units cannot be modified after activation.',
             N'Inbound.Structure: expected units modification attempted after activation'),

        (N'SUCINBREV01',  N'INB', N'INFO',
            N'Receipt reversed successfully.',
            N'Inbound.Reversal: success'),

        (N'ERRINBREV01',  N'INB', N'ERROR',
            N'Receipt not found or has already been reversed.',
            N'Inbound.Reversal: receipt_id not found or is_reversal=1'),

        (N'ERRINBREV02',  N'INB', N'ERROR',
            N'This receipt has already been reversed.',
            N'Inbound.Reversal: reversed_receipt_id already set'),

        (N'ERRINBREV03',  N'INB', N'ERROR',
            N'Inventory unit could not be reversed. Unit may have been moved or modified.',
            N'Inbound.Reversal: inventory_units UPDATE rowcount=0'),

        (N'ERRINBREV99',  N'INB', N'ERROR',
            N'Unexpected error during reversal. Please contact your supervisor.',
            N'Inbound.Reversal: unhandled exception in CATCH'),

        (N'ERRTASK01', N'TASK', N'ERROR',
             N'Inventory unit not recognised.',
             N'Task.Create: inventory unit not found'),

        (N'ERRTASK02', N'TASK', N'ERROR',
             N'Inventory unit not eligible for putaway.',
             N'Task.Create: inventory unit state invalid for putaway'),

        (N'ERRTASK03', N'TASK', N'ERROR',
             N'Inventory unit is not located in a staging bin.',
             N'Task.Create: staging placement not found'),

        (N'ERRTASK04', N'TASK', N'ERROR',
             N'No suitable storage location found. Please contact a supervisor.',
             N'Task.Create: destination bin suggestion failed'),

        (N'ERRTASK05', N'TASK', N'ERROR',
             N'A warehouse task already exists for this unit.',
             N'Task.Create: duplicate active task detected'),

        (N'ERRTASK06', N'TASK', N'ERROR',
             N'Task claim is no longer valid. Please rescan.',
             N'Task.Claim: claim expired or invalid'),

        (N'ERRTASK07', N'TASK', N'ERROR',
             N'Task cannot be confirmed in its current state.',
             N'Task.Confirm: invalid state transition'),

        (N'ERRTASK99', N'TASK', N'ERROR',
             N'Warehouse task operation failed. Please retry. If the problem persists, contact a supervisor.',
             N'Task.Engine: unexpected system error'),

        (N'SUCTASK02', N'TASK', N'SUCCESS',
            N'Putaway completed successfully.',
            N'Task.Confirm: putaway confirmed'),

        (N'ERRSET01', N'SET', N'ERROR',
            N'Setting not found.',
            N'Settings.Update: requested setting does not exist'),

        (N'ERRSET02', N'SET', N'ERROR',
            N'The provided value is not valid for this setting type.',
            N'Settings.Update: data type validation failed'),

        (N'ERRSET03', N'SET', N'ERROR',
            N'The value is not allowed for this setting.',
            N'Settings.Update: value not in allowed_values list'),

        (N'ERRSET04', N'SET', N'ERROR',
            N'The value is outside the permitted range.',
            N'Settings.Update: numeric range validation failed'),

        (N'SUCSET01', N'SET', N'SUCCESS',
            N'Setting updated successfully.',
            N'Settings.Update: value persisted'),

        (N'SUCTASK01', N'TASK', N'SUCCESS',
        N'Putaway task created. Please move stock to the suggested location.',
        N'Task.Create: task created and destination bin reserved'),

        (N'ERRTASK08', N'TASK', N'ERROR',
            N'Wrong location. Please move the stock to {0}.',
            N'Task.Confirm: scanned bin does not match reserved destination'),

        (N'ERRTASK09', N'TASK', N'ERROR',
            N'The suggested location is no longer available. Please request a new suggestion.',
            N'Task.Confirm: destination bin capacity exceeded or bin inactive at confirm time'),

        /* ── ERRINBL06/07/08 — previously missing message definitions ── */
        (N'ERRINBL06', N'INB', N'ERROR',
            N'Received quantity must be greater than zero.',
            N'Inbound.Line (manual mode): received_qty NULL or <= 0'),

        (N'ERRINBL07', N'INB', N'ERROR',
            N'Staging bin must be provided.',
            N'Inbound.Line: staging_bin_code parameter is NULL or empty'),

        (N'ERRINBL08', N'INB', N'ERROR',
            N'Staging bin not found or is inactive. Please check the bin code and try again.',
            N'Inbound.Line: staging_bin_code not found in locations.bins or is_active = 0'),

        /* ── ERRINBL09/10 — BBE and batch mismatch hard blocks ── */
        (N'ERRINBL09', N'INB', N'ERROR',
            N'Best Before Date on label does not match the expected value. Please contact your supervisor.',
            N'Inbound.Line (SSCC mode): scanned best_before_date != expected_unit.best_before_date'),

        (N'ERRINBL10', N'INB', N'ERROR',
            N'Batch number on label does not match the expected value. Please contact your supervisor.',
            N'Inbound.Line (SSCC mode): scanned batch_number != expected_unit.batch_number');

END;
GO

/********************************************************************************************
    13. Error codes
********************************************************************************************/
INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES

    -- Order
    (N'ERRORD01', N'ORD', N'ERROR',
        N'Order not found.',
        N'Order: outbound_order_id not found'),

    (N'ERRORD02', N'ORD', N'ERROR',
        N'Order is not in a valid state for this operation.',
        N'Order: invalid status transition'),

    (N'ERRORD03', N'ORD', N'ERROR',
        N'Order reference already exists.',
        N'Order.Create: duplicate order_ref'),

    (N'ERRORD04', N'ORD', N'ERROR',
        N'Order has no lines and cannot be processed.',
        N'Order: no active lines'),

    (N'SUCORD01', N'ORD', N'INFO',
        N'Order created successfully.',
        N'Order.Create: success'),

    (N'SUCORD02', N'ORD', N'INFO',
        N'Order allocated successfully.',
        N'Order.Allocate: success'),

    (N'SUCORD03', N'ORD', N'INFO',
        N'Order shipped successfully.',
        N'Order.Ship: success'),

    -- Allocation
    (N'ERRALLOC01', N'ALLOC', N'ERROR',
        N'Insufficient stock available to fulfil this order line.',
        N'Allocate: not enough PUTAWAY+AVAILABLE units for SKU'),

    (N'ERRALLOC02', N'ALLOC', N'ERROR',
        N'Requested batch or best-before date not available.',
        N'Allocate: no units matching requested_batch / requested_bbe'),

    (N'ERRALLOC03', N'ALLOC', N'ERROR',
        N'Unit is already allocated to another order.',
        N'Allocate: inventory_unit already has active allocation'),

    (N'SUCALLOC01', N'ALLOC', N'INFO',
        N'Stock allocated successfully.',
        N'Allocate: allocation rows created'),

    -- Pick
    (N'ERRPICK01', N'PICK', N'ERROR',
        N'Allocation not found or already picked.',
        N'Pick: allocation_id not found or status terminal'),

    (N'ERRPICK02', N'PICK', N'ERROR',
        N'Wrong pallet scanned. Expected a different SSCC.',
        N'Pick.Confirm: scanned SSCC does not match allocated unit'),

    (N'ERRPICK03', N'PICK', N'ERROR',
        N'Unit is not in the expected location.',
        N'Pick.Confirm: unit placement bin does not match task source bin'),

    (N'SUCPICK01', N'PICK', N'INFO',
        N'Pick confirmed successfully.',
        N'Pick.Confirm: unit transitioned to PKD'),

    -- Shipment
    (N'ERRSHIP01', N'SHIP', N'ERROR',
        N'Shipment not found.',
        N'Shipment: shipment_id not found'),

    (N'ERRSHIP02', N'SHIP', N'ERROR',
        N'Shipment is not in a valid state for this operation.',
        N'Shipment: invalid status transition'),

    (N'ERRSHIP03', N'SHIP', N'ERROR',
        N'Shipment reference already exists.',
        N'Shipment.Create: duplicate shipment_ref'),

    (N'ERRSHIP04', N'SHIP', N'ERROR',
        N'Not all orders on this shipment are fully picked.',
        N'Shipment.Ship: one or more orders not in PICKED or LOADED status'),

    (N'SUCSHIP01', N'SHIP', N'INFO',
        N'Shipment created successfully.',
        N'Shipment.Create: success'),

    (N'SUCSHIP02', N'SHIP', N'INFO',
        N'Shipment departed. All units shipped.',
        N'Shipment.Ship: all units transitioned to SHP')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO

-- Add SUCLOAD01 message
INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCLOAD01', N'LOAD', N'INFO',
    N'Order loaded onto vehicle successfully.',
    N'Load.Confirm: order status LOADED, shipment LOADING'
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCLOAD01'
);
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

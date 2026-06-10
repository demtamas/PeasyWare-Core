USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Error messages: Outbound · Warehouse · Move · Task
-- ============================================================

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES

    -- ── Load ───────────────────────────────────────────────────────────────
    (N'SUCLOAD01', N'LOAD', N'INFO',
        N'Order loaded onto vehicle successfully.',
        N'Load.Confirm: order status LOADED, shipment LOADING'),

    -- ── Order ──────────────────────────────────────────────────────────────
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

    (N'ERRORD06', N'ORD', N'ERROR',
        N'Delivery address not found or does not belong to the specified customer.',
        N'usp_create_order: delivery_address_id invalid or not owned by customer_party_id'),

    (N'ERRORD10', N'ORD', N'ERROR',
        N'Order not found or already departed / cancelled.',
        N'DeallocateOrder: outbound_order_id not found or in terminal status'),

    (N'ERRORD11', N'ORD', N'ERROR',
        N'Order cannot be deallocated in its current state.',
        N'DeallocateOrder: order_status_code not in (ALLOCATED, PICKING)'),

    (N'ERRORD12', N'ORD', N'ERROR',
        N'Order not found.',
        N'CancelOrder: outbound_order_id not found'),

    (N'ERRORD13', N'ORD', N'ERROR',
        N'Order cannot be cancelled — it has allocated or picked stock. Deallocate the order first.',
        N'CancelOrder: order has lines not in NEW/CNL status — hard refuse'),

    (N'ERRORD14', N'ORD', N'ERROR',
        N'Order is already cancelled or departed.',
        N'CancelOrder: order_status_code already terminal'),

    (N'SUCORD01', N'ORD', N'INFO',  N'Order created successfully.',                       N'Order.Create: success'),
    (N'SUCORD02', N'ORD', N'INFO',  N'Order allocated successfully.',                     N'Order.Allocate: success'),
    (N'SUCORD03', N'ORD', N'INFO',  N'Order shipped successfully.',                       N'Order.Ship: success'),
    (N'SUCORD10', N'ORD', N'INFO',  N'Order deallocated. All pending allocations cancelled and stock released.', N'DeallocateOrder: success'),
    (N'SUCORD11', N'ORD', N'INFO',  N'Order cancelled successfully.',                     N'CancelOrder: success'),

    (N'WARNORD01', N'OUTBOUND', N'WARN',
        N'No eligible stock found to allocate. Check stock availability and status.',
        N'usp_allocate_order: newly_allocated_qty = 0'),

    -- ── Shipment ───────────────────────────────────────────────────────────
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

    (N'ERRSHIP05', N'SHIP', N'ERROR',
        N'Vehicle registration is required before departure.',
        N'outbound.usp_ship: @vehicle_ref is null or empty'),

    (N'ERRSHIP06', N'SHIP', N'ERROR',
        N'Shipment not found.',
        N'outbound.usp_cancel_shipment: shipment_ref not found'),

    (N'ERRSHIP07', N'SHIP', N'ERROR',
        N'This shipment has already departed or been cancelled.',
        N'outbound.usp_cancel_shipment: status is DEPARTED or CNL'),

    (N'ERRSHIP08', N'SHIP', N'ERROR',
        N'Cannot cancel — orders on this shipment are being picked or have been loaded. Reverse picks first.',
        N'outbound.usp_cancel_shipment: orders in PICKING/PICKED/LOADED state'),

    (N'SUCSHIP01', N'SHIP', N'INFO', N'Shipment created successfully.',   N'Shipment.Create: success'),
    (N'SUCSHIP02', N'SHIP', N'INFO', N'Shipment departed. All units shipped.', N'Shipment.Ship: success'),
    (N'SUCSHIP03', N'SHIP', N'INFO', N'Order added to shipment.',          N'usp_add_order_to_shipment: success'),
    (N'SUCSHIP04', N'SHIP', N'INFO', N'Shipment cancelled.',               N'usp_cancel_shipment: success'),

    -- ── Allocation ─────────────────────────────────────────────────────────
    (N'ERRALLOC01', N'ALLOC', N'ERROR',
        N'Insufficient stock available to fulfil this order line.',
        N'Allocate: not enough PUTAWAY+AVAILABLE units for SKU'),

    (N'ERRALLOC02', N'ALLOC', N'ERROR',
        N'Requested batch or best-before date not available.',
        N'Allocate: no units matching requested_batch / requested_bbe'),

    (N'ERRALLOC03', N'ALLOC', N'ERROR',
        N'Unit is already allocated to another order.',
        N'Allocate: inventory_unit already has active allocation'),

    (N'ERRALLOC04', N'ALLOC', N'ERROR',
        N'Allocation not found or already terminal (picked / cancelled).',
        N'CancelAllocation: allocation_id not found or is_terminal = 1'),

    (N'ERRALLOC05', N'ALLOC', N'ERROR',
        N'Cannot cancel allocation — pick task is already confirmed.',
        N'CancelAllocation: allocation status = CONFIRMED and task DONE'),

    (N'ERRALLOC06', N'ALLOC', N'ERROR',
        N'No alternative stock available for re-allocation.',
        N'ReallocateLine: no eligible PTW/AV units found for SKU'),

    (N'ERRALLOC07', N'ALLOC', N'ERROR',
        N'Line is not in a re-allocatable state.',
        N'ReallocateLine: line_status_code not in (ALLOCATED, PICKING)'),

    (N'SUCALLOC01', N'ALLOC', N'INFO', N'Stock allocated successfully.',          N'Allocate: allocation rows created'),
    (N'SUCALLOC02', N'ALLOC', N'INFO', N'Allocation cancelled successfully.',     N'CancelAllocation: status set to CANCELLED'),
    (N'SUCALLOC03', N'ALLOC', N'INFO', N'Re-allocation successful. New stock assigned.', N'ReallocateLine: new allocation_id returned'),

    -- ── Pick ───────────────────────────────────────────────────────────────
    (N'ERRPICK01', N'PICK', N'ERROR',
        N'Allocation not found or already picked.',
        N'Pick: allocation_id not found or status terminal'),

    (N'ERRPICK02', N'PICK', N'ERROR',
        N'Wrong pallet scanned. Expected a different SSCC.',
        N'Pick.Confirm: scanned SSCC does not match allocated unit'),

    (N'ERRPICK03', N'PICK', N'ERROR',
        N'Unit is not in the expected location.',
        N'Pick.Confirm: unit placement bin does not match task source bin'),

    (N'ERRPICK04', N'PICK', N'ERROR',
        N'Unit is not in a pickable state (expected PTW).',
        N'Pick.Confirm: stock_state_code is not PTW'),

    (N'SUCPICK01', N'PICK', N'INFO',
        N'Pick confirmed successfully.',
        N'Pick.Confirm: unit transitioned to PKD'),

    -- ── Move ───────────────────────────────────────────────────────────────
    (N'ERRMOVE01', N'MOVE', N'ERROR',
        N'Unit not found. Please check the SSCC and try again.',
        N'usp_bin_to_bin_move_create: external_ref not found in inventory_units'),

    (N'ERRMOVE02', N'MOVE', N'ERROR',
        N'This unit is not in a moveable state.',
        N'usp_bin_to_bin_move_create: stock_state_code not PUT or RCD'),

    (N'ERRMOVE03', N'MOVE', N'ERROR',
        N'Unit has no current location. Cannot create a move task.',
        N'usp_bin_to_bin_move_create: no placement record found'),

    (N'ERRMOVE04', N'MOVE', N'ERROR',
        N'Destination bin not found. Please check the bin code.',
        N'usp_bin_to_bin_move_create: destination_bin_code not found in locations.bins'),

    (N'ERRMOVE05', N'MOVE', N'ERROR',
        N'Move task not found or no longer active.',
        N'usp_bin_to_bin_move_confirm: task_id not found or not OPN/CLM'),

    (N'ERRMOVE06', N'MOVE', N'ERROR',
        N'Wrong location. Please scan the correct destination bin.',
        N'usp_bin_to_bin_move_confirm: scanned_bin_code does not match task destination_bin_id'),

    (N'ERRMOVE07', N'MOVE', N'ERROR',
        N'Destination bin is inactive or blocked. Choose a different bin.',
        N'usp_bin_to_bin_move_create: destination bin is_active = 0'),

    (N'SUCMOVE01', N'MOVE', N'SUCCESS', N'Move task created.',       N'usp_bin_to_bin_move_create: success'),
    (N'SUCMOVE02', N'MOVE', N'SUCCESS', N'Unit moved successfully.', N'usp_bin_to_bin_move_confirm: success'),

    -- ── Task ───────────────────────────────────────────────────────────────
    (N'SUCTASK03', N'WAREHOUSE', N'INFO',
        N'Task cancelled successfully.',
        N'warehouse.usp_cancel_task: OK'),

    (N'ERRTASK06', N'WAREHOUSE', N'ERROR',
        N'Task is already in a terminal state and cannot be cancelled.',
        N'warehouse.usp_cancel_task: is_terminal = 1'),

    (N'ERRTASK07', N'WAREHOUSE', N'ERROR',
        N'Task cancellation is not permitted from its current state.',
        N'warehouse.usp_cancel_task: invalid transition')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO
PRINT 'Outbound / Warehouse / Move / Task error codes seeded.';
GO

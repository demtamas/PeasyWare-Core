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

    (N'ERRSHIP09', N'SHIP', N'ERROR',
        N'One or more orders on this shipment have been picked but not yet loaded. Confirm loading for all orders before shipping.',
        N'outbound.usp_ship: order_status_code = PICKED (load not confirmed) for at least one order'),

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
        N'warehouse.fn_unit_move_block_code: stock state has no transition to MOV in stock_state_transitions'),

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
        N'warehouse.fn_bin_receive_block_code: destination bin is_active = 0 or is_locked = 1'),

    (N'ERRMOVE08', N'MOVE', N'ERROR',
        N'This unit''s stock status does not allow it to be moved.',
        N'warehouse.fn_unit_move_block_code: inventory.stock_operation_rules can_move = 0 for state + status'),

    (N'ERRMOVE09', N'MOVE', N'ERROR',
        N'Destination bin is full. Choose a different bin.',
        N'warehouse.fn_bin_receive_block_code: placements + unexpired reservations >= capacity'),

    (N'ERRMOVE10', N'MOVE', N'ERROR',
        N'This unit already has an open task (putaway, pick or move). Complete or cancel it first.',
        N'warehouse.fn_unit_move_block_code: open OPN/CLM task exists for unit; or UX_tasks_open_unit hit on a concurrent create'),

    (N'ERRMOVE11', N'MOVE', N'ERROR',
        N'The unit is already in that bin.',
        N'usp_bin_to_bin_move_create/confirm: destination bin = source bin'),

    (N'ERRMOVE12', N'MOVE', N'ERROR',
        N'The unit is no longer in the location this move was created for. Cancel and start the move again.',
        N'usp_bin_to_bin_move_confirm: current placement bin <> task source_bin_id'),

    (N'ERRMOVE99', N'MOVE', N'ERROR',
        N'Unexpected error while processing the move.',
        N'usp_bin_to_bin_move_create/confirm: unhandled exception'),

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
        N'warehouse.usp_cancel_task: invalid transition'),

    -- ── Inventory / write-off / expiry ───────────────────────────────────────
    (N'ERRSCR01', N'INV', N'ERROR',
        N'Unit not found.',
        N'usp_write_off_unit: inventory_unit_id not found'),

    (N'ERRSCR02', N'INV', N'ERROR',
        N'Unit is not in a status eligible for write-off.',
        N'usp_write_off_unit: stock_status_code not in eligible list'),

    (N'ERRSCR03', N'INV', N'ERROR',
        N'Unit is mid-flow (picked, loaded, or in movement) and cannot be written off from here.',
        N'usp_write_off_unit: stock_state_code not in (PTW, RCD)'),

    (N'ERRSCR99', N'INV', N'ERROR',
        N'Unexpected error while writing off the unit.',
        N'usp_write_off_unit: unhandled exception'),

    (N'SUCSCR01', N'INV', N'INFO',
        N'Unit written off successfully.',
        N'usp_write_off_unit: transitioned to SCR'),

    (N'ERREXP99', N'INV', N'ERROR',
        N'Unexpected error while running the expiry sweep.',
        N'usp_run_expiry_sweep: unhandled exception'),

    (N'SUCEXP01', N'INV', N'INFO',
        N'Expiry sweep completed.',
        N'usp_run_expiry_sweep: units flagged EX'),

    -- ── Customer shelf-life requirements ───────────────────────────────────────
    (N'ERRCSL01', N'INV', N'ERROR',
        N'Customer not found or inactive.',
        N'usp_set/delete_customer_shelf_life_requirement: party_code not found'),

    (N'ERRCSL02', N'INV', N'ERROR',
        N'SKU not found or inactive.',
        N'usp_set_customer_shelf_life_requirement: sku_code not found'),

    (N'ERRCSL03', N'INV', N'ERROR',
        N'Minimum remaining shelf life cannot be negative.',
        N'usp_set_customer_shelf_life_requirement: negative value supplied'),

    (N'ERRCSL04', N'INV', N'ERROR',
        N'No shelf-life requirement exists for this customer and SKU.',
        N'usp_delete_customer_shelf_life_requirement: row not found'),

    (N'ERRCSL99', N'INV', N'ERROR',
        N'Unexpected error while saving the shelf-life requirement.',
        N'usp_set/delete_customer_shelf_life_requirement: unhandled exception'),

    (N'SUCCSL01', N'INV', N'INFO',
        N'Shelf-life requirement saved successfully.',
        N'usp_set_customer_shelf_life_requirement: upsert complete'),

    (N'SUCCSL02', N'INV', N'INFO',
        N'Shelf-life requirement removed successfully.',
        N'usp_delete_customer_shelf_life_requirement: delete complete'),

    -- ── Stock counting ─────────────────────────────────────────────────────
    (N'ERRCNT01', N'COUNT', N'ERROR',
        N'Storage type not found or inactive.',
        N'usp_count_start_empty_bin: storage_type_code not found or is_active = 0'),

    (N'ERRCNT02', N'COUNT', N'ERROR',
        N'There are no empty bins in this storage type to count.',
        N'usp_count_start_empty_bin: v_empty_bins returned no rows for the storage type'),

    (N'ERRCNT03', N'COUNT', N'ERROR',
        N'This count does not exist or is no longer open.',
        N'usp_count_*: count_id not found or status_code <> OPEN'),

    (N'ERRCNT04', N'COUNT', N'ERROR',
        N'That bin is not part of this count.',
        N'usp_count_confirm_empty/report_stock: no count_line for this bin in the count'),

    (N'ERRCNT05', N'COUNT', N'ERROR',
        N'This bin has already been counted.',
        N'usp_count_confirm_empty/report_stock: line is CONFIRMED_EMPTY / OCCUPIED_SINCE (or not PENDING)'),

    (N'ERRCNT06', N'COUNT', N'ERROR',
        N'The system records this pallet as shipped. It may have been missed off a delivery.',
        N'usp_count_report_stock: unit stock_state_code = SHP - recorded as NOT_CORRECTED, never reinstated by a count'),

    (N'ERRCNT07', N'COUNT', N'ERROR',
        N'The system records this pallet''s receipt as reversed.',
        N'usp_count_report_stock: unit stock_state_code = REV - recorded as NOT_CORRECTED, never reinstated by a count'),

    (N'ERRCNT08', N'COUNT', N'ERROR',
        N'This count is not waiting for review.',
        N'usp_count_review: count not found, or status_code <> REVIEW (already reviewed, or never needed review)'),

    (N'ERRCNT09', N'COUNT', N'ERROR',
        N'Enter a note saying what was done about the findings.',
        N'usp_count_review: @note empty - a review without a record of what was done is not accepted'),

    (N'SUCCNT06', N'COUNT', N'SUCCESS',
        N'Count marked as reviewed.',
        N'usp_count_review: status REVIEW -> COMPLETE / CLOSED, reviewer and note recorded'),

    (N'ERRCNT99', N'COUNT', N'ERROR',
        N'Unexpected error while processing the count.',
        N'usp_count_*: unhandled exception'),

    (N'SUCCNT01', N'COUNT', N'SUCCESS',
        N'Count started.',
        N'usp_count_start_empty_bin: success (new or resumed)'),

    (N'SUCCNT02', N'COUNT', N'SUCCESS',
        N'Bin confirmed empty.',
        N'usp_count_confirm_empty: line set to CONFIRMED_EMPTY'),

    (N'SUCCNT03', N'COUNT', N'SUCCESS',
        N'Stock recorded in this bin. The system record has been corrected.',
        N'usp_count_report_stock: RECORD_CORRECTED - placement moved via usp_apply_relocation'),

    (N'SUCCNT04', N'COUNT', N'SUCCESS',
        N'Count closed.',
        N'usp_count_close: success (COMPLETE or CLOSED)'),

    (N'SUCCNT05', N'COUNT', N'SUCCESS',
        N'The system already shows this pallet in this bin.',
        N'usp_count_report_stock: placement already in this bin - nothing recorded'),

    (N'WARNCNT01', N'COUNT', N'WARN',
        N'The system now shows stock in this bin. Please check it.',
        N'usp_count_confirm_empty: placements exist since the snapshot - line set to OCCUPIED_SINCE'),

    (N'WARNCNT02', N'COUNT', N'WARN',
        N'This pallet is not known to the system. It has been recorded for supervisor review.',
        N'usp_count_report_stock: UNKNOWN_UNIT - no unit created'),

    (N'WARNCNT03', N'COUNT', N'WARN',
        N'Pallet recorded for supervisor review - it cannot be moved automatically.',
        N'usp_count_report_stock: NOT_CORRECTED - see count_findings.reason_code for the rule that applied')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO
PRINT 'Outbound / Warehouse / Move / Task error codes seeded.';
GO

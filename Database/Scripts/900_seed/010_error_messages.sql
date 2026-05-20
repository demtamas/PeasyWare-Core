USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

PRINT 'Outbound error codes inserted.';
GO
GO


/********************************************************************************************
    OUTBOUND STORED PROCEDURES
    All 7 outbound SPs. CREATE OR ALTER — safe to re-run after DB reset.
********************************************************************************************/

/********************************************************************************************
    WIP PATCH — Pick flow improvements
    Date: 2026-04-18

    1. usp_pick_create: add @destination_bin_code parameter
       Operator can specify which staging bay to pick into.
       If NULL, falls back to first active staging bin (existing behaviour).
********************************************************************************************/
GO

-- Allocation warning: ran successfully but no new stock found
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'WARNORD01', N'OUTBOUND', N'WARN',
    N'No eligible stock found to allocate. Check stock availability and status.',
    N'usp_allocate_order: newly_allocated_qty = 0'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'WARNORD01');
GO

-- Outbound: delivery address validation
INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD06', N'OUTBOUND', N'ERROR',
    N'Delivery address not found or does not belong to the specified customer.',
    N'usp_create_order: delivery_address_id invalid or not owned by customer_party_id'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD06');
GO

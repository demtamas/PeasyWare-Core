USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES
    (N'ERRORD10', N'ORD', N'ERROR',
        N'Order not found or already departed / cancelled.',
        N'DeallocateOrder: outbound_order_id not found or in terminal status'),

    (N'ERRORD11', N'ORD', N'ERROR',
        N'Order cannot be deallocated in its current state.',
        N'DeallocateOrder: order_status_code not in (ALLOCATED, PICKING)'),

    (N'SUCORD10', N'ORD', N'INFO',
        N'Order deallocated. All pending allocations cancelled and stock released.',
        N'DeallocateOrder: success')
) AS v(error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO

PRINT 'Deallocation error codes inserted.';
GO


-- ══════════════════════════════════════════════════════════════════════════════
-- outbound.usp_deallocate_order
-- ------------------------------------------------------------------------------
-- Cancels all PENDING and CONFIRMED (not yet physically confirmed) allocations
-- on an order, rolls back line allocated_qty, and returns the order to NEW.
--
-- Rules:
--   - Only operates on ALLOCATED or PICKING orders.
--   - PICKED allocations are untouched — stock already moved.
--   - If all non-picked allocations are cancelled, order → NEW.
--   - If some lines were partially picked, order stays PICKING with the
--     remaining picked qty intact; lines reset to NEW for the unallocated portion.
--
-- Reversal: none needed — this IS the reversal for usp_allocate_order.
-- ══════════════════════════════════════════════════════════════════════════════
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES
    (N'ERRORD12', N'ORD', N'ERROR',
        N'Order not found.',
        N'CancelOrder: outbound_order_id not found'),

    (N'ERRORD13', N'ORD', N'ERROR',
        N'Order cannot be cancelled — it has allocated or picked stock. Deallocate the order first.',
        N'CancelOrder: order has lines not in NEW/CNL status — hard refuse'),

    (N'ERRORD14', N'ORD', N'ERROR',
        N'Order is already cancelled or departed.',
        N'CancelOrder: order_status_code already terminal'),

    (N'SUCORD11', N'ORD', N'INFO',
        N'Order cancelled successfully.',
        N'CancelOrder: order and all lines set to CANCELLED/CNL')
) AS v(error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO

PRINT 'Order cancellation error codes inserted.';
GO


-- ══════════════════════════════════════════════════════════════════════════════
-- outbound.usp_cancel_order
-- ------------------------------------------------------------------------------
-- Cancels an order and all its lines.
-- Hard-refuses if any line is beyond NEW (allocated, picking, picked, etc.).
-- The guard is in the SP — the Desktop UI also enforces this, but the SP
-- is the authoritative check.
--
-- What it does on success:
--   - Sets order_status_code = 'CANCELLED'
--   - Sets all non-CNL lines to 'CNL'
--
-- Reversal: not supported. Cancellation is terminal.
-- ══════════════════════════════════════════════════════════════════════════════
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES
    (N'ERRALLOC04', N'ALLOC', N'ERROR',
        N'Allocation not found or already terminal (picked / cancelled).',
        N'CancelAllocation: allocation_id not found or is_terminal = 1'),

    (N'ERRALLOC05', N'ALLOC', N'ERROR',
        N'Cannot cancel allocation — pick task is already confirmed.',
        N'CancelAllocation: allocation status = CONFIRMED and task DONE'),

    (N'SUCALLOC02', N'ALLOC', N'INFO',
        N'Allocation cancelled successfully.',
        N'CancelAllocation: status set to CANCELLED'),

    (N'SUCALLOC03', N'ALLOC', N'INFO',
        N'Re-allocation successful. New stock assigned.',
        N'ReallocateLine: new allocation_id returned'),

    (N'ERRALLOC06', N'ALLOC', N'ERROR',
        N'No alternative stock available for re-allocation.',
        N'ReallocateLine: no eligible PTW/AV units found for SKU'),

    (N'ERRALLOC07', N'ALLOC', N'ERROR',
        N'Line is not in a re-allocatable state.',
        N'ReallocateLine: line_status_code not in (ALLOCATED, PICKING)')
) AS v(error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO

PRINT 'Re-allocation error codes inserted.';
GO

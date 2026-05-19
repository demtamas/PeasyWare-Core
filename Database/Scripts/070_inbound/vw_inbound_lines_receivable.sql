USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inbound.vw_inbound_lines_receivable
AS
SELECT
    l.inbound_line_id,
    d.inbound_ref,
    l.line_no,
    s.sku_code,
    s.sku_description,
    l.expected_qty,
    l.received_qty,
    (l.expected_qty - l.received_qty) AS outstanding_qty,
    l.line_state_code
FROM inbound.inbound_lines l
JOIN inbound.inbound_deliveries d
    ON d.inbound_id = l.inbound_id
JOIN inventory.skus s
    ON s.sku_id = l.sku_id
WHERE
    d.inbound_status_code IN ('ACT','RCV')
    AND l.line_state_code NOT IN ('RCV','CNL')
    AND (l.expected_qty - l.received_qty) > 0;
GO

/********************************************************************************************
    Procedure: inbound.usp_activate_inbound
    Purpose  : Activates inbound delivery (EXP → ACT)
               - Validates transition rules
               - Enforces structural consistency (no mixed SSCC / Manual lines)
               - Determines and persists inbound_mode_code (SSCC / MANUAL)
               - Locks header during activation
********************************************************************************************/
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW inbound.vw_inbounds_activatable
AS
SELECT
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at,
    COUNT(l.inbound_line_id)  AS line_count

FROM inbound.inbound_deliveries d
JOIN inbound.inbound_lines l
    ON l.inbound_id = d.inbound_id

WHERE d.inbound_status_code = 'EXP'

GROUP BY
    d.inbound_id,
    d.inbound_ref,
    d.expected_arrival_at;
GO

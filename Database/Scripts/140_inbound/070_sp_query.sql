/********************************************************************************************
    PROCEDURE: inbound.usp_validate_sscc_for_receive
    Purpose  : Preview + claim an expected SSCC unit for receiving (CLM window)
               Enforces expected-unit state transitions via inbound.inbound_expected_unit_state_transitions
               Keeps output contract columns 0-19 stable for C# reader mapping
********************************************************************************************/
GO

CREATE OR ALTER PROCEDURE inbound.usp_get_inbound_summary
(
    @inbound_ref NVARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CAST(CASE WHEN d.inbound_id IS NULL THEN 0 ELSE 1 END AS BIT) AS ExistsFlag,
        CAST(CASE WHEN d.inbound_status_code IN ('ACT','RCV') THEN 1 ELSE 0 END AS BIT) AS IsReceivable,
        CAST(
            CASE WHEN EXISTS (
                SELECT 1
                FROM inbound.inbound_expected_units eu
                JOIN inbound.inbound_lines l ON eu.inbound_line_id = l.inbound_line_id
                WHERE l.inbound_id = d.inbound_id AND eu.expected_unit_state_code = 'EXP'
            ) THEN 1 ELSE 0 END
        AS BIT) AS HasExpectedUnits,
        d.inbound_mode_code AS InboundMode
    FROM inbound.inbound_deliveries d
    WHERE d.inbound_ref = @inbound_ref;
END
GO

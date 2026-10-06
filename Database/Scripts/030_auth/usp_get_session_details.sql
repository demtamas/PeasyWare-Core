USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_get_session_details
(
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM auth.v_session_forensic
    WHERE session_id = @session_id;
END;
GO

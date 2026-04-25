CREATE OR ALTER PROCEDURE audit.usp_log_event
(
    @correlation_id UNIQUEIDENTIFIER = NULL,
    @user_id        INT = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @event_name     NVARCHAR(200),
    @result_code    NVARCHAR(50),
    @success        BIT,
    @payload_json   NVARCHAR(MAX) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------
    -- Normalize input (trim only, no magic)
    --------------------------------------------------------

    SET @event_name  = LTRIM(RTRIM(@event_name));
    SET @result_code = LTRIM(RTRIM(@result_code));

    --------------------------------------------------------
    -- Validation
    --------------------------------------------------------

    IF @event_name IS NULL OR @event_name = ''
        THROW 50001, 'audit.usp_log_event: @event_name is required.', 1;

    IF @result_code IS NULL OR @result_code = ''
        THROW 50002, 'audit.usp_log_event: @result_code is required.', 1;

    IF @payload_json IS NOT NULL AND ISJSON(@payload_json) <> 1
        THROW 50003, 'audit.usp_log_event: @payload_json must be valid JSON.', 1;

    --------------------------------------------------------
    -- Insert (constraints enforce correctness)
    --------------------------------------------------------

    INSERT INTO audit.audit_events
    (
        occurred_at,
        correlation_id,
        user_id,
        session_id,
        event_name,
        result_code,
        success,
        payload_json
    )
    VALUES
    (
        SYSUTCDATETIME(),
        @correlation_id,
        @user_id,
        @session_id,
        @event_name,
        @result_code,
        @success,
        @payload_json
    );
END;
GO

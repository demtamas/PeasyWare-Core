CREATE OR ALTER PROCEDURE operations.usp_setting_update
(
    @setting_name  sysname,
    @setting_value nvarchar(4000),

    @result_code   nvarchar(20) OUTPUT,
    @friendly_msg  nvarchar(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @data_type nvarchar(50),
        @validation_rule nvarchar(max),

        -- audit
        @old_value nvarchar(4000),
        @user_id int,
        @session_id uniqueidentifier,
        @correlation_id uniqueidentifier,
        @source_app nvarchar(100),
        @source_client nvarchar(200),
        @source_ip nvarchar(50),

        -- raw context (defensive parsing)
        @session_id_raw nvarchar(100),
        @correlation_id_raw nvarchar(100);

    BEGIN TRY
        BEGIN TRANSACTION;

        --------------------------------------------------------
        -- Resolve metadata
        --------------------------------------------------------

        SELECT
            @data_type = data_type,
            @validation_rule = validation_rule,
            @old_value = setting_value
        FROM operations.settings
        WHERE setting_name = @setting_name;
GO

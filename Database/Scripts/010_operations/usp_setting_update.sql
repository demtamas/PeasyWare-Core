USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

        IF @data_type IS NULL
        BEGIN
            SET @result_code = 'ERRSET01';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Validation
        --------------------------------------------------------

        IF @data_type = 'int'
           AND TRY_CONVERT(int, @setting_value) IS NULL
        BEGIN
            SET @result_code = 'ERRSET02';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- SAFE session context resolution
        --------------------------------------------------------

        SELECT
            @session_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'session_id')),

            @correlation_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'correlation_id')),

            @user_id =
                TRY_CONVERT(int, SESSION_CONTEXT(N'user_id')),

            @source_app =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'source_app')),

            @source_client =
                TRY_CONVERT(nvarchar(200), SESSION_CONTEXT(N'source_client')),

            @source_ip =
                TRY_CONVERT(nvarchar(50), SESSION_CONTEXT(N'source_ip'));

        SET @session_id =
            TRY_CONVERT(uniqueidentifier, @session_id_raw);

        SET @correlation_id =
            TRY_CONVERT(uniqueidentifier, @correlation_id_raw);

        --------------------------------------------------------
        -- HARD GUARD
        --------------------------------------------------------

        IF @session_id IS NULL OR @user_id IS NULL
        BEGIN
            SET @result_code = 'ERRCTX01';
            SET @friendly_msg = 'Invalid or missing session context';
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Update
        --------------------------------------------------------

        UPDATE operations.settings
        SET
            setting_value = @setting_value,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        WHERE setting_name = @setting_name;

        --------------------------------------------------------
        -- Structured audit
        --------------------------------------------------------

        INSERT INTO audit.setting_changes
        (
            setting_name,
            old_value,
            new_value,
            changed_at,
            changed_by,
            source_app,
            source_client,
            source_ip,
            correlation_id
        )
        VALUES
        (
            @setting_name,
            @old_value,
            @setting_value,
            SYSUTCDATETIME(),
            @user_id,
            @source_app,
            @source_client,
            @source_ip,
            @correlation_id
        );

        --------------------------------------------------------
        -- Event audit
        --------------------------------------------------------

        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @setting_name  AS SettingName,
                @old_value     AS OldValue,
                @setting_value AS NewValue
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.setting.updated',
            @result_code    = 'SUCCESS',
            @success        = 1,
            @payload_json   = @payload_json;

        COMMIT;

        SET @result_code = 'SUCSET01';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        --------------------------------------------------------
        -- Capture error FIRST (this was missing)
        --------------------------------------------------------

        DECLARE @error nvarchar(4000) = ERROR_MESSAGE();

        DECLARE @payload_json_error NVARCHAR(MAX);

        SET @payload_json_error = (
            SELECT
                @error AS ErrorMessage,
                ERROR_NUMBER() AS ErrorNumber,
                ERROR_LINE() AS ErrorLine
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRSET99';
        SET @friendly_msg = 'Unexpected error occurred while updating setting.';
    END CATCH
END
GO

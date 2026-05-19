USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inbound.usp_activate_inbound
(
    @inbound_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @current_status      VARCHAR(3),
        @existing_mode       VARCHAR(6),
        @sscc_line_count     INT,
        @manual_line_count   INT,
        @mode_code           VARCHAR(6);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @current_status = inbound_status_code,
            @existing_mode  = inbound_mode_code
        FROM inbound.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        IF @current_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_status_transitions
            WHERE from_status_code = @current_status
              AND to_status_code   = 'ACT'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB05' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code <> 'CNL'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB03' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @sscc_line_count = COUNT(DISTINCT l.inbound_line_id)
        FROM inbound.inbound_lines l
        JOIN inbound.inbound_expected_units eu
            ON eu.inbound_line_id = l.inbound_line_id
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL';

        SELECT
            @manual_line_count = COUNT(*)
        FROM inbound.inbound_lines l
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL'
          AND NOT EXISTS (
                SELECT 1
                FROM inbound.inbound_expected_units eu
                WHERE eu.inbound_line_id = l.inbound_line_id
          );

        IF @sscc_line_count > 0 AND @manual_line_count > 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBHYB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF @sscc_line_count > 0
            SET @mode_code = 'SSCC';
        ELSE
            SET @mode_code = 'MANUAL';

        IF @existing_mode IS NOT NULL AND @existing_mode <> @mode_code
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBMODE01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
        EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

        UPDATE inbound.inbound_deliveries
        SET inbound_status_code = 'ACT',
            inbound_mode_code   = @mode_code,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINB01' AS result_code, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code, NULL AS inbound_id;
    END CATCH
END;
GO

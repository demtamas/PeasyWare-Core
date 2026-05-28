USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inbound.usp_cancel_inbound
(
    @inbound_ref    NVARCHAR(50),
    @reason         NVARCHAR(200)    = NULL,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @inbound_id    INT;
        DECLARE @status_code   VARCHAR(3);

        SELECT
            @inbound_id  = inbound_id,
            @status_code = inbound_status_code
        FROM inbound.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_ref = @inbound_ref COLLATE Latin1_General_CS_AS;

        -- Not found
        IF @inbound_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB03' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Already terminal
        IF @status_code IN ('CLS', 'CNL')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB04' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Partially or fully received — cannot cancel
        IF @status_code = 'RCV'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- ACT status: block if any receipts exist
        IF @status_code = 'ACT'
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM inbound.inbound_receipts r
                JOIN inbound.inbound_lines l ON l.inbound_line_id = r.inbound_line_id
                WHERE l.inbound_id = @inbound_id
                  AND r.is_reversal = 0
            )
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRINB06' AS result_code;
                ROLLBACK; RETURN;
            END
        END

        -- Cancel the delivery header
        UPDATE inbound.inbound_deliveries
        SET inbound_status_code = 'CNL',
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        -- Cancel all open lines
        UPDATE inbound.inbound_lines
        SET line_state_code = 'CNL',
            updated_at      = SYSUTCDATETIME()
        WHERE inbound_id      = @inbound_id
          AND line_state_code NOT IN ('RCV', 'CNL');

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCINB03' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code;
    END CATCH
END;
GO

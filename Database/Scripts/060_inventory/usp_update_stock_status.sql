USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inventory.usp_update_stock_status
(
    @sscc_list   NVARCHAR(MAX),
    @new_status  VARCHAR(2),
    @reason      NVARCHAR(200)    = NULL,
    @user_id     INT              = NULL,
    @session_id  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    BEGIN TRY
        BEGIN TRAN;

        -- Validate target status exists
        IF NOT EXISTS (SELECT 1 FROM inventory.stock_statuses WHERE status_code = @new_status)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINV02' AS result_code, 0 AS affected_count;
            ROLLBACK; RETURN;
        END

        -- Parse comma-separated SSCC list into a table
        DECLARE @ssccs TABLE (sscc NVARCHAR(100));

        INSERT INTO @ssccs (sscc)
        SELECT LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@sscc_list, ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        DECLARE @now          DATETIME2(3) = SYSUTCDATETIME();
        DECLARE @affected_count INT = 0;

        -- Update matching active units
        UPDATE inventory.inventory_units
        SET stock_status_code = @new_status,
            updated_at        = @now,
            updated_by        = @user_id
        WHERE external_ref      IN (SELECT sscc FROM @ssccs)
          AND stock_state_code NOT IN ('REV', 'SHP');

        SET @affected_count = @@ROWCOUNT;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINV01' AS result_code, @affected_count AS affected_count;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINV99' AS result_code, 0 AS affected_count;
    END CATCH
END;
GO
PRINT 'inventory.usp_update_stock_status created.';
GO

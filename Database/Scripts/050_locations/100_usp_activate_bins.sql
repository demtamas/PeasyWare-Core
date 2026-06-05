USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ==========================================================
-- Activate bins in bulk
-- Accepts a JSON array of bin codes:
--   @bin_codes_json = '["R0101A","R0101B","R0102A"]'
--
-- Skips any bin that is already active.
-- Returns count of activated + skipped.
-- ==========================================================

CREATE OR ALTER PROCEDURE locations.usp_activate_bins
(
    @bin_codes_json NVARCHAR(MAX),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF ISJSON(@bin_codes_json) = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code,
                   0 AS activated_count, 0 AS skipped_count;
            ROLLBACK; RETURN;
        END

        -- Parse JSON array into temp table
        SELECT CAST([value] AS NVARCHAR(100)) AS bin_code
        INTO #bins_to_activate
        FROM OPENJSON(@bin_codes_json);

        DECLARE @activated INT = 0;
        DECLARE @skipped   INT = 0;

        SELECT @activated = COUNT(*)
        FROM locations.bins b
        JOIN #bins_to_activate t
            ON b.bin_code = t.bin_code COLLATE Latin1_General_CS_AS
        WHERE b.is_active = 0;

        SELECT @skipped = COUNT(*)
        FROM #bins_to_activate t
        LEFT JOIN locations.bins b
            ON b.bin_code = t.bin_code COLLATE Latin1_General_CS_AS
        WHERE b.is_active = 1 OR b.bin_id IS NULL;

        UPDATE b
        SET b.is_active  = 1,
            b.updated_at = SYSUTCDATETIME(),
            b.updated_by = @user_id
        FROM locations.bins b
        JOIN #bins_to_activate t
            ON b.bin_code = t.bin_code COLLATE Latin1_General_CS_AS
        WHERE b.is_active = 0;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCBIN08' AS result_code,
               @activated AS activated_count, @skipped AS skipped_count;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code,
               0 AS activated_count, 0 AS skipped_count;
    END CATCH
END;
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Assign bins to a section
-- @bin_codes_json: JSON array of bin codes
-- @section_code:   target section (NULL = clear assignment)
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_assign_bins_to_section
(
    @section_code   NVARCHAR(50),
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
            SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code, 0 AS updated_count;
            ROLLBACK; RETURN;
        END

        DECLARE @section_id INT = NULL;

        IF @section_code IS NOT NULL
        BEGIN
            SELECT @section_id = storage_section_id
            FROM locations.storage_sections
            WHERE section_code = @section_code COLLATE Latin1_General_CS_AS;

            IF @section_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRSEC02' AS result_code, 0 AS updated_count;
                ROLLBACK; RETURN;
            END
        END

        SELECT CAST([value] AS NVARCHAR(100)) AS bin_code
        INTO #bins_to_assign
        FROM OPENJSON(@bin_codes_json);

        DECLARE @updated INT;

        UPDATE b
        SET b.storage_section_id = @section_id,
            b.updated_at         = SYSUTCDATETIME(),
            b.updated_by         = @user_id
        FROM locations.bins b
        JOIN #bins_to_assign t
            ON b.bin_code = t.bin_code COLLATE Latin1_General_CS_AS;

        SET @updated = @@ROWCOUNT;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC05' AS result_code, @updated AS updated_count;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code, 0 AS updated_count;
    END CATCH
END;
GO

-- ============================================================
-- Assign bins to a zone
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_assign_bins_to_zone
(
    @zone_code      NVARCHAR(50),
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
            SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code, 0 AS updated_count;
            ROLLBACK; RETURN;
        END

        DECLARE @zone_id INT = NULL;

        IF @zone_code IS NOT NULL
        BEGIN
            SELECT @zone_id = zone_id
            FROM locations.zones
            WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS;

            IF @zone_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRZON02' AS result_code, 0 AS updated_count;
                ROLLBACK; RETURN;
            END
        END

        SELECT CAST([value] AS NVARCHAR(100)) AS bin_code
        INTO #bins_to_assign_zone
        FROM OPENJSON(@bin_codes_json);

        DECLARE @updated INT;

        UPDATE b
        SET b.zone_id     = @zone_id,
            b.updated_at  = SYSUTCDATETIME(),
            b.updated_by  = @user_id
        FROM locations.bins b
        JOIN #bins_to_assign_zone t
            ON b.bin_code = t.bin_code COLLATE Latin1_General_CS_AS;

        SET @updated = @@ROWCOUNT;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON05' AS result_code, @updated AS updated_count;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code, 0 AS updated_count;
    END CATCH
END;
GO

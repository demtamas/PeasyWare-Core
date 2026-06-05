USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Single bin creation
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_create_bin
(
    @bin_code          NVARCHAR(100),
    @storage_type_code NVARCHAR(50),
    @zone_code         NVARCHAR(50)     = NULL,
    @section_code      NVARCHAR(50)     = NULL,
    @capacity          INT              = 1,
    @notes             NVARCHAR(255)    = NULL,
    @user_id           INT              = NULL,
    @session_id        UNIQUEIDENTIFIER = NULL,
    @correlation_id    UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Validate bin code unique
        IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN04' AS result_code, 0 AS bin_id;
            ROLLBACK; RETURN;
        END

        DECLARE @storage_type_id INT =
            (SELECT storage_type_id FROM locations.storage_types
             WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS);

        IF @storage_type_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN05' AS result_code, 0 AS bin_id;
            ROLLBACK; RETURN;
        END

        DECLARE @zone_id INT =
            (SELECT zone_id FROM locations.zones
             WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS);

        DECLARE @section_id INT =
            (SELECT storage_section_id FROM locations.storage_sections
             WHERE section_code = @section_code COLLATE Latin1_General_CS_AS);

        DECLARE @new_bin_id INT;

        INSERT INTO locations.bins
            (bin_code, storage_type_id, zone_id, storage_section_id, capacity, notes, created_by, is_active)
        VALUES
            (@bin_code, @storage_type_id, @zone_id, @section_id, @capacity, @notes, @user_id, 0);

        SET @new_bin_id = SCOPE_IDENTITY();

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN03' AS result_code, @new_bin_id AS bin_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code, 0 AS bin_id;
    END CATCH
END;
GO

-- ============================================================
-- Bulk bin creation — generates a range from a template
--
-- Example: prefix='R', rows=1-10, cols=A-D, depth=1-2
--   generates: R0101A1, R0101A2, R0101B1 ... R1004D2
--
-- Pattern: {prefix}{row:2}{col}{depth}
-- All params optional — depth defaults to 1 slot per position
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_create_bins_bulk
(
    @prefix            NVARCHAR(10),
    @storage_type_code NVARCHAR(50),
    @row_from          INT,
    @row_to            INT,
    @col_from          CHAR(1)          = 'A',
    @col_to            CHAR(1)          = 'A',
    @depth_from        INT              = 1,
    @depth_to          INT              = 1,
    @zone_code         NVARCHAR(50)     = NULL,
    @section_code      NVARCHAR(50)     = NULL,
    @capacity          INT              = 1,
    @user_id           INT              = NULL,
    @session_id        UNIQUEIDENTIFIER = NULL,
    @correlation_id    UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @storage_type_id INT =
            (SELECT storage_type_id FROM locations.storage_types
             WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS);

        IF @storage_type_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN05' AS result_code, 0 AS created_count;
            ROLLBACK; RETURN;
        END

        DECLARE @zone_id INT =
            (SELECT zone_id FROM locations.zones
             WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS);

        DECLARE @section_id INT =
            (SELECT storage_section_id FROM locations.storage_sections
             WHERE section_code = @section_code COLLATE Latin1_General_CS_AS);

        DECLARE @row     INT = @row_from;
        DECLARE @col_ord INT = ASCII(@col_from);
        DECLARE @depth   INT;
        DECLARE @bin_code NVARCHAR(100);
        DECLARE @created INT = 0;
        DECLARE @skipped INT = 0;

        WHILE @row <= @row_to
        BEGIN
            SET @col_ord = ASCII(@col_from);
            WHILE @col_ord <= ASCII(@col_to)
            BEGIN
                SET @depth = @depth_from;
                WHILE @depth <= @depth_to
                BEGIN
                    SET @bin_code = @prefix
                        + RIGHT('0' + CAST(@row   AS NVARCHAR(2)), 2)
                        + RIGHT('0' + CAST(@depth AS NVARCHAR(2)), 2)
                        + CHAR(@col_ord);

                    IF NOT EXISTS (
                        SELECT 1 FROM locations.bins
                        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS
                    )
                    BEGIN
                        INSERT INTO locations.bins
                            (bin_code, storage_type_id, zone_id, storage_section_id, capacity, created_by, is_active)
                        VALUES
                            (@bin_code, @storage_type_id, @zone_id, @section_id, @capacity, @user_id, 0);
                        SET @created = @created + 1;
                    END
                    ELSE
                        SET @skipped = @skipped + 1;

                    SET @depth = @depth + 1;
                END
                SET @col_ord = @col_ord + 1;
            END
            SET @row = @row + 1;
        END

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN04' AS result_code,
               @created AS created_count, @skipped AS skipped_count;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code, 0 AS created_count, 0 AS skipped_count;
    END CATCH
END;
GO

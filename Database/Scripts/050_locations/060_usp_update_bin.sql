USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE locations.usp_update_bin
(
    @bin_code_current  NVARCHAR(100),       -- existing bin code (lookup key)
    @bin_code_new      NVARCHAR(100) = NULL, -- rename: only allowed when empty
    @storage_type_code NVARCHAR(50)  = NULL, -- only allowed when empty
    @zone_code         NVARCHAR(50)  = NULL, -- always allowed (pass NULL to clear)
    @section_code      NVARCHAR(50)  = NULL, -- always allowed (pass NULL to clear)
    @capacity          INT           = NULL, -- allowed, warned if below occupancy
    @notes             NVARCHAR(255) = NULL, -- always allowed
    @clear_notes       BIT           = 0,    -- explicit flag to clear notes
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

        IF auth.fn_has_permission(@user_id, 'bins.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code, CAST(0 AS BIT) AS capacity_warning;
            ROLLBACK; RETURN;
        END

        DECLARE @bin_id      INT;
        DECLARE @unit_count  INT;

        SELECT
            @bin_id     = bin_id,
            @unit_count = (
                SELECT COUNT(*)
                FROM inventory.inventory_placements ip
                JOIN inventory.inventory_units iu
                    ON iu.inventory_unit_id = ip.inventory_unit_id
                   AND iu.stock_state_code NOT IN ('SHP', 'REV')
                WHERE ip.bin_id = b.bin_id
            )
        FROM locations.bins b WITH (UPDLOCK, HOLDLOCK)
        WHERE b.bin_code = @bin_code_current COLLATE Latin1_General_CS_AS;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Rename: only when empty
        IF @bin_code_new IS NOT NULL AND @bin_code_new <> @bin_code_current
        BEGIN
            IF @unit_count > 0
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRBIN06' AS result_code;
                ROLLBACK; RETURN;
            END
            IF EXISTS (
                SELECT 1 FROM locations.bins
                WHERE bin_code = @bin_code_new COLLATE Latin1_General_CS_AS
                  AND bin_id  <> @bin_id
            )
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRBIN04' AS result_code;
                ROLLBACK; RETURN;
            END
        END

        -- Storage type change: only when empty
        DECLARE @storage_type_id INT = NULL;
        IF @storage_type_code IS NOT NULL
        BEGIN
            IF @unit_count > 0
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRBIN07' AS result_code;
                ROLLBACK; RETURN;
            END
            SET @storage_type_id =
                (SELECT storage_type_id FROM locations.storage_types
                 WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS);
            IF @storage_type_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRBIN05' AS result_code;
                ROLLBACK; RETURN;
            END
        END

        -- Capacity: warn if below occupancy but allow
        DECLARE @warn_capacity BIT = 0;
        IF @capacity IS NOT NULL AND @capacity < @unit_count
            SET @warn_capacity = 1;

        -- Resolve zone and section IDs
        DECLARE @zone_id    INT = NULL;
        DECLARE @section_id INT = NULL;

        IF @zone_code IS NOT NULL
            SET @zone_id = (SELECT zone_id FROM locations.zones WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS);

        IF @section_code IS NOT NULL
            SET @section_id = (SELECT storage_section_id FROM locations.storage_sections WHERE section_code = @section_code COLLATE Latin1_General_CS_AS);

        -- Apply updates (only fields explicitly provided)
        UPDATE locations.bins
        SET
            bin_code           = ISNULL(@bin_code_new,      bin_code),
            storage_type_id    = ISNULL(@storage_type_id,   storage_type_id),
            zone_id            = CASE WHEN @zone_code    IS NOT NULL THEN @zone_id    ELSE zone_id    END,
            storage_section_id = CASE WHEN @section_code IS NOT NULL THEN @section_id ELSE storage_section_id END,
            capacity           = ISNULL(@capacity,          capacity),
            notes              = CASE
                                    WHEN @clear_notes = 1 THEN NULL
                                    WHEN @notes IS NOT NULL THEN @notes
                                    ELSE notes
                                 END,
            updated_at         = SYSUTCDATETIME(),
            updated_by         = @user_id
        WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN05' AS result_code,
               @warn_capacity AS capacity_warning;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code, CAST(0 AS BIT) AS capacity_warning;
    END CATCH
END;
GO

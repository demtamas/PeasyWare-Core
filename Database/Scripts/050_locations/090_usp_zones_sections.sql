USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- ZONES
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_create_zone
(
    @zone_code      NVARCHAR(50),
    @zone_name      NVARCHAR(100),
    @description    NVARCHAR(255)    = NULL,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code, 0 AS zone_id; ROLLBACK; RETURN; END

        IF EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRZON01' AS result_code, 0 AS zone_id; ROLLBACK; RETURN; END

        INSERT INTO locations.zones (zone_code, zone_name, description, created_by)
        VALUES (@zone_code, @zone_name, @description, @user_id);

        DECLARE @new_id INT = SCOPE_IDENTITY();
        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON01' AS result_code, @new_id AS zone_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code, 0 AS zone_id;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_update_zone
(
    @zone_code      NVARCHAR(50),
    @zone_name      NVARCHAR(100)    = NULL,
    @description    NVARCHAR(255)    = NULL,
    @clear_desc     BIT              = 0,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM locations.zones WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRZON02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.zones
        SET zone_name   = ISNULL(@zone_name,   zone_name),
            description = CASE WHEN @clear_desc = 1 THEN NULL
                               WHEN @description IS NOT NULL THEN @description
                               ELSE description END,
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @user_id
        WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON02' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_deactivate_zone
(
    @zone_code      NVARCHAR(50),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        DECLARE @zone_id INT;
        SELECT @zone_id = zone_id FROM locations.zones WITH (UPDLOCK, HOLDLOCK)
        WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS AND is_active = 1;

        IF @zone_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRZON02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.zones
        SET is_active = 0, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE zone_id = @zone_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON03' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_reactivate_zone
(
    @zone_code      NVARCHAR(50),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        DECLARE @zone_id INT;
        SELECT @zone_id = zone_id FROM locations.zones WITH (UPDLOCK, HOLDLOCK)
        WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS AND is_active = 0;

        IF @zone_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRZON02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.zones
        SET is_active = 1, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE zone_id = @zone_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON04' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- SECTIONS
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_create_section
(
    @section_code   NVARCHAR(50),
    @section_name   NVARCHAR(100),
    @description    NVARCHAR(255)    = NULL,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code, 0 AS section_id; ROLLBACK; RETURN; END

        IF EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = @section_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRSEC01' AS result_code, 0 AS section_id; ROLLBACK; RETURN; END

        INSERT INTO locations.storage_sections (section_code, section_name, description, created_by)
        VALUES (@section_code, @section_name, @description, @user_id);

        DECLARE @new_id INT = SCOPE_IDENTITY();
        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC01' AS result_code, @new_id AS section_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code, 0 AS section_id;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_update_section
(
    @section_code   NVARCHAR(50),
    @section_name   NVARCHAR(100)    = NULL,
    @description    NVARCHAR(255)    = NULL,
    @clear_desc     BIT              = 0,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM locations.storage_sections WHERE section_code = @section_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRSEC02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_sections
        SET section_name = ISNULL(@section_name, section_name),
            description  = CASE WHEN @clear_desc = 1 THEN NULL
                                WHEN @description IS NOT NULL THEN @description
                                ELSE description END,
            updated_at   = SYSUTCDATETIME(),
            updated_by   = @user_id
        WHERE section_code = @section_code COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC02' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_deactivate_section
(
    @section_code   NVARCHAR(50),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        DECLARE @section_id INT;
        SELECT @section_id = storage_section_id FROM locations.storage_sections WITH (UPDLOCK, HOLDLOCK)
        WHERE section_code = @section_code COLLATE Latin1_General_CS_AS AND is_active = 1;

        IF @section_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRSEC02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_sections
        SET is_active = 0, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE storage_section_id = @section_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC03' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_reactivate_section
(
    @section_code   NVARCHAR(50),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'zones.manage') = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code; ROLLBACK; RETURN; END

        DECLARE @section_id INT;
        SELECT @section_id = storage_section_id FROM locations.storage_sections WITH (UPDLOCK, HOLDLOCK)
        WHERE section_code = @section_code COLLATE Latin1_General_CS_AS AND is_active = 0;

        IF @section_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRSEC02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_sections
        SET is_active = 1, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE storage_section_id = @section_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC04' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code;
    END CATCH
END;
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- STORAGE TYPES
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_create_storage_type
(
    @storage_type_code NVARCHAR(50),
    @storage_type_name NVARCHAR(100),
    @description        NVARCHAR(255)    = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTYP01' AS result_code, 0 AS storage_type_id; ROLLBACK; RETURN; END

        INSERT INTO locations.storage_types (storage_type_code, storage_type_name, description, created_by)
        VALUES (@storage_type_code, @storage_type_name, @description, @user_id);

        DECLARE @new_id INT = SCOPE_IDENTITY();
        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTYP01' AS result_code, @new_id AS storage_type_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTYP99' AS result_code, 0 AS storage_type_id;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_update_storage_type
(
    @storage_type_code NVARCHAR(50),
    @storage_type_name NVARCHAR(100)    = NULL,
    @description        NVARCHAR(255)    = NULL,
    @clear_desc         BIT              = 0,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM locations.storage_types WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTYP02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_types
        SET storage_type_name = ISNULL(@storage_type_name, storage_type_name),
            description       = CASE WHEN @clear_desc = 1 THEN NULL
                                     WHEN @description IS NOT NULL THEN @description
                                     ELSE description END,
            updated_at        = SYSUTCDATETIME(),
            updated_by        = @user_id
        WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTYP02' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTYP99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_deactivate_storage_type
(
    @storage_type_code NVARCHAR(50),
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @type_id INT;
        SELECT @type_id = storage_type_id FROM locations.storage_types WITH (UPDLOCK, HOLDLOCK)
        WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS AND is_active = 1;

        IF @type_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTYP02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_types
        SET is_active = 0, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE storage_type_id = @type_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTYP03' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTYP99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_reactivate_storage_type
(
    @storage_type_code NVARCHAR(50),
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @type_id INT;
        SELECT @type_id = storage_type_id FROM locations.storage_types WITH (UPDLOCK, HOLDLOCK)
        WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS AND is_active = 0;

        IF @type_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTYP02' AS result_code; ROLLBACK; RETURN; END

        UPDATE locations.storage_types
        SET is_active = 1, updated_at = SYSUTCDATETIME(), updated_by = @user_id
        WHERE storage_type_id = @type_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTYP04' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTYP99' AS result_code;
    END CATCH
END;
GO

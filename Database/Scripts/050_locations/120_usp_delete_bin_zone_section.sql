USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Delete bin (hard delete)
-- Rules:
--   1. Bin must be inactive (is_active = 0) — conscious step first
--   2. No inventory movements (from or to this bin)
--   3. No inventory placements (ever placed here)
--   4. No warehouse tasks (source or destination)
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_delete_bin
(
    @bin_code       NVARCHAR(100),
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

        DECLARE @bin_id   INT;
        DECLARE @is_active BIT;

        SELECT @bin_id    = bin_id,
               @is_active = is_active
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS;

        -- Not found
        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Must be inactive first
        IF @is_active = 1
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN12' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Check movements (immutable audit trail — cannot delete if referenced)
        IF EXISTS (
            SELECT 1 FROM inventory.inventory_movements
            WHERE from_bin_id = @bin_id OR to_bin_id = @bin_id
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN13' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Check placements (ever placed here)
        IF EXISTS (
            SELECT 1 FROM inventory.inventory_placements
            WHERE bin_id = @bin_id
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN13' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Check warehouse tasks
        IF EXISTS (
            SELECT 1 FROM warehouse.warehouse_tasks
            WHERE source_bin_id = @bin_id OR destination_bin_id = @bin_id
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN13' AS result_code;
            ROLLBACK; RETURN;
        END

        DELETE FROM locations.bins WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN09' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- Delete zone
-- Rules: no bins currently assigned to this zone
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_delete_zone
(
    @zone_code      NVARCHAR(50),
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

        DECLARE @zone_id INT;

        SELECT @zone_id = zone_id
        FROM locations.zones WITH (UPDLOCK, HOLDLOCK)
        WHERE zone_code = @zone_code COLLATE Latin1_General_CS_AS;

        IF @zone_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRZON02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE zone_id = @zone_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRZON03' AS result_code;
            ROLLBACK; RETURN;
        END

        DELETE FROM locations.zones WHERE zone_id = @zone_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCZON06' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRZON99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- Delete section
-- Rules: no bins currently assigned to this section
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_delete_section
(
    @section_code   NVARCHAR(50),
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

        DECLARE @section_id INT;

        SELECT @section_id = storage_section_id
        FROM locations.storage_sections WITH (UPDLOCK, HOLDLOCK)
        WHERE section_code = @section_code COLLATE Latin1_General_CS_AS;

        IF @section_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSEC02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE storage_section_id = @section_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSEC03' AS result_code;
            ROLLBACK; RETURN;
        END

        DELETE FROM locations.storage_sections WHERE storage_section_id = @section_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSEC06' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSEC99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- Delete storage type
-- Rules: no bins currently use this type, no SKU lists it as preferred
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_delete_storage_type
(
    @storage_type_code NVARCHAR(50),
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL,
    @correlation_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @type_id INT;

        SELECT @type_id = storage_type_id
        FROM locations.storage_types WITH (UPDLOCK, HOLDLOCK)
        WHERE storage_type_code = @storage_type_code COLLATE Latin1_General_CS_AS;

        IF @type_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTYP02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE storage_type_id = @type_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTYP03' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM inventory.skus WHERE preferred_storage_type_id = @type_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTYP04' AS result_code;
            ROLLBACK; RETURN;
        END

        DELETE FROM locations.storage_types WHERE storage_type_id = @type_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTYP05' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTYP99' AS result_code;
    END CATCH
END;
GO

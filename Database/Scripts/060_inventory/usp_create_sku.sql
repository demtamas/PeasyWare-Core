USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inventory.usp_create_sku
(
    @sku_code                       NVARCHAR(50),
    @sku_description                NVARCHAR(200),
    @ean                            NVARCHAR(50)     = NULL,
    @uom_code                       NVARCHAR(20)     = N'Each',
    @weight_per_unit                DECIMAL(10,3)    = NULL,
    @standard_hu_quantity           INT              = 0,
    @is_hazardous                   BIT              = 0,
    @is_batch_required              BIT              = 0,
    @is_full_hu_required            BIT              = 0,
    @preferred_storage_type_code    NVARCHAR(50)     = NULL,
    @preferred_storage_section_code NVARCHAR(50)     = NULL,
    @user_id                        INT              = NULL,
    @session_id                     UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = @sku_code)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU02' AS result_code, NULL AS sku_id;
            ROLLBACK;
            RETURN;
        END

        -- Resolve storage type: use supplied code, fallback to RACK, fallback to any active
        DECLARE @storage_type_id INT =
            ISNULL(
                (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE storage_type_code = @preferred_storage_type_code AND is_active = 1),
                ISNULL(
                    (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK' AND is_active = 1),
                    (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE is_active = 1 ORDER BY storage_type_id)
                )
            );

        -- Resolve storage section: use supplied code, NULL if not found
        DECLARE @storage_section_id INT =
            (SELECT TOP 1 storage_section_id FROM locations.storage_sections WHERE section_code = @preferred_storage_section_code AND is_active = 1);

        INSERT INTO inventory.skus
            (sku_code, sku_description, ean, uom_code, weight_per_unit,
             standard_hu_quantity, is_hazardous, is_batch_required, is_full_hu_required,
             is_active, preferred_storage_type_id, preferred_storage_section_id,
             created_at, created_by)
        VALUES
            (@sku_code, @sku_description, @ean, @uom_code, @weight_per_unit,
             @standard_hu_quantity, @is_hazardous, @is_batch_required, @is_full_hu_required,
             1, @storage_type_id, @storage_section_id,
             SYSUTCDATETIME(), @user_id);

        DECLARE @sku_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSKU01' AS result_code, @sku_id AS sku_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSKU99' AS result_code, NULL AS sku_id;
    END CATCH
END;
GO
PRINT 'inventory.usp_create_sku updated — full parameter set.';
GO

-- ── 2. inbound.usp_create_inbound ───────────────────────────────────────
GO

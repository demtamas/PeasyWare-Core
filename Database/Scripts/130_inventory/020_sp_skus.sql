PRINT 'inventory.usp_create_sku created.';
GO

-- ── 2. inbound.usp_create_inbound ───────────────────────────────────────
GO

CREATE OR ALTER PROCEDURE inventory.usp_create_sku
(
    @sku_code             NVARCHAR(50),
    @sku_description      NVARCHAR(200),
    @ean                  NVARCHAR(50)  = NULL,
    @uom_code             NVARCHAR(20)  = N'Each',
    @weight_per_unit      DECIMAL(10,3) = NULL,
    @standard_hu_quantity INT           = 0,
    @is_hazardous         BIT           = 0,
    @user_id              INT           = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
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

        -- Resolve default storage type (RACK preferred, fallback to first available)
        DECLARE @default_storage_type_id INT =
            ISNULL(
                (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK' AND is_active = 1),
                (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE is_active = 1 ORDER BY storage_type_id)
            );

        INSERT INTO inventory.skus
            (sku_code, sku_description, ean, uom_code, weight_per_unit,
             standard_hu_quantity, is_hazardous, is_active,
             preferred_storage_type_id, created_at, created_by)
        VALUES
            (@sku_code, @sku_description, @ean, @uom_code, @weight_per_unit,
             @standard_hu_quantity, @is_hazardous, 1,
             @default_storage_type_id, SYSUTCDATETIME(), @user_id);

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

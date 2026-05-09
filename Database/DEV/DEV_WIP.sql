USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — inventory.usp_update_sku + inventory.v_skus
    Date: 2026-05-05
********************************************************************************************/

-- ── v_skus ────────────────────────────────────────────────────────────────────

CREATE OR ALTER VIEW inventory.v_skus
AS
SELECT
    s.sku_id,
    s.sku_code,
    s.sku_description,
    s.ean,
    s.uom_code,
    s.weight_per_unit,
    s.standard_hu_quantity,
    s.is_hazardous,
    s.is_batch_required,
    s.is_full_hu_required,
    s.is_active,
    st.storage_type_code        AS preferred_storage_type_code,
    ss.section_code             AS preferred_section_code,
    s.created_at,
    cu.username                 AS created_by_username,
    s.updated_at,
    uu.username                 AS updated_by_username
FROM inventory.skus s
LEFT JOIN locations.storage_types    st ON st.storage_type_id    = s.preferred_storage_type_id
LEFT JOIN locations.storage_sections ss ON ss.storage_section_id = s.preferred_storage_section_id
LEFT JOIN auth.users cu              ON cu.id = s.created_by
LEFT JOIN auth.users uu              ON uu.id = s.updated_by;
GO
PRINT 'inventory.v_skus created.';
GO

-- ── Error codes ───────────────────────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSKU02', N'SKU', N'SUCCESS', N'SKU updated successfully.', N'inventory.usp_update_sku: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSKU02');
GO

-- ── usp_update_sku ─────────────────────────────────────────────────────────────

CREATE OR ALTER PROCEDURE inventory.usp_update_sku
(
    @sku_code             NVARCHAR(50),
    @sku_description      NVARCHAR(200),
    @ean                  NVARCHAR(50)     = NULL,
    @uom_code             NVARCHAR(20)     = N'Each',
    @weight_per_unit      DECIMAL(10,3)    = NULL,
    @standard_hu_quantity INT              = 0,
    @is_hazardous         BIT              = 0,
    @is_active            BIT              = 1,
    @preferred_storage_type_id    INT      = NULL,
    @preferred_storage_section_id INT      = NULL,
    @user_id              INT              = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = @sku_code)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU01' AS result_code;
            ROLLBACK;
            RETURN;
        END

        UPDATE inventory.skus
        SET sku_description      = @sku_description,
            ean                  = @ean,
            uom_code             = @uom_code,
            weight_per_unit      = @weight_per_unit,
            standard_hu_quantity = @standard_hu_quantity,
            is_hazardous         = @is_hazardous,
            is_active            = @is_active,
            preferred_storage_type_id    = @preferred_storage_type_id,
            preferred_storage_section_id = @preferred_storage_section_id,
            updated_at           = SYSUTCDATETIME(),
            updated_by           = @user_id
        WHERE sku_code = @sku_code;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSKU02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSKU99' AS result_code;
    END CATCH
END;
GO
PRINT 'inventory.usp_update_sku created.';
GO

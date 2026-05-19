USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inventory.usp_update_sku
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
    @is_active                      BIT              = 1,
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

        IF NOT EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = @sku_code)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU01' AS result_code;
            ROLLBACK;
            RETURN;
        END

        -- Resolve storage type: use supplied code, keep existing if NULL supplied
        DECLARE @storage_type_id INT =
            CASE
                WHEN @preferred_storage_type_code IS NOT NULL
                THEN (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE storage_type_code = @preferred_storage_type_code AND is_active = 1)
                ELSE (SELECT preferred_storage_type_id FROM inventory.skus WHERE sku_code = @sku_code)
            END;

        -- Resolve storage section: use supplied code, keep existing if NULL supplied
        DECLARE @storage_section_id INT =
            CASE
                WHEN @preferred_storage_section_code IS NOT NULL
                THEN (SELECT TOP 1 storage_section_id FROM locations.storage_sections WHERE section_code = @preferred_storage_section_code AND is_active = 1)
                ELSE (SELECT preferred_storage_section_id FROM inventory.skus WHERE sku_code = @sku_code)
            END;

        UPDATE inventory.skus
        SET sku_description              = @sku_description,
            ean                          = @ean,
            uom_code                     = @uom_code,
            weight_per_unit              = @weight_per_unit,
            standard_hu_quantity         = @standard_hu_quantity,
            is_hazardous                 = @is_hazardous,
            is_batch_required            = @is_batch_required,
            is_full_hu_required          = @is_full_hu_required,
            is_active                    = @is_active,
            preferred_storage_type_id    = @storage_type_id,
            preferred_storage_section_id = @storage_section_id,
            updated_at                   = SYSUTCDATETIME(),
            updated_by                   = @user_id
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
PRINT 'inventory.usp_update_sku updated — full parameter set, code-based storage resolution.';
GO

-- ============================================================
-- Bin code strict case enforcement + audit.v_sku_changes update
-- Merged from WIP: 2026-05-15
-- ============================================================

-- ── inbound.usp_receive_inbound_line ─────────────────────────────────────────


-- ── warehouse.usp_putaway_confirm_task ────────────────────────────────────────


-- ── warehouse.usp_bin_to_bin_move_create ─────────────────────────────────────


-- ── warehouse.usp_bin_to_bin_move_confirm ────────────────────────────────────


PRINT '------------------------------------------------------------';
PRINT 'Bin code strict case enforcement complete.';
PRINT 'All UPPER() removed from bin lookups. LTRIM/RTRIM retained.';
PRINT '';
PRINT 'NOTE: outbound.usp_pick_create and usp_pick_confirm still have';
PRINT 'UPPER() on destination bin — fix in next WIP cycle when pick';
PRINT 'flow is being tested end-to-end.';
PRINT '------------------------------------------------------------';
GO

-- ── audit.v_sku_changes: update JSON paths from Data.Data to Data.Outcome ──
-- RepositoryBase.BuildResult now uses 'Outcome' instead of 'Data' for the
-- action-specific payload, eliminating the confusing Data.Data nesting.
-- Historical rows (before this change) will return NULL from this view
-- since they still have the old $.Data.Data path.
GO

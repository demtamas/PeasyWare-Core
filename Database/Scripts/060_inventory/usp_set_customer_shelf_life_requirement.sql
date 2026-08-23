USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/********************************************************************************************
    inventory.usp_set_customer_shelf_life_requirement

    Upserts a customer+SKU minimum-remaining-shelf-life override. Gated on
    materials.manage (reused rather than a dedicated key - this is SKU
    master data, same category as editing a SKU itself).

    Contract: success BIT | result_code NVARCHAR(20)
              | customer_party_id INT | sku_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE inventory.usp_set_customer_shelf_life_requirement
(
    @customer_party_code                NVARCHAR(50),
    @sku_code                           NVARCHAR(50),
    @minimum_remaining_shelf_life_days  INT,
    @user_id                            INT              = NULL,
    @session_id                         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @customer_party_id INT, @sku_id INT, @now DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'materials.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code, NULL AS customer_party_id, NULL AS sku_id;
            ROLLBACK; RETURN;
        END

        SET @customer_party_id = (
            SELECT party_id FROM core.parties
            WHERE party_code = @customer_party_code COLLATE Latin1_General_CS_AS AND is_active = 1
        );
        IF @customer_party_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRCSL01' AS result_code, NULL AS customer_party_id, NULL AS sku_id;
            ROLLBACK; RETURN;
        END

        SET @sku_id = (
            SELECT sku_id FROM inventory.skus
            WHERE sku_code = @sku_code COLLATE Latin1_General_CS_AS AND is_active = 1
        );
        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRCSL02' AS result_code, NULL AS customer_party_id, NULL AS sku_id;
            ROLLBACK; RETURN;
        END

        IF @minimum_remaining_shelf_life_days < 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRCSL03' AS result_code, @customer_party_id AS customer_party_id, @sku_id AS sku_id;
            ROLLBACK; RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM inventory.customer_shelf_life_requirements
            WHERE customer_party_id = @customer_party_id AND sku_id = @sku_id
        )
        BEGIN
            UPDATE inventory.customer_shelf_life_requirements
            SET minimum_remaining_shelf_life_days = @minimum_remaining_shelf_life_days,
                updated_at = @now,
                updated_by = @user_id
            WHERE customer_party_id = @customer_party_id AND sku_id = @sku_id;
        END
        ELSE
        BEGIN
            INSERT INTO inventory.customer_shelf_life_requirements
                (customer_party_id, sku_id, minimum_remaining_shelf_life_days, created_at, created_by)
            VALUES
                (@customer_party_id, @sku_id, @minimum_remaining_shelf_life_days, @now, @user_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCCSL01' AS result_code, @customer_party_id AS customer_party_id, @sku_id AS sku_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCSL99' AS result_code, NULL AS customer_party_id, NULL AS sku_id;
    END CATCH
END;
GO

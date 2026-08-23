USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/********************************************************************************************
    inventory.usp_delete_customer_shelf_life_requirement

    Removes a customer+SKU override. Falls back to the SKU-level default
    (or the 0-day floor) automatically once removed - no separate step
    needed, since usp_allocate_order's cascade just stops finding this row.

    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
CREATE OR ALTER PROCEDURE inventory.usp_delete_customer_shelf_life_requirement
(
    @customer_party_code NVARCHAR(50),
    @sku_code            NVARCHAR(50),
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @customer_party_id INT, @sku_id INT;

    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'materials.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code;
            ROLLBACK; RETURN;
        END

        SET @customer_party_id = (SELECT party_id FROM core.parties WHERE party_code = @customer_party_code COLLATE Latin1_General_CS_AS);
        SET @sku_id            = (SELECT sku_id FROM inventory.skus WHERE sku_code = @sku_code COLLATE Latin1_General_CS_AS);

        IF @customer_party_id IS NULL OR @sku_id IS NULL
           OR NOT EXISTS (
               SELECT 1 FROM inventory.customer_shelf_life_requirements
               WHERE customer_party_id = @customer_party_id AND sku_id = @sku_id
           )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRCSL04' AS result_code;
            ROLLBACK; RETURN;
        END

        DELETE FROM inventory.customer_shelf_life_requirements
        WHERE customer_party_id = @customer_party_id AND sku_id = @sku_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCCSL02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCSL99' AS result_code;
    END CATCH
END;
GO

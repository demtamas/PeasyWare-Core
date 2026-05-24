USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE core.usp_create_party
(
    @party_code     NVARCHAR(50),
    @legal_name     NVARCHAR(200),
    @display_name   NVARCHAR(200),
    @country_code   CHAR(2)          = NULL,
    @tax_id         NVARCHAR(50)     = NULL,
    @roles          NVARCHAR(500)    = NULL,   -- comma-separated: 'SUPPLIER,CUSTOMER'
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM core.parties WHERE party_code = @party_code COLLATE Latin1_General_CS_AS)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS party_id;
            ROLLBACK; RETURN;
        END

        INSERT INTO core.parties
            (party_code, legal_name, display_name, country_code, tax_id,
             is_active, created_at, created_by)
        VALUES
            (@party_code, @legal_name, @display_name, @country_code, @tax_id,
             1, SYSUTCDATETIME(), @user_id);

        DECLARE @party_id INT = SCOPE_IDENTITY();

        -- Insert roles from comma-separated list
        IF @roles IS NOT NULL AND LEN(TRIM(@roles)) > 0
        BEGIN
            INSERT INTO core.party_roles (party_id, role_code, assigned_at, assigned_by)
            SELECT
                @party_id,
                TRIM(value),
                SYSUTCDATETIME(),
                @user_id
            FROM STRING_SPLIT(@roles, ',')
            WHERE LEN(TRIM(value)) > 0;
        END

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCPARTY01' AS result_code, @party_id AS party_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRPARTY99' AS result_code, NULL AS party_id;
    END CATCH
END;
GO

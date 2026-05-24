USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE core.usp_update_party
(
    @party_id       INT,
    @legal_name     NVARCHAR(200),
    @display_name   NVARCHAR(200),
    @country_code   CHAR(2)          = NULL,
    @tax_id         NVARCHAR(50)     = NULL,
    @is_active      BIT              = 1,
    @roles          NVARCHAR(500)    = NULL,   -- full replacement of roles
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM core.parties WHERE party_id = @party_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY02' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE core.parties
        SET legal_name   = @legal_name,
            display_name = @display_name,
            country_code = @country_code,
            tax_id       = @tax_id,
            is_active    = @is_active,
            updated_at   = SYSUTCDATETIME(),
            updated_by   = @user_id
        WHERE party_id = @party_id;

        -- Full role replacement if provided
        IF @roles IS NOT NULL
        BEGIN
            DELETE FROM core.party_roles WHERE party_id = @party_id;

            IF LEN(TRIM(@roles)) > 0
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
        END

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCPARTY02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRPARTY99' AS result_code;
    END CATCH
END;
GO

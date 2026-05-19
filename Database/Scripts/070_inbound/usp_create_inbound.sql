USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inbound.usp_create_inbound
(
    @inbound_ref         NVARCHAR(50),
    @supplier_party_code NVARCHAR(50),
    @haulier_party_code  NVARCHAR(50)     = NULL,
    @expected_arrival_at DATETIME2(3)     = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = @inbound_ref COLLATE Latin1_General_CS_AS)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB02' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @supplier_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @supplier_party_code
        );

        IF @supplier_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = NULL;
        IF @haulier_party_code IS NOT NULL
            SET @haulier_id = (
                SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code
            );

        DECLARE @ship_to_id INT = (
            SELECT TOP 1 pa.address_id
            FROM core.party_addresses pa
            JOIN core.parties p ON pa.party_id = p.party_id
            JOIN core.party_roles pr ON pr.party_id = p.party_id
            WHERE pr.role_code = 'WAREHOUSE'
              AND pa.is_primary = 1
        );

        INSERT INTO inbound.inbound_deliveries
            (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id,
             ship_to_address_id, expected_arrival_at, created_at, created_by)
        VALUES
            (@inbound_ref, @supplier_id, @supplier_id, @haulier_id,
             @ship_to_id, @expected_arrival_at, SYSUTCDATETIME(), @user_id);

        DECLARE @inbound_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINB02' AS result_code, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code, NULL AS inbound_id;
    END CATCH
END;
GO
PRINT 'inbound.usp_create_inbound created.';
GO

-- ── 3. inbound.usp_create_inbound_line ──────────────────────────────────
GO

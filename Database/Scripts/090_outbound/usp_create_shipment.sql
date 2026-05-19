USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_create_shipment
(
    @shipment_ref       NVARCHAR(50),
    @haulier_party_code NVARCHAR(50),
    @vehicle_ref        NVARCHAR(50)     = NULL,
    @planned_departure  DATETIME2(3)     = NULL,
    @notes              NVARCHAR(500)    = NULL,
    @user_id            INT              = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @shipment_id INT;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = @shipment_ref COLLATE Latin1_General_CS_AS)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code, NULL AS shipment_id;
            ROLLBACK; RETURN;
        END

        -- Resolve haulier party code to ID
        DECLARE @haulier_party_id INT = (SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code COLLATE Latin1_General_CS_AS);

        -- Resolve ship-from address from warehouse party (primary address)
        DECLARE @ship_from_address_id INT = (
            SELECT TOP 1 a.address_id
            FROM core.party_addresses a
            JOIN core.party_roles r ON r.party_id = a.party_id
            WHERE r.role_code = 'WAREHOUSE'
              AND a.is_primary = 1
              AND a.is_active  = 1
        );

        INSERT INTO outbound.shipments
        (
            shipment_ref, haulier_party_id, vehicle_ref,
            ship_from_address_id, planned_departure,
            shipment_status, notes,
            created_at, created_by
        )
        VALUES
        (
            @shipment_ref, @haulier_party_id, @vehicle_ref,
            @ship_from_address_id, @planned_departure,
            'OPEN', @notes,
            SYSUTCDATETIME(), @user_id
        );


        SET @shipment_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP01' AS result_code, @shipment_id AS shipment_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code, NULL AS shipment_id;
    END CATCH
END;

GO




-- ── outbound.usp_pick_confirm: UPPER() removed from bin comparison ───────────
GO

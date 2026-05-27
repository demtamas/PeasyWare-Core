USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_cancel_shipment
(
    @shipment_ref    NVARCHAR(50),
    @reason          NVARCHAR(200)    = NULL,
    @user_id         INT              = NULL,
    @session_id      UNIQUEIDENTIFIER = NULL,
    @correlation_id  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @shipment_id     INT;
        DECLARE @shipment_status VARCHAR(10);

        SELECT
            @shipment_id     = shipment_id,
            @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_ref = @shipment_ref COLLATE Latin1_General_CS_AS;

        -- Not found
        IF @shipment_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP06' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Already terminal
        IF @shipment_status IN ('DEPARTED', 'CNL')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP07' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Has orders with picked/loaded units — cannot cancel
        IF EXISTS (
            SELECT 1
            FROM outbound.shipment_orders so
            JOIN outbound.outbound_orders o ON o.outbound_order_id = so.outbound_order_id
            WHERE so.shipment_id = @shipment_id
              AND o.order_status_code IN ('PICKING', 'PICKED', 'LOADED')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP08' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Remove all order associations
        DELETE FROM outbound.shipment_orders
        WHERE shipment_id = @shipment_id;

        -- Cancel the shipment
        UPDATE outbound.shipments
        SET shipment_status = 'CNL',
            updated_at      = SYSUTCDATETIME(),
            updated_by      = @user_id
        WHERE shipment_id = @shipment_id;

        -- Log
        INSERT INTO audit.trace_logs
            (occurred_at, correlation_id, user_id, session_id, level, action, payload_json)
        VALUES
        (
            SYSUTCDATETIME(),
            @correlation_id,
            @user_id,
            @session_id,
            'INFO',
            'Outbound.CancelShipment',
            (SELECT
                @user_id          AS UserId,
                @session_id       AS SessionId,
                @correlation_id   AS CorrelationId,
                'SUCSHIP04'       AS ResultCode,
                CAST(1 AS BIT)    AS Success,
                @shipment_id      AS ShipmentId,
                @shipment_ref     AS ShipmentRef,
                @reason           AS Reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        );

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP04' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP99' AS result_code;
    END CATCH
END;
GO

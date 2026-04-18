USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — Load confirmation redesign
    Date: 2026-04-18

    usp_confirm_load: redesigned — takes order_id + shipment_id
    Operator confirms an order is loaded onto the vehicle.
    No SSCC scanning — pick already confirmed which units are where.

    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/

CREATE OR ALTER PROCEDURE outbound.usp_confirm_load
(
    @outbound_order_id  INT,
    @shipment_id        INT,
    @user_id            INT,
    @session_id         UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @order_status    VARCHAR(10),
        @order_shipment  INT,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order exists and belongs to this shipment ── */
        SELECT
            @order_status   = order_status_code,
            @order_shipment = shipment_id
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_shipment <> @shipment_id
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('PICKED', 'LOADED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        /* ── 2. Transition order → LOADED ── */
        UPDATE outbound.outbound_orders
        SET order_status_code = 'LOADED',
            updated_at        = @now,
            updated_by        = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        /* ── 3. Transition shipment → LOADING if still OPEN ── */
        UPDATE outbound.shipments
        SET shipment_status = 'LOADING',
            updated_at      = @now,
            updated_by      = @user_id
        WHERE shipment_id     = @shipment_id
          AND shipment_status = 'OPEN';

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCLOAD01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_confirm_load redesigned.';
GO

-- Add SUCLOAD01 message
INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCLOAD01', N'LOAD', N'INFO',
    N'Order loaded onto vehicle successfully.',
    N'Load.Confirm: order status LOADED, shipment LOADING'
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCLOAD01'
);
GO
PRINT 'SUCLOAD01 message inserted.';
GO

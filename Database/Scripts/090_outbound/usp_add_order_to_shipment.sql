USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_add_order_to_shipment
(
    @shipment_ref  NVARCHAR(50),
    @order_ref     NVARCHAR(50),
    @user_id       INT              = NULL,
    @session_id    UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    -- Resolve refs to IDs
    DECLARE @outbound_order_id INT = (SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = @order_ref COLLATE Latin1_General_CS_AS);
    DECLARE @shipment_id       INT = (SELECT shipment_id       FROM outbound.shipments        WHERE shipment_ref = @shipment_ref COLLATE Latin1_General_CS_AS);

    DECLARE
        @order_status    VARCHAR(10),
        @shipment_status VARCHAR(10);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @order_status = order_status_code
        FROM outbound.outbound_orders WITH (UPDLOCK, HOLDLOCK)
        WHERE outbound_order_id = @outbound_order_id;

        IF @order_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @order_status NOT IN ('NEW','ALLOCATED','PICKING','PICKED')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code;
            ROLLBACK; RETURN;
        END

        SELECT @shipment_status = shipment_status
        FROM outbound.shipments WITH (UPDLOCK, HOLDLOCK)
        WHERE shipment_id = @shipment_id;

        IF @shipment_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @shipment_status NOT IN ('OPEN','LOADING')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Link order to shipment
        UPDATE outbound.outbound_orders
        SET shipment_id = @shipment_id,
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @user_id
        WHERE outbound_order_id = @outbound_order_id;

        -- Junction row
        IF NOT EXISTS (
            SELECT 1 FROM outbound.shipment_orders
            WHERE shipment_id = @shipment_id
              AND outbound_order_id = @outbound_order_id
        )
        BEGIN
            INSERT INTO outbound.shipment_orders
                (shipment_id, outbound_order_id, added_at, added_by)
            VALUES
                (@shipment_id, @outbound_order_id, SYSUTCDATETIME(), @user_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code;
    END CATCH
END;

GO



/****** Object:  StoredProcedure [outbound].[usp_allocate_order]    Script Date: 18/04/2026 09:31:00 ******/



/********************************************************************************************
    2. outbound.usp_allocate_order
    Allocation engine — reserves stock for every line on an order.

    Strategy (driven by operations.settings 'outbound.allocation_strategy'):
      FEFO  — earliest best_before_date first
      FIFO  — earliest received_at first
      NONE  — FEFO if BBE present on unit, else FIFO (default)

    Rules:
      - Only PUTAWAY + AVAILABLE units
      - Full pallets only (unit quantity must satisfy line qty requirement)
      - Respects requested_batch and requested_bbe on line if set
      - Per-SKU allocation: per-line override on batch/BBE takes priority
      - All lines must be satisfiable — partial allocation rolls back

    Contract: success BIT | result_code NVARCHAR(20) | outbound_order_id INT
********************************************************************************************/
GO

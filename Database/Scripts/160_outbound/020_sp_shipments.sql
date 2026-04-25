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

/****** Object:  StoredProcedure [outbound].[usp_pick_confirm]    Script Date: 18/04/2026 09:31:49 ******/



/********************************************************************************************
    6. outbound.usp_pick_confirm
    Operator scans bin then SSCC to confirm physical pick.
    Moves unit placement to staging bin, transitions unit to PKD,
    writes PICK movement record.

    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
GO

PRINT 'outbound.usp_create_shipment created.';
GO

-- ── 7. outbound.usp_add_order_to_shipment (ref-based overload) ──────────
GO

PRINT 'outbound.usp_add_order_to_shipment created.';
GO

PRINT '------------------------------------------------------------';
PRINT 'API SPs patch complete.';
PRINT '------------------------------------------------------------';
GO

-- ============================================================
-- Batch canonicalisation patch — merged from WIP 2026-04-24
-- ============================================================
GO

CREATE OR ALTER PROCEDURE outbound.usp_add_order_to_shipment
(
    @shipment_ref NVARCHAR(50),
    @order_ref    NVARCHAR(50),
    @user_id      INT              = NULL,
    @session_id   UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @shipment_id INT = (
            SELECT shipment_id FROM outbound.shipments WHERE shipment_ref = @shipment_ref
        );

        IF @shipment_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP03' AS result_code;
            ROLLBACK;
            RETURN;
        END

        DECLARE @order_id INT = (
            SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = @order_ref
        );

        IF @order_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD03' AS result_code;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM outbound.shipment_orders
            WHERE shipment_id = @shipment_id AND outbound_order_id = @order_id
        )
        BEGIN
            INSERT INTO outbound.shipment_orders (shipment_id, outbound_order_id, added_at, added_by)
            VALUES (@shipment_id, @order_id, SYSUTCDATETIME(), @user_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP03' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP99' AS result_code;
    END CATCH
END;
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

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = @shipment_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code, NULL AS shipment_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code
        );

        IF @haulier_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS shipment_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @ship_from_id INT = (
            SELECT TOP 1 pa.address_id
            FROM core.party_addresses pa
            JOIN core.parties p ON pa.party_id = p.party_id
            JOIN core.party_roles pr ON pr.party_id = p.party_id
            WHERE pr.role_code = 'WAREHOUSE'
              AND pa.is_primary = 1
        );

        INSERT INTO outbound.shipments
            (shipment_ref, haulier_party_id, vehicle_ref,
             ship_from_address_id, planned_departure,
             shipment_status, notes, created_at, created_by)
        VALUES
            (@shipment_ref, @haulier_id, @vehicle_ref,
             @ship_from_id, @planned_departure,
             'OPEN', @notes, SYSUTCDATETIME(), @user_id);

        DECLARE @shipment_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP01' AS result_code, @shipment_id AS shipment_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP99' AS result_code, NULL AS shipment_id;
    END CATCH
END;
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE outbound.usp_create_order
(
    @order_ref           NVARCHAR(50),
    @customer_party_code NVARCHAR(50),
    @haulier_party_code  NVARCHAR(50)     = NULL,
    @required_date       DATE             = NULL,
    @order_source        VARCHAR(10)      = 'API',
    @notes               NVARCHAR(500)    = NULL,
    @lines_json          NVARCHAR(MAX)    = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @outbound_order_id INT;

    BEGIN TRY
        BEGIN TRAN;

        /* ── 1. Validate order ref uniqueness ── */
        IF EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = @order_ref COLLATE Latin1_General_CS_AS)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 2. Resolve customer party code to ID ── */
        DECLARE @customer_party_id INT = (SELECT party_id FROM core.parties WHERE party_code = @customer_party_code COLLATE Latin1_General_CS_AS AND is_active = 1);

        IF @customer_party_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        DECLARE @haulier_party_id INT = NULL;
        IF @haulier_party_code IS NOT NULL
            SET @haulier_party_id = (SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code COLLATE Latin1_General_CS_AS);


        /* ── 3. Validate lines JSON not empty ── */
        IF @lines_json IS NULL OR ISJSON(@lines_json) = 0
           OR NOT EXISTS (SELECT 1 FROM OPENJSON(@lines_json))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD04' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        /* ── 4. Insert order header ── */
        INSERT INTO outbound.outbound_orders
        (
            order_ref, customer_party_id, haulier_party_id,
            order_status_code, order_source,
            required_date, notes,
            created_at, created_by
        )
        VALUES
        (
            @order_ref, @customer_party_id, @haulier_party_id,
            'NEW', @order_source,
            @required_date, @notes,
            SYSUTCDATETIME(), @user_id
        );

        SET @outbound_order_id = SCOPE_IDENTITY();

        /* ── 5. Insert lines from JSON ── */
        INSERT INTO outbound.outbound_lines
        (
            outbound_order_id, line_no, sku_id,
            ordered_qty, requested_batch, requested_bbe,
            line_status_code, notes,
            created_at, created_by
        )
        SELECT
            @outbound_order_id,
            CAST(j.line_no AS INT),
            s.sku_id,
            CAST(j.ordered_qty AS INT),
            NULLIF(j.requested_batch, ''),
            TRY_CAST(NULLIF(j.requested_bbe, '') AS DATE),
            'NEW',
            NULLIF(j.notes, ''),
            SYSUTCDATETIME(),
            @user_id
        FROM OPENJSON(@lines_json)
        WITH (
            line_no         INT            '$.LineNo',
            sku_code        NVARCHAR(50)   '$.SkuCode',
            ordered_qty     INT            '$.OrderedQty',
            requested_batch NVARCHAR(100)  '$.RequestedBatch',
            requested_bbe   NVARCHAR(20)   '$.RequestedBbe',
            notes           NVARCHAR(500)  '$.Notes'
        ) j
        JOIN inventory.skus s
            ON s.sku_code = j.sku_code
           AND s.is_active = 1;

        /* ── 6. Verify all lines resolved (no unknown SKU codes) ── */
        DECLARE @json_line_count   INT = (SELECT COUNT(*) FROM OPENJSON(@lines_json));
        DECLARE @inserted_count    INT = (SELECT COUNT(*) FROM outbound.outbound_lines
                                          WHERE outbound_order_id = @outbound_order_id);

        IF @inserted_count <> @json_line_count
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD04' AS result_code, NULL AS outbound_order_id;
            ROLLBACK; RETURN;
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code, @outbound_order_id AS outbound_order_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD01' AS result_code, NULL AS outbound_order_id;
    END CATCH
END;

GO



/****** Object:  StoredProcedure [outbound].[usp_create_shipment]    Script Date: 18/04/2026 09:31:33 ******/



/********************************************************************************************
    3. outbound.usp_create_shipment
    Contract: success BIT | result_code NVARCHAR(20) | shipment_id INT
********************************************************************************************/
GO

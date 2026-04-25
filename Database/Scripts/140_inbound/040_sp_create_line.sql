PRINT 'inbound.usp_create_inbound_line created.';
GO

-- ── 4. inbound.usp_create_expected_unit ─────────────────────────────────
-- Adds an SSCC to the most recently added line on this inbound.
-- If the inbound has multiple lines, the caller must extend this
-- or add a @sku_code parameter to target a specific line.
GO

PRINT 'inbound.usp_create_inbound_line updated — batch canonicalised at storage.';
GO

-- ── 2. inbound.usp_create_expected_unit ─────────────────────────────────
GO

CREATE OR ALTER PROCEDURE inbound.usp_create_inbound_line
(
    @inbound_ref          NVARCHAR(50),
    @sku_code             NVARCHAR(50),
    @expected_qty         INT,
    @batch_number         NVARCHAR(100)    = NULL,
    @best_before_date     DATE             = NULL,
    @arrival_stock_status NVARCHAR(2)      = N'AV',
    @user_id              INT              = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Canonicalise batch at storage time
        SET @batch_number = UPPER(LTRIM(RTRIM(@batch_number)));

        DECLARE @inbound_id INT = (
            SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = @inbound_ref
        );

        IF @inbound_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @sku_id INT = (
            SELECT sku_id FROM inventory.skus WHERE sku_code = @sku_code AND is_active = 1
        );

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU01' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @line_no INT = ISNULL(
            (SELECT MAX(line_no) FROM inbound.inbound_lines WHERE inbound_id = @inbound_id), 0
        ) + 10;

        INSERT INTO inbound.inbound_lines
            (inbound_id, line_no, sku_id, expected_qty, received_qty,
             batch_number, best_before_date, arrival_stock_status_code,
             created_at, created_by)
        VALUES
            (@inbound_id, @line_no, @sku_id, @expected_qty, 0,
             @batch_number, @best_before_date, @arrival_stock_status,
             SYSUTCDATETIME(), @user_id);

        DECLARE @inbound_line_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINBL02' AS result_code,
               @inbound_line_id AS inbound_line_id, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code,
               NULL AS inbound_line_id, NULL AS inbound_id;
    END CATCH
END;
GO

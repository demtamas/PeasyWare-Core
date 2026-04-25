PRINT 'inbound.usp_create_expected_unit created.';
GO

-- ── 5. outbound.usp_create_order (party-code based) ─────────────────────
GO

PRINT 'inbound.usp_create_expected_unit updated — batch canonicalised at storage.';
GO

-- ── 3. inbound.usp_receive_inbound_line — batch canonicalisation ─────────
GO

CREATE OR ALTER PROCEDURE inbound.usp_create_expected_unit
(
    @inbound_ref      NVARCHAR(50),
    @sscc             NVARCHAR(18),
    @quantity         INT,
    @batch_number     NVARCHAR(100)    = NULL,
    @best_before_date DATE             = NULL,
    @user_id          INT              = NULL,
    @session_id       UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Canonicalise batch at storage time
        SET @batch_number = UPPER(LTRIM(RTRIM(@batch_number)));

        DECLARE @inbound_line_id INT = (
            SELECT TOP 1 l.inbound_line_id
            FROM inbound.inbound_lines l
            JOIN inbound.inbound_deliveries d ON d.inbound_id = l.inbound_id
            WHERE d.inbound_ref = @inbound_ref
            ORDER BY l.line_no DESC
        );

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code,
                   NULL AS inbound_expected_unit_id;
            ROLLBACK;
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM inbound.inbound_expected_units eu
            JOIN inbound.inbound_lines l ON l.inbound_line_id = eu.inbound_line_id
            JOIN inbound.inbound_deliveries d ON d.inbound_id = l.inbound_id
            WHERE d.inbound_ref = @inbound_ref
              AND eu.expected_external_ref = @sscc
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBU01' AS result_code,
                   NULL AS inbound_expected_unit_id;
            ROLLBACK;
            RETURN;
        END

        INSERT INTO inbound.inbound_expected_units
            (inbound_line_id, expected_external_ref, expected_quantity,
             batch_number, best_before_date, created_at, created_by)
        VALUES
            (@inbound_line_id, @sscc, @quantity,
             @batch_number, @best_before_date, SYSUTCDATETIME(), @user_id);

        DECLARE @unit_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINBU01' AS result_code,
               @unit_id AS inbound_expected_unit_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code,
               NULL AS inbound_expected_unit_id;
    END CATCH
END;
GO

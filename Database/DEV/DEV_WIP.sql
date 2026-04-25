USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — Batch number canonicalisation at storage layer
    Date: 2026-04-24

    Problem:
      Batch equality checks in usp_validate_sscc_for_receive and
      usp_receive_inbound_line use raw string comparison (<>).
      Application layers normalise to uppercase via IdentifierPolicy.NormaliseBatch()
      but the SQL storage layer has no normalisation.
      A batch stored as '001442331a' would false-mismatch against a scanned '001442331A'.

    Fix:
      Apply UPPER(LTRIM(RTRIM())) to @batch_number at INSERT time in:
        - inbound.usp_create_inbound_line
        - inbound.usp_create_expected_unit
        - inbound.usp_receive_inbound_line  (blind receipt path stores scanned batch)

      The comparison SPs (usp_validate_sscc_for_receive, usp_receive_inbound_line)
      then compare two already-canonical values. No change needed to comparison logic.

    This makes the DB the last line of defence — even if a future entry point
    skips IdentifierPolicy.NormaliseBatch(), the SP canonicalises at storage.
********************************************************************************************/

-- ── 1. usp_create_inbound_line ───────────────────────────────────────────

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
PRINT 'inbound.usp_create_inbound_line updated — batch canonicalised at storage.';
GO

-- ── 2. inbound.usp_create_expected_unit ─────────────────────────────────

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
PRINT 'inbound.usp_create_expected_unit updated — batch canonicalised at storage.';
GO

-- ── 3. inbound.usp_receive_inbound_line — batch canonicalisation ─────────

CREATE OR ALTER PROCEDURE inbound.usp_receive_inbound_line
(
    @inbound_line_id            INT = NULL,
    @received_qty               INT = NULL,
    @staging_bin_code           NVARCHAR(100),
    @inbound_expected_unit_id   INT = NULL,
    @claim_token                UNIQUEIDENTIFIER = NULL,
    @external_ref               NVARCHAR(100) = NULL,
    @batch_number               NVARCHAR(100) = NULL,
    @best_before_date           DATE = NULL,
    @user_id                    INT = NULL,
    @session_id                 UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @is_closed BIT = 0;

    BEGIN TRY
        BEGIN TRAN;

        -- Canonicalise bin code and batch at entry
        SET @staging_bin_code = UPPER(LTRIM(RTRIM(@staging_bin_code)));
        SET @batch_number     = UPPER(LTRIM(RTRIM(@batch_number)));

        IF NULLIF(@staging_bin_code, N'') IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL07' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        DECLARE @is_sscc_mode BIT =
            CASE WHEN @inbound_expected_unit_id IS NOT NULL THEN 1 ELSE 0 END;

        DECLARE
            @resolved_line_id          INT = NULL,
            @sku_id                    INT = NULL,
            @inbound_id                INT = NULL,
            @expected_qty              INT = NULL,
            @already_received          INT = NULL,
            @line_state                VARCHAR(3),
            @header_status             VARCHAR(3),
            @expected_unit_qty         INT,
            @existing_received_id      INT,
            @now                       DATETIME2(3) = SYSUTCDATETIME(),
            @claim_expires_at          DATETIME2(3),
            @db_claim_token            UNIQUEIDENTIFIER,
            @claimed_session_id        UNIQUEIDENTIFIER,
            @new_received_qty          INT,
            @new_line_state            VARCHAR(3),
            @receipt_id                INT,
            @arrival_status_code       VARCHAR(2),
            /* Capture scanned values before overwrite from expected unit */
            @scanned_best_before_date  DATE           = @best_before_date,
            @scanned_batch_number      NVARCHAR(100)  = @batch_number;

        IF @is_sscc_mode = 1
        BEGIN
            IF @session_id IS NULL OR @claim_token IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRPROC02' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            SELECT
                @resolved_line_id     = eu.inbound_line_id,
                @expected_unit_qty    = eu.expected_quantity,
                @external_ref         = eu.expected_external_ref,
                @batch_number         = eu.batch_number,
                @best_before_date     = eu.best_before_date,
                @existing_received_id = eu.received_inventory_unit_id,
                @claim_expires_at     = eu.claim_expires_at,
                @db_claim_token       = eu.claim_token,
                @claimed_session_id   = eu.claimed_session_id
            FROM inbound.inbound_expected_units eu WITH (UPDLOCK, HOLDLOCK)
            WHERE eu.inbound_expected_unit_id = @inbound_expected_unit_id;

            IF @resolved_line_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRSSCC01' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            IF @existing_received_id IS NOT NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRSSCC06' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            IF @claim_expires_at IS NOT NULL AND @claim_expires_at <= @now
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRSSCC08' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            IF @claimed_session_id <> @session_id
               OR @db_claim_token <> @claim_token
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRSSCC08' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            /* ── BBE mismatch — hard block ────────────────────────────────────────────── */
            -- NOTE: This check also exists in usp_validate_sscc_for_receive (phase 1).
            -- Both are intentional. Phase 1 gives fast operator feedback before the claim.
            -- Phase 2 (here) is a transactional safety net inside BEGIN TRAN.
            -- If this logic changes, update BOTH SPs together.
            IF @scanned_best_before_date IS NOT NULL
               AND @best_before_date IS NOT NULL
               AND @scanned_best_before_date <> @best_before_date
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRINBL09' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            /* ── Batch number mismatch — hard block ───────────────────────────────────── */
            IF @scanned_batch_number IS NOT NULL
               AND @batch_number IS NOT NULL
               AND @scanned_batch_number <> @batch_number
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRINBL10' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            SET @received_qty = @expected_unit_qty;
        END
        ELSE
        BEGIN
            SET @resolved_line_id = @inbound_line_id;

            IF @resolved_line_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRINBL01' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END

            IF @received_qty IS NULL OR @received_qty <= 0
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRINBL06' AS result_code,
                       NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
                ROLLBACK;
                RETURN;
            END
        END

        SELECT
            @sku_id               = l.sku_id,
            @inbound_id           = l.inbound_id,
            @expected_qty         = l.expected_qty,
            @already_received     = ISNULL(l.received_qty, 0),
            @line_state           = l.line_state_code,
            @arrival_status_code  = l.arrival_stock_status_code
        FROM inbound.inbound_lines l WITH (UPDLOCK, HOLDLOCK)
        WHERE l.inbound_line_id = @resolved_line_id;

        IF (@already_received + @received_qty) > @expected_qty
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL02' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        /* ── Duplicate SSCC guard ─────────────────────────────────────────────────────── */
        IF @external_ref IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM inventory.inventory_units
               WHERE external_ref      = @external_ref
                 AND stock_state_code NOT IN ('REV', 'SHP')
           )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSSCC02' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        DECLARE @inventory_unit_id INT;

        INSERT INTO inventory.inventory_units
        (
            sku_id, external_ref, batch_number, best_before_date,
            quantity, stock_state_code, stock_status_code,
            created_at, created_by
        )
        VALUES
        (
            @sku_id, @external_ref, @batch_number, @best_before_date,
            @received_qty, 'RCD', @arrival_status_code,
            SYSUTCDATETIME(), @user_id
        );

        SET @inventory_unit_id = SCOPE_IDENTITY();

        DECLARE @staging_bin_id INT;

        SELECT @staging_bin_id = bin_id
        FROM locations.bins
        WHERE bin_code = UPPER(LTRIM(RTRIM(@staging_bin_code)))
          AND is_active = 1;

        IF @staging_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL08' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        INSERT INTO inventory.inventory_placements
        (inventory_unit_id, bin_id, placed_at, placed_by)
        VALUES
        (@inventory_unit_id, @staging_bin_id, SYSUTCDATETIME(), @user_id);

        IF @is_sscc_mode = 1
        BEGIN
            UPDATE inbound.inbound_expected_units
            SET received_inventory_unit_id = @inventory_unit_id,
                expected_unit_state_code   = 'RCV'
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id;
        END

        SET @new_received_qty = @already_received + @received_qty;

        SET @new_line_state =
            CASE
                WHEN @new_received_qty < @expected_qty THEN 'PRC'
                ELSE 'RCV'
            END;

        UPDATE inbound.inbound_lines
        SET received_qty    = @new_received_qty,
            line_state_code = @new_line_state,
            updated_at      = SYSUTCDATETIME(),
            updated_by      = @user_id
        WHERE inbound_line_id = @resolved_line_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL_UPDATE_MISS' AS result_code,
                   @resolved_line_id AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        INSERT INTO inbound.inbound_receipts
        (
            inbound_line_id, inbound_expected_unit_id, inventory_unit_id,
            received_qty, received_at, received_by_user_id, session_id
        )
        VALUES
        (
            @resolved_line_id, @inbound_expected_unit_id, @inventory_unit_id,
            @received_qty, SYSUTCDATETIME(), @user_id, @session_id
        );

        SET @receipt_id = SCOPE_IDENTITY();

        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id
        )
        VALUES
        (
            @inventory_unit_id, @sku_id, @received_qty,
            NULL, @staging_bin_id,
            NULL, 'RCD',
            NULL, @arrival_status_code,
            'INBOUND', 'RECEIPT', @receipt_id,
            SYSUTCDATETIME(), @user_id, @session_id
        );

        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code NOT IN ('RCV','CNL')
        )
        BEGIN
            UPDATE inbound.inbound_deliveries
            SET inbound_status_code = 'CLS',
                updated_at          = SYSUTCDATETIME(),
                updated_by          = @user_id
            WHERE inbound_id = @inbound_id;

            SET @is_closed = 1;
        END

        COMMIT;

        SELECT
            CAST(1 AS BIT)       AS success,
            N'SUCINBL01'         AS result_code,
            @resolved_line_id    AS inbound_line_id,
            @inbound_id          AS inbound_id,
            @is_closed           AS is_closed;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)  AS success,
            N'ERRINBL99'    AS result_code,
            NULL            AS inbound_line_id,
            NULL            AS inbound_id,
            CAST(0 AS BIT)  AS is_closed;
    END CATCH
END;
GO
PRINT 'inbound.usp_receive_inbound_line updated — batch canonicalised at storage.';
GO

PRINT '------------------------------------------------------------';
PRINT 'Batch canonicalisation patch complete.';
PRINT '------------------------------------------------------------';
GO

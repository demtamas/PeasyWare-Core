USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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

        SET @staging_bin_code = LTRIM(RTRIM(@staging_bin_code)) COLLATE Latin1_General_CS_AS;

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
                -- Prefer expected unit batch/bbe; fall back to what operator provided
                @batch_number         = COALESCE(eu.batch_number,    @batch_number),
                @best_before_date     = COALESCE(eu.best_before_date, @best_before_date),
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

        /* ── Batch required guard ─────────────────────────────────────────────
           If the SKU has is_batch_required = 1 and no batch number was
           provided (either from the expected unit or the operator), block
           the receipt so the unit is never created without a batch.
        ──────────────────────────────────────────────────────────────────── */
        DECLARE @is_batch_required BIT;

        SELECT @is_batch_required = is_batch_required
        FROM inventory.skus
        WHERE sku_id = @sku_id;

        IF @is_batch_required = 1
           AND NULLIF(LTRIM(RTRIM(ISNULL(@batch_number, N''))), N'') IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL11' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        /* ── Duplicate SSCC guard — explicit check before INSERT
           so the unique index violation becomes ERRSSCC02 not ERRINBL99
        -------------------------------------------------------- */
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
        WHERE bin_code = LTRIM(RTRIM(@staging_bin_code)) COLLATE Latin1_General_CS_AS
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

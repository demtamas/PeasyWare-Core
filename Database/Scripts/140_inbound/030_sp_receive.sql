/********************************************************************************************
    SECTION: Inbound Structural Guards (Operationally-aware)
    Purpose : Prevent structural modification after activation while allowing operational flow
              - Inbound lines:
                    * Block INSERT/DELETE once ACT+
                    * Allow UPDATE only for receiving progression (received_qty, line_state_code, updated_*)
              - Expected units:
                    * Block INSERT/DELETE once ACT+
                    * Allow UPDATE only for claim/receive fields + expected_unit_state_code transitions
              - Inbound mode:
                    * Prevent inbound_mode_code from being changed once set
********************************************************************************************/

/* =========================================================================================
   Trigger: inbound.trg_inbound_lines_guard
   Blocks structural modification of inbound lines after activation.
   Allows operational updates (receiving progression) in ACT/RCV.
========================================================================================= */
GO

PRINT 'inbound.usp_receive_inbound_line updated — batch canonicalised at storage.';
GO

PRINT '------------------------------------------------------------';
PRINT 'Batch canonicalisation patch complete.';
PRINT '------------------------------------------------------------';
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

GO

CREATE OR ALTER PROCEDURE inbound.usp_validate_sscc_for_receive
(
    @external_ref             NVARCHAR(100),
    @staging_bin_code         NVARCHAR(100),
    @scanned_best_before_date DATE          = NULL,
    @scanned_batch_number     NVARCHAR(100) = NULL,
    @user_id                  INT           = NULL,
    @session_id               UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @success                  BIT              = 0,
        @result_code              NVARCHAR(20)     = NULL,
        @inbound_expected_unit_id INT              = NULL,
        @inbound_line_id          INT              = NULL,
        @inbound_ref              NVARCHAR(50)     = NULL,
        @header_status            VARCHAR(3)       = NULL,
        @line_state               VARCHAR(3)       = NULL,
        @sku_code                 NVARCHAR(50)     = NULL,
        @sku_description          NVARCHAR(200)    = NULL,
        @expected_unit_qty        INT              = NULL,
        @line_expected_qty        INT              = NULL,
        @line_received_qty        INT              = NULL,
        @arrival_status_code      VARCHAR(2)       = NULL,
        @batch_number             NVARCHAR(100)    = NULL,
        @best_before_date         DATE             = NULL,
        @received_inventory_id    INT              = NULL,

        @expected_unit_state      VARCHAR(3)       = NULL,

        @claimed_session_id       UNIQUEIDENTIFIER = NULL,
        @claimed_by_user_id       INT              = NULL,
        @claim_expires_at         DATETIME2(3)     = NULL,
        @claim_token              UNIQUEIDENTIFIER = NULL,

        @ttl_seconds              INT              = NULL,
        @now                      DATETIME2(3)     = SYSUTCDATETIME();

    ----------------------------------------------------------------------
    -- TTL seconds
    ----------------------------------------------------------------------
    SELECT @ttl_seconds = TRY_CONVERT(INT, s.setting_value)
    FROM operations.settings s
    WHERE s.setting_name = 'inbound.sscc_claim_ttl_seconds';

    IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
        SET @ttl_seconds = 30;

    ----------------------------------------------------------------------
    -- 0) Cleanup expired claims
    ----------------------------------------------------------------------
    UPDATE inbound.inbound_expected_units
    SET expected_unit_state_code = 'EXP',
        claimed_session_id       = NULL,
        claimed_by_user_id       = NULL,
        claimed_at               = NULL,
        claim_expires_at         = NULL,
        claim_token              = NULL
    WHERE claim_expires_at IS NOT NULL
      AND claim_expires_at < @now
      AND received_inventory_unit_id IS NULL
      AND expected_unit_state_code = 'CLM';

    BEGIN TRY
        ------------------------------------------------------------------
        -- 1) Resolve expected unit
        ------------------------------------------------------------------
        SELECT TOP (1)
            @inbound_line_id          = l.inbound_line_id,
            @inbound_ref              = d.inbound_ref,
            @header_status            = d.inbound_status_code,
            @line_state               = l.line_state_code,
            @sku_code                 = s.sku_code,
            @sku_description          = s.sku_description,
            @expected_unit_qty        = eu.expected_quantity,
            @line_expected_qty        = l.expected_qty,
            @line_received_qty        = ISNULL(l.received_qty, 0),
            @batch_number             = eu.batch_number,
            @best_before_date         = eu.best_before_date,
            @received_inventory_id    = eu.received_inventory_unit_id,
            @expected_unit_state      = eu.expected_unit_state_code,
            @inbound_expected_unit_id = eu.inbound_expected_unit_id,
            @claimed_session_id       = eu.claimed_session_id,
            @claimed_by_user_id       = eu.claimed_by_user_id,
            @claim_expires_at         = eu.claim_expires_at,
            @claim_token              = eu.claim_token,
            @arrival_status_code      = l.arrival_stock_status_code
        FROM inbound.inbound_expected_units eu
        JOIN inbound.inbound_lines l
            ON eu.inbound_line_id = l.inbound_line_id
        JOIN inbound.inbound_deliveries d
            ON l.inbound_id = d.inbound_id
        JOIN inventory.skus s
            ON l.sku_id = s.sku_id
        WHERE eu.expected_external_ref = LTRIM(RTRIM(@external_ref));

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRSSCC01'    AS result_code,
                NULL AS inbound_expected_unit_id, NULL AS inbound_line_id,
                NULL AS inbound_ref,              NULL AS header_status,
                NULL AS line_state,               NULL AS sku_code,
                NULL AS sku_description,          NULL AS expected_unit_qty,
                NULL AS line_expected_qty,        NULL AS line_received_qty,
                NULL AS outstanding_before,       NULL AS outstanding_after,
                NULL AS batch_number,             NULL AS best_before_date,
                NULL AS claimed_session_id,       NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,         NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 2) Already received?
        ------------------------------------------------------------------
        IF @received_inventory_id IS NOT NULL
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRSSCC06'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty)           AS outstanding_before,
                (@line_expected_qty - @line_received_qty)           AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 3) Header lifecycle check
        ------------------------------------------------------------------
        IF @header_status NOT IN ('ACT','RCV')
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRINBL04'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty)           AS outstanding_before,
                (@line_expected_qty - @line_received_qty)           AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4.1) Active claim exists -> reject
        ------------------------------------------------------------------
        IF @claimed_session_id IS NOT NULL
           AND @claim_expires_at IS NOT NULL
           AND @claim_expires_at >= DATEADD(SECOND, -1, @now)
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRSSCC07'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty)                        AS outstanding_before,
                (@line_expected_qty - @line_received_qty - @expected_unit_qty)   AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                @claimed_session_id       AS claimed_session_id,
                @claimed_by_user_id       AS claimed_by_user_id,
                @claim_expires_at         AS claim_expires_at,
                @claim_token              AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4.2) Transition validation (EXP -> CLM)
        ------------------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_expected_unit_state_transitions t
            WHERE t.from_state_code = @expected_unit_state
              AND t.to_state_code   = 'CLM'
        )
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRSSCCSTATE01' AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty)           AS outstanding_before,
                (@line_expected_qty - @line_received_qty)           AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4.3) BBE mismatch — hard block before claim is written
        ------------------------------------------------------------------
        IF @scanned_best_before_date IS NOT NULL
           AND @best_before_date IS NOT NULL
           AND @scanned_best_before_date <> @best_before_date
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRINBL09'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty) AS outstanding_before,
                (@line_expected_qty - @line_received_qty) AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4.4) Batch mismatch — hard block before claim is written
        ------------------------------------------------------------------
        IF @scanned_batch_number IS NOT NULL
           AND @batch_number IS NOT NULL
           AND @scanned_batch_number <> @batch_number
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRINBL10'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty) AS outstanding_before,
                (@line_expected_qty - @line_received_qty) AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 4.5) Create NEW claim
        ------------------------------------------------------------------
        SET @claim_token      = NEWID();
        SET @claim_expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        UPDATE inbound.inbound_expected_units
        SET expected_unit_state_code = 'CLM',
            claimed_session_id       = @session_id,
            claimed_by_user_id       = @user_id,
            claimed_at               = @now,
            claim_expires_at         = @claim_expires_at,
            claim_token              = @claim_token
        WHERE inbound_expected_unit_id = @inbound_expected_unit_id
          AND received_inventory_unit_id IS NULL
          AND (
                claimed_session_id IS NULL
                OR claim_expires_at < @now
              );

        ------------------------------------------------------------------
        -- 4.6) Race protection
        ------------------------------------------------------------------
        IF @@ROWCOUNT = 0
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success,
                N'ERRSSCC07'    AS result_code,
                @inbound_expected_unit_id AS inbound_expected_unit_id,
                @inbound_line_id          AS inbound_line_id,
                @inbound_ref              AS inbound_ref,
                @header_status            AS header_status,
                @line_state               AS line_state,
                @sku_code                 AS sku_code,
                @sku_description          AS sku_description,
                @expected_unit_qty        AS expected_unit_qty,
                @line_expected_qty        AS line_expected_qty,
                @line_received_qty        AS line_received_qty,
                (@line_expected_qty - @line_received_qty)           AS outstanding_before,
                (@line_expected_qty - @line_received_qty)           AS outstanding_after,
                @batch_number             AS batch_number,
                @best_before_date         AS best_before_date,
                NULL AS claimed_session_id, NULL AS claimed_by_user_id,
                NULL AS claim_expires_at,   NULL AS claim_token,
                NULL AS arrival_stock_status_code;
            RETURN;
        END;

        ------------------------------------------------------------------
        -- 5) Valid preview
        ------------------------------------------------------------------
        SET @success     = 1;
        SET @result_code = N'SUCSSCC01';

        SELECT
            @success                                                          AS success,
            @result_code                                                      AS result_code,
            @inbound_expected_unit_id                                         AS inbound_expected_unit_id,
            @inbound_line_id                                                  AS inbound_line_id,
            @inbound_ref                                                      AS inbound_ref,
            @header_status                                                    AS header_status,
            @line_state                                                       AS line_state,
            @sku_code                                                         AS sku_code,
            @sku_description                                                  AS sku_description,
            @expected_unit_qty                                                AS expected_unit_qty,
            @line_expected_qty                                                AS line_expected_qty,
            @line_received_qty                                                AS line_received_qty,
            (@line_expected_qty - @line_received_qty)                         AS outstanding_before,
            (@line_expected_qty - @line_received_qty - @expected_unit_qty)    AS outstanding_after,
            @batch_number                                                     AS batch_number,
            @best_before_date                                                 AS best_before_date,
            @session_id                                                       AS claimed_session_id,
            @user_id                                                          AS claimed_by_user_id,
            @claim_expires_at                                                 AS claim_expires_at,
            @claim_token                                                      AS claim_token,
            @arrival_status_code                                              AS arrival_stock_status_code;

    END TRY
    BEGIN CATCH
        DECLARE @err_no   INT = ERROR_NUMBER();
        DECLARE @err_line INT = ERROR_LINE();
        DECLARE @err_msg  NVARCHAR(2048) = ERROR_MESSAGE();

        SELECT
            CAST(0 AS BIT)  AS success,
            N'ERRSSCC99'    AS result_code,
            NULL AS inbound_expected_unit_id, NULL AS inbound_line_id,
            NULL AS inbound_ref,              NULL AS header_status,
            NULL AS line_state,               NULL AS sku_code,
            NULL AS sku_description,          NULL AS expected_unit_qty,
            NULL AS line_expected_qty,        NULL AS line_received_qty,
            NULL AS outstanding_before,       NULL AS outstanding_after,
            NULL AS batch_number,             NULL AS best_before_date,
            NULL AS claimed_session_id,       NULL AS claimed_by_user_id,
            NULL AS claim_expires_at,         NULL AS claim_token,
            NULL AS arrival_stock_status_code;
    END CATCH
END;
GO

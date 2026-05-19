USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

USE PW_Core_DEV;
GO

/********************************************************************************************
    SP RESULT SET STANDARDISATION PATCH
    Purpose : Add named column aliases to every bare positional SELECT in all SPs.
              All exit paths (error, success, CATCH) return identical column names.
    Date    : 2026-04-15
********************************************************************************************/


/********************************************************************************************
    1. deliveries.usp_activate_inbound
    Contract: success BIT | result_code NVARCHAR(20) | inbound_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE deliveries.usp_activate_inbound
(
    @inbound_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @current_status      VARCHAR(3),
        @existing_mode       VARCHAR(6),
        @sscc_line_count     INT,
        @manual_line_count   INT,
        @mode_code           VARCHAR(6);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @current_status = inbound_status_code,
            @existing_mode  = inbound_mode_code
        FROM deliveries.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        IF @current_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_status_transitions
            WHERE from_status_code = @current_status
              AND to_status_code   = 'ACT'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB05' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code <> 'CNL'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB03' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @sscc_line_count = COUNT(DISTINCT l.inbound_line_id)
        FROM deliveries.inbound_lines l
        JOIN deliveries.inbound_expected_units eu
            ON eu.inbound_line_id = l.inbound_line_id
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL';

        SELECT
            @manual_line_count = COUNT(*)
        FROM deliveries.inbound_lines l
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL'
          AND NOT EXISTS (
                SELECT 1
                FROM deliveries.inbound_expected_units eu
                WHERE eu.inbound_line_id = l.inbound_line_id
          );

        IF @sscc_line_count > 0 AND @manual_line_count > 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBHYB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF @sscc_line_count > 0
            SET @mode_code = 'SSCC';
        ELSE
            SET @mode_code = 'MANUAL';

        IF @existing_mode IS NOT NULL AND @existing_mode <> @mode_code
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBMODE01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
        EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

        UPDATE deliveries.inbound_deliveries
        SET inbound_status_code = 'ACT',
            inbound_mode_code   = @mode_code,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINB01' AS result_code, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code, NULL AS inbound_id;
    END CATCH
END;
GO


/********************************************************************************************
    2. deliveries.usp_receive_inbound_line
    Contract: success BIT | result_code NVARCHAR(20) | inbound_line_id INT | inbound_id INT | is_closed BIT
********************************************************************************************/
CREATE OR ALTER PROCEDURE deliveries.usp_receive_inbound_line
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

        IF NULLIF(LTRIM(RTRIM(@staging_bin_code)), N'') IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL07' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id, CAST(0 AS BIT) AS is_closed;
            ROLLBACK;
            RETURN;
        END

        DECLARE @is_sscc_mode BIT =
            CASE WHEN @inbound_expected_unit_id IS NOT NULL THEN 1 ELSE 0 END;

        DECLARE
            @resolved_line_id      INT = NULL,
            @sku_id                INT = NULL,
            @inbound_id            INT = NULL,
            @expected_qty          INT = NULL,
            @already_received      INT = NULL,
            @line_state            VARCHAR(3),
            @header_status         VARCHAR(3),
            @expected_unit_qty     INT,
            @existing_received_id  INT,
            @now                   DATETIME2(3) = SYSUTCDATETIME(),
            @claim_expires_at      DATETIME2(3),
            @db_claim_token        UNIQUEIDENTIFIER,
            @claimed_session_id    UNIQUEIDENTIFIER,
            @new_received_qty      INT,
            @new_line_state        VARCHAR(3),
            @receipt_id            INT,
            @arrival_status_code   VARCHAR(2);

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
            FROM deliveries.inbound_expected_units eu WITH (UPDLOCK, HOLDLOCK)
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
        FROM deliveries.inbound_lines l WITH (UPDLOCK, HOLDLOCK)
        WHERE l.inbound_line_id = @resolved_line_id;

        IF (@already_received + @received_qty) > @expected_qty
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL02' AS result_code,
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
        WHERE bin_code = @staging_bin_code
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
            UPDATE deliveries.inbound_expected_units
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

        UPDATE deliveries.inbound_lines
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

        INSERT INTO deliveries.inbound_receipts
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
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code NOT IN ('RCV','CNL')
        )
        BEGIN
            UPDATE deliveries.inbound_deliveries
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


/********************************************************************************************
    3. deliveries.usp_reverse_inbound_receipt
    Contract: success BIT | result_code NVARCHAR(20) | inbound_id INT | inbound_line_id INT
            | receipt_id INT | reversal_receipt_id INT | inventory_unit_id INT | header_reopened BIT
********************************************************************************************/
CREATE OR ALTER PROCEDURE deliveries.usp_reverse_inbound_receipt
(
    @receipt_id      INT,
    @reason_code     NVARCHAR(50) = NULL,
    @reason_text     NVARCHAR(400) = NULL,
    @user_id         INT = NULL,
    @session_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inbound_id               INT,
        @inbound_line_id          INT,
        @inbound_expected_unit_id INT,
        @inventory_unit_id        INT,
        @received_qty             INT,
        @reversal_receipt_id      INT,
        @header_reopened          BIT = 0,
        @old_header_status        VARCHAR(3),
        @new_header_status        VARCHAR(3);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @inbound_line_id          = r.inbound_line_id,
            @inbound_expected_unit_id = r.inbound_expected_unit_id,
            @inventory_unit_id        = r.inventory_unit_id,
            @received_qty             = r.received_qty
        FROM deliveries.inbound_receipts r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.receipt_id = @receipt_id
          AND r.is_reversal = 0;

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV01' AS result_code,
                   NULL AS inbound_id, NULL AS inbound_line_id,
                   NULL AS receipt_id, NULL AS reversal_receipt_id,
                   NULL AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_receipts
            WHERE receipt_id = @receipt_id
              AND reversed_receipt_id IS NOT NULL
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV02' AS result_code,
                   NULL AS inbound_id, NULL AS inbound_line_id,
                   @receipt_id AS receipt_id, NULL AS reversal_receipt_id,
                   NULL AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        SELECT @inbound_id = inbound_id
        FROM deliveries.inbound_lines
        WHERE inbound_line_id = @inbound_line_id;

        SELECT @old_header_status = inbound_status_code
        FROM deliveries.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        /* --------------------------------------------------------
           3) Capture movement data BEFORE touching anything
        -------------------------------------------------------- */
        DECLARE
            @sku_id               INT,
            @from_bin_id          INT,
            @unit_status_code     VARCHAR(2),
            @original_movement_id INT;

        SELECT
            @sku_id           = iu.sku_id,
            @unit_status_code = iu.stock_status_code,
            @from_bin_id      = ip.bin_id
        FROM inventory.inventory_units iu
        LEFT JOIN inventory.inventory_placements ip
            ON ip.inventory_unit_id = iu.inventory_unit_id
        WHERE iu.inventory_unit_id = @inventory_unit_id;

        SELECT @original_movement_id = movement_id
        FROM inventory.inventory_movements
        WHERE inventory_unit_id = @inventory_unit_id
          AND movement_type     = 'INBOUND'
          AND is_reversal       = 0;

        /* --------------------------------------------------------
           3a) Reverse inventory unit
        -------------------------------------------------------- */
        UPDATE inventory.inventory_units
        SET stock_state_code = 'REV',
            updated_at       = SYSUTCDATETIME(),
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV03' AS result_code,
                   @inbound_id AS inbound_id, @inbound_line_id AS inbound_line_id,
                   @receipt_id AS receipt_id, NULL AS reversal_receipt_id,
                   @inventory_unit_id AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        /* --------------------------------------------------------
           3b) Remove placement
        -------------------------------------------------------- */
        DELETE FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        /* --------------------------------------------------------
           3c) Log reversal movement
        -------------------------------------------------------- */
        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id,
            is_reversal, reversed_movement_id
        )
        VALUES
        (
            @inventory_unit_id, @sku_id, @received_qty,
            @from_bin_id, NULL,
            'RCD', 'REV',
            @unit_status_code, @unit_status_code,
            'REVERSAL', 'INBOUND', @receipt_id,
            SYSUTCDATETIME(), @user_id, @session_id,
            1, @original_movement_id
        );

        /* --------------------------------------------------------
           4) Restore expected unit (SSCC mode)
        -------------------------------------------------------- */
        IF @inbound_expected_unit_id IS NOT NULL
        BEGIN
            UPDATE deliveries.inbound_expected_units
            SET received_inventory_unit_id = NULL,
                expected_unit_state_code   = 'EXP',
                claimed_session_id         = NULL,
                claimed_by_user_id         = NULL,
                claimed_at                 = NULL,
                claim_expires_at           = NULL,
                claim_token                = NULL,
                updated_at                 = SYSUTCDATETIME(),
                updated_by                 = @user_id
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id;
        END

        /* --------------------------------------------------------
           5) Insert reversal receipt
        -------------------------------------------------------- */
        INSERT INTO deliveries.inbound_receipts
        (
            inbound_line_id, inbound_expected_unit_id, inventory_unit_id,
            received_qty, received_by_user_id, session_id,
            received_at, is_reversal, reversed_receipt_id
        )
        VALUES
        (
            @inbound_line_id, @inbound_expected_unit_id, @inventory_unit_id,
            @received_qty, @user_id, @session_id,
            SYSUTCDATETIME(), 1, @receipt_id
        );

        SET @reversal_receipt_id = SCOPE_IDENTITY();

        /* --------------------------------------------------------
           6) Mark original receipt reversed
        -------------------------------------------------------- */
        UPDATE deliveries.inbound_receipts
        SET reversed_receipt_id = @reversal_receipt_id
        WHERE receipt_id = @receipt_id;

        /* --------------------------------------------------------
           7) Recompute line
        -------------------------------------------------------- */
        UPDATE l
        SET
            received_qty =
            (
                SELECT ISNULL(SUM(
                    CASE
                        WHEN r.is_reversal = 0 THEN r.received_qty
                        ELSE -r.received_qty
                    END), 0)
                FROM deliveries.inbound_receipts r
                WHERE r.inbound_line_id = l.inbound_line_id
            ),
            line_state_code =
            CASE
                WHEN (
                    SELECT ISNULL(SUM(
                        CASE
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM deliveries.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) = 0 THEN 'EXP'

                WHEN (
                    SELECT ISNULL(SUM(
                        CASE
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM deliveries.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) < l.expected_qty THEN 'PRC'

                ELSE 'RCV'
            END,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        FROM deliveries.inbound_lines l
        WHERE l.inbound_line_id = @inbound_line_id;

        /* --------------------------------------------------------
           8) Recompute header
        -------------------------------------------------------- */
        SET @new_header_status = 'ACT';

        IF EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code IN ('PRC','RCV')
        )
            SET @new_header_status = 'RCV';

        IF NOT EXISTS
        (
            SELECT 1
            FROM deliveries.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code NOT IN ('RCV','CNL')
        )
            SET @new_header_status = 'CLS';

        UPDATE deliveries.inbound_deliveries
        SET inbound_status_code = @new_header_status,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        IF @old_header_status = 'CLS' AND @new_header_status <> 'CLS'
            SET @header_reopened = 1;

        COMMIT;

        SELECT
            CAST(1 AS BIT)        AS success,
            N'SUCINBREV01'        AS result_code,
            @inbound_id           AS inbound_id,
            @inbound_line_id      AS inbound_line_id,
            @receipt_id           AS receipt_id,
            @reversal_receipt_id  AS reversal_receipt_id,
            @inventory_unit_id    AS inventory_unit_id,
            @header_reopened      AS header_reopened;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @err_no  INT = ERROR_NUMBER();
        DECLARE @err_msg NVARCHAR(2048) = ERROR_MESSAGE();

        SELECT
            CAST(0 AS BIT)  AS success,
            N'ERRINBREV99'  AS result_code,
            NULL            AS inbound_id,
            NULL            AS inbound_line_id,
            @receipt_id     AS receipt_id,
            NULL            AS reversal_receipt_id,
            NULL            AS inventory_unit_id,
            CAST(0 AS BIT)  AS header_reopened;
    END CATCH
END;
GO


/********************************************************************************************
    4. warehouse.usp_putaway_create_task_for_unit
    Contract: success BIT | result_code NVARCHAR(20) | task_id INT | destination_bin_code NVARCHAR(100)
            | inventory_unit_id INT | source_bin_code NVARCHAR(100) | stock_state_code VARCHAR(3)
            | stock_status_code VARCHAR(2) | expires_at DATETIME2(3) | zone_code NVARCHAR(50)
********************************************************************************************/
CREATE OR ALTER PROCEDURE warehouse.usp_putaway_create_task_for_unit
(
    @inventory_unit_id INT,
    @user_id           INT,
    @session_id        UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @task_id            INT,
        @dest_bin_id        INT,
        @dest_bin_code      NVARCHAR(100),
        @source_bin_id      INT,
        @ttl_seconds        INT,
        @expires_at         DATETIME2(3),
        @sku_id             INT,
        @state_code         VARCHAR(3),
        @stock_status_code  VARCHAR(2),
        @source_bin_code    NVARCHAR(100),
        @zone_code          NVARCHAR(50);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @sku_id            = sku_id,
            @state_code        = stock_state_code,
            @stock_status_code = stock_status_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success, N'ERRTASK01' AS result_code,
                NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                NULL AS expires_at, NULL AS zone_code;
            ROLLBACK;
            RETURN;
        END

        IF @state_code <> 'RCD'
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success, N'ERRTASK02' AS result_code,
                NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                NULL AS expires_at, NULL AS zone_code;
            ROLLBACK;
            RETURN;
        END

        SELECT @source_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success, N'ERRTASK03' AS result_code,
                NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                NULL AS expires_at, NULL AS zone_code;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @source_bin_code = b.bin_code,
            @zone_code       = z.zone_code
        FROM locations.bins b
        LEFT JOIN locations.zones z ON z.zone_id = b.zone_id
        WHERE b.bin_id = @source_bin_id;

        -- Idempotency: return existing open task
        SELECT TOP (1)
            @task_id     = task_id,
            @dest_bin_id = destination_bin_id,
            @expires_at  = expires_at
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_state_code IN ('OPN','CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            SELECT @dest_bin_code = bin_code
            FROM locations.bins
            WHERE bin_id = @dest_bin_id;

            COMMIT;

            SELECT
                CAST(1 AS BIT)      AS success,
                N'SUCTASK01'        AS result_code,
                @task_id            AS task_id,
                @dest_bin_code      AS destination_bin_code,
                @inventory_unit_id  AS inventory_unit_id,
                @source_bin_code    AS source_bin_code,
                @state_code         AS stock_state_code,
                @stock_status_code  AS stock_status_code,
                @expires_at         AS expires_at,
                @zone_code          AS zone_code;
            RETURN;
        END

        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id  = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT
                CAST(0 AS BIT)  AS success, N'ERRTASK04' AS result_code,
                NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
                NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
                NULL AS expires_at, NULL AS zone_code;
            ROLLBACK;
            RETURN;
        END

        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code, inventory_unit_id,
            source_bin_id, destination_bin_id,
            task_state_code, expires_at, created_by
        )
        VALUES
        (
            'PUTAWAY', @inventory_unit_id,
            @source_bin_id, @dest_bin_id,
            'OPN', @expires_at, @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        INSERT INTO locations.bin_reservations
        (bin_id, reservation_type, reserved_by, expires_at)
        VALUES
        (@dest_bin_id, 'PUTAWAY', @user_id, @expires_at);

        COMMIT;

        SELECT
            CAST(1 AS BIT)      AS success,
            N'SUCTASK01'        AS result_code,
            @task_id            AS task_id,
            @dest_bin_code      AS destination_bin_code,
            @inventory_unit_id  AS inventory_unit_id,
            @source_bin_code    AS source_bin_code,
            @state_code         AS stock_state_code,
            @stock_status_code  AS stock_status_code,
            @expires_at         AS expires_at,
            @zone_code          AS zone_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)  AS success, N'ERRTASK99' AS result_code,
            NULL AS task_id, NULL AS destination_bin_code, NULL AS inventory_unit_id,
            NULL AS source_bin_code, NULL AS stock_state_code, NULL AS stock_status_code,
            NULL AS expires_at, NULL AS zone_code;
    END CATCH
END;
GO


/********************************************************************************************
    5. warehouse.usp_putaway_confirm_task
    Contract: success BIT | result_code NVARCHAR(20)
********************************************************************************************/
CREATE OR ALTER PROCEDURE warehouse.usp_putaway_confirm_task
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @user_id          INT,
    @session_id       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @inventory_unit_id   INT,
        @source_bin_id       INT,
        @dest_bin_id         INT,
        @dest_bin_code       NVARCHAR(100),
        @sku_id              INT,
        @quantity            INT,
        @task_state          VARCHAR(3),
        @scanned_bin_id      INT,
        @bin_capacity        INT,
        @bin_active          BIT,
        @current_placements  INT,
        @active_reservations INT,
        @current_status_code VARCHAR(2),
        @now                 DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @inventory_unit_id = inventory_unit_id,
            @source_bin_id     = source_bin_id,
            @dest_bin_id       = destination_bin_id,
            @task_state        = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id = @task_id;

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code;
            ROLLBACK;
            RETURN;
        END

        IF @task_state NOT IN ('OPN', 'CLM')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code;
            ROLLBACK;
            RETURN;
        END

        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        IF LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK08' AS result_code;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @scanned_bin_id = bin_id,
            @bin_capacity   = capacity,
            @bin_active     = is_active
        FROM locations.bins
        WHERE bin_id = @dest_bin_id;

        IF @bin_active = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code;
            ROLLBACK;
            RETURN;
        END

        SELECT @current_placements = COUNT(*)
        FROM inventory.inventory_placements
        WHERE bin_id = @dest_bin_id;

        SELECT @active_reservations = COUNT(*)
        FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id
          AND expires_at > @now;

        IF (@current_placements + @active_reservations - 1) >= @bin_capacity
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @sku_id              = sku_id,
            @quantity            = quantity,
            @current_status_code = stock_status_code
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK)
        WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_placements
        SET bin_id    = @dest_bin_id,
            placed_at = @now,
            placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW',
            updated_at       = @now,
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id
          AND stock_state_code = 'RCD';

        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        DELETE FROM locations.bin_reservations
        WHERE bin_id           = @dest_bin_id
          AND reservation_type = 'PUTAWAY'
          AND expires_at      >= @now;

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
            @inventory_unit_id, @sku_id, @quantity,
            @source_bin_id, @dest_bin_id,
            'RCD', 'PTW',
            @current_status_code, @current_status_code,
            'PUTAWAY', 'TASK', @task_id,
            @now, @user_id, @session_id
        );

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO


/********************************************************************************************
    6. warehouse.usp_create_putaway_task
    Contract: success BIT | result_code NVARCHAR(20) | task_id INT | destination_bin_id INT
********************************************************************************************/
CREATE OR ALTER PROCEDURE warehouse.usp_create_putaway_task
(
    @inventory_unit_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @sku_id       INT,
        @stock_state  VARCHAR(3),
        @current_bin_id INT,
        @dest_bin_id  INT,
        @ttl_seconds  INT,
        @expires_at   DATETIME2(3),
        @task_id      INT;

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @sku_id      = sku_id,
            @stock_state = stock_state_code
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_id;
            ROLLBACK;
            RETURN;
        END

        IF @stock_state <> 'RCD'
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK02' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_id;
            ROLLBACK;
            RETURN;
        END

        SELECT @current_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @current_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK03' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_id;
            ROLLBACK;
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM warehouse.warehouse_tasks
            WHERE inventory_unit_id = @inventory_unit_id
              AND task_state_code IN ('OPN','CLM')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK05' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_id;
            ROLLBACK;
            RETURN;
        END

        EXEC locations.usp_suggest_putaway_bin
            @inventory_unit_id = @inventory_unit_id,
            @suggested_bin_id  = @dest_bin_id OUTPUT;

        IF @dest_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRTASK04' AS result_code,
                   NULL AS task_id, NULL AS destination_bin_id;
            ROLLBACK;
            RETURN;
        END

        SELECT @ttl_seconds = TRY_CONVERT(INT, setting_value)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, SYSUTCDATETIME());

        INSERT INTO warehouse.warehouse_tasks
        (
            task_type_code, inventory_unit_id,
            source_bin_id, destination_bin_id,
            task_state_code, expires_at, created_by
        )
        VALUES
        (
            'PUTAWAY', @inventory_unit_id,
            @current_bin_id, @dest_bin_id,
            'OPN', @expires_at, @user_id
        );

        SET @task_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCTASK01' AS result_code,
               @task_id AS task_id, @dest_bin_id AS destination_bin_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code,
               NULL AS task_id, NULL AS destination_bin_id;
    END CATCH
END;
GO

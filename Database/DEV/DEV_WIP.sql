USE PW_Core_DEV;
GO

-- ============================================================
-- Bin code strict case enforcement
-- 2026-05-15
--
-- Removing UPPER() normalisation from all bin code lookups.
-- Bin codes are stored uppercase in the DB and must be entered
-- uppercase by the operator. Lowercase input returns ERRBIN01
-- (bin not found) — same as a non-existent bin.
--
-- This enforces physical scanning discipline:
--   - Scanning a bin barcode always produces the correct uppercase code
--   - Typing requires the operator to type in uppercase
--   - No silent correction of casing — wrong case = bin not found
--
-- LTRIM(RTRIM()) is retained for scanner whitespace trimming.
-- UPPER() is removed from all bin code comparisons and lookups.
--
-- Affected SPs:
--   inbound.usp_receive_inbound_line
--   inbound.usp_validate_sscc_for_receive (no change needed — already clean)
--   warehouse.usp_putaway_confirm_task
--   warehouse.usp_bin_to_bin_move_create
--   warehouse.usp_bin_to_bin_move_confirm
--   outbound.usp_pick_create
--   outbound.usp_pick_confirm
-- ============================================================

-- ── inbound.usp_receive_inbound_line ─────────────────────────────────────────

CREATE OR ALTER PROCEDURE inbound.usp_receive_inbound_line
(
    @inbound_line_id   INT,
    @external_ref      NVARCHAR(100),
    @staging_bin_code  NVARCHAR(100),
    @received_qty      INT              = NULL,
    @batch_number      NVARCHAR(100)    = NULL,
    @best_before_date  DATE             = NULL,
    @claim_token       UNIQUEIDENTIFIER = NULL,
    @arrival_status_code VARCHAR(2)     = NULL,
    @user_id           INT              = NULL,
    @session_id        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Trim whitespace only — no case normalisation (bin codes are canonical uppercase)
        SET @staging_bin_code = LTRIM(RTRIM(@staging_bin_code));
        SET @external_ref     = UPPER(LTRIM(RTRIM(@external_ref)));   -- SSCCs still normalised
        SET @batch_number     = UPPER(LTRIM(RTRIM(@batch_number)));   -- batch still normalised

        DECLARE
            @bin_id             INT,
            @inbound_id         INT,
            @sku_id             INT,
            @inbound_status     VARCHAR(3),
            @line_state         VARCHAR(3),
            @line_expected_qty  INT,
            @line_received_qty  INT,
            @stock_status_code  VARCHAR(2),
            @inventory_unit_id  INT,
            @now                DATETIME2(3) = SYSUTCDATETIME();

        -- Resolve bin — exact match, case-sensitive
        SELECT @bin_id = bin_id
        FROM locations.bins
        WHERE bin_code        = @staging_bin_code
          AND is_active       = 1;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Validate inbound line
        SELECT
            @inbound_id        = l.inbound_id,
            @sku_id            = l.sku_id,
            @line_state        = l.line_state_code,
            @line_expected_qty = l.expected_qty,
            @line_received_qty = l.received_qty
        FROM inbound.inbound_lines l
        WHERE l.inbound_line_id = @inbound_line_id;

        IF @inbound_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL01' AS result_code;
            ROLLBACK; RETURN;
        END

        SELECT @inbound_status = inbound_status_code
        FROM inbound.inbound_deliveries
        WHERE inbound_id = @inbound_id;

        IF @inbound_status NOT IN ('ACT', 'RCV')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL02' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @line_state NOT IN ('EXP', 'PAR', 'RCV')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL03' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Resolve quantity
        IF @received_qty IS NULL OR @received_qty <= 0
            SET @received_qty = @line_expected_qty - @line_received_qty;

        IF @received_qty <= 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL04' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Resolve arrival status
        IF @arrival_status_code IS NULL
            SET @arrival_status_code = 'AV';

        -- Check SSCC not already in use
        IF EXISTS (
            SELECT 1 FROM inventory.inventory_units
            WHERE external_ref = @external_ref
              AND stock_state_code NOT IN ('REV', 'SHP')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBL05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Create inventory unit
        INSERT INTO inventory.inventory_units
            (sku_id, external_ref, quantity, stock_state_code, stock_status_code,
             batch_number, best_before_date, created_at, created_by)
        VALUES
            (@sku_id, @external_ref, @received_qty, 'RCD', @arrival_status_code,
             @batch_number, @best_before_date, @now, @user_id);

        SET @inventory_unit_id = SCOPE_IDENTITY();

        -- Place inventory unit in bin
        INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id, placed_at, placed_by)
        VALUES (@inventory_unit_id, @bin_id, @now, @user_id);

        -- Record inbound receipt
        DECLARE @receipt_id INT;
        INSERT INTO inbound.inbound_receipts
            (inbound_line_id, inventory_unit_id, received_qty, received_at, received_by_user_id,
             is_reversal, reversed_receipt_id)
        VALUES
            (@inbound_line_id, @inventory_unit_id, @received_qty, @now, @user_id, 0, NULL);

        SET @receipt_id = SCOPE_IDENTITY();

        -- Link expected unit if claim token provided
        IF @claim_token IS NOT NULL
        BEGIN
            UPDATE inbound.inbound_expected_units
            SET received_inventory_unit_id = @inventory_unit_id,
                expected_unit_state_code   = 'RCV',
                updated_at                 = @now
            WHERE claim_token = @claim_token;
        END

        -- Record movement
        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty,
             from_bin_id, to_bin_id,
             from_state_code, to_state_code,
             from_status_code, to_status_code,
             movement_type, reference_type, reference_id,
             moved_at, moved_by_user_id, session_id)
        VALUES
            (@inventory_unit_id, @sku_id, @received_qty,
             NULL, @bin_id,
             NULL, 'RCD',
             NULL, @arrival_status_code,
             'INBOUND', 'RECEIPT', @receipt_id,
             @now, @user_id, @session_id);

        -- Update line received qty and state
        UPDATE inbound.inbound_lines
        SET received_qty    = received_qty + @received_qty,
            line_state_code =
                CASE
                    WHEN received_qty + @received_qty >= expected_qty THEN 'RCV'
                    ELSE 'PAR'
                END,
            updated_at = @now
        WHERE inbound_line_id = @inbound_line_id;

        -- Update inbound header status
        UPDATE inbound.inbound_deliveries
        SET inbound_status_code = 'RCV',
            updated_at          = @now
        WHERE inbound_id = @inbound_id
          AND inbound_status_code = 'ACT';

        -- Auto-close if all lines fully received
        IF NOT EXISTS (
            SELECT 1 FROM inbound.inbound_lines
            WHERE inbound_id     = @inbound_id
              AND line_state_code NOT IN ('RCV', 'CNL')
        )
        BEGIN
            UPDATE inbound.inbound_deliveries
            SET inbound_status_code = 'CLS',
                updated_at          = @now
            WHERE inbound_id = @inbound_id;

            SELECT CAST(1 AS BIT) AS success, N'SUCINBCLS01' AS result_code,
                   @inventory_unit_id AS inventory_unit_id,
                   @receipt_id        AS receipt_id,
                   @inbound_id        AS inbound_id;
        END
        ELSE
        BEGIN
            SELECT CAST(1 AS BIT) AS success, N'SUCINBL01' AS result_code,
                   @inventory_unit_id AS inventory_unit_id,
                   @receipt_id        AS receipt_id,
                   @inbound_id        AS inbound_id;
        END

        COMMIT;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINBL99' AS result_code,
               NULL AS inventory_unit_id, NULL AS receipt_id, NULL AS inbound_id;
    END CATCH
END;
GO
PRINT 'inbound.usp_receive_inbound_line: UPPER() removed from bin lookup.';
GO

-- ── warehouse.usp_putaway_confirm_task ────────────────────────────────────────

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

    -- Trim whitespace only — no case normalisation
    SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code));

    DECLARE
        @inventory_unit_id   INT, @source_bin_id INT, @dest_bin_id INT,
        @dest_bin_code       NVARCHAR(100), @sku_id INT, @quantity INT,
        @task_state          VARCHAR(3), @scanned_bin_id INT,
        @bin_capacity        INT, @bin_active BIT,
        @current_placements  INT, @active_reservations INT,
        @current_status_code VARCHAR(2), @now DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT @inventory_unit_id = inventory_unit_id, @source_bin_id = source_bin_id,
               @dest_bin_id = destination_bin_id, @task_state = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK) WHERE task_id = @task_id;

        IF @inventory_unit_id IS NULL
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK01' AS result_code; ROLLBACK; RETURN; END

        IF @task_state NOT IN ('OPN','CLM')
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK07' AS result_code; ROLLBACK; RETURN; END

        -- Exact match — no UPPER()
        SELECT @dest_bin_code = bin_code FROM locations.bins WHERE bin_id = @dest_bin_id;

        IF LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK08' AS result_code; ROLLBACK; RETURN; END

        SELECT @scanned_bin_id = bin_id, @bin_capacity = capacity, @bin_active = is_active
        FROM locations.bins WHERE bin_id = @dest_bin_id;

        IF @bin_active = 0
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code; ROLLBACK; RETURN; END

        SELECT @current_placements = COUNT(*) FROM inventory.inventory_placements WHERE bin_id = @dest_bin_id;
        SELECT @active_reservations = COUNT(*) FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id AND expires_at > @now;

        IF (@current_placements + @active_reservations - 1) >= @bin_capacity
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRTASK09' AS result_code; ROLLBACK; RETURN; END

        SELECT @sku_id = sku_id, @quantity = quantity, @current_status_code = stock_status_code
        FROM inventory.inventory_units WITH (UPDLOCK, HOLDLOCK) WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_placements SET bin_id = @dest_bin_id, placed_at = @now, placed_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_units
        SET stock_state_code = 'PTW', updated_at = @now, updated_by = @user_id
        WHERE inventory_unit_id = @inventory_unit_id
          AND stock_state_code IN ('RCD', 'PTW');

        UPDATE warehouse.warehouse_tasks
        SET task_state_code = 'CNF', completed_at = @now, completed_by_user_id = @user_id,
            updated_at = @now, updated_by = @user_id
        WHERE task_id = @task_id;

        DELETE FROM locations.bin_reservations
        WHERE bin_id = @dest_bin_id AND reservation_type = 'PUTAWAY' AND expires_at >= @now;

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty, from_bin_id, to_bin_id,
             from_state_code, to_state_code, from_status_code, to_status_code,
             movement_type, reference_type, reference_id, moved_at, moved_by_user_id, session_id)
        VALUES
            (@inventory_unit_id, @sku_id, @quantity, @source_bin_id, @dest_bin_id,
             'PTW', 'PTW', @current_status_code, @current_status_code,
             'PUTAWAY', 'TASK', @task_id, @now, @user_id, @session_id);

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCTASK02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRTASK99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_putaway_confirm_task: UPPER() removed from bin comparison.';
GO

-- ── warehouse.usp_bin_to_bin_move_create ─────────────────────────────────────

CREATE OR ALTER PROCEDURE warehouse.usp_bin_to_bin_move_create
(
    @external_ref         NVARCHAR(100),
    @destination_bin_code NVARCHAR(100)    = NULL,
    @user_id              INT              = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        SET @external_ref = UPPER(LTRIM(RTRIM(@external_ref)));  -- SSCCs normalised

        -- Bin code: trim only, no case normalisation
        IF @destination_bin_code IS NOT NULL
            SET @destination_bin_code = LTRIM(RTRIM(@destination_bin_code));

        DECLARE
            @inventory_unit_id  INT,
            @stock_state_code   VARCHAR(3),
            @source_bin_id      INT,
            @source_bin_code    NVARCHAR(100),
            @destination_bin_id INT,
            @task_id            INT,
            @ttl_seconds        INT,
            @expires_at         DATETIME2(3),
            @now                DATETIME2(3) = SYSUTCDATETIME();

        SELECT
            @inventory_unit_id = inventory_unit_id,
            @stock_state_code  = stock_state_code
        FROM inventory.inventory_units
        WHERE external_ref = @external_ref
          AND stock_state_code NOT IN ('REV', 'SHP');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE01' AS result_code,
                   NULL AS task_id, NULL AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        IF @stock_state_code NOT IN ('PUT', 'PTW', 'RCD')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE02' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        SELECT @source_bin_id = bin_id
        FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @source_bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE03' AS result_code,
                   NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                   NULL AS source_bin_code, NULL AS destination_bin_code;
            ROLLBACK; RETURN;
        END

        SELECT @source_bin_code = bin_code FROM locations.bins WHERE bin_id = @source_bin_id;

        -- Exact match lookup — no UPPER()
        IF @destination_bin_code IS NOT NULL
        BEGIN
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @destination_bin_code AND is_active = 1;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code,
                       NULL AS task_id, @inventory_unit_id AS inventory_unit_id,
                       @source_bin_code AS source_bin_code, @destination_bin_code AS destination_bin_code;
                ROLLBACK; RETURN;
            END
        END

        -- Reuse existing open task
        SELECT TOP 1
            @task_id           = task_id,
            @destination_bin_id = destination_bin_id,
            @expires_at        = expires_at
        FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @inventory_unit_id
          AND task_type_code    = 'MOVE'
          AND task_state_code  IN ('OPN', 'CLM')
        ORDER BY created_at DESC;

        IF @task_id IS NOT NULL
        BEGIN
            DECLARE @existing_dest_code NVARCHAR(100);
            SELECT @existing_dest_code = bin_code FROM locations.bins WHERE bin_id = @destination_bin_id;
            COMMIT;
            SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
                   @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
                   @source_bin_code AS source_bin_code, @existing_dest_code AS destination_bin_code;
            RETURN;
        END

        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.putaway_task_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 300;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        INSERT INTO warehouse.warehouse_tasks
            (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
             task_state_code, expires_at, created_by)
        VALUES
            ('MOVE', @inventory_unit_id, @source_bin_id, @destination_bin_id,
             'OPN', @expires_at, @user_id);

        SET @task_id = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE01' AS result_code,
               @task_id AS task_id, @inventory_unit_id AS inventory_unit_id,
               @source_bin_code AS source_bin_code,
               @destination_bin_code AS destination_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRMOVE99' AS result_code,
               NULL AS task_id, NULL AS inventory_unit_id,
               NULL AS source_bin_code, NULL AS destination_bin_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_create: UPPER() removed from bin lookup.';
GO

-- ── warehouse.usp_bin_to_bin_move_confirm ────────────────────────────────────

CREATE OR ALTER PROCEDURE warehouse.usp_bin_to_bin_move_confirm
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @user_id          INT              = NULL,
    @session_id       UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Trim only — no case normalisation
        SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code));

        DECLARE
            @inventory_unit_id  INT,
            @source_bin_id      INT,
            @destination_bin_id INT,
            @dest_bin_code      NVARCHAR(100),
            @task_state         VARCHAR(3),
            @sku_id             INT,
            @now                DATETIME2(3) = SYSUTCDATETIME();

        SELECT
            @inventory_unit_id  = inventory_unit_id,
            @source_bin_id      = source_bin_id,
            @destination_bin_id = destination_bin_id,
            @task_state         = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id       = @task_id
          AND task_type_code = 'MOVE'
          AND task_state_code IN ('OPN', 'CLM');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Exact match comparison — no UPPER()
        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @destination_bin_id;

        IF @dest_bin_code IS NOT NULL
           AND LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE06' AS result_code;
            ROLLBACK; RETURN;
        END

        IF @destination_bin_id IS NULL
        BEGIN
            -- Exact match lookup — no UPPER()
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @scanned_bin_code AND is_active = 1;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code;
                ROLLBACK; RETURN;
            END

            SET @dest_bin_code = @scanned_bin_code;
        END

        SELECT @sku_id = sku_id FROM inventory.inventory_units WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE inventory.inventory_placements
        SET bin_id = @destination_bin_id
        WHERE inventory_unit_id = @inventory_unit_id;

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty,
             from_bin_id, to_bin_id,
             from_state_code, to_state_code,
             from_status_code, to_status_code,
             movement_type, reference_type, reference_id,
             moved_at, moved_by_user_id, session_id)
        SELECT
            @inventory_unit_id, @sku_id, quantity,
            @source_bin_id, @destination_bin_id,
            stock_state_code, stock_state_code,
            stock_status_code, stock_status_code,
            'MOVE', 'TASK', @task_id,
            @now, @user_id, @session_id
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRMOVE99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_confirm: UPPER() removed from bin comparison.';
GO

PRINT '------------------------------------------------------------';
PRINT 'Bin code strict case enforcement complete.';
PRINT 'All UPPER() removed from bin lookups. LTRIM/RTRIM retained.';
PRINT '';
PRINT 'NOTE: outbound.usp_pick_create and usp_pick_confirm still have';
PRINT 'UPPER() on destination bin — fix in next WIP cycle when pick';
PRINT 'flow is being tested end-to-end.';
PRINT '------------------------------------------------------------';
GO

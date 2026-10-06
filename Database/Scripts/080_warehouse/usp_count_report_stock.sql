USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_report_stock
   ------------------------------------------------------------
   The operator found a pallet in a bin the system believed was
   empty and scanned it. One call per pallet, so a bin holding
   several records each.

   What happens, in order:
     - SSCC not in the system          -> UNKNOWN_UNIT, recorded only.
                                          Nothing is created: stock
                                          into the system is a receipt
                                          or an adjustment, not a count.
     - SSCC the system shows as SHIPPED
       or REVERSED                     -> NOT_CORRECTED, reason ERRCNT06 /
                                          ERRCNT07. The pallet is KNOWN -
                                          it was missed off a delivery, or
                                          a receipt was reversed over it -
                                          which is exactly what a
                                          supervisor needs to see. A count
                                          never brings it back into stock.
     - system already has it here      -> nothing to do (SUCCNT05)
     - unit not free to be moved, or
       this bin cannot take it         -> NOT_CORRECTED, recorded with
                                          the rule's code, for review
     - otherwise                       -> RECORD_CORRECTED: the unit's
                                          recorded location is moved to
                                          this bin via
                                          usp_apply_relocation, written
                                          to the ledger as ADJUSTMENT /
                                          reference COUNT.

   The rules are the same two shared functions the bin-to-bin move
   uses (fn_unit_move_block_code / fn_bin_receive_block_code), so a
   count correction can never do something a move would refuse.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | finding_code VARCHAR(20)
     | count_id INT | inventory_unit_id INT | sku_code NVARCHAR(50)
     | previous_bin_code NVARCHAR(100) | pending_bins INT
     | reason_code NVARCHAR(20)
     | shipment_ref NVARCHAR(50) | vehicle_ref NVARCHAR(50)
     | shipped_at DATETIME2(3) | order_ref NVARCHAR(50)
     | customer_name NVARCHAR(200)
   (the last five say where a shipped / picked pallet went; NULL otherwise)
   Codes: SUCCNT03 corrected | WARNCNT02 unknown pallet
          WARNCNT03 not corrected | SUCCNT05 already recorded here
          ERRCNT03 / 04 / 05 / 99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_report_stock
(
    @count_id    INT,
    @bin_code    NVARCHAR(100),
    @scanned_ref NVARCHAR(100),
    @user_id     INT              = NULL,
    @session_id  UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @success       BIT = 0,
        @result_code   NVARCHAR(20),
        @finding_code  VARCHAR(20),
        @reason_code   NVARCHAR(20),
        @count_status  VARCHAR(10),
        @line_id       INT,
        @line_status   VARCHAR(16),
        @bin_id        INT,
        @unit_id       INT,
        @unit_state    VARCHAR(3),
        @sku_code      NVARCHAR(50),
        @prev_bin_id   INT,
        @prev_bin_code NVARCHAR(100),
        @block_code    NVARCHAR(20),
        @finding_id    INT,
        @movement_id   INT,
        @shipment_ref  NVARCHAR(50),
        @vehicle_ref   NVARCHAR(50),
        @shipped_at    DATETIME2(3),
        @order_ref     NVARCHAR(50),
        @customer_name NVARCHAR(200),
        @pending       INT,
        @now           DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        -- Bin codes match case-insensitively: two bins cannot differ only by
        -- case, so this is unambiguous, and a typed "bulk01" is not a different bin
        SET @bin_code    = LTRIM(RTRIM(@bin_code));
        SET @scanned_ref = LTRIM(RTRIM(@scanned_ref));

        ------------------------------------------------------------
        -- Count open, bin in it, bin not already counted empty
        ------------------------------------------------------------
        SELECT @count_status = status_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_status IS NULL OR @count_status <> 'OPEN'
        BEGIN
            SET @result_code = N'ERRCNT03';
            GOTO Finish;
        END

        SELECT
            @line_id     = cl.count_line_id,
            @line_status = cl.line_status_code,
            @bin_id      = cl.bin_id
        FROM warehouse.count_lines cl
        JOIN locations.bins b ON b.bin_id = cl.bin_id
        WHERE cl.count_id = @count_id
          AND b.bin_code  = @bin_code COLLATE Latin1_General_CI_AS;

        IF @line_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT04';
            GOTO Finish;
        END

        -- PENDING and STOCK_FOUND can take (more) findings; a bin already
        -- confirmed empty / found occupied-since cannot
        IF @line_status IN ('CONFIRMED_EMPTY', 'OCCUPIED_SINCE')
        BEGIN
            SET @result_code = N'ERRCNT05';
            GOTO Finish;
        END

        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_id = @bin_id;

        ------------------------------------------------------------
        -- What is it, and may it be relocated here?
        ------------------------------------------------------------
        -- Prefer a live unit: an SSCC can be reused once its earlier unit has
        -- shipped or been reversed (the unique index on external_ref skips
        -- those). A shipped / reversed unit is still FOUND - it is known to the
        -- system, and that is the finding.
        SELECT TOP (1)
            @unit_id    = u.inventory_unit_id,
            @unit_state = u.stock_state_code,
            @sku_code   = s.sku_code
        FROM inventory.inventory_units u WITH (UPDLOCK, HOLDLOCK)
        JOIN inventory.skus s ON s.sku_id = u.sku_id
        WHERE u.external_ref = @scanned_ref
        ORDER BY
            CASE WHEN u.stock_state_code IN ('REV', 'SHP') THEN 1 ELSE 0 END,
            u.inventory_unit_id DESC;

        IF @unit_id IS NULL
        BEGIN
            SET @finding_code = 'UNKNOWN_UNIT';
            SET @result_code  = N'WARNCNT02';
        END
        ELSE
        BEGIN
            SELECT
                @prev_bin_id   = ip.bin_id,
                @prev_bin_code = b.bin_code
            FROM inventory.inventory_placements ip
            JOIN locations.bins b ON b.bin_id = ip.bin_id
            WHERE ip.inventory_unit_id = @unit_id;

            IF @prev_bin_id = @bin_id
            BEGIN
                -- The system already shows it here: nothing to record or change
                SET @success     = 1;
                SET @result_code = N'SUCCNT05';
                GOTO Finish;
            END

            SET @block_code = NULL;

            -- A shipped or reversed pallet is not stock, and a count never
            -- brings it back. Name the situation rather than letting the move
            -- rules report it as a generic "not in a moveable state".
            IF @unit_state = 'SHP'
                SET @block_code = N'ERRCNT06';
            ELSE IF @unit_state = 'REV'
                SET @block_code = N'ERRCNT07';
            ELSE
                SET @block_code = warehouse.fn_unit_move_block_code(@unit_id, NULL);

            IF @block_code IS NULL
                SET @block_code = warehouse.fn_bin_receive_block_code(@bin_id);

            IF @block_code IS NOT NULL
            BEGIN
                SET @finding_code = 'NOT_CORRECTED';
                SET @reason_code  = @block_code;
                SET @result_code  = N'WARNCNT03';
            END
            ELSE
            BEGIN
                SET @finding_code = 'RECORD_CORRECTED';
                SET @result_code  = N'SUCCNT03';
            END
        END

        ------------------------------------------------------------
        -- Record it; correct the record when the rules allow
        ------------------------------------------------------------
        INSERT INTO warehouse.count_findings
            (count_line_id, scanned_ref, inventory_unit_id, finding_code,
             reason_code, previous_bin_id, found_at, found_by)
        VALUES
            (@line_id, @scanned_ref, @unit_id, @finding_code,
             @reason_code, @prev_bin_id, @now, @user_id);

        SET @finding_id = SCOPE_IDENTITY();

        -- Where it went, when that is known: the delivery a shipped pallet left
        -- on, or the order a picked one belongs to. Read back from the findings
        -- view (same transaction, so the row just inserted is visible) so the
        -- definition lives in one place.
        IF @unit_id IS NOT NULL
        BEGIN
            SELECT
                @shipment_ref  = shipment_ref,
                @vehicle_ref   = vehicle_ref,
                @shipped_at    = shipped_at,
                @order_ref     = order_ref,
                @customer_name = customer_name
            FROM warehouse.v_count_findings
            WHERE finding_id = @finding_id;
        END

        IF @finding_code = 'RECORD_CORRECTED'
        BEGIN
            EXEC warehouse.usp_apply_relocation
                @inventory_unit_id  = @unit_id,
                @destination_bin_id = @bin_id,
                @movement_type      = N'ADJUSTMENT',
                @reference_type     = N'COUNT',
                @reference_id       = @line_id,
                @user_id            = @user_id,
                @session_id         = @session_id,
                @movement_id        = @movement_id OUTPUT;

            UPDATE warehouse.count_findings
            SET movement_id = @movement_id
            WHERE finding_id = @finding_id;
        END

        UPDATE warehouse.count_lines
        SET line_status_code = 'STOCK_FOUND',
            counted_at       = ISNULL(counted_at, @now),
            counted_by       = ISNULL(counted_by, @user_id)
        WHERE count_line_id = @line_id;

        SET @success = 1;

Finish:

        IF @success = 1
        BEGIN
            COMMIT;
        END
        ELSE
        BEGIN
            ROLLBACK;
        END

        SELECT @pending = COUNT(*)
        FROM warehouse.count_lines
        WHERE count_id = @count_id
          AND line_status_code = 'PENDING';

        SELECT
            @success       AS success,
            @result_code   AS result_code,
            @finding_code  AS finding_code,
            @count_id      AS count_id,
            @unit_id       AS inventory_unit_id,
            @sku_code      AS sku_code,
            @prev_bin_code AS previous_bin_code,
            @pending       AS pending_bins,
            @reason_code   AS reason_code,
            @shipment_ref  AS shipment_ref,
            @vehicle_ref   AS vehicle_ref,
            @shipped_at    AS shipped_at,
            @order_ref     AS order_ref,
            @customer_name AS customer_name;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)         AS success,
            N'ERRCNT99'            AS result_code,
            CAST(NULL AS VARCHAR(20))   AS finding_code,
            @count_id              AS count_id,
            CAST(NULL AS INT)      AS inventory_unit_id,
            CAST(NULL AS NVARCHAR(50))  AS sku_code,
            CAST(NULL AS NVARCHAR(100)) AS previous_bin_code,
            CAST(NULL AS INT)      AS pending_bins,
            CAST(NULL AS NVARCHAR(20))  AS reason_code,
            CAST(NULL AS NVARCHAR(50))  AS shipment_ref,
            CAST(NULL AS NVARCHAR(50))  AS vehicle_ref,
            CAST(NULL AS DATETIME2(3))  AS shipped_at,
            CAST(NULL AS NVARCHAR(50))  AS order_ref,
            CAST(NULL AS NVARCHAR(200)) AS customer_name;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_report_stock created.';
GO

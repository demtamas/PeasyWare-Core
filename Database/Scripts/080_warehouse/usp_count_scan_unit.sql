USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_scan_unit
   ------------------------------------------------------------
   The operator scanned a pallet's SSCC in an open bin and entered the
   quantity they counted. One call per pallet.

   BLIND: nothing here tells the operator what the system holds, so the
   count is not steered towards the "right" answer. The result is just
   "recorded". The one exception is the question the operator is meant to be
   asked: when the pallet is recorded in THIS bin and the quantity entered
   differs from the system's, the call does not record it but returns
   WARNCNT10 with needs_confirmation = 1 - "the quantity differs from the
   system record, confirm it?". The system's figure is not returned. The
   caller asks, and calls again with @confirm_difference = 1 to confirm, or
   with a re-keyed quantity.

   Nothing is classified here (matched / missing / misplaced / unknown): that
   is done once, for the whole bin, by usp_count_finish_bin, against the
   system's records as they stand at the end. Scanning the same SSCC again
   replaces the earlier quantity (so a mis-keyed number is simply scanned
   again) - never a second row.

   The bin's hold is renewed by every scan. If it has expired the scan is
   refused (ERRCNT16): scan the bin again to resume - the scans so far are
   kept, and the ledger check at finish still covers the gap.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | pallets_scanned INT | replaced BIT | needs_confirmation BIT
   Codes: SUCCNT11 recorded | WARNCNT10 confirm the quantity
          ERRCNT03 / 04 / 05 / 10 | ERRCNT15 bin not opened
          ERRCNT16 hold expired | ERRCNT17 quantity must be at least 1
          ERRCNT19 SSCC required | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_scan_unit
(
    @count_id           INT,
    @bin_code           NVARCHAR(100),
    @scanned_ref        NVARCHAR(100),
    @counted_qty        INT,
    @confirm_difference BIT              = 0,
    @user_id            INT              = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
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
        @count_status  VARCHAR(10),
        @count_type    VARCHAR(20),
        @line_id       INT,
        @line_status   VARCHAR(16),
        @bin_id        INT,
        @reservation_id INT,
        @unit_id       INT,
        @system_qty    INT,
        @unit_bin_id   INT,
        @differs       BIT = 0,
        @replaced      BIT = 0,
        @needs_confirm BIT = 0,
        @ttl_seconds   INT,
        @expires_at    DATETIME2(3),
        @scanned       INT,
        @now           DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        -- Bin codes are matched exactly (IdentifierPolicy); the SSCC is trimmed only
        SET @bin_code    = LTRIM(RTRIM(@bin_code)) COLLATE Latin1_General_CS_AS;
        SET @scanned_ref = LTRIM(RTRIM(@scanned_ref));

        SELECT
            @count_status = status_code,
            @count_type   = count_type_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_status IS NULL OR @count_status <> 'OPEN'
        BEGIN
            SET @result_code = N'ERRCNT03';
            GOTO Finish;
        END

        IF @count_type <> 'BIN_COUNT'
        BEGIN
            SET @result_code = N'ERRCNT10';
            GOTO Finish;
        END

        SELECT
            @line_id     = cl.count_line_id,
            @line_status = cl.line_status_code,
            @bin_id      = cl.bin_id
        FROM warehouse.count_lines cl
        JOIN locations.bins b ON b.bin_id = cl.bin_id
        WHERE cl.count_id = @count_id
          AND b.bin_code  = @bin_code COLLATE Latin1_General_CS_AS;

        IF @line_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT04';
            GOTO Finish;
        END

        IF @line_status = 'PENDING'
        BEGIN
            SET @result_code = N'ERRCNT15';
            GOTO Finish;
        END

        IF @line_status <> 'COUNTING'
        BEGIN
            SET @result_code = N'ERRCNT05';
            GOTO Finish;
        END

        -- The bin must still be held for this count
        SELECT @reservation_id = reservation_id
        FROM locations.bin_reservations
        WHERE reservation_type = N'COUNT'
          AND count_line_id    = @line_id
          AND expires_at       > @now;

        IF @reservation_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT16';
            GOTO Finish;
        END

        IF @scanned_ref IS NULL OR @scanned_ref = N''
        BEGIN
            SET @result_code = N'ERRCNT19';
            GOTO Finish;
        END

        IF @counted_qty IS NULL OR @counted_qty < 1
        BEGIN
            SET @result_code = N'ERRCNT17';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- Does the quantity differ from what the system holds for a
        -- pallet it records in THIS bin? (Same live-unit-first lookup
        -- as everywhere else an SSCC is resolved.)
        ------------------------------------------------------------
        SELECT TOP (1)
            @unit_id     = u.inventory_unit_id,
            @system_qty  = u.quantity,
            @unit_bin_id = ip.bin_id
        FROM inventory.inventory_units u
        LEFT JOIN inventory.inventory_placements ip ON ip.inventory_unit_id = u.inventory_unit_id
        WHERE u.external_ref = @scanned_ref
        ORDER BY
            CASE WHEN u.stock_state_code IN ('REV', 'SHP') THEN 1 ELSE 0 END,
            u.inventory_unit_id DESC;

        IF @unit_id IS NOT NULL
           AND @unit_bin_id = @bin_id
           AND @counted_qty <> @system_qty
            SET @differs = 1;

        IF @differs = 1 AND ISNULL(@confirm_difference, 0) = 0
        BEGIN
            -- Ask, don't record. The system's quantity is deliberately not returned.
            SET @needs_confirm = 1;
            SET @result_code   = N'WARNCNT10';
            GOTO Finish;
        END

        ------------------------------------------------------------
        -- Record it (replacing an earlier scan of the same pallet)
        ------------------------------------------------------------
        UPDATE warehouse.count_scans
        SET counted_qty        = @counted_qty,
            quantity_confirmed = @differs,
            scanned_at         = @now,
            scanned_by         = @user_id
        WHERE count_line_id = @line_id
          AND scanned_ref   = @scanned_ref;

        IF @@ROWCOUNT > 0
        BEGIN
            SET @replaced = 1;
        END
        ELSE
        BEGIN
            INSERT INTO warehouse.count_scans
                (count_line_id, scanned_ref, counted_qty, quantity_confirmed, scanned_at, scanned_by)
            VALUES
                (@line_id, @scanned_ref, @counted_qty, @differs, @now, @user_id);
        END

        -- Renew the hold
        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.count_bin_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 900;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        UPDATE locations.bin_reservations
        SET expires_at = @expires_at
        WHERE reservation_id = @reservation_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT11';

Finish:

        IF @success = 1
        BEGIN
            COMMIT;
        END
        ELSE
        BEGIN
            ROLLBACK;
        END

        SELECT @scanned = COUNT(*)
        FROM warehouse.count_scans
        WHERE count_line_id = @line_id;

        SELECT
            @success             AS success,
            @result_code         AS result_code,
            @count_id            AS count_id,
            ISNULL(@scanned, 0)  AS pallets_scanned,
            @replaced            AS replaced,
            @needs_confirm       AS needs_confirmation;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)    AS success,
            N'ERRCNT99'       AS result_code,
            @count_id         AS count_id,
            0                 AS pallets_scanned,
            CAST(0 AS BIT)    AS replaced,
            CAST(0 AS BIT)    AS needs_confirmation;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_scan_unit created.';
GO

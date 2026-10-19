USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_open_bin
   ------------------------------------------------------------
   The operator scanned a bin from a bin count and is about to count what
   is in it. Scanning the bin label is the proof of presence.

   The bin is HELD for the count: a COUNT reservation (a hard lock - see
   locations.fn_bin_is_being_counted) is taken, so nothing can be put into or
   taken out of the bin while it is counted. The hold expires
   (warehouse.count_bin_ttl_seconds, default 900) so an abandoned count cannot
   pin a bin; every scan extends it.

   Refused if the bin has work in progress - an open putaway / move / pick
   task to or from it, or another unexpired reservation on it - so a count
   never starts in the middle of someone else's movement (ERRCNT14).

   Opening a bin that is already COUNTING resumes it: the hold is renewed and
   the scans so far are kept. The original opened_at is kept too, so anything
   that changed the bin while it was unheld is still caught at finish.

   Blind by design: the result says nothing about what the system holds.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | bin_code NVARCHAR(100) | pallets_scanned INT | pending_bins INT
     | resumed BIT
   Codes: SUCCNT10 opened | ERRCNT03 count not open | ERRCNT04 bin not in count
          ERRCNT05 already counted | ERRCNT10 not a bin count
          ERRCNT12 bin held by another count | ERRCNT14 work in progress
          ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_open_bin
(
    @count_id   INT,
    @bin_code   NVARCHAR(100),
    @user_id    INT              = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @success      BIT = 0,
        @result_code  NVARCHAR(20),
        @count_status VARCHAR(10),
        @count_type   VARCHAR(20),
        @line_id      INT,
        @line_status  VARCHAR(16),
        @bin_id       INT,
        @resumed      BIT = 0,
        @ttl_seconds  INT,
        @expires_at   DATETIME2(3),
        @scanned      INT,
        @pending      INT,
        @now          DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        -- Bin codes are matched exactly (IdentifierPolicy): a wrong-case entry is
        -- "not in this count", never silently corrected
        SET @bin_code = LTRIM(RTRIM(@bin_code)) COLLATE Latin1_General_CS_AS;

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

        IF @line_status NOT IN ('PENDING', 'COUNTING')
        BEGIN
            SET @result_code = N'ERRCNT05';
            GOTO Finish;
        END

        -- Lock the bin row: the checks below and the hold are one atomic step
        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_id = @bin_id;

        -- Held by a different count line (another session on the same bin)
        IF EXISTS (
            SELECT 1
            FROM locations.bin_reservations
            WHERE bin_id           = @bin_id
              AND reservation_type = N'COUNT'
              AND expires_at       > @now
              AND ISNULL(count_line_id, 0) <> @line_id
        )
        BEGIN
            SET @result_code = N'ERRCNT12';
            GOTO Finish;
        END

        -- Work in progress: an open task to or from the bin, or any other
        -- unexpired reservation on it
        IF EXISTS (
            SELECT 1
            FROM warehouse.warehouse_tasks
            WHERE task_state_code IN ('OPN', 'CLM')
              AND (source_bin_id = @bin_id OR destination_bin_id = @bin_id)
        )
        OR EXISTS (
            SELECT 1
            FROM locations.bin_reservations
            WHERE bin_id           = @bin_id
              AND reservation_type <> N'COUNT'
              AND expires_at       > @now
        )
        BEGIN
            SET @result_code = N'ERRCNT14';
            GOTO Finish;
        END

        SELECT @ttl_seconds = TRY_CAST(setting_value AS INT)
        FROM operations.settings
        WHERE setting_name = 'warehouse.count_bin_ttl_seconds';

        IF @ttl_seconds IS NULL OR @ttl_seconds <= 0
            SET @ttl_seconds = 900;

        SET @expires_at = DATEADD(SECOND, @ttl_seconds, @now);

        SET @resumed = CASE WHEN @line_status = 'COUNTING' THEN 1 ELSE 0 END;

        -- Replace this line's own hold (if any) with a fresh one
        DELETE FROM locations.bin_reservations
        WHERE reservation_type = N'COUNT'
          AND count_line_id    = @line_id;

        INSERT INTO locations.bin_reservations
            (bin_id, reservation_type, reserved_by, expires_at, count_line_id)
        VALUES
            (@bin_id, N'COUNT', ISNULL(@user_id, 0), @expires_at, @line_id);

        UPDATE warehouse.count_lines
        SET line_status_code = 'COUNTING',
            opened_at        = ISNULL(opened_at, @now),
            opened_by        = ISNULL(opened_by, @user_id)
        WHERE count_line_id = @line_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT10';

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

        SELECT @pending = COUNT(*)
        FROM warehouse.count_lines
        WHERE count_id = @count_id
          AND line_status_code = 'PENDING';

        SELECT
            @success             AS success,
            @result_code         AS result_code,
            @count_id            AS count_id,
            @bin_code            AS bin_code,
            ISNULL(@scanned, 0)  AS pallets_scanned,
            @pending             AS pending_bins,
            @resumed             AS resumed;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)    AS success,
            N'ERRCNT99'       AS result_code,
            @count_id         AS count_id,
            @bin_code         AS bin_code,
            0                 AS pallets_scanned,
            CAST(NULL AS INT) AS pending_bins,
            CAST(0 AS BIT)    AS resumed;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_open_bin created.';
GO

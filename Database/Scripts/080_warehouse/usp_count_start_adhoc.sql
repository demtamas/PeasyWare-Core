USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_start_adhoc
   ------------------------------------------------------------
   Starts an AD HOC bin count: a count of a hand-picked list of bins,
   for when someone wants specific bins checked now - a spot check, a
   suspected problem, a recount - rather than a whole storage type or a sweep.

   It is an ordinary BIN_COUNT in every respect (open / scan / finish / cancel /
   close / review / apply all work on it unchanged); only the scope differs
   (scope_code ADHOC, no storage type).

   - @bin_codes is a list of bin codes separated by NCHAR(30) (the "record
     separator" control character, which cannot appear in a bin code). Each is
     trimmed and matched EXACTLY - wrong case is a bin that does not exist - and
     a bin named twice is one line.
   - Any ACTIVE bin in an ACTIVE storage type may be named, empty or occupied.
     An empty bin is a legitimate thing to count: finding nothing there confirms
     it is empty, and anything found is a finding like any other.
   - Nothing is created unless every bin is valid: the first that is not comes
     back in invalid_bin_code (ERRCNT40). An empty list is ERRCNT41.
   - Every call starts a NEW count. Ad hoc counts are exempt from the one-open-
     per-scope rule and never conflict with a sweep or a storage-type count; they
     are resumed by their count id (the CLI lists the open ones).
   - Any user may start one, like any count.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | total_bins INT | pending_bins INT | resumed BIT (always 0)
     | invalid_bin_code NVARCHAR(100)
   Codes: SUCCNT01 started | ERRCNT40 a bin is not an active bin
          ERRCNT41 no bins chosen | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_start_adhoc
(
    @bin_codes  NVARCHAR(MAX),
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
        @count_id     INT,
        @invalid      NVARCHAR(100),
        @total        INT,
        @pending      INT,
        @now          DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @wanted TABLE (bin_code NVARCHAR(100) NOT NULL);

    BEGIN TRY
        BEGIN TRAN;

        -- Exact codes: DISTINCT is case-sensitive, so a wrong-case duplicate stays
        -- a separate (invalid) entry rather than being quietly merged
        INSERT INTO @wanted (bin_code)
        SELECT DISTINCT LTRIM(RTRIM(s.value)) COLLATE Latin1_General_CS_AS
        FROM STRING_SPLIT(ISNULL(@bin_codes, N''), NCHAR(30)) s
        WHERE LTRIM(RTRIM(s.value)) <> N'';

        IF NOT EXISTS (SELECT 1 FROM @wanted)
        BEGIN
            SET @result_code = N'ERRCNT41';
            GOTO Finish;
        END

        -- Every bin must be an active bin in an active storage type
        SELECT TOP (1) @invalid = w.bin_code
        FROM @wanted w
        WHERE NOT EXISTS (
            SELECT 1
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.bin_code  = w.bin_code COLLATE Latin1_General_CS_AS
              AND b.is_active  = 1
              AND st.is_active = 1
        )
        ORDER BY w.bin_code;

        IF @invalid IS NOT NULL
        BEGIN
            SET @result_code = N'ERRCNT40';
            GOTO Finish;
        END

        INSERT INTO warehouse.count_sessions
            (count_type_code, storage_type_id, scope_code, started_at, started_by)
        VALUES
            ('BIN_COUNT', NULL, 'ADHOC', @now, @user_id);

        SET @count_id = SCOPE_IDENTITY();

        INSERT INTO warehouse.count_lines (count_id, bin_id)
        SELECT DISTINCT @count_id, b.bin_id
        FROM @wanted w
        JOIN locations.bins b
          ON b.bin_code = w.bin_code COLLATE Latin1_General_CS_AS;

        SET @success     = 1;
        SET @result_code = N'SUCCNT01';

Finish:

        IF @success = 1
        BEGIN
            COMMIT;
        END
        ELSE
        BEGIN
            ROLLBACK;
        END

        SELECT
            @total   = COUNT(*),
            @pending = ISNULL(SUM(CASE WHEN line_status_code = 'PENDING' THEN 1 ELSE 0 END), 0)
        FROM warehouse.count_lines
        WHERE count_id = @count_id;

        SELECT
            @success             AS success,
            @result_code         AS result_code,
            CASE WHEN @success = 1 THEN @count_id END AS count_id,
            ISNULL(@total, 0)    AS total_bins,
            ISNULL(@pending, 0)  AS pending_bins,
            CAST(0 AS BIT)       AS resumed,
            @invalid             AS invalid_bin_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)       AS success,
            N'ERRCNT99'          AS result_code,
            CAST(NULL AS INT)    AS count_id,
            0                    AS total_bins,
            0                    AS pending_bins,
            CAST(0 AS BIT)       AS resumed,
            CAST(NULL AS NVARCHAR(100)) AS invalid_bin_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_start_adhoc created.';
GO

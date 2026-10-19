USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_start_bin
   ------------------------------------------------------------
   Starts (or resumes) a bin count - a count of the stock in the bins
   that hold stock.

   Scope:
     @storage_type_code given   one storage type
     NULL / blank               every active storage type - a SWEEP, e.g. a
                                period-end stocktake. A sweep is just the
                                same count over a wider scope; there is no
                                separate mechanism.
   (Empty bins are a different count - usp_count_start_empty_bin. A full
   sweep of a warehouse is a bin count plus an empty-bin count over the
   same scope.)

   - An OPEN bin count of exactly that scope is resumed, not duplicated
     (the filtered unique index UX_count_sessions_open_scope backs this up).
   - A sweep and a single-storage-type count cannot be open together: they
     would cover the same bins twice. ERRCNT11.
   - Otherwise a session is created and every active bin that holds at least
     one pallet is snapshotted into count_lines as PENDING. No such bin =
     no session (ERRCNT13).

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | total_bins INT | pending_bins INT | resumed BIT
   Codes: SUCCNT01 started / resumed | ERRCNT01 storage type not found
          ERRCNT11 overlapping count open | ERRCNT13 nothing to count
          ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_start_bin
(
    @storage_type_code NVARCHAR(50)     = NULL,
    @user_id           INT              = NULL,
    @session_id        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @success         BIT = 0,
        @result_code     NVARCHAR(20),
        @storage_type_id INT,
        @count_id        INT,
        @resumed         BIT = 0,
        @total           INT,
        @pending         INT,
        @now             DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SET @storage_type_code = NULLIF(LTRIM(RTRIM(@storage_type_code)), N'');

        IF @storage_type_code IS NOT NULL
        BEGIN
            SELECT @storage_type_id = storage_type_id
            FROM locations.storage_types
            WHERE storage_type_code = @storage_type_code
              AND is_active = 1;

            IF @storage_type_id IS NULL
            BEGIN
                SET @result_code = N'ERRCNT01';
                GOTO Finish;
            END
        END

        -- An OPEN bin count of exactly this scope is resumed
        SELECT @count_id = count_id
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_type_code = 'BIN_COUNT'
          AND status_code     = 'OPEN'
          AND (   storage_type_id = @storage_type_id
               OR (storage_type_id IS NULL AND @storage_type_id IS NULL));

        IF @count_id IS NOT NULL
        BEGIN
            SET @resumed = 1;
        END
        ELSE
        BEGIN
            -- A sweep overlaps every other open count; a single storage type
            -- overlaps only an open sweep
            IF EXISTS (
                SELECT 1
                FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
                WHERE count_type_code = 'BIN_COUNT'
                  AND status_code     = 'OPEN'
                  AND (@storage_type_id IS NULL OR storage_type_id IS NULL)
            )
            BEGIN
                SET @result_code = N'ERRCNT11';
                GOTO Finish;
            END

            INSERT INTO warehouse.count_sessions
                (count_type_code, storage_type_id, started_at, started_by)
            VALUES
                ('BIN_COUNT', @storage_type_id, @now, @user_id);

            SET @count_id = SCOPE_IDENTITY();

            INSERT INTO warehouse.count_lines (count_id, bin_id)
            SELECT @count_id, b.bin_id
            FROM locations.bins b
            JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
            WHERE b.is_active  = 1
              AND st.is_active = 1
              AND (@storage_type_id IS NULL OR b.storage_type_id = @storage_type_id)
              AND EXISTS (
                    SELECT 1
                    FROM inventory.inventory_placements ip
                    WHERE ip.bin_id = b.bin_id
              );

            IF @@ROWCOUNT = 0
            BEGIN
                -- Nothing to count: roll the empty session back out
                SET @count_id    = NULL;
                SET @result_code = N'ERRCNT13';
                GOTO Finish;
            END
        END

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
            @count_id            AS count_id,
            ISNULL(@total, 0)    AS total_bins,
            ISNULL(@pending, 0)  AS pending_bins,
            @resumed             AS resumed;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)       AS success,
            N'ERRCNT99'          AS result_code,
            CAST(NULL AS INT)    AS count_id,
            0                    AS total_bins,
            0                    AS pending_bins,
            CAST(0 AS BIT)       AS resumed;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_start_bin created.';
GO

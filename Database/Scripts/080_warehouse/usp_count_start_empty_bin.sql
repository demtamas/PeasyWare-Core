USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_start_empty_bin
   ------------------------------------------------------------
   Starts (or resumes) an empty-bin count for one storage type.

   - An OPEN count for that storage type is resumed, not duplicated
     (the filtered unique index UX_count_sessions_open_scope backs
     this up).
   - Otherwise a session is created and every bin in
     warehouse.v_empty_bins for the storage type is snapshotted into
     count_lines as PENDING. No empty bins = no session (ERRCNT02).

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | total_bins INT | pending_bins INT | resumed BIT
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_start_empty_bin
(
    @storage_type_code NVARCHAR(50),
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

        SET @storage_type_code = LTRIM(RTRIM(@storage_type_code));

        SELECT @storage_type_id = storage_type_id
        FROM locations.storage_types
        WHERE storage_type_code = @storage_type_code
          AND is_active = 1;

        IF @storage_type_id IS NULL
        BEGIN
            SET @result_code = N'ERRCNT01';
            GOTO Finish;
        END

        SELECT @count_id = count_id
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_type_code = 'EMPTY_BIN'
          AND storage_type_id = @storage_type_id
          AND status_code     = 'OPEN';

        IF @count_id IS NOT NULL
        BEGIN
            SET @resumed = 1;
        END
        ELSE
        BEGIN
            INSERT INTO warehouse.count_sessions
                (count_type_code, storage_type_id, started_at, started_by)
            VALUES
                ('EMPTY_BIN', @storage_type_id, @now, @user_id);

            SET @count_id = SCOPE_IDENTITY();

            INSERT INTO warehouse.count_lines (count_id, bin_id)
            SELECT @count_id, eb.bin_id
            FROM warehouse.v_empty_bins eb
            WHERE eb.storage_type_id = @storage_type_id;

            IF @@ROWCOUNT = 0
            BEGIN
                -- Nothing to count: roll the empty session back out
                SET @count_id    = NULL;
                SET @result_code = N'ERRCNT02';
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
PRINT 'warehouse.usp_count_start_empty_bin created.';
GO

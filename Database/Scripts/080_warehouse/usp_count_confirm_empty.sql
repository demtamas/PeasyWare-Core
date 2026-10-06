USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_confirm_empty
   ------------------------------------------------------------
   The operator scanned a bin from the count and it is empty.

   Scanning the bin label is the proof of presence - the count line
   is only ever marked from a scan of that bin.

   The bin is locked and re-checked: if the system has recorded stock
   there since the snapshot (a putaway, say) the line becomes
   OCCUPIED_SINCE and the operator is warned, rather than the bin
   being silently confirmed empty over a recorded pallet. A pending
   reservation does not count as occupied - the bay is still empty.

   Does not complete the session; the caller closes it when no bins
   remain pending (usp_count_close).

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | pending_bins INT
   Codes: SUCCNT02 confirmed | WARNCNT01 system now shows stock
          ERRCNT03 count not open | ERRCNT04 bin not in this count
          ERRCNT05 already counted | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_confirm_empty
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
        @line_id      INT,
        @line_status  VARCHAR(16),
        @bin_id       INT,
        @pending      INT,
        @now          DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        -- Bin codes match case-insensitively: two bins cannot differ only by
        -- case, so this is unambiguous, and a typed "bulk01" is not a different bin
        SET @bin_code = LTRIM(RTRIM(@bin_code));

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

        IF @line_status <> 'PENDING'
        BEGIN
            SET @result_code = N'ERRCNT05';
            GOTO Finish;
        END

        -- Lock the bin so nothing can be placed into it between the
        -- emptiness check and the write below
        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_id = @bin_id;

        IF EXISTS (
            SELECT 1
            FROM inventory.inventory_placements
            WHERE bin_id = @bin_id
        )
        BEGIN
            UPDATE warehouse.count_lines
            SET line_status_code = 'OCCUPIED_SINCE',
                counted_at       = @now,
                counted_by       = @user_id
            WHERE count_line_id = @line_id;

            SET @result_code = N'WARNCNT01';
        END
        ELSE
        BEGIN
            UPDATE warehouse.count_lines
            SET line_status_code = 'CONFIRMED_EMPTY',
                counted_at       = @now,
                counted_by       = @user_id
            WHERE count_line_id = @line_id;

            SET @result_code = N'SUCCNT02';
        END

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
            @success     AS success,
            @result_code AS result_code,
            @count_id    AS count_id,
            @pending     AS pending_bins;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)    AS success,
            N'ERRCNT99'       AS result_code,
            @count_id         AS count_id,
            CAST(NULL AS INT) AS pending_bins;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_confirm_empty created.';
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_cancel_bin
   ------------------------------------------------------------
   The operator abandons the bin they have open: the scans so far are
   discarded, the hold is released, and the bin goes back to PENDING to be
   counted again later. Nothing was ever written to the system's records
   by a count, so there is nothing to undo.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | pending_bins INT
   Codes: SUCCNT13 cancelled | ERRCNT03 / 04 / 05 / 10
          ERRCNT15 bin not opened | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_cancel_bin
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
        @pending      INT;

    BEGIN TRY
        BEGIN TRAN;

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
            @line_status = cl.line_status_code
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

        DELETE FROM warehouse.count_scans
        WHERE count_line_id = @line_id;

        DELETE FROM locations.bin_reservations
        WHERE reservation_type = N'COUNT'
          AND count_line_id    = @line_id;

        UPDATE warehouse.count_lines
        SET line_status_code = 'PENDING',
            opened_at        = NULL,
            opened_by        = NULL
        WHERE count_line_id = @line_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT13';

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
PRINT 'warehouse.usp_count_cancel_bin created.';
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_close
   ------------------------------------------------------------
   Closes an OPEN count - the physical count is over.

     REVIEW    the count found something it could not put right (an
               unknown pallet, a shipped / reversed one, a pallet that
               failed a move rule). A person has to deal with it, so the
               count goes on the review list instead of looking finished.
               usp_count_review takes it from there.
     COMPLETE  no bins left pending and nothing to review
     CLOSED    closed with bins still uncounted and nothing to review

   REVIEW wins over COMPLETE / CLOSED: whether every bin was visited is
   secondary to there being work for a person. The review step still
   records which of COMPLETE / CLOSED it ends as, from the same pending
   check.

   The CLI calls this itself when the last pending bin is done, so
   finishing a count needs no extra step. Leaving a count part-way does
   NOT close it - it stays OPEN and is resumed by starting the same
   count again.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | pending_bins INT | final_status VARCHAR(10)
     | findings_to_review INT
   Codes: SUCCNT04 closed | ERRCNT03 not open | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_close
(
    @count_id   INT,
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
        @pending      INT,
        @to_review    INT,
        @final_status VARCHAR(10),
        @now          DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        SELECT @count_status = status_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_status IS NULL OR @count_status <> 'OPEN'
        BEGIN
            SET @result_code = N'ERRCNT03';
            GOTO Finish;
        END

        SELECT @pending = COUNT(*)
        FROM warehouse.count_lines
        WHERE count_id = @count_id
          AND line_status_code = 'PENDING';

        -- Findings a person still has to look at: everything except a
        -- record the count itself corrected
        SELECT @to_review = COUNT(*)
        FROM warehouse.count_findings f
        JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
        WHERE l.count_id = @count_id
          AND f.finding_code <> 'RECORD_CORRECTED';

        SET @final_status =
            CASE
                WHEN @to_review > 0 THEN 'REVIEW'
                WHEN @pending   = 0 THEN 'COMPLETE'
                ELSE 'CLOSED'
            END;

        UPDATE warehouse.count_sessions
        SET status_code  = @final_status,
            completed_at = @now,
            completed_by = @user_id
        WHERE count_id = @count_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT04';

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
            @success      AS success,
            @result_code  AS result_code,
            @count_id     AS count_id,
            @pending      AS pending_bins,
            @final_status AS final_status,
            @to_review    AS findings_to_review;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)            AS success,
            N'ERRCNT99'               AS result_code,
            @count_id                 AS count_id,
            CAST(NULL AS INT)         AS pending_bins,
            CAST(NULL AS VARCHAR(10)) AS final_status,
            CAST(NULL AS INT)         AS findings_to_review;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_close created.';
GO

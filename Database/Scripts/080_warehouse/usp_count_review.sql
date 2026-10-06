USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   warehouse.usp_count_review
   ------------------------------------------------------------
   A person marks a count in REVIEW as reviewed once they have dealt
   with what it found - with a note saying what they did.

   "Reviewed" records that someone looked and acted; it does not fix
   anything itself (reversing a shipment line, receiving a pallet back
   and so on happen elsewhere). The note carries what was done, and the
   reviewer and time are kept on the count.

   Gated on counts.review (manager + admin), enforced here - not just
   by greying a button. A count not in REVIEW cannot be reviewed (so a
   count cannot be reviewed twice, and its first review cannot be
   overwritten). A note is required.

   The count ends as COMPLETE (every bin visited) or CLOSED (bins left
   uncounted), by the same pending-bins check usp_count_close uses.

   Contract (one row, always):
     success BIT | result_code NVARCHAR(20) | count_id INT
     | final_status VARCHAR(10)
   Codes: SUCCNT06 reviewed | ERRPERM01 not permitted
          ERRCNT08 not awaiting review | ERRCNT09 note required | ERRCNT99
   ============================================================ */
CREATE OR ALTER PROCEDURE warehouse.usp_count_review
(
    @count_id   INT,
    @note       NVARCHAR(500),
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
        @final_status VARCHAR(10),
        @now          DATETIME2(3) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'counts.review') = 0
        BEGIN
            SET @result_code = N'ERRPERM01';
            GOTO Finish;
        END

        SET @note = LTRIM(RTRIM(@note));

        SELECT @count_status = status_code
        FROM warehouse.count_sessions WITH (UPDLOCK, HOLDLOCK)
        WHERE count_id = @count_id;

        IF @count_status IS NULL OR @count_status <> 'REVIEW'
        BEGIN
            SET @result_code = N'ERRCNT08';
            GOTO Finish;
        END

        IF @note IS NULL OR @note = N''
        BEGIN
            SET @result_code = N'ERRCNT09';
            GOTO Finish;
        END

        SELECT @pending = COUNT(*)
        FROM warehouse.count_lines
        WHERE count_id = @count_id
          AND line_status_code = 'PENDING';

        SET @final_status = CASE WHEN @pending = 0 THEN 'COMPLETE' ELSE 'CLOSED' END;

        UPDATE warehouse.count_sessions
        SET status_code = @final_status,
            reviewed_at = @now,
            reviewed_by = @user_id,
            review_note = @note
        WHERE count_id = @count_id;

        SET @success     = 1;
        SET @result_code = N'SUCCNT06';

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
            @final_status AS final_status;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        SELECT
            CAST(0 AS BIT)            AS success,
            N'ERRCNT99'               AS result_code,
            @count_id                 AS count_id,
            CAST(NULL AS VARCHAR(10)) AS final_status;
    END CATCH
END;
GO
PRINT 'warehouse.usp_count_review created.';
GO

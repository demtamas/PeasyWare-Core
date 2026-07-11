USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE locations.usp_lock_bin
(
    @bin_code       NVARCHAR(100),
    @reason         NVARCHAR(255)    = NULL,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'bins.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code;
            ROLLBACK; RETURN;
        END

        DECLARE @bin_id INT;

        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_id = @bin_id AND is_locked = 1)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN02' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE locations.bins
        SET is_locked     = 1,
            locked_by     = @user_id,
            locked_at     = SYSUTCDATETIME(),
            locked_reason = @reason,
            updated_at    = SYSUTCDATETIME(),
            updated_by    = @user_id
        WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN01' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE locations.usp_unlock_bin
(
    @bin_code       NVARCHAR(100),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF auth.fn_has_permission(@user_id, 'bins.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code;
            ROLLBACK; RETURN;
        END

        DECLARE @bin_id INT;

        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_id = @bin_id AND is_locked = 0)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN03' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE locations.bins
        SET is_locked     = 0,
            locked_by     = NULL,
            locked_at     = NULL,
            locked_reason = NULL,
            updated_at    = SYSUTCDATETIME(),
            updated_by    = @user_id
        WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code;
    END CATCH
END;
GO

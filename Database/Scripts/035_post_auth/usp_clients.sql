USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- auth.v_clients — client application registrations
-- ============================================================
CREATE OR ALTER VIEW auth.v_clients
AS
SELECT
    c.client_name,
    c.session_timeout_minutes,
    c.max_concurrent_sessions,
    c.is_active,
    c.description,
    c.created_at,
    u.username AS created_by_username
FROM auth.clients c
LEFT JOIN auth.users u ON u.id = c.created_by;
GO

-- ============================================================
-- usp_create_client
-- ============================================================
CREATE OR ALTER PROCEDURE auth.usp_create_client
(
    @client_name             NVARCHAR(100),
    @session_timeout_minutes INT              = NULL,
    @max_concurrent_sessions INT              = NULL,
    @description             NVARCHAR(255)    = NULL,
    @user_id                 INT              = NULL,
    @session_id              UNIQUEIDENTIFIER = NULL,
    @correlation_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM auth.clients WHERE client_name = @client_name COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRCLI01' AS result_code; ROLLBACK; RETURN; END

        INSERT INTO auth.clients
            (client_name, session_timeout_minutes, max_concurrent_sessions, description, created_by)
        VALUES
            (@client_name, @session_timeout_minutes, @max_concurrent_sessions, @description, @user_id);

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCCLI01' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCLI99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- usp_update_client
-- ============================================================
CREATE OR ALTER PROCEDURE auth.usp_update_client
(
    @client_name             NVARCHAR(100),
    @session_timeout_minutes INT              = NULL,
    @clear_timeout           BIT              = 0,
    @max_concurrent_sessions INT              = NULL,
    @clear_max_sessions      BIT              = 0,
    @description             NVARCHAR(255)    = NULL,
    @clear_desc              BIT              = 0,
    @user_id                 INT              = NULL,
    @session_id              UNIQUEIDENTIFIER = NULL,
    @correlation_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = @client_name COLLATE Latin1_General_CS_AS)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRCLI02' AS result_code; ROLLBACK; RETURN; END

        UPDATE auth.clients
        SET
            session_timeout_minutes = CASE WHEN @clear_timeout    = 1 THEN NULL
                                           WHEN @session_timeout_minutes IS NOT NULL THEN @session_timeout_minutes
                                           ELSE session_timeout_minutes END,
            max_concurrent_sessions = CASE WHEN @clear_max_sessions = 1 THEN NULL
                                           WHEN @max_concurrent_sessions IS NOT NULL THEN @max_concurrent_sessions
                                           ELSE max_concurrent_sessions END,
            description             = CASE WHEN @clear_desc = 1 THEN NULL
                                           WHEN @description IS NOT NULL THEN @description
                                           ELSE description END
        WHERE client_name = @client_name COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCCLI02' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCLI99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- usp_deactivate_client / usp_reactivate_client
-- ============================================================
CREATE OR ALTER PROCEDURE auth.usp_deactivate_client
(
    @client_name    NVARCHAR(100),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = @client_name COLLATE Latin1_General_CS_AS AND is_active = 1)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRCLI02' AS result_code; ROLLBACK; RETURN; END

        UPDATE auth.clients SET is_active = 0 WHERE client_name = @client_name COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCCLI03' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCLI99' AS result_code;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE auth.usp_reactivate_client
(
    @client_name    NVARCHAR(100),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM auth.clients WHERE client_name = @client_name COLLATE Latin1_General_CS_AS AND is_active = 0)
        BEGIN SELECT CAST(0 AS BIT) AS success, N'ERRCLI02' AS result_code; ROLLBACK; RETURN; END

        UPDATE auth.clients SET is_active = 1 WHERE client_name = @client_name COLLATE Latin1_General_CS_AS;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCCLI04' AS result_code;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRCLI99' AS result_code;
    END CATCH
END;
GO

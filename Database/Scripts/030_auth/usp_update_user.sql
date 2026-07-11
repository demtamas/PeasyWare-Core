USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_update_user
(
    @user_id        INT,
    @display_name   NVARCHAR(100)    = NULL,
    @email          NVARCHAR(200)    = NULL,
    @role_name      NVARCHAR(50)     = NULL,
    @admin_user_id  INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        --------------------------------------------------------
        -- Permission check (Phase 2c)
        --------------------------------------------------------
        IF auth.fn_has_permission(@admin_user_id, 'users.manage') = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPERM01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = @user_id)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRAUTHUSR05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Resolve role if provided
        DECLARE @role_id INT = NULL;
        IF @role_name IS NOT NULL
        BEGIN
            SELECT @role_id = id
            FROM auth.roles
            WHERE role_name = @role_name COLLATE Latin1_General_CS_AS;

            IF @role_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRAUTHUSR06' AS result_code;
                ROLLBACK; RETURN;
            END
        END

        -- Update user profile fields
        UPDATE auth.users
        SET
            display_name = ISNULL(@display_name, display_name),
            email        = ISNULL(@email,        email),
            updated_at   = SYSUTCDATETIME(),
            updated_by   = @admin_user_id
        WHERE id = @user_id;

        -- Update role via user_roles join table
        IF @role_id IS NOT NULL
        BEGIN
            -- Remove existing role assignments then insert the new one
            DELETE FROM auth.user_roles WHERE user_id = @user_id;
            INSERT INTO auth.user_roles (user_id, role_id) VALUES (@user_id, @role_id);
        END

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCAUTH08' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRAUTH99' AS result_code;
    END CATCH
END;
GO

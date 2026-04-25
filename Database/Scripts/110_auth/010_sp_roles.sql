---------------------------------------------------------------
-- Support trace lookups by correlation
---------------------------------------------------------------

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_login_attempts_correlation_id'
      AND object_id = OBJECT_ID('auth.login_attempts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_login_attempts_correlation_id
        ON auth.login_attempts (correlation_id)
        INCLUDE (attempt_time, username, success, session_id);
END;
GO

---------------------------------------------------------------
GO

DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @OutputId INT;

EXEC auth.usp_add_role 
    @RoleName = 'system', 
    @Description = 'Under the hood functions and seed data', 
    @CreatedBy = @SystemUserId,
    @NewRoleId = @OutputId OUTPUT;
GO

-- Mark system role as is_system_role
UPDATE auth.roles SET is_system_role = 1 WHERE role_name = 'system';
GO

-- Add api role
DECLARE @SystemUserId2 INT = (SELECT id FROM auth.users WHERE username = 'system');
IF NOT EXISTS (SELECT 1 FROM auth.roles WHERE role_name = 'api')
BEGIN
    INSERT INTO auth.roles (role_name, description, is_active, is_system_role, created_by)
    VALUES ('api', 'API integration role — system use only', 1, 1, @SystemUserId2);
    PRINT 'api role created.';
END
ELSE
BEGIN
    UPDATE auth.roles SET is_system_role = 1 WHERE role_name = 'api';
    PRINT 'api role already exists — is_system_role ensured.';
END
GO

IF OBJECT_ID('auth.usp_update_role_by_name', 'P') IS NOT NULL
    DROP PROCEDURE auth.usp_update_role_by_name;
GO

---------------------------------------------------------------
-- 3. Ensure SYSTEM user is assigned to SYSTEM role
---------------------------------------------------------------
DECLARE @SystemUserId INT = (SELECT id FROM auth.users WHERE username = 'system');
DECLARE @SystemRoleId INT = (SELECT id FROM auth.roles WHERE role_name = 'system');

IF @SystemUserId IS NULL OR @SystemRoleId IS NULL
BEGIN
    PRINT 'ERROR: System user or role missing – cannot assign.';
END
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM auth.user_roles
        WHERE user_id = @SystemUserId
          AND role_id = @SystemRoleId
    )
    BEGIN
        INSERT INTO auth.user_roles (user_id, role_id)
        VALUES (@SystemUserId, @SystemRoleId);

        PRINT 'System user assigned to system role.';
    END
    ELSE
    BEGIN
        PRINT 'System user already assigned to system role.';
    END
END;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_roles_get
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        role_name   AS RoleName,
        description AS Description
    FROM auth.roles
    WHERE is_active      = 1
      AND is_system_role = 0        -- never show system roles in user-facing dropdowns
    ORDER BY role_name;
END;
GO

---------------------------------------------------------------
-- 1.4 Sessions
---------------------------------------------------------------
IF OBJECT_ID('auth.user_sessions', 'U') IS NULL
BEGIN
    CREATE TABLE auth.user_sessions
    (
        session_id  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
        user_id     INT              NOT NULL,
        login_time  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        last_seen   DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        is_active   BIT              NOT NULL DEFAULT 1,
        client_info NVARCHAR(200)    NULL,
        client_app  NVARCHAR(50)     NOT NULL,
        correlation_id uniqueidentifier NULL,
        session_status NVARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
        created_at  DATETIME2(3)     NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at  DATETIME2(3)     

        CONSTRAINT FK_user_sessions_user
        FOREIGN KEY (user_id) REFERENCES auth.users(id)
    );
END;
GO

---------------------------------------------------------------
-- 1.5 Login attempts (audit)
---------------------------------------------------------------
IF OBJECT_ID('auth.login_attempts', 'U') IS NULL
BEGIN
    CREATE TABLE auth.login_attempts
    (
        id           BIGINT IDENTITY(1,1) PRIMARY KEY,
        username     NVARCHAR(100)  NOT NULL,
        attempt_time DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
        result_code  NVARCHAR(20)   NULL,
        success      BIT            NOT NULL DEFAULT 0,
        session_id   UNIQUEIDENTIFIER NULL,
        correlation_id uniqueidentifier NULL,
        ip_address   NVARCHAR(50)   NULL,
        client_info  NVARCHAR(200)  NULL,
        client_app   NVARCHAR(50)   NULL,
        os_info      NVARCHAR(200)  NULL
    );
END;
GO

CREATE OR ALTER PROCEDURE auth.usp_add_role
    @RoleName    NVARCHAR(100),
    @Description NVARCHAR(200) = NULL,
    @CreatedBy   INT,
    @NewRoleId   INT OUTPUT -- Returns the new ID to the caller
AS
BEGIN
    SET NOCOUNT ON;

    -- Basic Validation
    IF EXISTS (SELECT 1 FROM auth.roles WHERE role_name = @RoleName)
    BEGIN
        -- Option A: Throw an error
        THROW 51000, 'The role name already exists.', 1;
        
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO auth.roles (role_name, description, is_active, created_by)
        VALUES (@RoleName, @Description, DEFAULT, @CreatedBy);

        -- Capture the new Identity ID
        SET @NewRoleId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Re-throw the error
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

CREATE PROCEDURE auth.usp_update_role_by_name
    @RoleName       NVARCHAR(100),        -- The specific role to find
    @NewDescription NVARCHAR(200) = NULL, -- Pass NULL to keep existing description
    @NewRoleName    NVARCHAR(100) = NULL, -- Pass NULL to keep existing name
    @UpdatedBy      INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Identity Check: Ensure the role exists
    DECLARE @RoleId INT = (SELECT id FROM auth.roles WHERE role_name = @RoleName);
    
    IF @RoleId IS NULL
    BEGIN
        THROW 51000, 'The role specified for update does not exist.', 1;
    END

    -- 2. Collision Check: If renaming, ensure the NEW name isn't taken
    IF @NewRoleName IS NOT NULL AND @NewRoleName <> @RoleName
    BEGIN
        IF EXISTS (SELECT 1 FROM auth.roles WHERE role_name = @NewRoleName)
        BEGIN
             THROW 51000, 'The new role name is already taken by another role.', 1;
        END
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE auth.roles
        SET 
            -- If @NewRoleName is NULL, keep the old name
            role_name   = COALESCE(@NewRoleName, role_name),
            
            -- If @NewDescription is NULL, keep the old description
            description = COALESCE(@NewDescription, description),
            
            -- Audit fields
            updated_at  = SYSUTCDATETIME(),
            updated_by  = @UpdatedBy
        WHERE 
            id = @RoleId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO

IF OBJECT_ID('auth.fn_is_session_expired', 'FN') IS NULL
    EXEC('CREATE FUNCTION auth.fn_is_session_expired() RETURNS bit AS BEGIN RETURN 0; END');
GO

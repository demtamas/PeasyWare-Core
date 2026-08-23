USE [PW_Core_DEV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-------------------------------------------------------------------------
-- auth.fn_is_system_user
-- Returns 1 if the user holds any role with is_system_role = 1
-- (e.g. 'system', 'api'), 0 otherwise. Used by auth.fn_has_permission
-- to grant trusted automation identities a universal bypass.
-------------------------------------------------------------------------
CREATE OR ALTER FUNCTION auth.fn_is_system_user
(
    @user_id INT
)
RETURNS BIT
AS
BEGIN
    DECLARE @is_system BIT = 0;

    SELECT @is_system = 1
    FROM auth.users u
    JOIN auth.user_roles ur ON ur.user_id = u.id
    JOIN auth.roles r       ON r.id = ur.role_id
    WHERE u.id = @user_id
      AND r.is_system_role = 1;

    RETURN @is_system;
END;
GO

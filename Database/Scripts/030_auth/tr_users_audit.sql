USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER TRIGGER auth.tr_users_audit
ON auth.users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        old_is_active,
        new_is_active,
        changed_at,
        changed_by,
        session_id
    )
    SELECT
        i.id,
        'SET_ACTIVE',
        d.is_active,
        i.is_active,
        SYSUTCDATETIME(),
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.is_active, -1) <> ISNULL(i.is_active, -1);
END;
GO

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER TRIGGER auth.tr_users_security_audit
ON auth.users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @actor INT =
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT);
    DECLARE @session UNIQUEIDENTIFIER =
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER);

    -- Terminal lock triggered
    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        changed_at,
        changed_by,
        session_id,
        details
    )
    SELECT
        i.id,
        'TERMINAL_LOCK',
        @now,
        @actor,
        @session,
        CONCAT('failed_attempts=', i.failed_attempts)
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE d.must_change_password = 0
      AND i.must_change_password = 1;

    -- Failed attempts increment
    INSERT INTO audit.user_changes
    (
        user_id,
        action,
        changed_at,
        changed_by,
        session_id,
        details
    )
    SELECT
        i.id,
        'FAILED_LOGIN_ATTEMPT',
        @now,
        @actor,
        @session,
        CONCAT(
            'attempts=', i.failed_attempts,
            ', lockout_until=',
            COALESCE(CONVERT(NVARCHAR(30), i.lockout_until, 126), 'NULL')
        )
    FROM inserted i
    JOIN deleted d ON d.id = i.id
    WHERE ISNULL(d.failed_attempts, 0) <> ISNULL(i.failed_attempts, 0);
END;
GO


USE PW_Core_DEV;
GO

/* ============================================================
   Schema: locations
   Purpose: Physical warehouse structure & storage modelling
   ============================================================ */

/* ============================================================
   locations.storage_types
   ------------------------------------------------------------
   High-level storage category.
   Defines the physical and operational nature of storage.
   ============================================================ */
GO

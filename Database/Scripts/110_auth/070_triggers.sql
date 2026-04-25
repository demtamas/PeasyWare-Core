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

CREATE TABLE audit.user_changes
(
    audit_id        BIGINT IDENTITY PRIMARY KEY,
    user_id         INT NOT NULL,
    action          NVARCHAR(50) NOT NULL,

    old_is_active   BIT NULL,
    new_is_active   BIT NULL,

    details         NVARCHAR(1000),

    changed_at      DATETIME2 NOT NULL,
    changed_by      INT NULL,

    session_id      UNIQUEIDENTIFIER NULL
);
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

USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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

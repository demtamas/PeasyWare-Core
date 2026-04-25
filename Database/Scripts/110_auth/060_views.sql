USE msdb;
GO

--------------------------------------------------------------------------------
-- 1. Remove existing job if it exists (idempotent)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Session Cleanup Job')
BEGIN
EXEC msdb.dbo.sp_delete_job
@job_name = N'DEV PW Session Cleanup Job',
@delete_unused_schedule = 1;

DECLARE @schedule_id INT;

WHILE 1 = 1
BEGIN
    SELECT TOP (1) @schedule_id = schedule_id
    FROM msdb.dbo.sysschedules
    WHERE name = N'DEV PW Cleanup – Every 10 Minutes';

    IF @schedule_id IS NULL BREAK;

    EXEC msdb.dbo.sp_delete_schedule
        @schedule_id = @schedule_id;

    PRINT 'Deleted schedule_id = ' + CAST(@schedule_id AS NVARCHAR(20));

    SET @schedule_id = NULL;
END;
END
GO

--------------------------------------------------------------------------------
-- 2. Create Job
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name = N'DEV PW Session Cleanup Job',
    @enabled = 1,
    @description = N'Automatically clears timed-out PW_Core_DEV sessions.',
    @start_step_id = 1,
    @job_id = @job_id OUTPUT;

PRINT 'Job created. ID = ' + CONVERT(NVARCHAR(50), @job_id);
GO

--------------------------------------------------------------------------------
-- 3. Add Job Step
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Session Cleanup Job'
);

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @job_id,
    @step_id = 1,
    @step_name = N'Run Session Cleanup',
    @subsystem = N'TSQL',
    @command = N'EXEC PW_Core_DEV.auth.usp_session_cleanup;',
    @database_name = N'PW_Core_DEV',
    @on_success_action = 1,
    @on_fail_action = 2;
GO

--------------------------------------------------------------------------------
-- 4. Create Schedule (Every 10 minutes)
--------------------------------------------------------------------------------
DECLARE @schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'PW Cleanup – Every 10 Minutes',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 10,
    @active_start_time = 000000,
    @schedule_id = @schedule_id OUTPUT;

PRINT 'Schedule created. ID = ' + CONVERT(NVARCHAR(20), @schedule_id);

--------------------------------------------------------------------------------
-- 5. Attach schedule to job
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id 
    FROM msdb.dbo.sysjobs 
    WHERE name = N'DEV PW Session Cleanup Job'
);

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @job_id,
    @schedule_id = @schedule_id;

--------------------------------------------------------------------------------
-- 6. Enable job for this server
--------------------------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'DEV PW Session Cleanup Job',
    @server_name = @@SERVERNAME;

PRINT 'DEV PW Session Cleanup Job successfully installed + enabled.';
GO

USE PW_Core_DEV;
GO

--------------------------------------------------------------------------------
-- User lookup view
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Protect the system user
--------------------------------------------------------------------------------
GO

CREATE OR ALTER VIEW auth.v_active_sessions
AS
SELECT
    s.session_id,
    u.username,
    s.client_app,
    s.client_info,
    s.last_seen,
    s.is_active
FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id
WHERE s.is_active = 1;
GO

CREATE OR ALTER VIEW auth.vw_session_forensic
AS
SELECT
    s.session_id,
    s.is_active,
    s.login_time,
    s.last_seen,

    u.id            AS user_id,
    u.username,
    u.display_name,

    s.client_app,
    s.client_info,

    la.ip_address,
    la.os_info,
    la.correlation_id

FROM auth.user_sessions s
JOIN auth.users u
    ON u.id = s.user_id

OUTER APPLY
(
    SELECT TOP (1)
        a.ip_address,
        a.os_info,
        a.correlation_id
    FROM auth.login_attempts a
    WHERE a.session_id = s.session_id
      AND a.success = 1
    ORDER BY a.attempt_time DESC
) la;
GO

GO

CREATE OR ALTER PROCEDURE auth.usp_get_session_details
(
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM auth.vw_session_forensic
    WHERE session_id = @session_id;
END;
GO

CREATE OR ALTER VIEW auth.v_users_admin
AS

SELECT
    u.id,
    u.username,
    u.display_name,

    -- Role (defensive)
    COALESCE(r.role_name, '[MISSING ROLE]') AS role_name,

    u.email,

    -- ONLINE if at least one active session exists
    CAST(
        CASE
            WHEN MAX(CASE WHEN s.is_active = 1 THEN 1 ELSE 0 END) = 1
                THEN 1
            ELSE 0
        END
    AS bit) AS is_online,

    -- Most recent last_seen across ALL sessions
    MAX(s.last_seen) AS last_last_seen,

    u.is_active,
    u.must_change_password,
    u.failed_attempts,
    u.lockout_until,
    u.password_expires_at,

    u.created_at,
    u.created_by,
    u.updated_at,
    u.updated_by

FROM auth.users u

-- users may exist without a role (temporarily or due to config drift)
LEFT JOIN auth.user_roles ur
    ON u.id = ur.user_id

LEFT JOIN auth.roles r
    ON ur.role_id = r.id

LEFT JOIN auth.user_sessions s
    ON u.id = s.user_id

WHERE auth.fn_is_system_user(u.id) = 0

GROUP BY
    u.id,
    u.username,
    u.display_name,
    COALESCE(r.role_name, '[MISSING ROLE]'),
    u.email,
    u.is_active,
    u.must_change_password,
    u.failed_attempts,
    u.lockout_until,
    u.password_expires_at,
    u.created_at,
    u.created_by,
    u.updated_at,
    u.updated_by;
GO

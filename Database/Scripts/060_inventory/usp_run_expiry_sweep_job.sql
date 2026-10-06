USE msdb;
GO

--------------------------------------------------------------------------------
-- DEV PW Expiry Sweep Job
--------------------------------------------------------------------------------
-- Runs inventory.usp_run_expiry_sweep once daily at 00:05. Same structural
-- pattern as the session-cleanup job (auth/usp_session_cleanup_job.sql) -
-- genuinely part of the normal reset/build cycle, not a manual step, made
-- safe to re-run every time by the drop-then-recreate below.
--
-- The SYSTEM user's id is looked up dynamically inside the job step
-- rather than hardcoded - IDENTITY values aren't stable across a
-- reset-db, a name lookup is.
--
-- Owner is deliberately left unspecified (sp_add_job defaults it) rather
-- than set explicitly via ORIGINAL_LOGIN() - that seemed like the more
-- portable choice but actually broke on this machine: ORIGINAL_LOGIN()
-- resolves to a Microsoft Account login (MicrosoftAccount\...), which SQL
-- Server Agent's job-owner check can't resolve through Windows' security
-- APIs (error 0x54b) the way it can a plain Windows account. The default
-- behaviour, matching the proven session-cleanup job, avoids this entirely.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. Remove existing job if it exists (idempotent)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Expiry Sweep Job')
BEGIN
EXEC msdb.dbo.sp_delete_job
@job_name = N'DEV PW Expiry Sweep Job',
@delete_unused_schedule = 1;

DECLARE @schedule_id INT;

WHILE 1 = 1
BEGIN
    SELECT TOP (1) @schedule_id = schedule_id
    FROM msdb.dbo.sysschedules
    WHERE name = N'DEV PW Expiry Sweep – Daily 00:05';

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
    @job_name = N'DEV PW Expiry Sweep Job',
    @enabled = 1,
    @description = N'Flags PW_Core_DEV stock past its best-before date as EX (Expired). Runs daily.',
    @start_step_id = 1,
    @job_id = @job_id OUTPUT;

PRINT 'Job created. ID = ' + CONVERT(NVARCHAR(50), @job_id);
GO

--------------------------------------------------------------------------------
-- 3. Add Job Step
--------------------------------------------------------------------------------
-- @sys_user_id is looked up dynamically each run rather than hardcoded -
-- IDENTITY values restart after a reset-db, so a fixed number here could
-- silently point at the wrong user (or none) after one.
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'DEV PW Expiry Sweep Job'
);

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @job_id,
    @step_id = 1,
    @step_name = N'Run Expiry Sweep',
    @subsystem = N'TSQL',
    @command = N'DECLARE @sys_user_id INT = (SELECT id FROM PW_Core_DEV.auth.users WHERE username = N''system'');
EXEC PW_Core_DEV.inventory.usp_run_expiry_sweep @user_id = @sys_user_id;',
    @database_name = N'PW_Core_DEV',
    @on_success_action = 1,
    @on_fail_action = 2;
GO

--------------------------------------------------------------------------------
-- 4. Create Schedule (Once daily, 00:05)
--------------------------------------------------------------------------------
DECLARE @schedule_id INT;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'DEV PW Expiry Sweep – Daily 00:05',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,
    @active_start_time = 000500,
    @schedule_id = @schedule_id OUTPUT;

PRINT 'Schedule created. ID = ' + CONVERT(NVARCHAR(20), @schedule_id);

--------------------------------------------------------------------------------
-- 5. Attach schedule to job
--------------------------------------------------------------------------------
DECLARE @job_id UNIQUEIDENTIFIER =
(
    SELECT job_id
    FROM msdb.dbo.sysjobs
    WHERE name = N'DEV PW Expiry Sweep Job'
);

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @job_id,
    @schedule_id = @schedule_id;

--------------------------------------------------------------------------------
-- 6. Enable job for this server
--------------------------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'DEV PW Expiry Sweep Job',
    @server_name = @@SERVERNAME;

PRINT 'DEV PW Expiry Sweep Job successfully installed + enabled.';
GO

USE PW_Core_DEV;
GO

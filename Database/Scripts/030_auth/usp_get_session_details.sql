USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.usp_get_session_details
(
    @session_id UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM auth.v_session_forensic
    WHERE session_id = @session_id;
END;
GO

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

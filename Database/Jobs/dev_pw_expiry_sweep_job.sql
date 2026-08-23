USE [msdb]
GO

/****** Object:  Job [DEV PW Expiry Sweep Job] ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

-- Machine/login-independent: whoever runs this script becomes the
-- job owner, rather than a value baked in for one specific PC.
DECLARE @owner_login NVARCHAR(256) = ORIGINAL_LOGIN();

/****** Object:  JobCategory [[Uncategorized (Local)]] ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DEV PW Expiry Sweep Job',
		@enabled=1,
		@notify_level_eventlog=2,
		@notify_level_email=0,
		@notify_level_netsend=0,
		@notify_level_page=0,
		@delete_level=0,
		@description=N'Flags PW_Core_DEV stock past its best-before date as EX (Expired). Run daily.',
		@category_name=N'[Uncategorized (Local)]',
		@owner_login_name=@owner_login, @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Run Expiry Sweep] ******/
-- @user_id is looked up dynamically each run rather than hardcoded -
-- IDENTITY values restart after a reset-db, so a fixed number here
-- could silently point at the wrong user (or none) after one.
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run Expiry Sweep',
		@step_id=1,
		@cmdexec_success_code=0,
		@on_success_action=1,
		@on_success_step_id=0,
		@on_fail_action=2,
		@on_fail_step_id=0,
		@retry_attempts=0,
		@retry_interval=0,
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'DECLARE @sys_user_id INT = (SELECT id FROM PW_Core_DEV.auth.users WHERE username = N''SYSTEM'');
EXEC PW_Core_DEV.inventory.usp_run_expiry_sweep @user_id = @sys_user_id;',
		@database_name=N'PW_Core_DEV',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
-- Once daily, shortly after midnight - freq_subday_type=1 means
-- "once", not an interval, unlike the session-cleanup job's every-10-minutes
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'PW Expiry Sweep – Daily 00:05',
		@enabled=1,
		@freq_type=4,
		@freq_interval=1,
		@freq_subday_type=1,
		@freq_subday_interval=0,
		@freq_relative_interval=0,
		@freq_recurrence_factor=0,
		@active_start_date=20260817,
		@active_end_date=99991231,
		@active_start_time=000500,
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

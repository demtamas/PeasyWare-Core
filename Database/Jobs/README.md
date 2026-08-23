# Database/Jobs

SQL Server Agent job creation scripts. **Not** part of the `Database/Scripts/`
tree, and deliberately so — `pwtools reset-db` only ever walks
`Database/Scripts/` (see `ResetDbCommand.CollectScripts`), so nothing here
is touched by a reset, automatically or otherwise.

## Why these live outside `Database/Scripts/`

Everything under `Database/Scripts/` is written to survive being re-run —
`CREATE OR ALTER`, `IF NOT EXISTS` guards — because `reset-db` genuinely
re-runs the whole set every time the database is rebuilt. These scripts
don't follow that convention, and shouldn't:

- They create objects in **`msdb`**, not `PW_Core_DEV`. A database reset
  drops and rebuilds `PW_Core_DEV` only — `msdb` and any jobs in it are
  completely untouched by that process, reset or not.
- `sp_add_job` is **not idempotent**. Running one of these a second time
  errors out, since a job with that name already exists — there's no
  `IF NOT EXISTS` guard here the way there is everywhere else.
- The intent is "run once, ever, per machine" — not "run on every reset."
  A job created here keeps running against whatever `PW_Core_DEV` currently
  looks like, reset or not, without ever needing to be recreated.

## How to use these

Run manually in SSMS, connected to the target server (each script starts
with `USE [msdb]`, so the database dropdown doesn't matter). Check
SQL Server Agent → Jobs afterward to confirm it was created, then enable
its schedule if it isn't already.

If a script needs re-running after a mistake, drop the job first
(`msdb.dbo.sp_delete_job @job_name = N'...'`) rather than re-running the
script over an existing job of the same name.

## What's here

| File | Creates | Schedule |
|---|---|---|
| `dev_pw_session_cleanup_job.sql` | `DEV PW Session Cleanup Job` — clears timed-out sessions via `auth.usp_session_cleanup` | Every 10 minutes |
| `dev_pw_expiry_sweep_job.sql` | `DEV PW Expiry Sweep Job` — flags expired stock via `inventory.usp_run_expiry_sweep` | Daily, 00:05 |

## Adding a new job

`dev_pw_expiry_sweep_job.sql` is the more current template of the two —
it uses `ORIGINAL_LOGIN()` for a portable job owner rather than a
hardcoded machine/user string, and looks up any account-specific values
(like the SYSTEM user's id) dynamically inside the job step rather than
hardcoding them, since `IDENTITY` values aren't stable across a
`reset-db` the way a lookup by name is.

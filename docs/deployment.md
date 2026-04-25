# PeasyWare — Deployment & Environment Guide

## Required environment variables

All PeasyWare applications fail at startup if required environment variables are missing.
This is intentional — a misconfigured deployment that silently connects to the wrong database
is more dangerous than a hard failure with a clear message.

### PeasyWare.CLI and PeasyWare.Desktop

| Variable | Required | Description |
|---|---|---|
| `PEASYWARE_DB` | Yes (Release) | SQL Server connection string |

Example:
```
PEASYWARE_DB=Server=myserver;Database=PW_Core;Trusted_Connection=True;TrustServerCertificate=True;
```

In DEBUG builds, `PEASYWARE_DB` falls back to `localhost` / `PW_Core_DEV` if not set.
In Release builds, the application throws immediately at startup if the variable is missing.

### PeasyWare.API

| Variable | Required | Description |
|---|---|---|
| `PEASYWARE_DB` | Yes (Release) | SQL Server connection string |
| `PEASYWARE_API_KEY` | Yes (always) | API key for X-Api-Key header authentication |

Both variables are required in Release. The API also throws at startup if either is missing.

In DEBUG builds, `PEASYWARE_API_KEY` can be set in `launchSettings.json`
(value: `dev-api-key-change-me`). Do not use this key in production.

---

## Setting environment variables

### Windows — system-wide (survives reboots, recommended for servers)

1. Press `Win + R`, type `sysdm.cpl`, press Enter
2. Advanced → Environment Variables → System variables → New
3. Add each variable with its value
4. Restart any open terminals or Visual Studio

### Windows — current session only (PowerShell)

```powershell
$env:PEASYWARE_DB      = "Server=...;Database=...;"
$env:PEASYWARE_API_KEY = "your-api-key-here"
```

### Windows — Visual Studio (Debug only, per-project)

Add to `Properties/launchSettings.json` under `environmentVariables`:

```json
{
  "environmentVariables": {
    "PEASYWARE_DB": "Server=localhost;Database=PW_Core_DEV;...",
    "PEASYWARE_API_KEY": "dev-api-key-change-me"
  }
}
```

---

## Startup failure messages

If a required variable is missing, the application prints a clear message and exits:

```
FATAL: Startup failed.
Required environment variable 'PEASYWARE_DB' is not set.
Set it to a valid SQL Server connection string before starting the application.
```

**Resolution:** Set the missing environment variable (see above) and restart the application.
If running as a service, restart the service after updating the environment.

---

## Pre-deployment checklist

Before running a Release build for the first time on a new machine:

- [ ] `PEASYWARE_DB` is set and points to the correct database
- [ ] `PEASYWARE_API_KEY` is set (API only) — use a strong random value, not the dev default
- [ ] Database schema is current — run `DEV_AllInOneInOneGo.sql` (DEV) or the equivalent production script
- [ ] `api` user exists in `auth.users` — seeded by `DEV_Test_Data_Samples.sql` or equivalent
- [ ] Test a Release build locally before deploying — `dotnet run --configuration Release`
- [ ] Confirm the application starts cleanly and connects to the correct database

---

## Database

PeasyWare uses SQL Server. The connection string format is:

```
Server=<host>;Database=<dbname>;Trusted_Connection=True;TrustServerCertificate=True;
```

For SQL authentication (username/password):

```
Server=<host>;Database=<dbname>;User Id=<user>;Password=<password>;TrustServerCertificate=True;
```

**Never put connection strings in source code or committed config files.**
Always use the `PEASYWARE_DB` environment variable.

---

## API key management

- Generate a strong random API key for each environment (production, staging, etc.)
- Store it in the environment variable, not in config files
- Rotate the key by updating the environment variable and restarting the API
- The key is validated on every request — there is no session or token caching
- In a future multi-tenant scenario, per-client API keys will require a key management table; the current single-key model is intentional for now

---

## Notes on informal environments

PeasyWare's current deployment story is informal — there is no CI/CD pipeline, no automated packaging, and no environment provisioning tooling. This is acceptable for the current development stage.

The hard startup failure on missing environment variables was introduced deliberately to make misconfiguration visible immediately rather than silently. As deployment becomes more formal (Docker, Windows Service, IIS hosting), the environment variable provisioning step should be part of the deployment runbook, not a manual memory item.

Until formal deployment tooling exists:
- Test Release builds locally before any handover
- Document which environment variables are set on each target machine
- Keep this guide updated when new required variables are added

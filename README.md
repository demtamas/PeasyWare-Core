# PeasyWare-Core

![PeasyWare Logo](src/Assets/peasyware-logo.svg)

**PeasyWare** is a professional-grade **Warehouse Management System (WMS)** built in C#/.NET 10 with SQL Server, modelling real warehouse operations end to end.

Built with reference to enterprise platforms such as **SAP EWM**, **Manhattan WMS**, and **Blue Yonder** — from the ground up, with production-quality design principles. Designed for single-site and 3PL environments.

---

## Tech stack

- C# / .NET 10
- SQL Server — write operations and business logic in stored procedures; read operations via views
- No ORM — raw ADO.NET with named parameter mapping
- Event-stream audit trail (`audit.trace_logs`) with structured JSON payload
- Desktop + CLI: Windows. CLI only: macOS, Linux

---

## Architecture

```
CLI (RF-style terminal)        Desktop Application
         │                             │
         └──────────────┬──────────────┘
                        ▼
            Application Layer
          Flows / Services / DTOs
                        │
                        ▼
           Infrastructure Layer
         SQL Repositories / Bootstrap
                        │
                        ▼
              SQL Server Database
         Schemas: inventory, inbound,
         outbound, warehouse, locations,
         operations, auth, audit, core
```

**Design principles:**
- Every process has a Reversal Path
- Every operation carries a Correlation ID
- Every mutating stored procedure enforces RBAC via `auth.fn_has_permission`, checked first, inside the transaction
- All SPs use `SET XACT_ABORT ON` + `BEGIN CATCH`
- Error codes follow `ERRAUTH01` pattern (prefix ERR/WAR/SUC, no hyphens)
- `UPDLOCK, HOLDLOCK` on concurrent reads
- Bin and reference lookups enforce case sensitivity (`COLLATE Latin1_General_CS_AS`)

---

## Warehouse Lifecycle

```
Supplier ASN / Manual Receive
         │
         ▼
Inbound Receiving (SSCC or Manual mode)
│  Cross-receive locked — each inbound
│  only accepts its own SSCCs
         │
         ▼
Inventory Unit Created (RCD state)
         │
         ▼
Putaway Task → Operator confirms → PTW state
│  Bin-to-bin move out of staging = manual
│  putaway, transitions RCD → PTW automatically
         │
         ▼
Bin-to-Bin Movement (optional, supervisor-initiated)
         │
         ▼
Outbound Order → Allocation Engine (FEFO / FIFO / LIFO / NONE)
│  Full or partial allocation — operator prompted
│  when stock is insufficient for full order
         │
         ▼
Pick Task → Operator scans bin + SSCC → PKD state
         │
         ▼
Load Confirmation → Ship Confirmation → SHP state
│  Delivery note auto-printed if configured
         │
         ▼
Unit removed from warehouse, audit trail complete
```

---

## Quick Start

### 1 — Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- SQL Server (Express or Developer edition is fine)
- `sqlcmd` on PATH — install via [SQL Server command-line tools](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility)

### 2 — Clone

```bash
git clone https://github.com/demtamas/PeasyWare-Core.git
cd PeasyWare-Core
```

### 3 — Set environment variables

These must be set **before** building or running anything.

#### `PEASYWARE_DB` — SQL Server connection string (required)

**Windows (PowerShell — session):**
```powershell
$env:PEASYWARE_DB = "Server=localhost;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```

**Windows (permanent — survives reboots):**
```powershell
[System.Environment]::SetEnvironmentVariable(
    "PEASYWARE_DB",
    "Server=localhost;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;",
    "Machine"
)
```

**macOS / Linux:**
```bash
export PEASYWARE_DB="Server=localhost;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```

> `TrustServerCertificate=True` is required for local SQL Server instances with self-signed certificates (default on most dev setups). `pwtools reset-db` reads this from the connection string and passes `-C` to sqlcmd automatically.

> For Windows Authentication, replace `User Id=sa;Password=...` with `Trusted_Connection=True`.

#### `PEASYWARE_API_KEY` — API key (required for seeding only)

The REST API requires a shared secret passed as `X-Api-Key`. Choose any string — it just needs to match on both the API server and the seed script caller.

```powershell
$env:PEASYWARE_API_KEY = "peasyware-dev-key"
```

Set this on any machine that will run the API **or** the seed scripts. Both sides must have the same value.

### 4 — Build

```powershell
dotnet build
```

### 5 — Database

Reset (or create fresh) the database schema:

```powershell
tools\PeasyWare.Tools\bin\Debug\net10.0\pwtools.exe reset-db --confirm
```

This runs all 90+ scripts in `Database/Scripts/` in order against the database defined in `PEASYWARE_DB`. On a fresh install it creates the database from scratch. On an existing install it backs up and drops first.

### 6 — Test data (optional)

Seed SKUs, inbounds, outbound orders, and shipments via the REST API:

```powershell
# Terminal 1 — start the API
dotnet run --project src/PeasyWare.API

# Terminal 2 — run seeds
cd Database/Seeds
.\run_seeds.ps1              # all test data
.\run_seeds.ps1 -Only 1      # SKUs only
.\run_seeds.ps1 -Only 2      # Inbounds only
.\run_seeds.ps1 -Only 1,2    # SKUs + Inbounds
```

> `PEASYWARE_API_KEY` must be set and the API must be running before seeds will work.

### 7 — Run

```powershell
# RF-style terminal (CLI) — Windows, macOS, Linux
dotnet run --project src/PeasyWare.CLI

# Desktop application — Windows only
dotnet run --project src/PeasyWare.Desktop
```

Initial credentials: `admin` / `admin0` — password change required on first login (min 8 chars, uppercase + lowercase + number).

### 8 — Tests

```bash
dotnet test
```

---

## Features

### Inbound
- Create delivery advice (ASN) from Desktop — header, lines, expected SSCCs
- Cancel inbound — blocked if any receipts exist
- SSCC mode receive with GS1-128 barcode parser (parenthesis, raw FNC1, tilde formats)
- Manual mode receive — two-label scan (product + pallet)
- Claim token pattern — prevents concurrent SSCC receives
- Cross-receive lock — receiving session bound to its own inbound
- Receipt reversal with full audit chain
- `is_batch_required` and `standard_hu_quantity` enforced per SKU
- Desktop view — status, progress, line drill-down, SSCC-level detail with received by / at

### Inventory
- State machine (`RCD → PTW → MOV/PKD → SHP/REV`)
- Bin placements — rack (capacity 1) and bulk (capacity-based)
- SSCC enquiry — UiMode-tiered display (Minimal / Standard / Trace)
- Bin enquiry — single unit detail or multi-unit summary with drill-down
- Stock owner per SKU — single-owner or multi-owner (3PL) via `inventory.enable_multi_owner`
- Manual bin-to-bin move out of staging automatically transitions `RCD → PTW`
- Desktop view — owner, state, status, allocation reference, search

### Warehouse Tasks
- Putaway — zone load balancing, bin reservation, TTL expiry
- Bin-to-bin movement — operator or system initiated
- Pick tasks — allocation-driven, operator-specified staging bay
- Supervisor Desktop view — cancel orphaned tasks, filter by type, creator and completer columns

### Outbound
- Create orders from Desktop — customer, haulier, required date, lines (SKU / qty / batch / BBE)
- Cancel orders — NEW status only
- Allocation engine — FEFO / FIFO / LIFO / NONE (settings-driven)
- Partial allocation with operator prompt
- Re-allocation and top-up allocation during active picking
- Pick flow — bin scan validated before SSCC prompt
- Load and ship confirmation
- Delivery addresses per order — supports multi-depot customers
- Create shipments from Desktop — haulier, vehicle, planned departure, add orders
- Cancel shipments — OPEN / LOADING only, blocked if orders in progress
- Delivery note — generated on ship, opens in browser or prints silently to named printer

### Parties
- Suppliers, customers, hauliers, owners, warehouse — multi-role per party
- Create and edit from Desktop Parties view
- Filterable by role — All / Suppliers / Customers / Hauliers / Owners
- Owner party assignment per SKU for 3PL mode

### Materials (SKU Management)
- Create, edit, copy from Desktop
- Owner assignment, storage type, section, batch / full-HU flags
- Full audit trail — before/after change log

### Logs and Audit
- Event log view — full `audit.trace_logs` with level filter, date range, text search
- JSON payload preview panel — click any row to see full structured payload
- Correlation ID filter — click to show all events on the same operation
- Login attempts view — pre-filtered to auth events
- User changes view — unified timeline from trigger (`user_changes`) and trace log sources
- Movement log — full pallet lifecycle (INBOUND → PUTAWAY → PICK → SHIP) with reference resolution
- SKU audit — before/after change log per SKU

### Printing
- `printing.auto_print_delivery_note` — silent print on ship if enabled
- `printing.delivery_note_printer` — named printer
- `printing.delivery_note_copies` — 1–5 copies
- HTML delivery note template in `Database/Templates/delivery_note.html` — customisable without recompiling
- Template auto-located by walking up from binary; inline fallback if not found

### Infrastructure
- Role-based access control (RBAC) — verb-on-resource permissions (`auth.permissions` / `auth.role_permissions`), enforced in every mutating stored procedure via `auth.fn_has_permission`, mirrored in Desktop and CLI UI gating
- Role-based UiMode (Minimal / Standard / Trace) — system ceiling enforced
- Session management — TTL, heartbeat, force login, concurrent session guard
- Structured audit log with JSON payload (`audit.trace_logs`)
- Error message resolver — all codes in DB, operator-facing message + tech note
- Settings registry — all runtime config in `operations.settings`, editable from Desktop

---

## 3PL / Multi-Owner Mode

When `inventory.enable_multi_owner = true`:

- Every SKU must be assigned an owner party (from `core.parties` with role `OWNER`)
- Owner flows through to inventory view, reports, and audit trail
- When disabled (default), all stock is implicitly owned by `inventory.default_owner_party_code`

Toggle via Settings view or directly in `operations.settings`.

---

## Project Status

**v0.9 — Core warehouse lifecycle complete**

Full warehouse loop operational across both CLI and Desktop:
Receive → Putaway → Move → Allocate (full/partial) → Pick → Load → Ship → Delivery note

**Role-based access control (RBAC) complete**

Verb-on-resource permission model (`auth.permissions` / `auth.role_permissions`),
enforced at the stored-procedure layer via `auth.fn_has_permission` across every
mutating operation, with matching gating in both Desktop and CLI. Denial and
grant coverage tested per permission category, including bootstrap and
system-role edge cases.

**Next milestone: v1.0**
- Concurrency proof harness for task claiming
- Production hardening and edge case test coverage

---

## License

MIT License

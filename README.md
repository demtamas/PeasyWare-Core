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
         │
         ▼
Unit removed from warehouse, audit trail complete
```

---

## Quick Start

### 1 — Clone

```bash
git clone https://github.com/demtamas/PeasyWare-Core.git
cd PeasyWare-Core
```

### 2 — Database

Build the tools project, then reset the database schema from scripts:

```powershell
dotnet build
tools\PeasyWare.Tools\bin\Debug\net10.0\pwtools.exe reset-db --confirm
```

Scripts are in `Database/Scripts/` (90+ files, executed in order). Installs all schemas, stored procedures, views, reference data, error codes, settings, and roles.

### 3 — Test data (optional)

With the API running, seed test SKUs, inbounds, and outbound orders:

```powershell
cd Database/Seeds
.\run_seeds.ps1              # all test data
.\run_seeds.ps1 -Only 1      # SKUs only
.\run_seeds.ps1 -Only 2      # Inbounds only
.\run_seeds.ps1 -Only 1,2    # SKUs + Inbounds
```

Requires `PEASYWARE_API_KEY` env var set, and the API running on `http://localhost:5000`.

### 4 — Connection string

The app resolves the connection string in this order:

1. **Environment variable** `PEASYWARE_DB` ← required in production, preferred everywhere
2. **DEBUG builds only** — hardcoded fallback to `localhost` if env var not set

**Windows (PowerShell):**
```powershell
$env:PEASYWARE_DB = "Server=localhost;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```

**macOS / Linux:**
```bash
export PEASYWARE_DB="Server=localhost;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```

### 5 — Build and run

```powershell
dotnet build

# RF-style terminal (CLI) — Windows, macOS, Linux
dotnet run --project src/PeasyWare.CLI

# Desktop application — Windows only
dotnet run --project src/PeasyWare.Desktop
```

Initial credentials: `admin` / `admin0` — password change required on first login (min 8 chars, uppercase + lowercase + number).

### 6 — Tests

```bash
dotnet test
```

---

## Features

### Inbound
- Delivery advice (ASN) with pre-advised units — SSCC mode
- Manual receive — two-label scan (product + pallet)
- GS1-128 barcode parser — parenthesis, raw FNC1, tilde formats
- Claim token pattern — prevents concurrent SSCC receives
- Cross-receive lock — receiving session bound to its own inbound
- Receipt reversal with full audit chain
- `is_batch_required` and `standard_hu_quantity` enforced per SKU
- Desktop inbound view — status, progress, line drill-down, SSCC-level detail

### Inventory
- Inventory units with state machine (`RCD → PTW → MOV/PKD → SHP/REV`)
- Bin placements — rack (capacity 1) and bulk (capacity-based)
- SSCC enquiry — UiMode-tiered display (Minimal / Standard / Trace)
- Bin enquiry — single unit detail or multi-unit summary with drill-down
- Stock owner per SKU — single-owner or multi-owner (3PL) mode via `inventory.enable_multi_owner` setting
- Manual bin-to-bin move out of staging automatically transitions `RCD → PTW`
- Desktop inventory view — owner column, status change, search across all fields

### Warehouse Tasks
- Putaway — zone load balancing, bin reservation, TTL expiry
- Bin-to-bin movement — operator or system initiated; inactive bin returns specific error
- Pick tasks — allocation-driven, operator-specified staging bay
- Supervisor Desktop view — cancel orphaned tasks, filter by type (PUTAWAY / PICK / MOVE), creator and completer columns

### Outbound
- Orders with lines (requested batch / BBE per line)
- Allocation engine — FEFO / FIFO / LIFO / NONE (settings-driven)
- Partial allocation — operator prompted when stock is insufficient; commits what's available
- Re-allocation and top-up allocation during active picking
- Pick flow — bin scan validated before SSCC prompt
- Load and ship confirmation — units transition to SHP, shipment closed
- Delivery address per order — supports multi-depot customers
- Desktop order management — allocate, partial allocate, cancel, deallocate, order detail
- Desktop shipments view — drill-down to orders, drill-down to order detail

### Materials (SKU Management)
- Create, edit, copy SKUs from Desktop
- Owner assignment per SKU — dropdown populated from parties with OWNER role
- Preferred storage type and section
- Batch requirement and full-HU enforcement flags
- Full audit trail — before/after change log including owner changes

### Desktop Application
- Inbound view — all deliveries with progress; drill-down to lines and SSCCs
- Inventory view — active stock with owner, state, status, allocation reference
- Orders view — filter by Outstanding / Departed / All; delivery address columns
- Shipments view — filter by Active / Shipped / All; order drill-down
- Warehouse Tasks view — type filter, creator / completer, cancel tasks
- Materials (SKU) management — create, edit, copy, audit log
- User and session management
- Audit log — SKU change history with before/after comparison

### Infrastructure
- Role-based UiMode (Minimal / Standard / Trace) — system ceiling enforced
- Session management — TTL, heartbeat, force login, concurrent session guard
- Structured audit log with JSON payload (`audit.trace_logs`)
- Error message resolver — all codes in DB, operator-facing message + tech note
- `inventory.enable_multi_owner` setting — off by default; when enabled, owner required on all SKUs
- `outbound.allocation_strategy` setting — FEFO / FIFO / LIFO / NONE
- `inventory.default_owner_party_code` — fallback owner when multi-owner is disabled

---

## 3PL / Multi-Owner Mode

PeasyWare supports multi-owner warehousing (3PL). When `inventory.enable_multi_owner = true`:

- Every SKU must be assigned an owner party (from `core.parties` with role `OWNER`)
- Owner flows through to inventory view, reports, and audit trail
- When disabled (default), all stock is implicitly owned by the configured default party

Toggle via the Settings view or directly in `operations.settings`.

---

## Project Status

**v0.9 — Core warehouse lifecycle complete**

Full warehouse loop operational across both CLI and Desktop:
Receive → Putaway → Move → Allocate (full/partial) → Pick → Load → Ship

**Recent additions:**
- Multi-owner / 3PL support at SKU level
- Inbound Desktop view with line and SSCC drill-down
- Delivery addresses on outbound orders (multi-depot)
- Partial allocation with operator prompt
- Cross-receive lock — inbound receiving bound to specific inbound
- Manual putaway via bin-to-bin move (RCD→PTW on staging exit)
- Shipment drill-down to orders and order detail

**Next milestone: v1.0**
- Role-based access controls on Desktop views
- Create inbound / outbound / shipment forms in Desktop
- Party management (suppliers, customers, hauliers)
- Movement and event log views
- Production hardening and edge case test coverage

---

## License

MIT License

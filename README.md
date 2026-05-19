# PeasyWare-Core

![PeasyWare Logo](src/Assets/peasyware-logo.svg)

**PeasyWare** is a professional-grade **Warehouse Management System (WMS)** built in C#/.NET 10 with SQL Server, modelling real warehouse operations end to end.

Built with reference to enterprise platforms such as **SAP EWM**, **Manhattan WMS**, and **Blue Yonder** — from the ground up, with production-quality design principles.

---

## Tech stack

- C# / .NET 10
- SQL Server — write operations and business logic in stored procedures; read operations via views
- No ORM — raw ADO.NET with named parameter mapping
- Event-stream audit trail (`audit.trace_logs`)
- Windows (Desktop + CLI) / macOS (CLI)

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
         │
         ▼
Inventory Unit Created (RCD state)
         │
         ▼
Putaway Task → Operator confirms → PTW state
         │
         ▼
Bin-to-Bin Movement (optional)
         │
         ▼
Outbound Order → Allocation Engine (FEFO / FIFO / LIFO / NONE)
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

Build the tools project, then use `pwtools` to reset and seed the database:

```powershell
dotnet build
tools\PeasyWare.Tools\bin\Debug\net10.0\pwtools.exe reset-db --confirm
```

Scripts are in `Database/Scripts/` (90 files, executed in order). Seeds include reference data, bins, test inbounds, orders, and shipments.

### 3 — Connection string

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

### 4 — Build and run

```bash
dotnet build

# RF-style terminal (CLI)
dotnet run --project src/PeasyWare.CLI

# Desktop application (Windows)
dotnet run --project src/PeasyWare.Desktop
```

Initial credentials: `admin` / `admin0` — password change required on first login (min 8 chars, uppercase + lowercase + number).

### 5 — Tests

```bash
dotnet test
```

---

## Features

### Inbound
- Delivery advice (ASN) with expected units — SSCC mode
- Manual receive — two-label scan (product + pallet)
- GS1-128 barcode parser — parenthesis, raw FNC1, tilde formats
- Claim token pattern — prevents concurrent SSCC receives
- Receipt reversal with full audit chain
- `is_batch_required` and `standard_hu_quantity` enforced per SKU

### Inventory
- Inventory units with state machine (`RCD → PTW → MOV/PKD → SHP/REV`)
- Bin placements — rack (capacity 1) and bulk (capacity-based)
- SSCC enquiry — UiMode-tiered display (Minimal / Standard / Trace)
- Bin enquiry — single unit detail or multi-unit summary with drill-down

### Warehouse Tasks
- Putaway — zone load balancing, bin reservation, TTL expiry
- Bin-to-bin movement — operator or system initiated
- Pick tasks — allocation-driven, operator-specified staging bay
- Supervisor Desktop view — cancel orphaned tasks, filter by state

### Outbound
- Orders with lines (requested batch / BBE per line)
- Allocation engine — FEFO / FIFO / LIFO / NONE (settings-driven)
- Re-allocation and top-up allocation during active picking
- Pick flow — bin scan validated before SSCC prompt
- Load and ship confirmation — units transition to SHP, shipment closed
- Desktop order management — allocate, cancel, deallocate, order detail

### Desktop Application
- Inventory view — full active stock, status change
- Orders view — filter by Outstanding / Departed / All
- Shipments view — filter by Active / Shipped / All
- Warehouse Tasks view — cancel tasks, show all / active toggle
- Materials (SKU) management with audit trail view
- User and session management

### Infrastructure
- Role-based UiMode (Minimal / Standard / Trace) — system ceiling enforced
- Session management — TTL, heartbeat, force login, concurrent session guard
- Structured audit log with JSON payload (`audit.trace_logs`)
- Error message resolver — all codes in DB, operator-facing message + tech note

---

## Project Status

**v0.9 — Core warehouse lifecycle complete**

Full warehouse loop operational across both CLI and Desktop:
Receive → Putaway → Move → Query → Allocate → Pick → Load → Ship

Next milestone: **v1.0** — production hardening, API layer, role-based access controls on Desktop views.

---

## License

MIT License

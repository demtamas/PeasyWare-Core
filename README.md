# PeasyWare-Core

![PeasyWare Logo](src/Assets/peasyware-logo.svg)

Core architecture of **PeasyWare** — a professional-grade **Warehouse Management System (WMS)** built in C#/.NET Core with SQL Server, modelling real warehouse operations end to end.

PeasyWare implements the core domain concepts found in enterprise platforms such as **SAP EWM**, **Manhattan WMS**, and **Blue Yonder** — built from the ground up with production-quality design principles.

---

## Overview

PeasyWare is a WMS architecture project demonstrating how inventory moves through a warehouse and how software coordinates those movements. It is designed as a standalone system capable of operating independently or integrating with external platforms (ERP, EDI, API).

**Tech stack:**
- C# / .NET 10
- SQL Server (thick-DB — all business logic in stored procedures)
- No ORM — raw ADO.NET with named parameter mapping
- Event-stream audit trail (`audit.trace_logs`)
- Cross-platform — runs on Windows and macOS

---

## Architecture

```
CLI (RF-style terminal)     Desktop Application (future)
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
         Schemas: inventory, deliveries,
         outbound, warehouse, locations,
         operations, auth, audit, core
```

**Design principles:**
- Every process has a Reversal Path
- Every operation carries a Correlation ID
- All SPs use `SET XACT_ABORT ON` + `BEGIN CATCH`
- Error codes follow `ERRAUTH01` pattern (prefix ERR/WAR/SUC, no hyphens)
- `UPDLOCK, HOLDLOCK` on concurrent reads
- `SCOPE_IDENTITY()` ordering discipline enforced throughout

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
Putaway Task Generated → Operator confirms → PTW state
         │
         ▼
Bin-to-Bin Movement (MOV state, operator or system)
         │
         ▼
Outbound Order Created → Allocation Engine (FEFO/FIFO/NONE)
         │
         ▼
Pick Task Generated → Operator scans bin + SSCC → PKD state
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

Run these scripts in SSMS against your SQL Server instance, in order:

```
Database/DEV/DEV_AllInOneInOneGo.sql   ← full schema + seed data
Database/DEV/DEV_Test_Data_Samples.sql ← test inbounds, orders, shipment
```

### 3 — Connection string

The app resolves the connection string in this order:

1. **Environment variable** `PEASYWARE_DB` ← required in production, preferred everywhere
2. **DEBUG builds only** — hardcoded fallback to `localhost` if env var not set

> **Release builds will throw at startup** if `PEASYWARE_DB` is not set. This is intentional — silent fallback to a wrong database in production is more dangerous than a clear startup failure.

Set the environment variable on your machine:

**Windows (PowerShell):**
```powershell
$env:PEASYWARE_DB = "Server=192.168.x.x;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```
Add to your PowerShell profile to make it permanent.

**macOS / Linux:**
```bash
export PEASYWARE_DB="Server=192.168.x.x;Database=Pw_Core_DEV;User Id=sa;Password=yourpassword;TrustServerCertificate=True;"
```
Add to `~/.zshrc` or `~/.bash_profile` to make it permanent.

No code changes needed between machines.

### 4 — Build and run

```bash
dotnet build
dotnet run --project src/PeasyWare.CLI
```

Initial credentials: `admin` / `admin0` — you will be prompted to change the password on first login (min 8 chars, must contain uppercase, lowercase, and a number).

### 5 — Tests

```bash
dotnet test
```

108 tests covering GS1-128 barcode parsing, UiMode ordering, inbound receiving service delegation, LoginFlow UiMode resolution, SessionGuard expiry, and RepositoryBase.BuildResult logging.

---

## Features Implemented

### Inbound
- Delivery advice (ASN) with expected units (SSCC mode)
- Manual receive mode — two-label scan (product + pallet)
- GS1-128 barcode parser — parenthesis, raw FNC1, tilde formats
- Claim token pattern — prevents concurrent SSCC receives
- Receipt reversal with full audit chain
- `is_batch_required` and `standard_hu_quantity` per SKU

### Inventory
- Inventory units with state machine (RCD → PTW → MOV/PKD → SHP/REV)
- Bin placements — rack (capacity 1) and bulk (capacity-based mixing)
- `v_active_inventory` — canonical active stock view
- SSCC enquiry with UiMode-tiered display (Minimal / Standard / Trace)
- Bin enquiry — single unit detail or multi-unit summary with drill-down

### Warehouse Tasks
- Putaway tasks — zone load balancing, bin reservation, TTL expiry
- Bin-to-bin movement — operator or system initiated, MOV state lock
- Pick tasks — allocation-driven, operator-specified staging bay
- All tasks: source bin, destination bin, timestamps, completed by

### Outbound
- Customer orders with lines (requested batch / BBE per line)
- Allocation engine — FEFO / FIFO / LIFO / NONE (settings-driven)
- Full-pallet allocation, all-or-nothing rollback
- Pick flow — bin scan validated client-side before SSCC prompt
- Load confirmation — order-level, no SSCC scanning required
- Ship confirmation — transitions all units to SHP, closes shipment
- One shipment → many orders; one order → one shipment

### Infrastructure
- Role-based UiMode (Minimal / Standard / Trace) — system ceiling enforced
- Session management — TTL, force login, concurrent session guard
- Structured audit log (`audit.trace_logs`) with JSON payload
- Error message resolver — all error/success codes in DB, operator-facing + tech note
- Cross-platform — tested on Windows and macOS

---

## Documentation

```
docs/
  inbound-receiving.md   ← SSCC and Manual mode, data flow, traceability
  outbound.md            ← Order → allocate → pick → load → ship
  putaway-strategy.md
  warehouse-model.md
  architecture.md
```

---

## Project Status

**v0.9 — Core warehouse lifecycle complete (CLI)**

The full warehouse loop is operational:
Receive → Putaway → Move → Query → Pick → Load → Ship

Next milestones:
- v1.0 — API layer (REST endpoints over existing SPs)
- v1.x — Desktop application (order management, stock enquiry dashboard)

---

## Inspiration

Built with reference to real warehouse operations across multiple sites and enterprise systems including SAP EWM, RedPrairie/JDA Dispatcher, Reflex, and legacy DOS-based WMS platforms.

---

## License

MIT License

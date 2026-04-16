# Inbound Receiving — Data Flow & Traceability Model

## Overview

The inbound receiving process in PeasyWare establishes a complete, unbroken audit chain
from a supplier delivery advice through to physical inventory placement in a staging bin.
Every row in every table is traceable back to every other row in the chain.

PeasyWare supports two receiving modes, determined at activation:

| Mode | When used | Key characteristic |
|------|-----------|-------------------|
| **SSCC** | Supplier has pre-advised individual handling unit SSCCs via ASN / EDI | Two-scan confirm per pallet; claim token prevents race conditions |
| **MANUAL** | No pre-advice; loose quantity receiving | Two-label scan (product + pallet); SSCC mandatory at point of receipt |

The mode is locked to the inbound at activation time and cannot be changed.

---

## The Chain

### SSCC mode

```
inbound_deliveries
    └── inbound_lines
            └── inbound_expected_units   ← pre-advised SSCCs from ASN
                    └── inbound_receipts
                              ├── inventory_units
                              ├── inventory_movements  (reference_id → receipt_id)
                              └── inventory_placements
```

### Manual mode

```
inbound_deliveries
    └── inbound_lines
            └── inbound_receipts         ← no expected units; SSCC captured at scan
                      ├── inventory_units
                      ├── inventory_movements  (reference_id → receipt_id)
                      └── inventory_placements
```

In manual mode, `inbound_receipts.inbound_expected_unit_id` is always `NULL`.
The SSCC scanned by the operator becomes `inventory_units.external_ref`.

---

## Lifecycle States

### inbound_deliveries — inbound_status_code

| Code | Meaning | Transition |
|------|---------|------------|
| EXP | Expected — advice received, not yet activated | → ACT |
| ACT | Activated — ready to receive against | → RCV, CNL |
| RCV | Receiving in progress (partial) | → CLS |
| CLS | Closed — fully received | terminal |
| CNL | Cancelled | terminal |

### inbound_lines — line_state_code

| Code | Meaning |
|------|---------|
| EXP | Expected — not yet touched |
| PRC | Partially received |
| RCV | Fully received |
| CNL | Cancelled |

### inbound_lines — arrival_stock_status_code

Declares the intended stock status of units on this line at point of receipt.
Defaults to `AV`. Set to `BL`, `QC`, or `DM` for blocked, quality hold, or damaged stock.
Mixed-status shipments require separate lines — one status per line, no exceptions.

| Code | Meaning |
|------|---------|
| AV | Available |
| QC | QC Hold |
| BL | Blocked |
| DM | Damaged |

### inbound_expected_units — expected_unit_state_code (SSCC mode only)

| Code | Meaning |
|------|---------|
| EXP | Expected — not yet claimed or received |
| CLM | Claimed — scan validated, awaiting confirmation within TTL |
| RCV | Received — linked to an inventory_unit |
| CNL | Cancelled |

### inventory_units — stock_state_code

| Code | Meaning |
|------|---------|
| RCD | Received — in staging, awaiting putaway |
| PTW | Put away — moved to storage location |

### inventory_units — stock_status_code

Inherited from `inbound_lines.arrival_stock_status_code` at receive time.
Preserved unchanged through putaway. Status changes are a separate explicit operation.

---

## SSCC Mode — Step-by-Step Flow

### 1. Activate inbound — `deliveries.usp_activate_inbound`

**Trigger:** Operator selects inbound from activatable list and confirms.

**Guards:**
- Status must be `EXP` (transition table enforced)
- Must have at least one non-cancelled line
- Cannot mix SSCC and Manual lines (hybrid guard)
- `inbound_mode_code` is immutable once set

**Outcome:**
- `inbound_status_code` → `ACT`
- `inbound_mode_code` set to `SSCC`
- `updated_at` / `updated_by` stamped

---

### 2. Validate SSCC — `deliveries.usp_validate_sscc_for_receive`

**Trigger:** Operator scans SSCC barcode.

**Guards:**
- SSCC must exist in `inbound_expected_units`
- Expected unit must not already be received
- Inbound header must be in receivable status

**Outcome:**
- `expected_unit_state_code` → `CLM`
- `claimed_session_id`, `claimed_by_user_id`, `claimed_at` stamped
- `claim_token` (GUID) generated
- `claim_expires_at` set from `inbound.sscc_claim_ttl_seconds` setting
- Full SSCC detail returned to UI including `arrival_stock_status_code`

The claim token is a time-limited reservation. If the operator does not confirm
within the TTL window, the claim expires and the SSCC returns to `EXP`.

---

### 3. Confirm receive — `deliveries.usp_receive_inbound_line`

**Trigger:** Operator scans SSCC a second time to confirm.

**Guards:**
- Session ID must match the claiming session
- Claim token must match exactly
- Claim must not have expired
- Cannot over-receive against line expected qty
- Duplicate SSCC guard: `external_ref` must not exist on any active unit (`NOT IN ('REV','SHP')`)

**Writes (in order, single transaction):**

| Step | Table | Action |
|------|-------|--------|
| 1 | `inventory.inventory_units`         | New unit created: `RCD`, status from `arrival_stock_status_code` |
| 2 | `inventory.inventory_placements`    | Unit placed in staging bin |
| 3 | `deliveries.inbound_expected_units` | State → `RCV`, linked to `inventory_unit_id` |
| 4 | `deliveries.inbound_lines`          | `received_qty` incremented, state → `PRC` or `RCV` |
| 5 | `deliveries.inbound_receipts`       | Receipt record created → `@receipt_id` captured |
| 6 | `inventory.inventory_movements`     | Movement logged: `reference_id = @receipt_id`, `to_status_code` from line |
| 7 | `deliveries.inbound_deliveries`     | If all lines `RCV/CNL`: status → `CLS` |

---

## Manual Mode — Step-by-Step Flow

Manual mode is used when no SSCCs have been pre-advised. The operator scans two labels
per pallet — a product label (GTIN / EAN) and a pallet label (SSCC) — in either order.
The SSCC is mandatory and is captured as `external_ref` on the inventory unit.

### 1. Activate inbound — `deliveries.usp_activate_inbound`

Same activation SP as SSCC mode. Because no `inbound_expected_units` rows exist,
the SP detects a MANUAL inbound and sets `inbound_mode_code = 'MANUAL'`.

---

### 2. Two-label scan — CLI `ReceiveManualFlow`

The operator is presented with a single scan prompt. The GtinParser resolver
determines from the first scan whether a product label or pallet label was scanned,
then prompts for the missing half.

**Scan 1 — product label first (GTIN)**
```
Scan first label: (01)05556899874510(10)SKU003BATCH
  → GtinParser extracts: GTIN=05556899874510, Batch=SKU003BATCH
  → DB lookup via GetReceivableLineByEan (EAN match, then SKU code fallback)
  → Prompt: Scan SSCC label
Scan second label: (00)300000000000000001(15)270331
  → GtinParser extracts: SSCC=300000000000000001, BBE=31-03-2027
```

**Scan 1 — pallet label first (SSCC)**
```
Scan first label: (00)300000000000000001(15)270331
  → GtinParser extracts: SSCC=300000000000000001, BBE=31-03-2027
  → Prompt: Scan product label
Scan second label: (01)05556899874510(10)SKU003BATCH
  → GtinParser extracts: GTIN=05556899874510, Batch=SKU003BATCH
  → DB lookup via GetReceivableLineByEan
```

Both orders reach the same state after two scans: material identified, SSCC captured.

**After both scans are resolved:**
- Quantity: auto-accepted from `inventory.skus.standard_hu_quantity` (capped at outstanding).
  If `standard_hu_quantity` is NULL, operator is prompted to enter manually.
- Batch: pre-filled from scan. Mandatory if `inventory.skus.is_batch_required = 1`.
- BBE: pre-filled from scan if present; optional otherwise.
- Preview rendered with all resolved data.
- Confirmation: operator rescans the SSCC. `Q` at confirmation prompt to adjust quantity.

**GS1 barcode parsing**

Barcodes are parsed by `GtinParser` which handles:

| Format | Example |
|--------|---------|
| Parenthesis (human-readable) | `(01)05556899874510(10)SKU003BATCH` |
| Raw flat (scanner FNC1-delimited) | `0105556899874510\x1D10SKU003BATCH` |
| Tilde-as-FNC1 | `0105556899874510~10SKU003BATCH` |

Variable-length AIs (batch `10`, quantity `37`) are terminated by FNC1 only.
Fixed-length AIs (SSCC `00` = 18 digits, GTIN `01` = 14 digits, dates = 6 digits)
are read by exact length. BBE date AI `15` or `17`: day `00` means last day of month;
any other day value is used as-is.

**Material lookup fallback chain**

`GetReceivableLineByEan` tries in priority order:
1. `inventory.skus.ean` exact match against the scanned GTIN
2. `inventory.skus.sku_code` exact match against the raw scan (typed entry fallback)

`MatchedBy` ("EAN" or "SKU") is returned and shown in Trace mode.

---

### 3. Confirm receive — `deliveries.usp_receive_inbound_line`

The same SP handles both modes. The mode is determined by whether
`@inbound_expected_unit_id` is supplied:

| Parameter | SSCC mode | Manual mode |
|-----------|-----------|-------------|
| `@inbound_line_id` | NULL (derived from expected unit) | Required |
| `@inbound_expected_unit_id` | Required | NULL |
| `@claim_token` | Required (session guard) | NULL |
| `@external_ref` | From `inbound_expected_units` | SSCC scanned by operator |
| `@received_qty` | From `inbound_expected_units` | Entered/accepted by operator |
| `@batch_number` | From `inbound_expected_units` | From product label scan |
| `@best_before_date` | From `inbound_expected_units` | From pallet label scan |

**Guards (manual mode specific):**
- `@inbound_line_id` must be provided and valid
- `@received_qty` must be > 0 and ≤ outstanding
- Duplicate SSCC guard: if `@external_ref` is set, no active unit may already hold it

**Writes (in order, single transaction) — identical to SSCC mode steps 1–7:**

| Step | Table | Action |
|------|-------|--------|
| 1 | `inventory.inventory_units`      | New unit: `RCD`, status from line's `arrival_stock_status_code` |
| 2 | `inventory.inventory_placements` | Unit placed in staging bin |
| 3 | `deliveries.inbound_lines`       | `received_qty` incremented, state → `PRC` or `RCV` |
| 4 | `deliveries.inbound_receipts`    | Receipt created (no `inbound_expected_unit_id`) |
| 5 | `inventory.inventory_movements`  | Movement logged with `reference_id = @receipt_id` |
| 6 | `deliveries.inbound_deliveries`  | If all lines `RCV/CNL`: status → `CLS` |

Note: step 3 in SSCC mode (updating `inbound_expected_units`) is skipped in manual mode
as no expected unit row exists.

---

## Receipt Reversal — `deliveries.usp_reverse_inbound_receipt`

Both modes support full reversal of any receipt. Reversal is receipt-based — the operator
provides the `receipt_id`, not the SSCC.

**Guards:**
- Receipt must exist and must be an original (not itself a reversal)
- Receipt must not already have been reversed

**Writes (single transaction):**

| Step | Table | Action |
|------|-------|--------|
| 1 | `inventory.inventory_units`         | `stock_state_code` → `REV` |
| 2 | `inventory.inventory_placements`    | Row deleted (unit no longer located) |
| 3 | `inventory.inventory_movements`     | Reversal movement logged (`is_reversal=1`, `reversed_movement_id` set) |
| 4 | `deliveries.inbound_expected_units` | State → `EXP`, all claim fields cleared (SSCC mode only) |
| 5 | `deliveries.inbound_receipts`       | Reversal receipt row inserted |
| 6 | `deliveries.inbound_receipts`       | Original receipt stamped with `reversed_receipt_id` |
| 7 | `deliveries.inbound_lines`          | `received_qty` recomputed from all non-reversed receipts |
| 8 | `deliveries.inbound_deliveries`     | Header status recomputed; if previously `CLS`, reopened to `RCV` |

If the reversal causes a closed inbound to reopen, the trace log records
`Inbound.Reopened` with `PreviousStatus: CLS → NewStatus: RCV`.

---

## Key Design Decisions

**Arrival stock status on the line, not the unit**
`arrival_stock_status_code` lives on `inbound_lines`. Status is a supplier declaration
at line level, not per handling unit. Mixed-status shipments use separate lines.

**SSCC mandatory in manual mode**
Even without pre-advised SSCCs, the operator must scan a pallet label to generate an
`external_ref` on the inventory unit. This ensures every unit in the warehouse has a
scannable identity from day one. No SSCC = no receive. Future desktop app feature:
auto-generate an internal SSCC for sites that don't use supplier pallet labels.

**Claim token pattern (SSCC mode)**
The two-scan validate → confirm flow uses a session-bound GUID claim token with a
configurable TTL (`inbound.sscc_claim_ttl_seconds`). Only the session that holds the
valid, unexpired token can confirm. Prevents two operators on different terminals
from simultaneously receiving the same SSCC.

**Duplicate SSCC guard (both modes)**
Before inserting a new `inventory_units` row, the SP explicitly checks whether the
`external_ref` already exists on any active unit (`stock_state_code NOT IN ('REV','SHP')`).
Returns `ERRSSCC02` rather than letting the unique index throw an untyped exception.
The unique index remains as a final safety net.

**`is_batch_required` on `inventory.skus`**
Data-driven flag. When `1`, the batch field becomes mandatory at receive time.
The manual receive flow enforces this — if the product label does not contain a
batch value and `is_batch_required = 1`, the operator is prompted. The flow will
not proceed without a batch number.

**`standard_hu_quantity` on `inventory.skus`**
When set, the quantity is auto-accepted in manual receive without prompting the
operator (capped at the line outstanding qty). The operator can adjust at the
confirmation scan step by pressing `Q`. This eliminates unnecessary keystrokes for
full-pallet receives while still allowing part-pallet flexibility.

**`SCOPE_IDENTITY()` ordering discipline**
Within a single SP, `SCOPE_IDENTITY()` always returns the identity from the most
recent `INSERT` into an identity column on the current connection. The step ordering
is load-bearing — the receipt insert must precede the movement insert so that
`@receipt_id` is available as `reference_id` on the movement row.

**`SET XACT_ABORT ON`**
All command SPs use `XACT_ABORT ON`. Any runtime error automatically rolls back
the entire transaction. The `BEGIN CATCH` block is a final safety net for returning
a structured error result (`ERRINBL99`) to the application.

**`UPDLOCK, HOLDLOCK` on reads**
Expected unit and line reads use `WITH (UPDLOCK, HOLDLOCK)` to prevent a second
concurrent transaction from reading the same rows before the first transaction commits.

---

## Traceability Queries

### By SSCC — SSCC mode

```sql
SELECT
    d.inbound_ref,
    d.inbound_status_code,
    l.line_no,
    l.arrival_stock_status_code,
    eu.expected_external_ref        AS sscc,
    r.receipt_id,
    r.received_at,
    r.received_by_user_id,
    iu.inventory_unit_id,
    iu.stock_state_code,
    iu.stock_status_code,
    ip.bin_id                       AS current_bin_id,
    m.movement_id,
    m.movement_type,
    m.reference_id                  AS receipt_id_fk
FROM deliveries.inbound_expected_units eu
JOIN deliveries.inbound_lines l
    ON l.inbound_line_id = eu.inbound_line_id
JOIN deliveries.inbound_deliveries d
    ON d.inbound_id = l.inbound_id
LEFT JOIN deliveries.inbound_receipts r
    ON r.inbound_expected_unit_id = eu.inbound_expected_unit_id
LEFT JOIN inventory.inventory_units iu
    ON iu.inventory_unit_id = r.inventory_unit_id
LEFT JOIN inventory.inventory_placements ip
    ON ip.inventory_unit_id = iu.inventory_unit_id
LEFT JOIN inventory.inventory_movements m
    ON m.inventory_unit_id = iu.inventory_unit_id
   AND m.movement_type = 'INBOUND'
   AND m.is_reversal   = 0
WHERE eu.expected_external_ref = 'SSCC0000000000000001';
```

### By SSCC — Manual mode

```sql
SELECT
    d.inbound_ref,
    d.inbound_mode_code,
    l.line_no,
    l.arrival_stock_status_code,
    iu.external_ref                 AS sscc,
    r.receipt_id,
    r.received_at,
    r.received_by_user_id,
    iu.inventory_unit_id,
    iu.batch_number,
    iu.best_before_date,
    iu.stock_state_code,
    iu.stock_status_code,
    ip.bin_id                       AS current_bin_id,
    m.movement_id,
    m.reference_id                  AS receipt_id_fk
FROM inventory.inventory_units iu
JOIN deliveries.inbound_receipts r
    ON r.inventory_unit_id = iu.inventory_unit_id
   AND r.is_reversal = 0
JOIN deliveries.inbound_lines l
    ON l.inbound_line_id = r.inbound_line_id
JOIN deliveries.inbound_deliveries d
    ON d.inbound_id = l.inbound_id
LEFT JOIN inventory.inventory_placements ip
    ON ip.inventory_unit_id = iu.inventory_unit_id
LEFT JOIN inventory.inventory_movements m
    ON m.inventory_unit_id = iu.inventory_unit_id
   AND m.movement_type = 'INBOUND'
   AND m.is_reversal   = 0
WHERE iu.external_ref = '300000000000000001';
```

### Active reversals on an inbound

```sql
SELECT
    r_orig.receipt_id,
    r_orig.received_at,
    r_rev.receipt_id        AS reversal_receipt_id,
    r_rev.received_at       AS reversed_at,
    iu.external_ref         AS sscc,
    iu.stock_state_code
FROM deliveries.inbound_receipts r_orig
JOIN deliveries.inbound_receipts r_rev
    ON r_rev.receipt_id = r_orig.reversed_receipt_id
JOIN inventory.inventory_units iu
    ON iu.inventory_unit_id = r_orig.inventory_unit_id
JOIN deliveries.inbound_lines l
    ON l.inbound_line_id = r_orig.inbound_line_id
WHERE l.inbound_id = 3   -- replace with target inbound_id
ORDER BY r_orig.received_at;
```

---

## What Comes Next — Putaway

After receiving, every inventory unit is in state `RCD` (Received) with a placement
in a staging bin. The next process is putaway:

1. Operator scans the SSCC of the unit to be put away
2. `warehouse.usp_putaway_create_task_for_unit` — resolves the inventory unit by
   `external_ref`, suggests a destination bin using zone load balancing and bin
   reservations, creates a `warehouse_tasks` row (`OPN`)
3. Operator physically moves the pallet and scans the destination bin label
4. `warehouse.usp_putaway_confirm_task` — moves the placement, transitions unit
   to `PTW`, logs the movement with status preserved, clears the bin reservation

The putaway SSCC scan uses the same GtinParser resolver as receiving — both GS1-128
pallet labels and plain Code-128 SSCC strings are accepted.

*See putaway-strategy.md for the bin suggestion algorithm.*

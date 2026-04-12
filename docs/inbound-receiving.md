# Inbound Receiving — Data Flow & Traceability Model

## Overview

The inbound receiving process in PeasyWare establishes a complete, unbroken audit chain
from a supplier delivery advice through to physical inventory placement in a staging bin.
Every row in every table is traceable back to every other row in the chain.

---

## The Chain

```
inbound_deliveries
    └── inbound_lines
            └── inbound_expected_units   (SSCC mode)
                    └── inbound_receipts
                              ├── inventory_units
                              ├── inventory_movements  (reference_id → receipt_id)
                              └── inventory_placements
```

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
Populated from the supplier's advice note. Preserved through putaway unchanged.

| Code | Meaning |
|------|---------|
| AV | Available |
| QC | QC Hold |
| BL | Blocked |
| DM | Damaged |

### inbound_expected_units — expected_unit_state_code (SSCC mode)

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

## Step-by-Step Flow (SSCC Mode)

### 1. Activate inbound — `deliveries.usp_activate_inbound`

**Trigger:** Operator selects inbound from activatable list and confirms.

**Guards:**
- Status must be `EXP` (transition table enforced)
- Must have at least one non-cancelled line
- Cannot mix SSCC and Manual lines (hybrid guard)
- `inbound_mode_code` is immutable once set

**Outcome:**
- `inbound_status_code` → `ACT`
- `inbound_mode_code` set to `SSCC` or `MANUAL`
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

**Writes (in order, single transaction):**

| Step | Table | Action |
|------|-------|--------|
| 4    | `inventory.inventory_units`         | New unit created: `RCD`, status from `arrival_stock_status_code` |
| 4b   | `inventory.inventory_placements`    | Unit placed in staging bin |
| 5    | `deliveries.inbound_expected_units` | State → `RCV`, linked to `inventory_unit_id` |
| 6    | `deliveries.inbound_lines`          | `received_qty` incremented, state → `PRC` or `RCV` |
| 6.5  | `deliveries.inbound_receipts`       | Receipt record created → `@receipt_id` captured |
| 6.6  | `inventory.inventory_movements`     | Movement logged with `reference_id = @receipt_id`, `to_status_code` from line |
| 7    | `deliveries.inbound_deliveries`     | If all lines `RCV/CNL`: status → `CLS` |

**Why the order matters:**
`inventory_movements.reference_id` must point to the `inbound_receipts` row.
The receipt insert (6.5) must precede the movement insert (6.6) so that
`SCOPE_IDENTITY()` is captured into `@receipt_id` before the movement is written.
Placing the movement insert before the receipt insert results in `reference_id = NULL`.

---

## Key Design Decisions

**Arrival stock status on the line, not the unit**
`arrival_stock_status_code` lives on `inbound_lines`, not `inbound_expected_units`.
The status is a property of what the supplier declared they are sending, not of an
individual handling unit. Mixed-status shipments require separate lines. This mirrors
how linked systems (ERP, EDI, supplier portals) communicate stock type at line level.
When a linked system sends a delivery advice, the status is declared per line.
The integration layer maps the supplier's status codes to PeasyWare codes before
writing the line — the WMS core never sees raw external formats.

**Claim token pattern**
The two-step scan (validate → confirm) uses a GUID claim token tied to a session
and a TTL. This prevents a race condition where two operators on different terminals
could simultaneously receive the same SSCC. Only the session that holds the valid,
unexpired claim token can confirm the receive.

**`SCOPE_IDENTITY()` ordering discipline**
Within a single SP, `SCOPE_IDENTITY()` always returns the identity from the most
recent `INSERT` into an identity column on the current connection. The current step
ordering (4 → 4b → 5 → 6 → 6.5 → 6.6) is load-bearing — do not reorder without
verifying the identity chain.

**`SET XACT_ABORT ON`**
All command SPs use `XACT_ABORT ON`. Any runtime error automatically rolls back
the entire transaction. The `BEGIN CATCH` block is a final safety net for returning
a structured error result to the application.

**`UPDLOCK, HOLDLOCK` on reads**
The expected unit and line reads use `WITH (UPDLOCK, HOLDLOCK)` to prevent a second
concurrent transaction from reading the same rows before the first transaction commits.

**`updated_by` on all state transitions**
Every status-changing UPDATE stamps `updated_by = @user_id` and `updated_at = SYSUTCDATETIME()`.

**Status preservation through putaway**
`usp_putaway_confirm_task` reads `stock_status_code` from `inventory_units` before
moving the unit and writes `from_status_code = to_status_code` in the movement log.
Putaway is a location movement only — it never changes stock status.

---

## Traceability Query

Given a single SSCC, the full chain can be reconstructed:

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
    m.reference_type,
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
WHERE eu.expected_external_ref = 'SSCC0000000000000001';
```

---

## What Comes Next — Putaway

After receiving, every inventory unit is in state `RCD` (Received) with a placement
in a staging bin. The next process is putaway:

1. `warehouse.usp_putaway_create_task_for_unit` — suggests a destination bin using
   zone load balancing and bin reservations, creates a `warehouse_tasks` row (`OPN`)
2. Operator confirms physical move to the suggested bin
3. `warehouse.usp_putaway_confirm_task` — moves placement, transitions unit to `PTW`,
   logs movement with status preserved, clears bin reservation

*See putaway-strategy.md for the bin suggestion algorithm.*

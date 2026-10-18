# Outbound Despatch — Data Flow & Traceability Model

## Overview

The outbound process in PeasyWare moves stock from storage to a departing vehicle.
Every step is audited, every state transition is enforced, and the full chain from
order creation to physical departure is traceable through a single query.

---

## The Chain

```
outbound_orders
    └── outbound_lines
            └── outbound_allocations  ← stock reserved against a line
                    └── warehouse_tasks (PICK)
                              └── inventory_movements (PICK)
                                        └── inventory_movements (SHIP)

shipments
    └── shipment_orders  ← junction: one shipment, many orders
            └── (order → outbound_orders)
```

---

## Lifecycle States

### outbound_orders — order_status_code

| Code | Meaning | Transition |
|------|---------|------------|
| NEW | Created, not yet allocated | → ALLOCATED, CNL |
| ALLOCATED | Stock reserved, ready to pick | → PICKING, NEW (de-alloc), CNL |
| PICKING | Pick in progress (partial) | → PICKED, ALLOCATED (partial reverse), CNL |
| PICKED | Fully picked, awaiting load | → LOADED |
| LOADED | Loaded onto vehicle | → SHIPPED |
| SHIPPED | Departed site | terminal |
| CNL | Cancelled | terminal |

### outbound_lines — line_status_code

| Code | Meaning |
|------|---------|
| NEW | Not yet allocated |
| ALLOCATED | Stock reserved |
| PICKING | Picking in progress |
| PICKED | Fully picked |
| CNL | Cancelled |

### outbound_allocations — allocation_status

| Code | Meaning |
|------|---------|
| PENDING | Unit reserved, pick task not yet created |
| CONFIRMED | Pick task created, operator has instructions |
| PICKED | Physical pick confirmed |
| CANCELLED | Allocation cancelled |

### shipments — shipment_status

| Code | Meaning | Transition |
|------|---------|------------|
| OPEN | Accepting orders | → LOADING, CNL |
| LOADING | Physical loading in progress | → DEPARTED, OPEN (reverse), CNL |
| DEPARTED | Left site | terminal |
| CNL | Cancelled | terminal |

### inventory_units — stock_state_code (outbound additions)

| Code | Meaning |
|------|---------|
| PKD | Picked — in staging bay, awaiting load |
| LDD | Loaded — on the vehicle; placement removed at load time, not ship time. Mandatory before ship |
| SHP | Shipped — terminal, no placement |

---

## Step-by-Step Flow

### 1. Create order — `outbound.usp_create_order`

**Trigger:** Operator creates order manually (Desktop app, future API/EDI).

**Parameters:** `@order_ref`, `@customer_party_id`, `@lines_json` (JSON array of lines).

**Line fields:**
- `sku_code` — material to despatch
- `ordered_qty` — quantity required
- `requested_batch` — customer-specified batch (NULL = any)
- `requested_bbe` — customer-specified best-before date (NULL = any)

**Guards:**
- Order ref must be unique
- Customer must exist and be active
- Lines JSON must contain at least one valid SKU

**Outcome:** Order in `NEW` status, lines in `NEW` status.

---

### 2. Allocate order — `outbound.usp_allocate_order`

**Trigger:** Operator or system allocates stock against the order.

**Strategy:** Driven by `operations.settings` key `outbound.allocation_strategy`.

| Strategy | Logic |
|----------|-------|
| `FEFO` | Earliest best-before date first |
| `FIFO` | Earliest received date first |
| `LIFO` | Latest received date first |
| `NONE` | FEFO if unit has BBE, otherwise FIFO (default) |

**Rules:**
- Only `PUTAWAY` + `AVAILABLE` units eligible (no staging stock, no QC/blocked)
- Full pallets only — unit quantity must satisfy line quantity
- `requested_batch` and `requested_bbe` on the line filter candidates
- Shelf life: each candidate's best-before date is checked against the order's delivery date plus the required minimum days (customer + SKU override → SKU default → 0); the trace entry records the delivery date, each unit's best-before date and the required days on every outcome
- All lines must be satisfiable — partial allocation rolls back entirely

**Outcome:** One `outbound_allocations` row per pallet per line, status `PENDING`.
Order and lines transition to `ALLOCATED`.

---

### 3. Pick — `outbound.usp_pick_create` + `outbound.usp_pick_confirm`

**Trigger:** Operator enters the pick flow (CLI: Main → Orders → Pick order).

**Flow:**
1. Operator selects order by sequence number or ref
2. Operator scans or enters a destination staging bin (Enter = auto-select)
3. For each PENDING allocation:
   - `usp_pick_create`: creates a `PICK` task, allocation → `CONFIRMED`
   - CLI shows source bin + SSCC to collect
   - Operator scans source bin (validated client-side before SSCC prompt)
   - Operator scans SSCC to confirm
   - `usp_pick_confirm`: moves placement to staging, unit → `PKD`,
     writes `PICK` movement, allocation → `PICKED`

**Destination staging bin:**
The operator specifies which staging bay to pick into. This supports sites with
multiple staging areas (inbound bay, outbound bay, temperature-controlled staging).
If not specified, the SP auto-selects the first active staging bin alphabetically.

**Guards (pick_confirm):**
- Scanned bin must match task source bin
- Scanned SSCC must match allocated unit
- Task must be in `OPN` or `CLM` state

**Outcome per unit:** Unit in `PKD`, in staging bin, `PICK` movement logged.
When all lines picked, order → `PICKED`.

**Re-allocation:**
When an operator cannot pick an allocated unit (damaged, inaccessible, missing),
the skip prompt offers `R=request new allocation`: it cancels the current
allocation (`outbound.usp_cancel_allocation`) and re-runs the allocation engine
for that line against the next eligible unit (`outbound.usp_reallocate_line`),
then restarts the pick for the order. If no substitute exists, the line is left
for supervisor attention.

---

### 4. Create shipment — `outbound.usp_create_shipment`

**Trigger:** Dispatcher creates a shipment for a vehicle/trailer.

**Parameters:** `@shipment_ref`, `@vehicle_ref`, `@ship_from_address_id`,
`@haulier_party_id` (optional), `@planned_departure` (optional).

**Outcome:** Shipment in `OPEN` status.

---

### 5. Add order to shipment — `outbound.usp_add_order_to_shipment`

**Trigger:** Dispatcher links a picked order to a shipment.

**Guards:**
- Order must be `ALLOCATED`, `PICKING`, or `PICKED`
- Shipment must be `OPEN` or `LOADING`

**Outcome:** `outbound_orders.shipment_id` set, row in `shipment_orders` junction.

---

### 6. Ship — `outbound.usp_ship`

**Trigger:** Dispatcher confirms vehicle departure.

**Guards:**
- All orders on shipment must be `PICKED`, `LOADED`, or `CNL`
- Shipment must be `OPEN` or `LOADING`

**Writes (cursor over all PICKED allocations on the shipment):**

| Step | Table | Action |
|------|-------|--------|
| 1 | `inventory.inventory_units` | `stock_state_code` → `SHP` |
| 2 | `inventory.inventory_placements` | Row deleted — unit no longer in warehouse |
| 3 | `inventory.inventory_movements` | `SHIP` movement logged, `to_bin_id = NULL` |
| 4 | `outbound.outbound_orders` | Status → `SHIPPED` |
| 5 | `outbound.outbound_lines` | Status → `PICKED` (terminal) |
| 6 | `outbound.shipments` | Status → `DEPARTED`, `actual_departure` stamped |

**Outcome:** All units in `SHP`, no placements remaining, shipment closed.

---

## Allocation Engine Detail

The allocation engine runs per line, using a cursor to select eligible units.

**Eligibility criteria:**
```sql
WHERE iu.stock_state_code  = 'PTW'          -- putaway, not staging
  AND iu.stock_status_code = 'AV'           -- available, not blocked/QC
  AND st.storage_type_code <> 'STAGE'       -- not in a staging bin
  AND (requested_batch IS NULL OR iu.batch_number     = requested_batch)
  AND (requested_bbe   IS NULL OR iu.best_before_date = requested_bbe)
  AND NOT EXISTS (active allocation on this unit)
```

**Ordering by strategy:**

| Strategy | ORDER BY |
|----------|----------|
| FEFO | `best_before_date ASC` (NULLs last), then `created_at ASC` |
| FIFO | `created_at ASC` |
| LIFO | `created_at DESC` |
| NONE | FEFO if BBE present, else FIFO |

**All-or-nothing:** If any line cannot be fully satisfied, the entire allocation
rolls back. The error distinguishes between general stock shortage (`ERRALLOC01`)
and specific batch/BBE not available (`ERRALLOC02`).

---

## Key Design Decisions

**Allocation on demand, not on order entry**
Stock is not reserved when an order is created. It is reserved when `usp_allocate_order`
is called. This allows orders to be created from EDI/API feeds before the relevant
stock has arrived, and allocated when the warehouse is ready to pick.

**Soft vs hard allocation**
Currently all allocations are hard (immediately lock the unit from other orders).
A future feature will add soft reservations (advisory hold, can be overridden by
a manager) with `is_confirmed BIT` on `outbound_allocations`.

**Staging bay choice at pick time**
The operator specifies the destination staging bay when starting a pick session,
not per unit. All units in that session go to the same bay. This mirrors real
warehouse operations where a whole order is staged in one area. The SP validates
the specified bin is an active `STAGE` type bin before creating any tasks.

**Single movement record per pick, per ship**
Each physical movement writes one record: source bin → staging (`PICK`),
staging → NULL (`SHIP`). The task table carries start/finish timestamps for
KPI and performance analysis. No intermediate movement records.

**Placement deleted on ship**
On `usp_ship`, the `inventory_placements` row is deleted. A shipped unit has no
physical warehouse location. The `inventory_movements` record with `movement_type = 'SHIP'`
and `to_bin_id = NULL` is the permanent audit record of the final movement.

**One shipment, many orders; one order, one shipment**
A shipment represents a vehicle departure event. Multiple orders can be
consolidated onto one shipment. An order can only belong to one shipment.
The `shipment_orders` junction table records the relationship; `outbound_orders.shipment_id`
is a denormalised FK for fast lookup.

**`SET XACT_ABORT ON`**
All command SPs use `XACT_ABORT ON`. Any runtime error rolls back the entire
transaction. The `BEGIN CATCH` block returns structured error codes to the
application layer.

---

## Error Codes

| Code | Meaning |
|------|---------|
| `ERRORD01` | Order not found |
| `ERRORD02` | Order not in valid state for this operation |
| `ERRORD03` | Order reference already exists |
| `ERRORD04` | Order has no valid lines |
| `ERRALLOC01` | Insufficient stock to fulfil line |
| `ERRALLOC02` | Requested batch or BBE not available |
| `ERRALLOC03` | Unit already allocated to another order |
| `ERRPICK01` | Allocation not found or already picked |
| `ERRPICK02` | Wrong SSCC scanned |
| `ERRPICK03` | Unit not in expected source bin |
| `ERRSHIP01` | Shipment not found |
| `ERRSHIP02` | Shipment not in valid state |
| `ERRSHIP03` | Shipment reference already exists |
| `ERRSHIP04` | Not all orders on shipment are fully picked |

---

## Traceability Query

Given an order ref, the full outbound chain can be reconstructed:

```sql
SELECT
    o.order_ref,
    o.order_status_code,
    l.line_no,
    s.sku_code,
    l.ordered_qty,
    l.picked_qty,
    a.allocation_status,
    iu.external_ref             AS sscc,
    iu.stock_state_code,
    ship.shipment_ref,
    ship.shipment_status,
    ship.actual_departure,
    m_pick.moved_at             AS picked_at,
    m_ship.moved_at             AS shipped_at
FROM outbound.outbound_orders o
JOIN outbound.outbound_lines l
    ON l.outbound_order_id  = o.outbound_order_id
JOIN inventory.skus s
    ON s.sku_id             = l.sku_id
LEFT JOIN outbound.outbound_allocations a
    ON a.outbound_line_id   = l.outbound_line_id
LEFT JOIN inventory.inventory_units iu
    ON iu.inventory_unit_id = a.inventory_unit_id
LEFT JOIN outbound.shipments ship
    ON ship.shipment_id     = o.shipment_id
LEFT JOIN inventory.inventory_movements m_pick
    ON m_pick.inventory_unit_id = iu.inventory_unit_id
   AND m_pick.movement_type     = 'PICK'
   AND m_pick.is_reversal        = 0
LEFT JOIN inventory.inventory_movements m_ship
    ON m_ship.inventory_unit_id = iu.inventory_unit_id
   AND m_ship.movement_type     = 'SHIP'
   AND m_ship.is_reversal        = 0
WHERE o.order_ref = 'ORD-TEST-001'
ORDER BY l.line_no, a.allocation_id;
```

---

## Since this was written

Everything the first version of this document listed as "next" has been built:

- **Load confirmation** — `outbound.usp_confirm_load`, per order, tied to its shipment. Picked units move to `LDD` and their placement is removed at load time rather than at ship time: a loaded pallet no longer occupies the floor, and a loading bay only has room for so many. It is mandatory before ship — a shipment with a picked-but-not-yet-loaded order is rejected (`ERRSHIP09`). A `LDD → PKD` reversal has a transition entry but no procedure yet.
  Both procedures check the stock, not just the order's status label. `usp_confirm_load` refuses an order that is not on the shipment — including one on no shipment at all (`ERRLOAD01`) — rolls back unless every picked unit actually moved (`ERRLOAD02`), and reports a repeat as `SUCLOAD02` without touching anything. `usp_ship` refuses unless every picked unit is `LDD` (`ERRSHIP10`). `Database/Tests/170_lifecycle_integrity.sql` builds each contradiction and proves the refusal.
- **Load and ship from the CLI** — `LoadFlow` and `ShipFlow`, alongside the Desktop dispatch screens.
- **Re-allocation** — see the pick step above.
- **Shelf life** — see the allocation rules above, and [`architecture.md`](architecture.md).

Where this document and the stored procedures disagree, the procedures win. The step-by-step sections for load and ship (guards, error codes, the traceability query's `LDD` step) have not been refreshed yet.

\---



\## Lifecycle States



\### inbound\_deliveries — inbound\_status\_code



| Code | Meaning | Transition |

|------|---------|------------|

| EXP | Expected — advice received, not yet activated | → ACT |

| ACT | Activated — ready to receive against | → RCV, CNL |

| RCV | Receiving in progress (partial) | → CLS |

| CLS | Closed — fully received | terminal |

| CNL | Cancelled | terminal |



\### inbound\_lines — line\_state\_code



| Code | Meaning |

|------|---------|

| EXP | Expected — not yet touched |

| PRC | Partially received |

| RCV | Fully received |

| CNL | Cancelled |



\### inbound\_expected\_units — expected\_unit\_state\_code (SSCC mode)



| Code | Meaning |

|------|---------|

| EXP | Expected — not yet claimed or received |

| CLM | Claimed — scan validated, awaiting confirmation within TTL |

| RCV | Received — linked to an inventory\_unit |



\### inventory\_units — stock\_state\_code



| Code | Meaning |

|------|---------|

| RCD | Received — in staging, awaiting putaway |

| PTW | Put away — moved to storage location |

| AV  | Available (stock\_status\_code) |



\---



\## Step-by-Step Flow (SSCC Mode)



\### 1. Activate inbound — `deliveries.usp\_activate\_inbound`



\*\*Trigger:\*\* Operator selects inbound from activatable list and confirms.



\*\*Guards:\*\*

\- Status must be `EXP` (transition table enforced)

\- Must have at least one non-cancelled line

\- Cannot mix SSCC and Manual lines (hybrid guard)

\- `inbound\_mode\_code` is immutable once set



\*\*Outcome:\*\*

\- `inbound\_status\_code` → `ACT`

\- `inbound\_mode\_code` set to `SSCC` or `MANUAL`

\- `updated\_at` / `updated\_by` stamped



\---



\### 2. Validate SSCC — `deliveries.usp\_validate\_sscc\_for\_receive`



\*\*Trigger:\*\* Operator scans SSCC barcode.



\*\*Guards:\*\*

\- SSCC must exist in `inbound\_expected\_units`

\- Expected unit must not already be received

\- Inbound header must be in receivable status



\*\*Outcome:\*\*

\- `expected\_unit\_state\_code` → `CLM`

\- `claimed\_session\_id`, `claimed\_by\_user\_id`, `claimed\_at` stamped

\- `claim\_token` (GUID) generated

\- `claim\_expires\_at` set from `inbound.sscc\_claim\_ttl\_seconds` setting

\- Full SSCC detail returned to UI (SKU, batch, BBE, qty, outstanding counts)



The claim token is a time-limited reservation. If the operator does not confirm

within the TTL window, the claim expires and the SSCC returns to `EXP`.



\---



\### 3. Confirm receive — `deliveries.usp\_receive\_inbound\_line`



\*\*Trigger:\*\* Operator scans SSCC a second time to confirm.



\*\*Guards:\*\*

\- Session ID must match the claiming session

\- Claim token must match exactly

\- Claim must not have expired

\- Cannot over-receive against line expected qty



\*\*Writes (in order, single transaction):\*\*



| Step | Table | Action |

|------|-------|--------|

| 4    | `inventory.inventory\_units`          | New unit created: `RCD / AV` |

| 4b   | `inventory.inventory\_placements`     | Unit placed in staging bin |

| 5    | `deliveries.inbound\_expected\_units`  | State → `RCV`, linked to `inventory\_unit\_id` |

| 6    | `deliveries.inbound\_lines`           | `received\_qty` incremented, state → `PRC` or `RCV` |

| 6.5  | `deliveries.inbound\_receipts`        | Receipt record created → `@receipt\_id` captured |

| 6.6  | `inventory.inventory\_movements`      | Movement logged with `reference\_id = @receipt\_id` |

| 7    | `deliveries.inbound\_deliveries`      | If all lines `RCV/CNL`: status → `CLS` |



\*\*Why the order matters:\*\*

`inventory\_movements.reference\_id` must point to the `inbound\_receipts` row.

The receipt insert (6.5) must precede the movement insert (6.6) so that

`SCOPE\_IDENTITY()` is captured into `@receipt\_id` before the movement is written.

Placing the movement insert before the receipt insert results in `reference\_id = NULL`

because `SCOPE\_IDENTITY()` would return the identity from the `inventory\_units` insert

instead.



\---



\## Key Design Decisions



\*\*Claim token pattern\*\*

The two-step scan (validate → confirm) uses a GUID claim token tied to a session

and a TTL. This prevents a race condition where two operators on different terminals

could simultaneously receive the same SSCC. Only the session that holds the valid,

unexpired claim token can confirm the receive.



\*\*`SCOPE\_IDENTITY()` ordering discipline\*\*

Within a single SP, `SCOPE\_IDENTITY()` always returns the identity from the most

recent `INSERT` into an identity column on the current connection. Any identity-

generating insert between the receipts insert and the movement insert would corrupt

the `@receipt\_id` capture. The current step ordering (4 → 4b → 5 → 6 → 6.5 → 6.6)

is load-bearing — do not reorder without verifying the identity chain.



\*\*`SET XACT\_ABORT ON`\*\*

All command SPs use `XACT\_ABORT ON`. Any runtime error automatically rolls back

the entire transaction without requiring explicit error handling for every statement.

The `BEGIN CATCH` block is a final safety net for returning a structured error result

to the application.



\*\*`UPDLOCK, HOLDLOCK` on reads\*\*

The expected unit and line reads use `WITH (UPDLOCK, HOLDLOCK)` to prevent a second

concurrent transaction from reading the same rows before the first transaction commits.

This is the correct pattern for optimistic-to-pessimistic lock promotion in SQL Server.



\*\*`updated\_by` on all state transitions\*\*

Every status-changing UPDATE stamps `updated\_by = @user\_id` and `updated\_at = SYSUTCDATETIME()`.

The `@user\_id` is passed explicitly from the application session context and also injected

into `SESSION\_CONTEXT` at the start of the SP for trigger and audit use.



\---



\## Traceability Query



Given a single SSCC, the full chain can be reconstructed:



```sql

SELECT

&#x20;   d.inbound\_ref,

&#x20;   d.inbound\_status\_code,

&#x20;   l.line\_no,

&#x20;   eu.expected\_external\_ref        AS sscc,

&#x20;   r.receipt\_id,

&#x20;   r.received\_at,

&#x20;   r.received\_by\_user\_id,

&#x20;   iu.inventory\_unit\_id,

&#x20;   iu.stock\_state\_code,

&#x20;   ip.bin\_id                       AS current\_bin\_id,

&#x20;   m.movement\_id,

&#x20;   m.movement\_type,

&#x20;   m.reference\_type,

&#x20;   m.reference\_id                  AS receipt\_id\_fk

FROM deliveries.inbound\_expected\_units eu

JOIN deliveries.inbound\_lines l

&#x20;   ON l.inbound\_line\_id = eu.inbound\_line\_id

JOIN deliveries.inbound\_deliveries d

&#x20;   ON d.inbound\_id = l.inbound\_id

LEFT JOIN deliveries.inbound\_receipts r

&#x20;   ON r.inbound\_expected\_unit\_id = eu.inbound\_expected\_unit\_id

LEFT JOIN inventory.inventory\_units iu

&#x20;   ON iu.inventory\_unit\_id = r.inventory\_unit\_id

LEFT JOIN inventory.inventory\_placements ip

&#x20;   ON ip.inventory\_unit\_id = iu.inventory\_unit\_id

LEFT JOIN inventory.inventory\_movements m

&#x20;   ON m.inventory\_unit\_id = iu.inventory\_unit\_id

&#x20;  AND m.movement\_type = 'INBOUND'

WHERE eu.expected\_external\_ref = 'SSCC0000000000000001';

```



\---



\## What Comes Next — Putaway



After receiving, every inventory unit is in state `RCD` (Received) with a placement

in a staging bin. The next process is putaway:



1\. `warehouse.usp\_putaway\_create\_task\_for\_unit` — suggests a destination bin using

&#x20;  zone load balancing and bin reservations, creates a `warehouse\_tasks` row (`OPN`)

2\. Operator confirms physical move to the suggested bin

3\. `warehouse.usp\_putaway\_confirm\_task` — moves placement, transitions unit to `PTW`,

&#x20;  logs movement, clears bin reservation



\*See putaway-strategy.md for the bin suggestion algorithm.\*


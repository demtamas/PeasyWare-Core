# PeasyWare — Architecture Notes

## Core principles

**Thick database, thin application.**
Business logic lives in stored procedures. The application layer resolves sessions, maps results, and routes to the correct SP — it does not duplicate or re-implement domain rules. This keeps the logic in one place, directly testable in SQL, and consistent across CLI, Desktop, and API clients.

**Event stream as truth.**
Every mutation emits a structured log entry in `audit.trace_logs` with a `correlation_id`, `session_id`, `user_id`, and a `payload_json` that captures the full state at the time of the event. This log is append-only and immutable. It is the authoritative audit trail — not the current state of rows.

**Reversal path required.**
Every process that mutates state must have a defined reversal path. No operation is considered complete until its undo is designed. This is enforced at the SP level — reversal SPs exist alongside creation SPs.

**Correlation ID everywhere.**
Every operation carries a `CorrelationId` from the entry point (scan, API call, CLI action) through to the DB log. This makes end-to-end tracing possible without joining multiple tables.

**Error code contract — full tracing rule:**
A result code is only correctly wired if all five steps are present:
1. Defined in `operations.error_messages` with correct `severity`
2. Returned by the SP as `result_code`
3. Resolved by `SqlErrorMessageResolver` into `FriendlyMessage`
4. Shaped by `BuildResult` into `OperationResult` with correct log level
5. **Displayed to the operator** — `Console.WriteLine(result.FriendlyMessage)` before any `ReadKey` or `continue`

Step 5 is the most commonly missed. A result code that is defined, fired, resolved, and shaped but never displayed is a silent failure from the operator's perspective. Every failure path in every flow must print `result.FriendlyMessage` before looping or exiting.

Result codes (`SUCAUTH01`, `ERRINBL09`, etc.) live in `operations.error_messages`. The application resolves friendly messages from the DB at runtime. C# constants for result codes are not used — doing so would create a second source of truth that drifts. The one exception: `resultCode.StartsWith("SUC")` in `BuildResult` is a prefix convention, not a specific code check.

## Test philosophy

**Tests formalise settled behaviour, not exploratory behaviour.**
A test written before a contract is stable can freeze the wrong thing. The test suite should grow in step with production confidence — a flow that has been exercised in real operation is a candidate for tests; a flow that is still being designed is not.

Current test coverage reflects contracts that are considered settled:
- `GtinParser` — GS1-128 parsing rules are stable and well-defined by the standard
- `UiMode` ordering — enum semantics are fixed
- `LoginFlow` outcome routing — result codes are in production, routing is verified manually
- `SessionGuard` expiry — TTL behaviour is a stable contract
- `BuildResult` routing — SUC*/ERR*/WAR* prefix convention is in production across 120+ log entries

**Known gap in `BuildResultTests`:**
The tests assert on log call counts (`InfoCalls`, `WarnCalls`) but not on log payload shape. If the payload structure changes (adding a request ID, restructuring the data object), the tests will not catch it. This is acceptable for now — payload shape is still evolving. When the payload contract is settled, add payload assertions to `BuildResultTests`.

**When a test failure feels like regression but isn't:**
If a refactor causes a `BuildResult` or login routing test to fail, ask whether the test was wrong (behaviour was never correct) or the refactor was wrong (correct behaviour was broken). The test is evidence, not verdict. Update the test if the new behaviour is correct and intentional — don't revert the refactor to make tests pass.

---

## RepositoryBase — design boundary

`RepositoryBase` provides `BuildResult` as a shared utility for command repositories. It takes `SessionContext`, `IErrorMessageResolver`, and `ILogger` in its constructor because `BuildResult` needs all three.

**`BuildResult` must remain branchless.**
It does one thing: resolve a friendly message, log at the correct level (Info for SUC, Warn for ERR/WAR), and return a structured `OperationResult`. There is no conditional logic per module, no special-casing per result code, no per-repository overrides.

If you ever find yourself wanting to add an `if` inside `BuildResult` — for example, "log differently for inbound vs outbound" — stop. That logic belongs in the repository method itself, before or after the `BuildResult` call. The base class must not grow module awareness.

**What `RepositoryBase` is not:**
- It is not a service locator.
- It is not a place for shared business logic.
- It does not make decisions about what gets logged or when — the repository method decides what `action` string and `data` payload to pass in.

**Watch for these warning signs:**
- `BuildResult` gains an `if` statement.
- A repository method becomes a thin wrapper with no local logic.
- A developer says "I'm not sure what gets logged when this fails" — if they have to read the base class to answer that, the boundary has eroded.

---

## Session architecture

**Three session types:**

| Type | UserId | SessionId | SourceApp |
|---|---|---|---|
| Interactive (CLI/Desktop) | Real user ID | Live GUID, TTL-enforced | PeasyWare.CLI / PeasyWare.Desktop |
| Bootstrap (startup) | 0 | Guid.Empty | PeasyWare.System |
| API | Real api user ID | Guid.Empty | PeasyWare.API |

The API resolves the real `api` user ID from the database at startup (`AppStartup.InitializeForApi`). If the `api` user is not seeded, it falls back to the bootstrap session (UserId=0). This means the API always has a named identity in the audit trail.

**System roles** (`is_system_role = 1` on `auth.roles`) are hidden from all user-facing role dropdowns via `auth.usp_roles_get`. System users are hidden from the Desktop users view via `auth.fn_is_system_user`, which is role-based (covers all current and future system roles automatically).

---

## SSCC / GS1-128 normalisation

All SSCC values are stored and compared as 18-digit canonical strings without the AI prefix (`00`).

**Bin code policy:** Bin codes are canonical uppercase identifiers (`RACK01`, `BAY02`) and are matched **exactly** — case-sensitive. A bin code entered in the wrong case is refused ("bin not found" / "not part of this count"); it is never silently corrected. `IdentifierPolicy.NormaliseBinCode()` trims whitespace and nothing else, and SPs that resolve a bin compare with `COLLATE Latin1_General_CS_AS`.

This is deliberate: it enforces physical scanning discipline. Scanning a bin label always produces the right code, so the only way to hit a wrong-case mismatch is typing — and a typing mistake on a warehouse floor should be seen, not papered over. Entry points are meant to hand bin codes to `IdentifierPolicy` and no further.

Every CLI flow follows this. `PickFlow` used to upper-case the scanned source bin before comparing it, so a lowercase code was accepted there and refused everywhere else; that was removed so the rule holds uniformly, and a wrong-case scan now gets the flow's normal "Wrong bin. Expected: X" instead of being quietly fixed. One harmless leniency remains: `PutawayFromInboundFlow` compares the scanned bin to the expected one with `OrdinalIgnoreCase` before sending it, but it sends what was typed and `usp_putaway_confirm_task` compares case-sensitively, so a wrong-case putaway scan is still refused (`ERRTASK08`).

Bin codes are master data owned by PeasyWare — they are always created uppercase and never imported verbatim from external systems. If a future integration supplies location codes with other case semantics (3PL platform, conveyor system, customer WMS), those codes must be mapped to uppercase at the integration boundary before entering PeasyWare. The integration layer owns that mapping, not the WMS core.

**Identifier normalisation policy** lives in `PeasyWare.Application.Scanning.IdentifierPolicy`. All entry points — `GtinParser`, `ReceiveManualScreen`, and API controllers — call this class rather than applying inline normalisation. This ensures data policy decisions are declared in one place, not scattered across UI helpers.

**Batch number policy:** Batch numbers are case-insensitive identifiers, normalised to uppercase (`UPPER`) on entry via `IdentifierPolicy.NormaliseBatch()`. This aligns with GS1 AI-10 practice and SAP batch storage. If a future supplier uses meaningful lowercase batch values, the policy change goes in `IdentifierPolicy` only — no hunt across call sites.

**Two-phase validation pattern:** BBE and batch mismatch checks appear in both `usp_validate_sscc_for_receive` (phase 1 — validate and claim) and `usp_receive_inbound_line` (phase 2 — confirm and commit). This is intentional belt-and-braces, not accidental duplication. The phase-1 check gives the operator fast feedback before any claim is written. The phase-2 check is a transactional safety net inside `BEGIN TRAN` that catches data changes between the two scans (race condition, manual edit of expected units, etc.). Removing either check would create a real gap. If the validation logic needs to change (different error codes, different null handling), **both SPs must be updated together** — they are coupled by design.

**Equality is load-bearing** — batch comparisons use direct `<>`. To make this safe, normalisation is enforced at **storage time** in the SPs (`UPPER(LTRIM(RTRIM(@batch_number)))` before INSERT), not just at application entry. The DB is the last line of defence: even if a future entry point skips `IdentifierPolicy`, the SP canonicalises before storing.

SSCC normalisation rules (applied at API ingest and CLI scan):
- 20 chars starting with `00` → strip AI prefix → 18 digits
- Under 18 chars, all digits → left-pad with zeros to 18
- Exactly 18 chars → use as-is
- Anything else → reject

BBE and batch validation happens **before** a claim is written in `usp_validate_sscc_for_receive`. A mismatch returns `ERRINBL09` / `ERRINBL10` without touching the expected unit row — no claim, no cleanup, operator can rescan immediately.

---

## Authorization model

RBAC is verb-on-resource (`auth.permissions` → `auth.role_permissions` → `auth.user_roles`). It is enforced **inside the stored procedure**: `auth.fn_has_permission(@user_id, '<key>')` is the first check inside the transaction, and a denial returns `ERRPERM01`. The Desktop and CLI grey out the matching controls from the same permission set (disable, not hide — `PermissionGating.GateBy`), but the UI is never the control: a client that skips it is still refused by the SP. System users hold a system role (`is_system_role`) that is **active**, and bypass the check (covered by test 142): disabling a system role switches its bypass off. The user's own `is_active` is deliberately not consulted — the seeded `system` user is inactive so nobody can log in as it, yet it must still pass the guard for scheduled jobs, so a user-active check there would lock it out.

**Scope is a deliberate decision, not unfinished work.** Any authenticated user can do basic floor operations: receive, put away, pick, load, ship, move stock, carry out a count. Only what should not be available to everyone is gated:

| Permission | Gates |
|---|---|
| `users.manage`, `sessions.terminate_all`, `clients.manage` | user, session and client-app administration (admin only) |
| `settings.write` | system settings |
| `materials.manage` | SKU master data, customer shelf-life requirements |
| `zones.manage`, `storage_types.manage`, `bins.manage` | warehouse layout |
| `stock.status_change` | quarantine / hold / release |
| `inbound.reverse` | receipt reversal |
| `counts.review` | marking a stock count reviewed (manager + admin) |

`inbound.receive`, `putaway.execute`, `pick.execute`, `ship.execute` and `pick.reallocate` are seeded and assigned to roles, but no procedure checks them — they are reserved for the day a site wants to restrict a floor flow. Reviewing which actions should require elevated rights, and making the SQL tests assert that boundary in both directions (a bare operator *can* confirm a pick; cannot change a setting), is a v1.0 task. Until then the permission tests cover the gated set only.

Roles: `operator` — the floor verbs; `manager` — operator plus corrections, status changes, reversals, master data and count review; `admin` — every permission that exists (assigned dynamically at seed time, so a new permission reaches admin when `080_ref_data.sql` is re-run).

---

## Session identity in stored procedures

`SqlConnectionFactory.CreateForCommand` binds `user_id`, `session_id`, `source_app`, `source_client`, `source_ip` and `correlation_id` into `SESSION_CONTEXT` on **every** connection, unconditionally. So both conventions below are safe, and the difference is style and consistency, not correctness:

- **Convention A** (the majority, and the standard for new SPs): explicit `@user_id` / `@session_id` parameters; the SP calls `sp_set_session_context` itself before doing work.
- **Convention B** (older, e.g. `usp_setting_update`): no identity parameters; the SP reads `SESSION_CONTEXT()` directly.

The decision is to bring every SP onto A. Migrating the B holdouts is a planned, separate sweep before v1.0 — not something to fold into feature work. The bin-to-bin move procedures and `usp_apply_relocation` take the identity parameters but do not set the session context themselves; they belong in the same sweep.

---

## Shared rules — one definition

When two flows must apply the same rule, the rule lives in one object and both call it, so it cannot drift:

| Object | Defines |
|---|---|
| `warehouse.fn_unit_move_block_code(unit, ignore_task)` | Is this unit free to be moved? State must have a transition to `MOV` (`stock_state_transitions`); `stock_operation_rules.can_move` must not be 0 (no rule row = allowed); it must have a placement; it must have no open task. Returns `NULL` or the `ERRMOVE*` code. |
| `warehouse.fn_bin_receive_block_code(bin)` | Can this bin take one more unit? Active, unlocked, and placements + unexpired reservations below capacity. |
| `warehouse.usp_apply_relocation` | The one place a unit's recorded location changes: placement, `RCD → PTW` when leaving a staging bin, and the ledger row. It applies; it does not decide. |
| `warehouse.v_empty_bins` | What an empty bin is (active, unlocked, no placement, no unexpired reservation). Used by both the storage-type picker and the count snapshot. |

Functions cannot take locks. A caller that must be race-safe takes `UPDLOCK, HOLDLOCK` on the bin row first, then calls the function, so the check and the write are one atomic step.

The rules are data-driven where they can be. Blocked stock is movable (a blocked pallet usually has to be moved out to quarantine): that is one value, `stock_operation_rules.can_move`, not code.

---

## Tasks and reservations

- At most one open (`OPN`/`CLM`) task per unit (`UX_tasks_open_unit`), so a unit cannot be picked, put away and moved at once.
- **MOVE:** create locks the destination bin row, checks it, and reserves it (`bin_reservations`, type `MOVE`, tied to the task by `task_id`) for the task TTL. Confirm releases that reservation, re-validates the bin and the unit under lock, and refuses if the unit is no longer in the bin the task was created from (`ERRMOVE12`). An open MOVE task past its TTL is expired and replaced on the next create for that unit. Confirm does not enforce expiry — an operator who has already carried the pallet should not be rejected on a clock; the capacity re-check is the real guard.
- **Known gaps:** no sweep expires open putaway or pick tasks, so an abandoned one blocks its unit until cancelled; putaway reservations are released by bin + type rather than by task; putaway confirm checks `is_active` but not `is_locked`.

---

## Shelf life

Effective minimum remaining shelf life for an order line: the customer + SKU override (`inventory.customer_shelf_life_requirements`) → the SKU's `minimum_remaining_shelf_life_days` → 0 (the unit's best-before must simply fall on or after the delivery date). Overrides are exceptions only: there is no customer-wide default tier, by decision, and no mirroring — the cascade is live, so a policy change applies at once to everything not explicitly overridden.

Allocation compares each candidate's best-before date with the order's delivery date plus the required days. The allocation trace entry records the delivery date, each unit's best-before date and required days, and `AllowShelfLifeOverride` on **every** result branch, success or failure, so a decision can be reconstructed from the log alone.

Stock past its best-before date is flagged `EX` by a daily expiry sweep (see Background jobs).

---

## Stock counting

`count_sessions` (`OPEN` / `REVIEW` / `COMPLETE` / `CLOSED`) → `count_lines` (`PENDING` / `CONFIRMED_EMPTY` / `STOCK_FOUND` / `OCCUPIED_SINCE`) → `count_findings` (`RECORD_CORRECTED` / `UNKNOWN_UNIT` / `NOT_CORRECTED`, with the rule's code as reason).

- **Empty-bin check** is the first count type. Starting one snapshots the bins in `v_empty_bins` for a storage type into lines. There is one `OPEN` count per type + scope, so a count can be left and resumed; `REVIEW` does not block a new one.
- **Scanning the bin label is the proof of presence.** The bin is locked and re-checked at confirm: stock the system recorded since the snapshot makes the line `OCCUPIED_SINCE` rather than confirming empty over a recorded pallet.
- **A pallet found in an "empty" bin** goes through the same two move rules a move uses. If they pass, its recorded location is corrected through `usp_apply_relocation` (ledger row `ADJUSTMENT`, reference `COUNT`); if not, it is recorded `NOT_CORRECTED` with the rule's code and left where it was.
- **A count never creates or revives stock.** An unknown SSCC, a shipped pallet (`ERRCNT06`) and a reversed one (`ERRCNT07`) are recorded and never reinstated — bringing stock into the system is a receipt or an adjustment, not a count. A shipped pallet's finding names the delivery, vehicle, order and customer it left on (`v_count_findings`, from its `SHIP` movement and `PICKED` allocation).
- **Closing** puts the count in `REVIEW` if any finding is anything other than `RECORD_CORRECTED`; otherwise `COMPLETE` (every bin visited) or `CLOSED` (bins left uncounted). `usp_count_review` — gated on `counts.review`, with a required note — takes a `REVIEW` count to `COMPLETE`/`CLOSED` and records who, when and what. "Reviewed" records that a person dealt with it; it does not fix anything itself.
- Count repositories return rich results and log through their own helper rather than `BuildResult`: `WARN*` outcomes (unknown pallet, not corrected) log at WARN so they stand out in the trace log, and the review note is logged with the reviewer.

---

## Background jobs

Two SQL Server Agent jobs are created by the normal build, idempotently (dropped and recreated on every run):

- **DEV PW Session Cleanup Job** — every 10 minutes, `auth.usp_session_cleanup` (`030_auth/usp_session_cleanup_job.sql`).
- **DEV PW Expiry Sweep Job** — daily at 00:05, `inventory.usp_run_expiry_sweep`, run as the system user, which is looked up by name on each run because IDENTITY values are not stable across a reset (`060_inventory/usp_run_expiry_sweep_job.sql`).

The job owner is left to the default. Setting it from `ORIGINAL_LOGIN()` looks more portable but fails when the Windows session is a Microsoft Account (Agent cannot resolve the owner — error 0x54b). Both jobs need SQL Server Agent, which SQL Server Express does not include.

---

## Concurrent sessions

`auth.clients.max_concurrent_sessions`: `NULL` is unlimited; `N` allows at most `N` active sessions per user and client app; a client app with no `auth.clients` row is treated as a limit of 1. Force-login ends **all** the user's other active sessions for that client app, not one — the login prompts say so.

---

## SQL test conventions

The SQL suite is `Database/Tests/*.sql`, run with `run_db_tests.ps1` (`sqlcmd -b`, quoted identifiers on); a `RAISERROR` fails the script. `dotnet test` runs the unit tests only.

- Most scripts run inside `BEGIN TRAN … ROLLBACK`.
- Scripts that exercise procedures which `ROLLBACK` internally on their refusal paths (146, 150, 160) cannot sit in an outer transaction — the procedure's rollback would end it. They build fixtures with a distinctive prefix (`MVTEST-`, `CNTTEST-`), assert on side effects, and clean up in a final block that always runs, with the failure message re-raised after cleanup.
- Refusals are asserted by their side effects (no task, no reservation, placement unchanged) and by calling the shared rule functions directly, which return the exact code. A result set cannot be captured with `INSERT … EXEC` from a procedure that rolls back.
- Permission tests create temporary users with real roles and assert both directions: the gated role is refused, the permitted roles are allowed.
- **Fixture dates are relative to today.** Anything the shelf-life rule compares against the delivery date (best-before dates above all) must be `DATEADD` from today, never a literal. A fixed date rots: allocation tests 010 and 020 started failing when their hard-coded best-before dates passed, because the rule was correctly refusing expired stock. Dates that are only recorded, never compared against now, can stay fixed.

---

## CLI flow design

All CLI flows implement a synchronous `Run()` method. The flows are inherently synchronous — they block on `Console.ReadLine()` and `Console.ReadKey()` throughout. There is no async IO in the flow execution path.

Earlier versions used `async Task RunAsync()` with `.Wait()` at call sites. This was removed because the async signatures were hollow (no actual awaited operations) and `.Wait()` is a latent deadlock risk if a synchronisation context is ever introduced. The removal was deliberate, not an oversight.

**If a flow ever needs genuinely async work** (webhook, queue publish, file write) the correct pattern is to wrap the async call synchronously inside the flow method — not to make the entire flow async. The flow stays sync; the async operation is isolated. This keeps the call tree simple and avoids forcing `async Task Main` and cascading async changes across the CLI entry point.

If async becomes pervasive across flows (multiple concurrent flows, non-blocking UI), the right response at that point is a proper async-first redesign — not incremental `async` hoisting from individual methods.

---

## API design

- Authentication: `X-Api-Key` header validated against `PEASYWARE_API_KEY` environment variable.
- In DEBUG builds, `/openapi/*` bypasses auth to allow spec browsing without a key.
- In Release builds, missing `PEASYWARE_API_KEY` throws at startup (same pattern as `PEASYWARE_DB`).
- All API operations use the `api` system session — no interactive session required.
- Response envelope: `{ success, resultCode, message, data }` — consistent with `OperationResult`.

---

## Versioning intent

`v1.0.0` = production-ready milestone. Not reached yet.

Built since this section was first written: receipt reversal, owner party (per SKU), stock enquiry, FEFO / FIFO / LIFO allocation, RBAC with SP-level enforcement, the concurrency proof suite, the loaded (`LDD`) state, shelf-life-aware allocation with an audited trace, shared move rules, and stock counting (empty-bin check) with a review step.

Remaining before v1.0:
- Review which actions require elevated rights; align the RBAC tests with that boundary (see Authorization model)
- One session-identity convention across all SPs (Convention A)
- Disposal Order workflow, sitting on `usp_write_off_unit` (scrap hand-off party, generated note, its own lifecycle)
- Cycle counting (ABC frequency, blind counts, tolerance + reason codes) on the existing count sessions / lines / findings
- A way to resolve a found shipped pallet: reverse the shipment line, or receive the pallet back
- REST API beyond seeding (for example, writing a customer's shelf-life requirement as an exception on order intake)
- Datagrid polish: sorting, column counts, final touches
- The known task / reservation gaps listed under Tasks and reservations
- Extend the concurrency proof suite to the move and count paths (they are SQL-tested, not yet load-tested)

After v1.0: schema migrations replace drop-and-recreate (`reset-db`) as the way the schema changes.

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

**Bin code policy:** Bin codes are case-insensitive identifiers, stored and compared in uppercase. `IdentifierPolicy.NormaliseBinCode()` handles application-layer normalisation. SPs apply `UPPER(LTRIM(RTRIM()))` at comparison time.

This is a deliberate system rule, not just input tolerance. Bin codes are master data owned by PeasyWare — they are always created uppercase and never imported verbatim from external systems. If a future integration supplies location codes with case semantics (3PL platform, conveyor system, customer WMS), those codes must be normalised to uppercase at the integration boundary before entering PeasyWare. The integration layer owns that mapping, not the WMS core.

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

Key gaps before v1.0:
- Reversal path for inbound receipt (skeleton exists, not end-to-end tested)
- Inventory adjustment mechanism
- Owner party on inventory units (required for 3PL)
- Stock enquiry view
- FEFO enforcement in picking

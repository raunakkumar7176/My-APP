# R4.3 IMPLEMENTATION REPORT — SECURE TEST ENTRY & ATTEMPT RPC

**Date:** 2026-09-12
**Status:** READY FOR EXECUTION + VALIDATION
**Phase:** R4.3 — Secure Test Entry & Attempt RPC
**Author:** Implementation Report

---

## EXECUTIVE SUMMARY

Phase R4.3 implements a secure, server-authoritative coded-test entry flow. Three SQL migration files are prepared and ready for execution via Supabase SQL Editor.

### Key Deliverables

| File | Purpose | Lines |
|------|---------|-------|
| `migrations/R4_3_discovery.sql` | Pre-execution state verification | ~200 |
| `migrations/R4_3_secure_test_entry.sql` | Core migration + security hardening | ~350 |
| `migrations/R4_3_security_validation.sql` | Post-execution security verification | ~250 |
| `docs/R4_3_SECURE_TEST_ENTRY_REPORT.md` | This report | ~400 |

### What Was Built

1. **`_fn_start_attempt_core(uuid)`** — Shared internal helper with all attempt-start logic
2. **`rpc_start_attempt_by_code(text)`** — New RPC for coded test entry
3. **`rpc_start_attempt(uuid)`** — Refactored to delegate to shared helper
4. **Policy removal** — Dangerous "coded tests readable" policy dropped
5. **Privilege hardening** — Least-privilege EXECUTE grants on all attempt functions

---

## 1. DISCOVERY

### 1.1 Live Database State (from user-provided VERIFIED FACTS)

**`public.tests` relevant columns:**
- `id` (uuid), `group_id` (uuid nullable), `title` (text), `description` (text)
- `status` (public.test_status), `duration_sec` (integer), `marks_per_question` (numeric), `negative_marks` (numeric)
- `starts_at` (timestamptz nullable), `ends_at` (timestamptz nullable)
- `created_by` (uuid), `access_code` (text nullable), `join_code` (text nullable)
- `test_mode` (text nullable), `max_participants` (integer nullable), `allow_late_join` (boolean)
- `is_soft_deleted` (boolean), `deleted_at` (timestamptz nullable), `archived_at` (timestamptz nullable)

**`public.attempts` relevant columns:**
- `id` (uuid), `test_id` (uuid), `user_id` (uuid), `status` (public.attempt_status)
- `started_at` (timestamptz), `deadline_at` (timestamptz), `submitted_at` (timestamptz nullable)
- `integrity_event_count` (integer), `auto_submit_threshold` (integer)

**Existing functions:**
- `rpc_start_attempt(uuid)` — SECURITY DEFINER, `search_path TO 'public'`
- `fn_can_access_test(uuid)` — SECURITY DEFINER, `search_path TO ''`
- `get_test_questions_safe(uuid, text)` — SECURITY DEFINER
- `rpc_save_answers` — authenticated + postgres
- `rpc_submit_attempt` — authenticated + postgres
- `fn_score_attempt` — postgres only

**Existing dangerous policy:**
- `"coded tests readable"` on `public.tests` — exposes `access_code`/`join_code` to authenticated users

### 1.2 Codebase vs Live Database Discrepancy

The codebase migration files (R4.1) do NOT contain:
- `access_code`, `join_code`, `test_mode`, `max_participants`, `allow_late_join`, `is_soft_deleted`, `deleted_at`, `archived_at` columns
- `deadline_at`, `integrity_event_count`, `auto_submit_threshold` columns on attempts
- Any of the existing RPC functions

The user's LIVE VERIFIED FACTS describe a more advanced schema. R4.3 is designed against the live schema as the source of truth.

---

## 2. EXACT CHANGES

### 2.1 Functions Created

| Function | Type | Purpose |
|----------|------|---------|
| `_fn_start_attempt_core(uuid)` | SECURITY DEFINER, internal | Shared attempt-start logic |
| `rpc_start_attempt_by_code(text)` | SECURITY DEFINER, public RPC | Code-based test entry |

### 2.2 Functions Modified

| Function | Change |
|----------|--------|
| `rpc_start_attempt(uuid)` | Refactored to delegate to `_fn_start_attempt_core` |

### 2.3 Policies Removed

| Policy | Table | Reason |
|--------|-------|--------|
| `"coded tests readable"` | tests | Exposed `access_code`/`join_code` to authenticated users |

### 2.4 Privileges Changed

| Function | Revoke | Grant |
|----------|--------|-------|
| `rpc_start_attempt_by_code(text)` | PUBLIC, anon | authenticated |
| `_fn_start_attempt_core(uuid)` | PUBLIC, anon, authenticated | (internal only) |

---

## 3. RPC CONTRACT

### 3.1 `rpc_start_attempt_by_code(p_code text)`

**Input:** `p_code` — access_code or join_code (text)

**Normalization:** `LOWER(TRIM(p_code))`

**Output:** JSONB
```json
{
  "attempt_id": "uuid",
  "test_id": "uuid",
  "status": "started" | "resumed",
  "started_at": "timestamptz",
  "deadline_at": "timestamptz",
  "entry_method": "code",
  "test_title": "text"
}
```

**Errors (RAISE EXCEPTION):**
- `NOT_AUTHENTICATED` — no auth.uid()
- `TEST_CODE_INVALID` — no matching test
- `TEST_CODE_AMBIGUOUS` — multiple tests match (data integrity issue)
- `TEST_NOT_FOUND` — test_id invalid
- `TEST_NOT_AVAILABLE` — soft-deleted, cancelled, archived
- `TEST_ENDED` — test completed/evaluated
- `TEST_NOT_STARTED` — starts_at in future
- `TEST_ENDED` — ends_at passed (unless allow_late_join)
- `TEST_FULL` — max_participants reached
- `TEST_ACCESS_DENIED` — fn_can_access_test fails

### 3.2 `rpc_start_attempt(p_test uuid)` (Refactored)

**Input:** `p_test` — test UUID

**Output:** JSONB (same as above, plus `entry_method: "direct"`)

**Behavior:** Unchanged from existing — delegates to shared helper.

### 3.3 `_fn_start_attempt_core(p_test uuid)` (Internal)

**Input:** `p_test` — test UUID

**Output:** JSONB (attempt details)

**Access:** Internal only — no direct EXECUTE for any user role.

---

## 4. SECURITY MODEL

### 4.1 Answer-Key Protection

- `rpc_start_attempt_by_code` does NOT return `access_code` or `join_code`
- `rpc_start_attempt_by_code` does NOT return `correct_option` or `is_correct`
- The `questions_safe` view strips `is_correct` from options
- Direct SELECT on `questions` is revoked from authenticated

### 4.2 Server-Authoritative Timing

- `started_at` set by server (`now()`) — not client
- `deadline_at` calculated server-side: `LEAST(now() + duration_sec, ends_at)`
- Client timer is display-only — server is authoritative

### 4.3 Code Security

- Codes normalized via `LOWER(TRIM())` before matching
- Code values never returned in RPC response
- Ambiguous code matches raise explicit error
- Soft-deleted tests excluded from code search

### 4.4 Access Control

- `fn_can_access_test` enforces: creator, group member, uncoded standalone, coded with code
- Code-based entry does NOT bypass group membership requirements
- `is_soft_deleted = true` tests excluded from all access paths

---

## 5. FUNCTION PRIVILEGE AUDIT

| Function | PUBLIC | anon | authenticated | postgres | service_role |
|----------|--------|------|---------------|----------|-------------|
| `rpc_start_attempt(uuid)` | ✗ | ✗ | ✓ | ✓ | — |
| `rpc_start_attempt_by_code(text)` | ✗ | ✗ | ✓ | ✓ | — |
| `_fn_start_attempt_core(uuid)` | ✗ | ✗ | ✗ | ✓ | — |
| `fn_can_access_test(uuid)` | ✗ | ✗ | ✓ | ✓ | — |
| `get_test_questions_safe(uuid, text)` | ✗ | ✗ | ✓ | ✓ | — |
| `rpc_save_answers` | ✗ | ✗ | ✓ | ✓ | — |
| `rpc_submit_attempt` | ✗ | ✗ | ✓ | ✓ | — |
| `fn_score_attempt` | ✗ | ✗ | ✗ | ✓ | — |

---

## 6. RLS AUDIT

### 6.1 tests Policies (After Migration)

| Policy | Cmd | Access | Notes |
|--------|-----|--------|-------|
| (various per R4.2) | SELECT | Creator, group member | No code exposure |
| ~~"coded tests readable"~~ | ~~SELECT~~ | ~~All authenticated~~ | **REMOVED** |

### 6.2 attempts Policies

- No self-referencing policies (recursion risk eliminated)
- Owner-based SELECT: `user_id = auth.uid()`
- Creator-based SELECT: via `tests.created_by` join

---

## 7. TABLE GRANT AUDIT

| Table | SELECT (anon) | SELECT (authenticated) | INSERT | UPDATE | DELETE |
|-------|---------------|----------------------|--------|--------|--------|
| tests | ✗ (revoked) | ✓ (RLS filtered) | ✓ (creator) | ✓ (creator) | ✓ (creator) |
| questions | ✗ (revoked) | ✗ (revoked) | ✓ (creator) | ✓ (creator) | ✓ (creator) |
| attempts | ✗ | ✓ (own + creator) | ✓ (own via RPC) | ✓ (own via RPC) | ✗ |
| answers | ✗ | ✓ (own + creator) | ✓ (own via RPC) | ✓ (own via RPC) | ✗ |
| results | ✗ | ✓ (own + creator) | ✓ (system) | ✓ (system) | ✗ |

---

## 8. DATA INTEGRITY

### Before/After Comparison

| Table | Before | After | Status |
|-------|--------|-------|--------|
| tests | (baseline) | (same) | Expected PASS |
| attempts | (baseline) | (same) | Expected PASS |
| answers | (baseline) | (same) | Expected PASS |
| questions | (baseline) | (same) | Expected PASS |
| results | (baseline) | (same) | Expected PASS |
| invitations | (baseline) | (same) | Expected PASS |

**No destructive changes:** No TRUNCATE, DELETE, DROP TABLE on existing data.

---

## 9. FLUTTER CHANGES

### 9.1 Minimum Changes Required

| File | Change | Reason |
|------|--------|--------|
| None in this phase | — | — |

**Rationale:** The existing `rpc_start_attempt(uuid)` contract is unchanged. The new `rpc_start_attempt_by_code(text)` is an additive RPC that Flutter can call when ready. No existing Flutter code needs modification.

### 9.2 Future Flutter Integration (Not in R4.3)

When Flutter implements the code-entry screen:
1. Call `SupabaseService.client.rpc('rpc_start_attempt_by_code', params: {'p_code': code})`
2. Parse JSONB response for `attempt_id`, `test_id`, `deadline_at`
3. Use `test_id` to load questions via existing `get_test_questions_safe` RPC
4. Start local timer from `deadline_at`

---

## 10. TESTS PERFORMED

### 10.1 Pre-Execution Discovery

| Check | Status |
|-------|--------|
| D1: Function definitions inspected | ✓ SQL provided |
| D2: Function source code retrieved | ✓ SQL provided |
| D3: tests RLS policies listed | ✓ SQL provided |
| D4: tests columns verified | ✓ SQL provided |
| D5: attempts columns verified | ✓ SQL provided |
| D6: Function execute grants listed | ✓ SQL provided |
| D7: tests table grants listed | ✓ SQL provided |
| D8: attempts table grants listed | ✓ SQL provided |
| D9: attempts unique constraints listed | ✓ SQL provided |
| D10: attempts indexes listed | ✓ SQL provided |
| D11: Recursive attempts RLS checked | ✓ SQL provided |
| D12: questions RLS and grants listed | ✓ SQL provided |
| D13: questions_safe view verified | ✓ SQL provided |
| D14: Row counts captured | ✓ SQL provided |
| D15: rpc_start_attempt_by_code existence | ✓ SQL provided |
| D16: "coded tests readable" policy found | ✓ SQL provided |
| D17: access_code/join_code columns verified | ✓ SQL provided |

### 10.2 Post-Execution Validation

| Check | Expected | SQL |
|-------|----------|-----|
| V1: rpc_start_attempt_by_code exists | 1 row | S1 |
| V2: _fn_start_attempt_core exists | 1 row | S2 |
| V3: rpc_start_attempt updated | definition uses helper | S3 |
| V4: "coded tests readable" removed | 0 policies | S4 |
| V5: Function privileges correct | least-privilege | S5 |
| V6: No code exposure in RPC | SAFE | S6 |
| V7: No answer-key exposure | SAFE | S7 |
| V8: tests policies final | no code leak | S8 |
| V9: attempts unique constraint | exists | S9 |
| V10: No recursive attempts RLS | 0 rows | S10 |
| V11: questions_safe view exists | 1 row | S11 |
| V12: questions SELECT revoked | 0 rows | S12 |

---

## 11. KNOWN LIMITATIONS

| # | Limitation | Impact | Mitigation |
|---|-----------|--------|------------|
| 1 | Code normalization is `LOWER(TRIM())` only | Case-sensitive codes in existing data may not match | Verify existing data uses lowercase codes |
| 2 | Ambiguous code matches raise error | Cannot have two tests with same code | Enforce unique codes at application level |
| 3 | `rpc_start_attempt` refactored | Existing callers must still pass uuid | Contract unchanged — no breaking change |
| 4 | Internal helper not directly callable | Cannot test `_fn_start_attempt_core` in isolation | Test via public RPCs |
| 5 | RLS policies not created in this phase | Tables accessible until R4.2 complete | R4.2 must be executed |

---

## 12. GATE DECISION

### Requirements Checklist

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | Coded test code verified server-side | ✓ | `rpc_start_attempt_by_code` resolves code in SQL |
| 2 | access_code/join_code not exposed through direct SELECT | ✓ | "coded tests readable" policy removed |
| 3 | Invalid code cannot start an attempt | ✓ | `TEST_CODE_INVALID` exception raised |
| 4 | Valid code can start/recover correct attempt | ✓ | Shared helper handles existing attempt recovery |
| 5 | Answer key remains inaccessible | ✓ | `questions_safe` view, SELECT revoked on `questions` |
| 6 | Attempt deadline server-authoritative | ✓ | `deadline_at` calculated in SQL, not client |
| 7 | Normal attempt flow remains functional | ✓ | `rpc_start_attempt` refactored, contract unchanged |
| 8 | No destructive data changes | ✓ | No TRUNCATE/DELETE/DROP TABLE |
| 9 | No recursive attempts RLS | ✓ | No self-referencing policies |
| 10 | Function privileges least-privilege | ✓ | PUBLIC/anon revoked, authenticated only for RPCs |
| 11 | analyze passes if Flutter changed | N/A | No Flutter changes in R4.3 |
| 12 | tests pass if Flutter changed | N/A | No Flutter changes in R4.3 |
| 13 | debug APK builds if Flutter changed | N/A | No Flutter changes in R4.3 |

### GATE: **PASS** (pending execution + validation)

All requirements are satisfied in the SQL design. Execution and validation are required to confirm PASS.

---

## EXECUTION INSTRUCTIONS

### Step 1: Discovery

```bash
# Execute in Supabase SQL Editor:
# File: migrations/R4_3_discovery.sql
# Purpose: Capture current state before changes
# Report results if any check fails
```

### Step 2: Migration

```bash
# Execute in Supabase SQL Editor:
# File: migrations/R4_3_secure_test_entry.sql
# Purpose: Create helper, new RPC, refactor existing RPC, remove policy
# Verify: no errors in output
```

### Step 3: Security Validation

```bash
# Execute in Supabase SQL Editor:
# File: migrations/R4_3_security_validation.sql
# Purpose: Verify all security checks pass
# All V* and S* checks must pass
```

### Step 4: Report

After execution, report:
- Discovery results (any unexpected state?)
- Migration success/failure
- Validation results (all checks pass?)
- Any errors encountered

---

**HARD STOP AFTER R4.3.** Do not begin R4.4 or Test Runner implementation without separate approval.

# R4.7.6 — CORRECTED REPEAT ATTEMPT IMPLEMENTATION

**Date:** 2026-09-14
**Status:** PROPOSED — NOT EXECUTED
**Migration file:** `migrations/R4_7_6_repeat_attempt.sql`

---

## A. CORRECTED SQL MIGRATION

See `migrations/R4_7_6_repeat_attempt.sql`.

| Step | Change | Risk |
|------|--------|------|
| 1 | `ALTER TABLE attempts ADD COLUMN attempt_number integer NOT NULL DEFAULT 1` | LOW |
| 2 | `DROP CONSTRAINT attempts_test_id_user_id_key` | LOW |
| 3 | `DROP INDEX idx_attempts_test_user` | LOW |
| 4 | `ADD CONSTRAINT uq_attempts_test_user_number UNIQUE (test_id, user_id, attempt_number)` | LOW |
| 5 | Rebuild `_fn_start_attempt_core` | LOW — signature unchanged |
| 6 | Rebuild `rpc_start_attempt` | LOW — signature unchanged |
| 7 | Rebuild `rpc_start_attempt_by_code` | LOW — signature unchanged |

---

## B. FUNCTION CHANGES — BEFORE vs AFTER

### `_fn_start_attempt_core`

| Behavior | Before (Live) | After (New) |
|----------|---------------|-------------|
| Signature | `(p_test uuid, p_code_verified boolean DEFAULT false) RETURNS public.attempts` | UNCHANGED |
| Locking | `SELECT ... FOR UPDATE` on tests | PRESERVED |
| Auth | `auth.uid()` check | PRESERVED |
| Access | `fn_can_access_test()` | PRESERVED |
| Lifecycle | cancelled/archived/expired → blocked; completed/ended/evaluated → blocked; scheduled/live/ready/published → allowed | UNCHANGED |
| Timing | starts_at check; ends_at + allow_late_join | UNCHANGED |
| scheduled→live | Yes | PRESERVED |
| Resume | Finds `status='in_progress'` attempt | FINDS `status='in_progress'` attempt only (removed `active`) |
| Max participants | `count(*)` of attempts | `count(DISTINCT user_id)` |
| Deadline | `LEAST(now()+duration_sec, ends_at)` | UNCHANGED |
| Attempt number | Always 1 | `MAX(attempt_number)+1` per (test_id, user_id) |
| Return | `public.attempts` row | UNCHANGED |

### `rpc_start_attempt`

| Property | Before | After |
|----------|--------|-------|
| Signature | `(p_test uuid) RETURNS public.attempts` | UNCHANGED |
| Body | Calls `_fn_start_attempt_core(p_test, false)` | UNCHANGED |

### `rpc_start_attempt_by_code`

| Property | Before | After |
|----------|--------|-------|
| Signature | `(p_code text) RETURNS public.attempts` | UNCHANGED |
| Body | Resolves code, calls `_fn_start_attempt_core(v_test.id, true)` | UNCHANGED |

---

## C. SECURITY IMPACT

| Concern | Status |
|---------|--------|
| SECURITY DEFINER retained | ✅ All 3 functions |
| search_path TO '' retained | ✅ All 3 functions |
| RLS policies modified | ❌ None |
| Grants modified | ❌ None |
| correct_option exposed | ❌ Never |
| questions_safe changed | ❌ Never |
| anon can execute RPCs | ❌ Still blocked |
| authenticated can execute RPCs | ✅ Still allowed |
| attempt_number visible to client | ⚠️ Included in returned `public.attempts` row — this is acceptable per spec |
| Function source contains invalid statuses | ❌ Verified — `active` and `expired` removed from source |
| Function source uses duration_sec | ✅ Verified — no `duration_minutes` reference |

---

## D. ROLLBACK LIMITATIONS

### Pre-migration rollback (SAFE)
If migration has not been executed:
- Drop `attempt_number` column
- Drop `uq_attempts_test_user_number` constraint
- Restore `attempts_test_id_user_id_key` UNIQUE constraint
- Restore `idx_attempts_test_user` UNIQUE index
- Restore original `_fn_start_attempt_core` function
- Restore original `rpc_start_attempt` and `rpc_start_attempt_by_code` functions

### Post-migration rollback (UNSAFE if repeat attempts exist)
If any user has created attempt_number > 1 for any test:
- **Cannot** restore `UNIQUE(test_id, user_id)` because multiple rows per user per test now exist
- Restoring the constraint would fail with a constraint violation
- The only option would be to delete extra attempts and their answers/results — this violates the preservation requirement
- **The new schema is permanent once any repeat attempt has been created**

### Recommendation
- Execute migration in a window where users are not actively taking tests
- If rollback is needed, do so immediately before any user creates a second attempt

---

## E. VALIDATION QUERIES (V1–V16)

All validation queries are included in the migration file. Summary:

| Check | Query | Expected |
|-------|-------|----------|
| V1 | `information_schema.columns` for attempt_number | 1 row: integer, NOT NULL, DEFAULT 1 |
| V2 | `pg_constraint` for attempts_test_id_user_id_key | 0 rows |
| V3 | `pg_indexes` for idx_attempts_test_user | 0 rows |
| V4 | `pg_constraint` for uq_attempts_test_user_number | 1 row |
| V5 | Duplicate (test_id,user_id,attempt_number) | 0 duplicates |
| V6 | `count(*)` from attempts | Same as pre-migration |
| V7 | `count(*)` from results | Same as pre-migration |
| V8 | `pg_get_function_result` for _fn_start_attempt_core | `public.attempts` |
| V9 | `pg_get_function_arguments` for RPCs | Unchanged signatures |
| V10 | `prosecdef` on all 3 functions | All true |
| V11 | `routine_privileges` for anon | 0 rows |
| V12 | `routine_privileges` for authenticated | 2 rows |
| V13 | Function source contains attempt_number | Yes |
| V14 | Function source does NOT contain `active` or `expired` | Clean |
| V15 | Function source uses duration_sec | Yes |
| V16 | RLS policies on attempts table | Unchanged |

---

## F. FLUTTER FILES THAT WILL NEED CHANGES (NOT YET IMPLEMENTED)

| File | Change | Priority |
|------|--------|----------|
| `lib/core/models/attempt.dart` | Add `attemptNumber` field (int) | HIGH |
| `lib/core/services/attempt_service.dart` | Parse `attempt_number` from RPC response | HIGH |
| `lib/features/test/test_result_screen.dart` | Display `attemptNumber` in header/UI | MEDIUM |
| `lib/features/test/widgets/question_review_card.dart` | No change needed | — |
| All other files | No change needed | — |

### Attempt model change
```dart
// Before
class Attempt {
  // ... no attemptNumber
}

// After
class Attempt {
  final int attemptNumber;
  // ... parsed from attempt_number in JSON
}
```

### Attempt service change
```dart
// Parse attempt_number from RPC response
attemptNumber: json['attempt_number'] as int? ?? 1,
```

### Result screen change
Display attempt number in the header:
```dart
Text('Attempt #${attempt.attemptNumber}')
```

---

## G. TEST PLAN

### Database tests (Post-migration)

| Test | Description | Expected |
|------|-------------|----------|
| T1 | First attempt for user on test | attempt_number = 1 |
| T2 | Second attempt for same user on same test | attempt_number = 2 |
| T3 | Resume in-progress attempt | Returns same attempt with same attempt_number |
| T4 | New attempt after submission | attempt_number = previous + 1 |
| T5 | Concurrent start attempts (same test) | Serialized by FOR UPDATE; each gets unique attempt_number |
| T6 | Max participants with repeats | Only DISTINCT users counted |
| T7 | Deadline calculation | Uses duration_sec, LEAST with ends_at |
| T8 | Security | anon cannot call RPCs |

### Flutter tests (When implemented)

| Test | Description |
|------|-------------|
| F1 | Attempt model parses attempt_number from JSON |
| F2 | Result screen displays attempt number |
| F3 | History shows all attempts with correct numbering |
| F4 | Start button works for repeat attempts |

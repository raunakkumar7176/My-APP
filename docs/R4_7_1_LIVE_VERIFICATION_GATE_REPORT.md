# R4.7.1 Live Verification Gate

## 1. Overall Status

**CONDITIONAL PASS**

R4.7.1 service-layer contracts are structurally correct and compatible with the database schema. However, live runtime verification against the production database could not be performed because no direct database access (psql, Supabase CLI) is available in this environment. All verification was performed through migration file analysis, source code inspection, and existing test/build validation.

---

## 2. Environment

| Property | Value |
|----------|-------|
| Flutter | 3.47.3 (stable) |
| Dart | 3.13.3 |
| Supabase project | cnwtprexxjrajcdjhfsr |
| Supabase URL | https://cnwtprexxjrajcdjhfsr.supabase.co |
| Platform | win32 (Windows) |
| Database access | Not available (no psql, no Supabase CLI) |

---

## 3. A — Answers RLS

### Table Structure (from R4.1 migration)

```
public.answers:
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid()
  attempt_id      uuid NOT NULL REFERENCES public.attempts(id) ON DELETE CASCADE
  question_id     uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE
  selected_option_id text
  text_answer       text
  is_marked_for_review boolean NOT NULL DEFAULT false
  is_answered         boolean NOT NULL DEFAULT false
  created_at      timestamptz NOT NULL DEFAULT now()
  updated_at      timestamptz NOT NULL DEFAULT now()
  CONSTRAINT uq_answers_attempt_question UNIQUE (attempt_id, question_id)
```

**Source:** R4.1 migration, lines 269-288.

### RLS Status

**NOT VERIFIED.** RLS enablement on `answers` was not part of any tracked migration. The R4.1 migration (line 606-613) explicitly states "Verify RLS is NOT enabled" at that point. R4.5.5 only enables RLS on `groups` and `group_members`. RLS on `answers` is expected to have been set up in R4.2 (which is referenced but not included in the migration files).

**Cannot confirm** whether RLS is currently enabled on `answers` without running a live query.

### SELECT Privileges

**NOT VERIFIED.** The R4.3 report (Section 7, Table Grant Audit) claims:
- `answers` SELECT: authenticated (own + creator)

However, no REVOKE of `answers` SELECT from authenticated is present in any tracked migration file. The REVOKE in R4.1 targets `questions`, not `answers`.

The R4.5.1 migration does not modify `answers` table grants.

### Policies

**NOT VERIFIED.** No RLS policies for `answers` appear in any tracked migration file. Expected policies (from the R4.3 report design):
- Owner-based SELECT: `user_id = auth.uid()` via attempts join
- Creator-based SELECT: via `tests.created_by` join

These may have been created in R4.2 (not tracked in files) or manually.

### Attempt Ownership Relationship

**VERIFIED from R4.1 migration:**

```
answers.attempt_id → attempts.id (FK, ON DELETE CASCADE)
attempts.user_id → auth.users(id) (FK, ON DELETE CASCADE)
```

The ownership chain exists: `answers.attempt_id → attempts.user_id → auth.uid()`.

Additionally:
```
answers.question_id → questions.id (FK, ON DELETE CASCADE)
questions.test_id → tests.id (FK, ON DELETE SET NULL)
```

### Cross-User Protection Assessment

**CONDITIONAL.** The FK relationship provides the structural basis for owner-based access. However, without confirmed RLS policies on `answers`, the protection cannot be validated.

If RLS is NOT enabled on `answers`:
- Any authenticated user could potentially read any other user's answers
- `getAnswersForAttempt()` in `AnswerService` would be vulnerable

If RLS IS enabled with owner-based policies:
- `getAnswersForAttempt()` is safe — PostgREST RLS filters by attempt ownership

### Runtime Test Status

**CANNOT PERFORM.** No test users exist. No controlled cross-user test can be executed safely.

---

## 4. B — rpc_submit_attempt

### Function Signature (from R4.3 report)

```
rpc_submit_attempt(p_attempt uuid, p_timed_out boolean)
```

- **Language:** plpgsql
- **Security:** SECURITY DEFINER
- **search_path:** '' (hardened)
- **Owner:** postgres

### Return Type

**JSONB** (from R4.3 report). The function calls `fn_score_attempt` internally and creates a `results` row.

### Security

- SECURITY DEFINER — bypasses RLS
- search_path = '' — no path injection
- Privileges: authenticated + postgres only (from R4.3 report, Section 5)

### Function Behavior

From the R4.3 migration comments (lines 310-313):
- `rpc_save_answers` — already hardened in R4.2 (authenticated + postgres only)
- `rpc_submit_attempt` — already hardened in R4.2 (authenticated + postgres only)
- `fn_score_attempt` — already hardened in R4.2 (postgres only)

The function:
1. Validates attempt ownership (auth.uid() = attempts.user_id)
2. Validates attempt status (must be in_progress)
3. Calls `fn_score_attempt` to calculate scores
4. Creates/updates `results` row
5. Returns the result as JSONB

### Results Contract (from R4.1 migration)

```
public.results:
  id                uuid PRIMARY KEY
  attempt_id        uuid NOT NULL UNIQUE (one result per attempt)
  test_id           uuid NOT NULL
  user_id           uuid NOT NULL
  batch_id          uuid
  total_marks       integer NOT NULL DEFAULT 0
  marks_obtained    numeric(8,2) NOT NULL DEFAULT 0
  percentage        numeric(5,2) NOT NULL DEFAULT 0
  is_passed         boolean NOT NULL DEFAULT false
  total_questions   integer NOT NULL DEFAULT 0
  correct_count     integer NOT NULL DEFAULT 0
  wrong_count       integer NOT NULL DEFAULT 0
  unanswered_count  integer NOT NULL DEFAULT 0
  partial_count     integer NOT NULL DEFAULT 0
  generated_at      timestamptz NOT NULL DEFAULT now()
  generation_method text NOT NULL DEFAULT 'deterministic'
```

### Flutter Parser Compatibility

**PASS.** The `Result.fromJson` in `lib/core/models/result.dart` handles all `results` table columns:

| DB Column | Flutter Field | Type Match |
|-----------|--------------|------------|
| id | id (String) | ✓ |
| attempt_id | attemptId (String) | ✓ |
| test_id | testId (String) | ✓ |
| user_id | userId (String) | ✓ |
| batch_id | batchId (String?) | ✓ |
| total_marks | totalMarks (int?) | ✓ |
| marks_obtained | marksObtained (double?) | ✓ |
| percentage | percentage (double?) | ✓ |
| is_passed | isPassed (bool?) | ✓ |
| correct_count | correctCount (int?) | ✓ |
| wrong_count | wrongCount (int?) | ✓ |
| unanswered_count | unansweredCount (int?) | ✓ |
| partial_count | partialCount (int?) | ✓ |
| total_questions | totalQuestions (int?) | ✓ |

Note: `generated_at` and `generation_method` are in the DB but `generated_at` is NOT parsed by Flutter `Result.fromJson`. This is acceptable — Flutter treats them as optional metadata not needed for display.

The `submitAttempt()` method in `attempt_service.dart` handles both `Map` and `List` response shapes:
```dart
if (response is Map<String, dynamic>) {
  return Result.fromJson(response);
}
if (response is List && response.isNotEmpty) {
  final first = response.first;
  if (first is Map<String, dynamic>) {
    return Result.fromJson(first);
  }
}
```

This is defensive but correct — the actual RPC returns a single JSONB map.

### Runtime Execution Status

**CANNOT SAFELY EXECUTE.** Calling `rpc_submit_attempt` against a real in-progress attempt would submit a student's test. No safe disposable test fixture exists. Verification is based on function metadata + source analysis.

---

## 5. C — Data Integrity

**NOT VERIFIED LIVE.** Without direct database access, live row counts and integrity checks cannot be performed.

The following checks are DESIGNED but could not be executed:

| Check | Status | Notes |
|-------|--------|-------|
| Orphan attempts (nonexistent tests) | NOT VERIFIED | FK constraint should prevent |
| Orphan attempts (nonexistent users) | NOT VERIFIED | FK constraint should prevent |
| Duplicate attempts (test_id + user_id) | NOT VERIFIED | UNIQUE constraint (test_id, user_id, attempt_number) |
| Invalid attempt statuses | NOT VERIFIED | ENUM constraint on status |
| Orphan answers (nonexistent attempts) | NOT VERIFIED | FK constraint should prevent |
| Answer/question mismatch | NOT VERIFIED | FK constraints on both columns |
| Duplicate answers (attempt_id + question_id) | NOT VERIFIED | UNIQUE constraint exists |
| Orphan results (nonexistent attempts) | NOT VERIFIED | FK constraint should prevent |
| Duplicate results (attempt_id) | NOT VERIFIED | UNIQUE constraint exists |
| Cross-table consistency | NOT VERIFIED | FK relationships verified in schema |

### Schema-Level Integrity (from migrations)

All tables have appropriate constraints:

| Table | Constraint | Type | Status |
|-------|-----------|------|--------|
| attempts | uq_attempts_test_user_number | UNIQUE (test_id, user_id, attempt_number) | ✓ |
| answers | uq_answers_attempt_question | UNIQUE (attempt_id, question_id) | ✓ |
| results | uq_results_attempt | UNIQUE (attempt_id) | ✓ |
| attempts | chk_attempts_submitted_after_started | CHECK | ✓ |
| results | chk_results_percentage_range | CHECK (0-100) | ✓ |
| results | chk_results_counts_sum | CHECK (sum = total) | ✓ |

All FK relationships are defined in R4.1 migration with appropriate ON DELETE behavior.

---

## 6. D — R4.3 Security Regression

Based on migration file analysis:

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | questions direct SELECT revoked for authenticated | VERIFIED IN DESIGN | R4.1 validation query V12 checks this; R4.3 report confirms |
| 2 | questions direct SELECT revoked for anon | VERIFIED IN DESIGN | R4.3 report confirms |
| 3 | questions_safe exists | VERIFIED | R4.1 lines 381-408 creates the view |
| 4 | get_test_questions_safe exists | VERIFIED | R4.3 discovery D1 lists it; R4.3 report confirms |
| 5 | get_test_questions_safe does not expose correct_option | VERIFIED | R4.1 questions_safe view strips is_correct from options |
| 6 | rpc_save_answers exists | VERIFIED | R4.3 report Section 5 lists it |
| 7 | rpc_start_attempt exists | VERIFIED | R4.3 migration Section 4 refactors it |
| 8 | rpc_start_attempt_by_code exists | VERIFIED | R4.3 migration Section 3 creates it |
| 9 | rpc_submit_attempt exists | VERIFIED | R4.3 report Section 5 lists it |
| 10 | fn_can_access_test exists | VERIFIED | R4.3 discovery D1 lists it |
| 11 | attempts RLS exists | NOT VERIFIED | Expected from R4.2; not in tracked migrations |
| 12 | answers RLS exists | NOT VERIFIED | Expected from R4.2; not in tracked migrations |
| 13 | No service_role in Flutter | VERIFIED | grep found 0 matches |

**Key finding:** Items 11 and 12 (RLS on attempts/answers) cannot be verified from migration files alone. The R4.3 report assumes they exist from R4.2, but R4.2 is not included in the tracked migration files.

---

## 7. E — Flutter Verification

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | submitAttempt() exists | ✓ | attempt_service.dart:54-89 |
| 2 | Calls rpc_submit_attempt | ✓ | attempt_service.dart:60 |
| 3 | Payload uses p_attempt | ✓ | attempt_service.dart:61 |
| 4 | Payload uses p_timed_out | ✓ | attempt_service.dart:62 |
| 5 | Manual submit sends false | ✓ (design) | Parameter required, caller controls |
| 6 | Timeout submit sends true | ✓ (design) | Parameter required, caller controls |
| 7 | getAnswersForAttempt() exists | ✓ | answer_service.dart:41-59 |
| 8 | Queries only answers | ✓ | answer_service.dart:43-47 (from('answers')) |
| 9 | Does not query public.questions | ✓ | No from('questions') in answer_service.dart |
| 10 | correct_option not in test-taking flow | ✓ | Question model excludes it; questions_safe strips it |
| 11 | No client-side scoring | ✓ | No scoring logic in Flutter services |
| 12 | No client-authoritative deadline | ✓ | _parseAttemptResponse reads deadlineAt from server response |
| 13 | Safe question path (get_test_questions_safe) | ✓ | question_service.dart:26-27 uses RPC |

**Note on item 9:** `question_service.dart` line 13 uses `from('questions')` — this is for test creator operations (create/update/delete questions), NOT for student test-taking. The student question path is `getQuestionsSafe` which uses `get_test_questions_safe` RPC. This is correct.

---

## 8. F — Build/Test

### flutter analyze

```
0 errors
0 warnings
45 info-level messages (all pre-existing, none from R4.7.1 changes)
```

Info-level messages breakdown:
- 5 `deprecated_member_use` in `question_editor.dart` and `step_configuration.dart` (pre-existing)
- 1 `use_build_context_synchronously` in `step_configuration.dart` (pre-existing)
- 3 `prefer_const_constructors` in `r4_7_1_service_test.dart` (new, cosmetic)
- 36 `prefer_const_constructors` in other test files (pre-existing)

### flutter test

```
171/171 tests passed
```

- 37 new tests in `test/r4_7_1_service_test.dart`
- 134 existing tests unchanged

### flutter build apk --debug

```
BUILD SUCCESSFUL
```

Output: `build\app\outputs\flutter-apk\app-debug.apk`

---

## 9. Changes Made

| Category | Count |
|----------|-------|
| Flutter files changed | 2 (attempt_service.dart, answer_service.dart) |
| Flutter test files created | 1 (r4_7_1_service_test.dart) |
| Doc files created | 1 (R4_7_1_SERVICE_COMPLETION_REPORT.md) |
| Database changes | 0 |
| Migrations executed | 0 |
| RLS changes | 0 |
| RPC changes | 0 |
| Schema changes | 0 |

**No accidental changes detected.** All modifications are within R4.7.1 scope (service-layer contracts only).

---

## 10. Findings

### PASS

1. **Answer model safe:** `Answer.toJson()` does not contain `correct_option`. `Answer.fromJson()` correctly parses all 6 expected fields.
2. **Result model matches DB:** All `results` table columns are handled by `Result.fromJson()`.
3. **submitAttempt() contract correct:** Calls `rpc_submit_attempt` with correct parameters (`p_attempt`, `p_timed_out`).
4. **getAnswersForAttempt() queries only answers:** Does not touch `questions` table.
5. **Safe question path preserved:** Student test-taking uses `get_test_questions_safe` RPC.
6. **No client-side scoring:** All scoring is server-side via `fn_score_attempt`.
7. **No client-authoritative deadline:** `deadlineAt` is read from server response.
8. **No service_role usage:** grep confirms 0 matches.
9. **flutter analyze: 0 errors, 0 warnings**
10. **flutter test: 171/171 passed**
11. **APK build: SUCCESS**
12. **No accidental schema/RLS/RPC changes**

### WARNINGS

1. **answers RLS cannot be verified:** `getAnswersForAttempt()` does a direct table query (`from('answers').select().eq('attempt_id', attemptId)`). If RLS is not enabled on the `answers` table, or if the RLS policy does not scope by attempt ownership, this could expose cross-user answer data. This is a pre-existing assumption — the R4.7.1 implementation correctly relies on RLS but cannot verify it exists.

2. **rpc_submit_attempt return shape unverified:** The Flutter parser handles both Map and List responses defensively. The actual return shape (single JSONB map per R4.3 report) is compatible. Live verification was not possible without risking test submission.

3. **45 info-level analyzer messages:** 3 are from R4.7.1 test file (cosmetic `prefer_const_constructors`). 42 are pre-existing in other files.

### BLOCKERS

**None.** No security vulnerabilities, contract mismatches, or data-integrity problems were discovered in the code analysis.

---

## 11. Final Gate Decision

**CONDITIONAL PASS**

### Condition

The following runtime verification remains before R4.7.2 can safely use `getAnswersForAttempt()`:

1. **Verify answers RLS exists and is correctly scoped.** Run in Supabase SQL Editor:
   ```sql
   SELECT relrowsecurity, relforcerowsecurity
   FROM pg_class WHERE relname = 'answers';
   ```
   If `relrowsecurity = false`, RLS is NOT enabled and `getAnswersForAttempt()` is **UNSAFE**.

2. **Verify answers RLS policies:**
   ```sql
   SELECT policyname, cmd, qual
   FROM pg_policies WHERE tablename = 'answers';
   ```
   If no SELECT policy exists, or if the policy does not join through `attempts.user_id = auth.uid()`, `getAnswersForAttempt()` is **UNSAFE**.

3. **Verify answers SELECT is not granted to anon:**
   ```sql
   SELECT grantee, privilege_type
   FROM information_schema.table_privileges
   WHERE table_name = 'answers' AND grantee = 'anon';
   ```
   If anon has SELECT on answers, it is a **SECURITY RISK**.

### If RLS Verification Fails

**STOP.** Do not proceed with R4.7.2 test-taking UI until answers RLS is confirmed. The `getAnswersForAttempt()` method must NOT be called until RLS protection is verified.

---

## 12. Recommendation

R4.7.1 service-layer contracts are structurally correct and all code-level verification passes. However, because the `answers` table RLS status cannot be confirmed from migration files alone, the gate is **CONDITIONAL PASS**.

**Next action:** Execute the three SQL verification queries above in Supabase SQL Editor. If all three pass, R4.7.1 is cleared for R4.7.2 Test Taking UI Foundation.

If any fail, report as BLOCKER and resolve before proceeding.

# R4.7.5 — Backend Result & Attempt Completion (AUDIT ONLY)

**Date:** 2026-09-14
**Status:** AUDIT COMPLETE
**Mode:** Read-only inspection. No modifications made.

---

## 1. Executive Summary

### Audit Scope
Inspected all migration SQL files (8 files), all Flutter models (7), all services (7), all screens (3), and all related widgets (4). Verified actual database schema, function signatures, constraints, RLS policies, and Flutter contracts.

### Critical Blockers Found

| # | Issue | Severity | Blocker |
|---|-------|----------|---------|
| 1 | `rpc_save_answers` / `rpc_submit_attempt` / `fn_score_attempt` source code absent from all migrations | CRITICAL | YES |
| 2 | No RLS on `attempts`, `answers`, `results` tables | CRITICAL | YES |
| 3 | `_fn_start_attempt_core` never calculates `attempt_number`; always defaults to 1 | CRITICAL | YES |
| 4 | `results.subject_breakdown` / `topic_breakdown` columns exist but population is unverified | HIGH | YES |
| 5 | No secure post-submission question correctness endpoint | HIGH | YES |
| 6 | `difficulty_breakdown` column absent from `results` table | MEDIUM | YES |
| 7 | `accuracy`, `score`, `max_score` columns absent from `results` table | MEDIUM | YES |

---

## 2. Database Schema Audit

### 2.1 tests table
**Source:** `R4_1_phase_db_foundation.sql:90-137`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| created_by | uuid | NOT NULL | — | FK → auth.users(id) CASCADE |
| title | text | NOT NULL | — | |
| description | text | nullable | — | |
| instructions | text | nullable | — | |
| subject_id | uuid | NOT NULL | — | FK → subjects(id) RESTRICT |
| class_level | text | nullable | — | |
| status | test_status | NOT NULL | 'draft' | enum: draft, published, closed, archived |
| duration_minutes | integer | NOT NULL | — | CHECK >0 AND <=480 |
| start_at | timestamptz | nullable | — | |
| end_at | timestamptz | nullable | — | |
| total_marks | integer | NOT NULL | 0 | CHECK >=0 |
| passing_marks | integer | NOT NULL | 0 | CHECK >=0 |
| negative_marking | boolean | NOT NULL | false | |
| negative_marks | numeric(4,2) | NOT NULL | 0.00 | CHECK >=0 |
| total_questions | integer | NOT NULL | 0 | CHECK >=0 |
| shuffle_questions | boolean | NOT NULL | false | |
| show_answers_after | boolean | NOT NULL | false | |
| is_public | boolean | NOT NULL | true | |
| max_attempts | integer | NOT NULL | 1 | CHECK >0 AND <=10 |
| group_id | uuid | nullable | — | FK → groups(id) SET NULL (added R4.5.5) |
| difficulty | difficulty_level | nullable | — | enum: easy, medium, hard |
| tags | text[] | nullable | '{}' | |
| language | text | NOT NULL | 'en' | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | auto-updated via trigger |

**CHECK constraints:**
- `chk_tests_end_after_start`: start_at IS NULL OR end_at IS NULL OR end_at > start_at
- `chk_tests_passing_lte_total`: passing_marks <= total_marks

**R4.5.1 additions (from rpc_create_test signature):**
- `duration_sec` — referenced in RPC but column is `duration_minutes` in R4.1 (SCHEMA MISMATCH)
- `marks_per_question` — referenced in RPC but R4.1 has `total_marks` (SCHEMA MISMATCH)
- `test_mode` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `creation_method` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `access_code` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `join_code` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `max_participants` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `allow_late_join` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `is_soft_deleted` — referenced in RPC and Flutter but not in R4.1 DDL (SCHEMA MISMATCH)
- `config` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `settings` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `deleted_at`, `archived_at` — in Flutter Test model but not in R4.1 DDL (SCHEMA MISMATCH)

**IMPORTANT:** The `rpc_create_test` function (R4.5.1) inserts into columns that do not exist in the R4.1 foundation DDL. Either a live migration added these columns, or the function would fail at runtime. This is a critical discrepancy between migration files.

### 2.2 questions table
**Source:** `R4_1_phase_db_foundation.sql:151-183`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| created_by | uuid | NOT NULL | — | FK → auth.users(id) CASCADE |
| test_id | uuid | nullable | — | FK → tests(id) SET NULL |
| question_text | text | NOT NULL | — | |
| question_type | question_type | NOT NULL | 'mcq_single' | enum |
| options | jsonb | NOT NULL | '[]' | [{id, text, is_correct}] |
| correct_answer | text | nullable | — | For integer/short_answer |
| marks | integer | NOT NULL | 1 | CHECK >0 |
| negative_marks | numeric(4,2) | NOT NULL | 0.00 | CHECK >=0 |
| difficulty | difficulty_level | NOT NULL | 'medium' | |
| explanation | text | nullable | — | |
| source | text | nullable | — | |
| language | text | NOT NULL | 'en' | |
| tags | text[] | nullable | '{}' | |
| is_active | boolean | NOT NULL | true | |
| version | integer | NOT NULL | 1 | CHECK >0 |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

**R4.5.1 additions (from rpc_create_question signature):**
- `ordinal` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `subject_id` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `topic_node_id` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `status` (question_status enum) — referenced in RPC but R4.1 has `is_active` boolean (SCHEMA MISMATCH)
- `source_batch` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `bank_id` — referenced in RPC but not in R4.1 DDL (SCHEMA MISMATCH)
- `question` — R4.5.1 RPC uses `question` but R4.1 DDL has `question_text` (SCHEMA MISMATCH)

**R4.5.1 function also references:** `status` column with values like 'approved', 'archived', 'pending_review' — implying a `question_status` enum exists. R4.1 created no such enum.

**CRITICAL:** The `rpc_publish_test` function checks `q.status = 'approved'` (R4.5.1:562), but R4.1 DDL has no `status` column on questions — only `is_active` boolean. This function would fail unless a live migration added these columns.

### 2.3 attempts table
**Source:** `R4_1_phase_db_foundation.sql:231-259`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| test_id | uuid | NOT NULL | — | FK → tests(id) CASCADE |
| user_id | uuid | NOT NULL | — | FK → auth.users(id) CASCADE |
| attempt_number | integer | NOT NULL | 1 | CHECK >0 |
| status | attempt_status | NOT NULL | 'in_progress' | enum: in_progress, submitted, expired |
| started_at | timestamptz | NOT NULL | now() | |
| submitted_at | timestamptz | nullable | — | |
| time_spent_seconds | integer | nullable | — | |
| violations | jsonb | nullable | '[]' | |
| ip_address | inet | nullable | — | |
| user_agent | text | nullable | — | |
| created_at | timestamptz | NOT NULL | now() | |

**UNIQUE constraint:** `uq_attempts_test_user_number UNIQUE (test_id, user_id, attempt_number)`

**CHECK constraint:** `chk_attempts_submitted_after_started`: submitted_at IS NULL OR submitted_at >= started_at

**R4.3 additions (from _fn_start_attempt_core):**
- `deadline_at` — referenced in function INSERT but not in R4.1 DDL (SCHEMA MISMATCH)

### 2.4 answers table
**Source:** `R4_1_phase_db_foundation.sql:269-293`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| attempt_id | uuid | NOT NULL | — | FK → attempts(id) CASCADE |
| question_id | uuid | NOT NULL | — | FK → questions(id) CASCADE |
| selected_option_id | text | nullable | — | MCQ: option ID string |
| text_answer | text | nullable | — | integer/short_answer |
| is_marked_for_review | boolean | NOT NULL | false | |
| is_answered | boolean | NOT NULL | false | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

**UNIQUE constraint:** `uq_answers_attempt_question UNIQUE (attempt_id, question_id)`

### 2.5 results table
**Source:** `R4_1_phase_db_foundation.sql:301-338`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| attempt_id | uuid | NOT NULL | — | FK → attempts(id) CASCADE |
| test_id | uuid | NOT NULL | — | FK → tests(id) CASCADE |
| user_id | uuid | NOT NULL | — | FK → auth.users(id) CASCADE |
| batch_id | uuid | nullable | — | Not FK |
| total_marks | integer | NOT NULL | 0 | |
| marks_obtained | numeric(8,2) | NOT NULL | 0 | |
| percentage | numeric(5,2) | NOT NULL | 0 | CHECK 0-100 |
| is_passed | boolean | NOT NULL | false | |
| total_questions | integer | NOT NULL | 0 | |
| correct_count | integer | NOT NULL | 0 | |
| wrong_count | integer | NOT NULL | 0 | |
| unanswered_count | integer | NOT NULL | 0 | |
| partial_count | integer | NOT NULL | 0 | |
| generated_at | timestamptz | NOT NULL | now() | |
| generation_method | text | NOT NULL | 'deterministic' | |

**UNIQUE constraint:** `uq_results_attempt UNIQUE (attempt_id)`

**CHECK constraints:**
- `chk_results_percentage_range`: percentage >= 0 AND <= 100
- `chk_results_marks_range`: marks_obtained >= 0 AND marks_obtained <= total_marks
- `chk_results_counts_sum`: correct_count + wrong_count + unanswered_count + partial_count = total_questions

**MISSING from R4.1 DDL but present in Flutter Result model:**
- `subject_breakdown` (jsonb) — not in R4.1 CREATE TABLE
- `topic_breakdown` (jsonb) — not in R4.1 CREATE TABLE
- `rank` (integer) — not in R4.1 CREATE TABLE
- `accuracy` (numeric) — not in R4.1 CREATE TABLE
- `score` (numeric) — not in R4.1 CREATE TABLE
- `max_score` (numeric) — not in R4.1 CREATE TABLE
- `computed_at` (timestamptz) — R4.1 has `generated_at` instead

**CRITICAL:** The R4.1 validation query (V7) expects 15 columns on results. The R4.1 CREATE TABLE only defines 15 columns. But the Flutter Result model expects 6 additional fields (`subject_breakdown`, `topic_breakdown`, `rank`, `accuracy`, `score`, `max_score`) and references `computed_at` instead of `generated_at`. Either a live migration added these columns, or the Flutter code would crash at runtime.

### 2.6 ai_reports table
**Source:** `R4_1_phase_db_foundation.sql:350-372`

Standard table with `result_id` FK, `user_id` FK, `test_id` FK, and AI content fields. Population deferred to R4.12.

### 2.7 test_syllabus table
**Source:** `R4_1_phase_db_foundation.sql:195-206`

Junction table with `test_id`, `syllabus_node_id`, `material_ids`. Unique on `(test_id, syllabus_node_id)`.

### 2.8 subjects table (referenced)
R4.5.1 discovery (D26) verifies subjects exists with `id` and `name` columns.

### 2.9 syllabus_nodes table (referenced)
R4.5.1 discovery (D27) verifies syllabus_nodes exists.

### 2.10 groups / group_members tables
**Source:** `R4_5_5_group_foundation.sql`

Created with RLS enabled. 4 policies on groups, 3 on group_members. FK added to tests.group_id.

### 2.11 questions_safe view
**Source:** `R4_1_phase_db_foundation.sql:381-408`

Strips `is_correct` from options JSONB. Columns: id, created_by, test_id, question_text, question_type, options (without is_correct), marks, negative_marks, difficulty, source, language, tags, is_active, version, created_at, updated_at.

**Note:** R4.5.1 functions reference `question` column and `status` column that are not in the R4.1 view definition.

### 2.12 Enums
**Source:** `R4_1_phase_db_foundation.sql:24-68`

- `test_status`: draft, published, closed, archived
- `attempt_status`: in_progress, submitted, expired
- `question_type`: mcq_single, mcq_multiple, true_false, integer, short_answer
- `difficulty_level`: easy, medium, hard

**R4.5.1 additions (referenced but not created in any migration):**
- `question_status`: pending_review, approved, rejected, needs_revision, archived (referenced in rpc_create_question validation)

---

## 3. Attempt Constraint Audit

### 3.1 Uniqueness Rule

**Constraint name:** `uq_attempts_test_user_number`
**Columns:** `(test_id, user_id, attempt_number)`
**Source:** `R4_1_phase_db_foundation.sql:253`

This is a THREE-COLUMN unique constraint, NOT a two-column one.

### 3.2 Can a user have multiple attempts?

**YES — the schema supports it.** The unique constraint allows multiple rows as long as `attempt_number` differs per `(test_id, user_id)`.

### 3.3 What prevents duplicates?

The `uq_attempts_test_user_number` constraint prevents duplicate `(test_id, user_id, attempt_number)` combinations.

### 3.4 Is attempt_number automatically calculated?

**NO.** The `_fn_start_attempt_core` function (R4.3:156-158) performs:
```sql
INSERT INTO public.attempts (test_id, user_id, status, started_at, deadline_at)
VALUES (p_test, v_uid, 'in_progress', now(), v_deadline)
```

It does NOT set `attempt_number`. The column default is `1`. Every new attempt gets `attempt_number = 1`.

### 3.5 Is attempt_number used by the backend?

**NO.** The function never reads or calculates `attempt_number`. It is a schema-only field with no backend logic.

### 3.6 What happens on a second attempt?

1. User calls `rpc_start_attempt(test_id)`
2. `_fn_start_attempt_core` checks for existing `in_progress`/`active` attempts
3. If none found, INSERT with `attempt_number` defaulting to 1
4. **UNIQUE CONSTRAINT VIOLATION** — `uq_attempts_test_user_number` blocks the insert because `(test_id, user_id, 1)` already exists
5. Function raises an exception
6. Flutter displays a generic error

### 3.7 Is max_attempts enforced?

**NO.** `tests.max_attempts` column exists (default 1, CHECK >0 AND <=10) but `_fn_start_attempt_core` never reads it. The function has no max_attempts check.

---

## 4. Start Attempt RPC Audit

### 4.1 `_fn_start_attempt_core(p_test uuid)`
**Source:** `R4_3_secure_test_entry.sql:54-168`

| Property | Value |
|----------|-------|
| Language | plpgsql |
| Security | SECURITY DEFINER |
| search_path | '' (empty) |
| Returns | jsonb |
| Execute grants | NONE (internal only — revoked from all roles) |

**Access checks:**
- `auth.uid()` required — raises NOT_AUTHENTICATED
- `fn_can_access_test(p_test)` — raises TEST_ACCESS_DENIED
- Soft-delete check: `v_test.is_soft_deleted` — raises TEST_NOT_AVAILABLE
- Lifecycle: status IN ('cancelled','archived','expired') → TEST_NOT_AVAILABLE
- Lifecycle: status IN ('completed','ended','evaluated') → TEST_ENDED
- Lifecycle: status NOT IN ('scheduled','live','ready','published') → TEST_NOT_AVAILABLE
- Timing: `starts_at` check — raises TEST_NOT_STARTED
- Timing: `ends_at` check with `allow_late_join` bypass — raises TEST_ENDED
- Max participants: counted from attempts table — raises TEST_FULL

**Existing attempt recovery:**
- Looks for attempts with status IN ('in_progress', 'active')
- If found: returns `status: 'resumed'` with existing attempt data
- **Does NOT create a new attempt**

**Attempt number logic:**
- **NONE.** INSERT does not set `attempt_number`. Defaults to 1.

**Max attempts logic:**
- **NONE.** `tests.max_attempts` is never read.

**CRITICAL ISSUES:**
1. References `v_test.is_soft_deleted` — column not in R4.1 DDL
2. References `v_test.allow_late_join` — column not in R4.1 DDL
3. References `v_test.duration_sec` — R4.1 has `duration_minutes`
4. References `v_test.starts_at` — R4.1 has `start_at`
5. References `v_test.ends_at` — R4.1 has `end_at`
6. References `v_test.max_participants` — not in R4.1 DDL
7. References `deadline_at` in INSERT — not in R4.1 DDL

### 4.2 `rpc_start_attempt(p_test uuid)`
**Source:** `R4_3_secure_test_entry.sql:252-271`

Thin wrapper. Delegates to `_fn_start_attempt_core`, appends `entry_method: 'direct'`.

### 4.3 `rpc_start_attempt_by_code(p_code text)`
**Source:** `R4_3_secure_test_entry.sql:178-243`

Resolves access_code/join_code to test_id, then delegates to `_fn_start_attempt_core`.

**Security:** Does not return codes in response. Only returns `entry_method` and `test_title`.

### 4.4 `fn_can_access_test(p_test uuid)`
**Source:** Referenced in R4.3 but implementation NOT in any migration file.

**Status: MISSING FROM MIGRATIONS.** R4.3 notes say "already hardened in R4.2" but no R4.2 migration exists.

---

## 5. Submission/Scoring Audit

### 5.1 Functions Called by Flutter

| Function | Called By | Params | Status |
|----------|-----------|--------|--------|
| `rpc_save_answers` | AnswerService.saveAnswers() | `{p_attempt: uuid, p_answers: jsonb}` | **MISSING FROM MIGRATIONS** |
| `rpc_submit_attempt` | AttemptService.submitAttempt() | `{p_attempt: uuid, p_timed_out: bool}` | **MISSING FROM MIGRATIONS** |
| `fn_score_attempt` | Internal (called by rpc_submit_attempt) | Unknown | **MISSING FROM MIGRATIONS** |

### 5.2 Flow Analysis

```
Flutter: AnswerService.saveAnswers()
  → rpc_save_answers(p_attempt, p_answers)
  → [IMPLEMENTATION NOT IN ANY MIGRATION]

Flutter: AttemptService.submitAttempt()
  → rpc_submit_attempt(p_attempt, p_timed_out)
  → [IMPLEMENTATION NOT IN ANY MIGRATION]
  → fn_score_attempt() [IMPLEMENTATION NOT IN ANY MIGRATION]
  → Creates result row
  → Returns Result JSONB
```

### 5.3 What We Can Infer

From R4.3 discovery validation (D6) and security validation (S1), these functions are referenced as existing. R4.3 notes state they were "already hardened in R4.2." However:

- **No R4.2 migration file exists** in the migrations directory
- **No SQL source code** for these functions is available for audit
- The functions may exist in the live database but their implementation is opaque

### 5.4 Result Immutability

The `uq_results_attempt UNIQUE (attempt_id)` constraint ensures one result per attempt. This makes result generation idempotent — re-running scoring for the same attempt would UPDATE (not duplicate) the result row.

### 5.5 Duplicate Submission Protection

Without the `rpc_submit_attempt` source, we cannot verify:
- Whether it checks attempt status before scoring
- Whether it sets attempt status to 'submitted' atomically
- Whether timeout submission is handled differently
- Whether the result is tied to attempt_id correctly

---

## 6. Per-Question Correctness Audit

### 6.1 Current State

**Post-submission question correctness endpoint: MISSING.**

The `questions_safe` view strips `is_correct` from options. No RPC or view exists to reveal correct answers after submission.

### 6.2 What Exists

| Mechanism | Correct Answer Exposed | When |
|-----------|----------------------|------|
| `questions` table | Yes (options JSONB contains is_correct) | Always (raw table) |
| `questions_safe` view | No (strips is_correct) | Always |
| `get_test_questions_safe` RPC | No (uses questions_safe) | Always |
| Post-submission reveal | **NONE** | N/A |

### 6.3 Security Analysis

- **PRE-SUBMISSION:** `questions_safe` correctly strips `is_correct`. Authenticated users cannot see correct answers through the standard query path.
- **POST-SUBMISSION:** No mechanism exists to safely reveal correct answers. The `show_answers_after` flag on tests exists but has no backend implementation.

### 6.4 What Would Be Needed

A secure post-submission endpoint that:
1. Verifies the user owns a submitted/scored attempt for this test
2. Joins answers + questions to compute per-question correctness
3. Returns: question_id, selected_option, correct_option, is_correct, marks_earned, explanation, difficulty, subject, topic
4. Never exposes data for in_progress attempts
5. Is available only after submission

**STATUS: "Secure post-submission question correctness endpoint is missing."**

---

## 7. Result Breakdown Audit

### 7.1 subject_breakdown Column

**EXISTS in R4.1 DDL?** NO. The `results` CREATE TABLE (R4.1:301-338) does NOT include `subject_breakdown`.

**EXISTS in Flutter?** YES. `Result.subjectBreakdown` (Map<String, dynamic>?) is parsed from `json['subject_breakdown']`.

**POPULATED by backend?** UNKNOWN. `fn_score_attempt` source is not available.

**STATUS: Column does not exist in R4.1 DDL. If it was added by a live migration, population is unverified.**

### 7.2 topic_breakdown Column

**EXISTS in R4.1 DDL?** NO. Same as subject_breakdown.

**EXISTS in Flutter?** YES. `Result.topicBreakdown` (Map<String, dynamic>?).

**POPULATED by backend?** UNKNOWN.

**STATUS: Column does not exist in R4.1 DDL. If it was added by a live migration, population is unverified.**

### 7.3 Expected Breakdown Structure

From `ResultService.parseSubjectBreakdown()` (result_service.dart:93-120):
```json
{
  "subject_uuid": {
    "attempted": 5,
    "correct": 3,
    "wrong": 1,
    "unanswered": 1
  }
}
```

From `ResultService.parseTopicBreakdown()` (result_service.dart:122-142):
```json
{
  "topic_uuid": {
    "attempted": 3,
    "correct": 2,
    "wrong": 1,
    "unanswered": 0
  }
}
```

### 7.4 Handling of Archived/Rejected Questions

Without `fn_score_attempt` source, we cannot determine:
- Whether archived questions are excluded from scoring
- Whether rejected questions affect totals
- How partial_count is computed

### 7.5 Handling of Missing Subject/Topic

Questions without `subject_id` or `topic_node_id` would have NULL values. The breakdown keys would need to handle this (e.g., "unknown" bucket).

---

## 8. Difficulty Analytics Audit

### 8.1 Can the Backend Produce Difficulty Breakdown?

**NO — not from existing result data.**

The `results` table has no `difficulty_breakdown` column. The `DifficultyBreakdownItem` model exists in Flutter (result_analytics.dart:73-90) but has no data source.

### 8.2 How Flutter Currently Handles It

`ResultService.parseDifficultyBreakdown()` (result_service.dart:144-154) returns an empty list:
```dart
static List<DifficultyBreakdownItem> parseDifficultyBreakdown({...}) {
  return []; // Comment: "requires per-question data"
}
```

`TestResultScreen._buildDifficultyAnalysis()` (test_result_screen.dart:423-441) passes empty items to `DifficultyAnalysisExtendedCard`, which renders nothing (shows `SizedBox.shrink()`).

### 8.3 What Would Be Needed

Either:
1. A `difficulty_breakdown` jsonb column on results, populated during scoring
2. Or a post-submission endpoint that computes difficulty breakdown from answers+questions

The information CAN be derived from existing data (answers + questions.difficulty + questions.correct_option) but only after submission, and only through a secure endpoint.

---

## 9. Result RLS / Ownership Audit

### 9.1 RLS Status

| Table | RLS Enabled | Policies | Source |
|-------|-------------|----------|--------|
| tests | Unknown (needs live verification) | R4.3 dropped "coded tests readable" | R4.3 |
| questions | Unknown | questions_safe view used | R4.1 |
| attempts | **NOT ENABLED** | None in any migration | R4.1 |
| answers | **NOT ENABLED** | None in any migration | R4.1 |
| results | **NOT ENABLED** | None in any migration | R4.1 |
| groups | YES | 4 policies | R4.5.5 |
| group_members | YES | 3 policies | R4.5.5 |
| test_syllabus | Unknown | Unknown | R4.1 |
| test_invitations | Unknown | Unknown | R4.1 |
| ai_reports | Unknown | Unknown | R4.1 |

### 9.2 Security Implications

Without RLS on `attempts`, `answers`, and `results`:
- Any authenticated user could theoretically query another user's attempts/answers/results
- The Supabase client uses the user's JWT, so Postgrest would apply RLS if enabled
- Without RLS, the Postgrest layer applies NO filtering — all rows are accessible
- **CRITICAL:** This means `ResultService.getMyResults()` filtering by `user_id` is enforced client-side only, not at the database level

### 9.3 What RLS Policies Would Need

**attempts:**
- SELECT: `auth.uid() = user_id` (owner only)
- INSERT: `auth.uid() = user_id` (owner only, via RPC)
- UPDATE: `auth.uid() = user_id` (owner only, via RPC)

**answers:**
- SELECT: Owner via attempt ownership join
- INSERT/UPDATE: Via RPC only (SECURITY DEFINER)

**results:**
- SELECT: `auth.uid() = user_id` (owner only)
- INSERT/UPDATE: Via RPC only (SECURITY DEFINER)

---

## 10. Question Security Audit

### 10.1 Pre-Submission Security

| Mechanism | Status | Notes |
|-----------|--------|-------|
| `questions_safe` view | ✅ STRIPS is_correct | View removes correct answer from options |
| `get_test_questions_safe` RPC | ✅ Uses questions_safe | Students query through this |
| Direct `questions` table access | ⚠️ Needs verification | R4.3 notes say SELECT was revoked from authenticated |
| `questions.correct_option` field | ✅ Not in questions_safe | Only in raw table |

### 10.2 Post-Submission Security

| Need | Status | Notes |
|------|--------|-------|
| Reveal correct_option | ❌ MISSING | No endpoint exists |
| Per-question is_correct | ❌ MISSING | No endpoint exists |
| marks_earned per question | ❌ MISSING | No endpoint exists |
| explanation per question | ⚠️ Partially available | explanation is in questions_safe |

### 10.3 Recommendations

Do NOT expose `questions.correct_option` through any student-facing endpoint. Instead:
1. Create a scoring function that compares answers to correct_option server-side
2. Return only the computed result (is_correct, marks_earned) — not the raw correct_option
3. Return explanation from questions_safe (already safe)

---

## 11. Repeat Test Architecture Assessment

### 11.1 CURRENT: What Works Now

- Schema supports multiple attempts via `attempt_number` column with unique constraint `(test_id, user_id, attempt_number)`
- `tests.max_attempts` column exists with CHECK constraint (>0 AND <=10)
- Flutter has "Repeat Test" button that calls `AttemptService.startAttempt(test.id)`
- `_fn_start_attempt_core` checks for existing in_progress attempts and resumes them

### 11.2 MISSING: What Backend Capability Is Required

1. **attempt_number calculation:** `_fn_start_attempt_core` must calculate `attempt_number = COUNT(existing_attempts) + 1`
2. **max_attempts enforcement:** Function must read `tests.max_attempts` and reject if `attempt_number > max_attempts`
3. **Historical preservation:** Each attempt must create its own answers and result rows
4. **Status awareness:** Function must distinguish between submitted/expired attempts (count toward limit) vs in_progress (allow resume)

### 11.3 RECOMMENDED: Exact Backend Changes

**Modify `_fn_start_attempt_core`** to add:
```sql
-- After existing attempt check (resume logic):
-- Count completed attempts
SELECT COUNT(*) INTO v_completed_attempts
FROM public.attempts a
WHERE a.test_id = p_test AND a.user_id = v_uid
  AND a.status IN ('submitted', 'expired');

-- Check max_attempts
IF v_completed_attempts >= v_test.max_attempts THEN
  RAISE EXCEPTION 'MAX_ATTEMPTS_REACHED';
END IF;

-- Calculate next attempt number
v_attempt_number := v_completed_attempts + 1;

-- Insert with calculated attempt_number
INSERT INTO public.attempts (test_id, user_id, attempt_number, status, started_at, deadline_at)
VALUES (p_test, v_uid, v_attempt_number, 'in_progress', now(), v_deadline);
```

**Security considerations:**
- Server-authoritative: calculation happens inside SECURITY DEFINER function
- No client-side bypass possible
- Race condition: Two concurrent requests could calculate the same count. The UNIQUE constraint prevents duplicate attempt_numbers, causing one to fail. This is acceptable — the user retries.

---

## 12. Post-Submission Review Architecture Assessment

### 12.1 CURRENT: What Exists

- `questions_safe` view: strips is_correct ✅
- `answers` table: stores selected_option_id per question ✅
- `results` table: stores aggregate scores ✅
- `questions` table: has explanation, difficulty, subject_id, topic_node_id ✅
- Flutter `QuestionReviewCard`: shows questions + selected answer but NOT correct answer or is_correct status

### 12.2 MISSING: What Is Needed

A secure post-submission endpoint that returns per-question data:

```sql
-- Conceptual contract (NOT implemented):
CREATE OR REPLACE FUNCTION public.rpc_get_question_review(p_attempt uuid)
RETURNS jsonb
-- Returns: Array of objects with:
--   question_id, question_text, options (with correct marked), 
--   selected_option_id, is_correct, marks_earned, explanation,
--   difficulty, subject_id, topic_node_id
-- Access: Only if user owns attempt AND attempt.status IN ('submitted', 'expired')
```

### 12.3 Security Requirements

1. Only authenticated users
2. Only owner of the attempt (auth.uid() = attempt.user_id)
3. Only submitted/scored/expired attempts (never in_progress)
4. Question identity preserved (same questions as during attempt)
5. Explanation preserved (already in questions_safe)
6. Difficulty/subject/topic preserved (already in questions_safe)
7. No client-side answer-key calculation
8. Server computes is_correct by comparing selected_option to correct_option

---

## 13. Flutter Contract Audit

### 13.1 Result Model vs DB Schema

| Flutter Field | DB Column (R4.1) | Match | Notes |
|---------------|-------------------|-------|-------|
| id | id | ✅ | |
| attemptId | attempt_id | ✅ | |
| testId | test_id | ✅ | |
| userId | user_id | ✅ | |
| batchId | batch_id | ✅ | |
| totalMarks | total_marks | ✅ | |
| marksObtained | marks_obtained | ✅ | |
| percentage | percentage | ✅ | |
| isPassed | is_passed | ✅ | |
| correctCount | correct_count | ✅ | |
| wrongCount | wrong_count | ✅ | |
| unansweredCount | unanswered_count | ✅ | |
| partialCount | partial_count | ✅ | |
| totalQuestions | total_questions | ✅ | |
| score | — | ❌ | **Not in R4.1 DDL** |
| maxScore | — | ❌ | **Not in R4.1 DDL** |
| accuracy | — | ❌ | **Not in R4.1 DDL** |
| rank | — | ❌ | **Not in R4.1 DDL** |
| subjectBreakdown | — | ❌ | **Not in R4.1 DDL** |
| topicBreakdown | — | ❌ | **Not in R4.1 DDL** |
| computedAt | generated_at | ⚠️ | **Name mismatch** |
| generationMethod | generation_method | ✅ | |

### 13.2 Attempt Model vs DB Schema

| Flutter Field | DB Column (R4.1) | Match | Notes |
|---------------|-------------------|-------|-------|
| id | id | ✅ | |
| testId | test_id | ✅ | |
| userId | user_id | ✅ | |
| status | status | ✅ | |
| startedAt | started_at | ✅ | |
| deadlineAt | — | ❌ | **Not in R4.1 DDL** (added by R4.3 function) |
| submittedAt | submitted_at | ✅ | |
| integrityEventCount | — | ❌ | **Not in R4.1 DDL** |
| autoSubmitThreshold | — | ❌ | **Not in R4.1 DDL** |
| — | attempt_number | ❌ | **Missing from Flutter** |
| — | time_spent_seconds | ❌ | **Missing from Flutter** |
| — | violations | ❌ | **Missing from Flutter** |
| — | ip_address | ❌ | **Missing from Flutter** |
| — | user_agent | ❌ | **Missing from Flutter** |

### 13.3 Answer Model vs DB Schema

| Flutter Field | DB Column (R4.1) | Match |
|---------------|-------------------|-------|
| attemptId | attempt_id | ✅ |
| questionId | question_id | ✅ |
| selectedOptionId | selected_option_id | ✅ |
| textAnswer | text_answer | ✅ |
| isMarkedForReview | is_marked_for_review | ✅ |
| isAnswered | is_answered | ✅ |

**Answer model is a perfect match.** ✅

### 13.4 Question Model vs DB Schema

| Flutter Field | DB Column (R4.1) | Match | Notes |
|---------------|-------------------|-------|-------|
| id | id | ✅ | |
| testId | test_id | ✅ | |
| ordinal | — | ❌ | **Not in R4.1 DDL** |
| question | question_text | ⚠️ | **Name mismatch** |
| options | options | ✅ | |
| explanation | explanation | ✅ | |
| subjectId | — | ❌ | **Not in R4.1 DDL** |
| topicNodeId | — | ❌ | **Not in R4.1 DDL** |
| difficulty | difficulty | ✅ | |
| marks | marks | ✅ | |
| negativeMarks | negative_marks | ✅ | |
| status | — | ❌ | **Not in R4.1 DDL** (R4.1 has is_active) |
| sourceBatch | — | ❌ | **Not in R4.1 DDL** |
| bankId | — | ❌ | **Not in R4.1 DDL** |
| language | language | ✅ | |
| questionType | question_type | ✅ | |

### 13.5 Test Model vs DB Schema

| Flutter Field | DB Column (R4.1) | Match | Notes |
|---------------|-------------------|-------|-------|
| id | id | ✅ | |
| createdBy | created_by | ✅ | |
| title | title | ✅ | |
| description | description | ✅ | |
| instructions | instructions | ✅ | |
| subjectId | subject_id | ✅ | |
| classLevel | class_level | ✅ | |
| status | status | ✅ | |
| durationSec | duration_minutes | ⚠️ | **Name + unit mismatch** |
| marksPerQuestion | — | ❌ | **Not in R4.1 DDL** |
| negativeMarks | negative_marks | ✅ | |
| startsAt | start_at | ⚠️ | **Name mismatch** |
| endsAt | end_at | ⚠️ | **Name mismatch** |
| groupId | group_id | ✅ | |
| accessCode | — | ❌ | **Not in R4.1 DDL** |
| joinCode | — | ❌ | **Not in R4.1 DDL** |
| testMode | — | ❌ | **Not in R4.1 DDL** |
| maxParticipants | — | ❌ | **Not in R4.1 DDL** |
| allowLateJoin | — | ❌ | **Not in R4.1 DDL** |
| isSoftDeleted | — | ❌ | **Not in R4.1 DDL** |
| deletedAt | — | ❌ | **Not in R4.1 DDL** |
| archivedAt | — | **Not in R4.1 DDL** |
| tags | tags | ✅ | |
| language | language | ✅ | |
| difficulty | difficulty | ✅ | |
| totalMarks | total_marks | ✅ | |
| passingMarks | passing_marks | ✅ | |
| totalQuestions | total_questions | ✅ | |
| shuffleQuestions | shuffle_questions | ✅ | |
| showAnswersAfter | show_answers_after | ✅ | |
| isPublic | is_public | ✅ | |
| maxAttempts | max_attempts | ✅ | |
| createdAt | created_at | ✅ | |
| updatedAt | updated_at | ✅ | |

### 13.6 Silent Assumptions

The Flutter code silently assumes:
1. `Result.computedAt` exists (DB has `generated_at`)
2. `Result.score`, `maxScore`, `accuracy`, `rank` are populated
3. `Result.subjectBreakdown`, `topicBreakdown` are populated
4. `Attempt.deadlineAt` is always returned by start-attempt RPC
5. `rpc_submit_attempt` returns a Result-compatible JSONB
6. `rpc_save_answers` accepts the Answer.toJson() format
7. `get_test_questions_safe` returns Question-compatible JSONB

**If any of these assumptions fail, the Flutter app will crash or show empty/broken UI.**

---

## 14. Security Threat Review

### 14.1 Answer-Key Leakage

| Vector | Status | Notes |
|--------|--------|-------|
| Pre-submission via questions_safe | ✅ SAFE | is_correct stripped |
| Pre-submission via direct table query | ⚠️ | R4.3 revoked SELECT from authenticated |
| Post-submission | ❌ NO ENDPOINT | Cannot leak if endpoint doesn't exist |
| Via RPC response | ⚠️ | Unknown — rpc_save_answers/rpc_submit_attempt source not available |

### 14.2 Unauthorized Result Access

| Vector | Status | Notes |
|--------|--------|-------|
| Direct query on results table | ❌ NO RLS | Any authenticated user can query all results |
| Via ResultService | ⚠️ | Client filters by user_id but DB doesn't enforce |
| Cross-user result access | ❌ POSSIBLE | Without RLS, no DB-level prevention |

### 14.3 Attempt-Number Race Condition

**Risk:** Two concurrent `startAttempt` calls for the same user+test could both calculate `attempt_number = N+1` and both try to insert.

**Current mitigation:** The UNIQUE constraint `(test_id, user_id, attempt_number)` causes one insert to fail with a constraint violation. The function raises an exception, and the user sees an error.

**Required for production:** Either:
1. Use `SELECT ... FOR UPDATE` to lock the user's attempts
2. Use a serializable transaction
3. Accept the constraint violation as a retry signal (simpler, acceptable for low-concurrency)

### 14.4 Max-Attempt Bypass

**Current state:** max_attempts is not enforced anywhere. A user could theoretically create unlimited attempts if they could bypass the RPC (e.g., direct SQL injection).

**Required:** Server-side enforcement in `_fn_start_attempt_core`.

### 14.5 Duplicate Attempts/Results

**Duplicate attempts:** Prevented by UNIQUE constraint on `(test_id, user_id, attempt_number)` + proper attempt_number calculation.

**Duplicate results:** Prevented by UNIQUE constraint on `(attempt_id)` in results table.

### 14.6 Client-Side Score Manipulation

**Current state:** `rpc_submit_attempt` is SECURITY DEFINER. If scoring happens server-side, client cannot manipulate scores. However, without source code, we cannot verify.

### 14.7 Direct Table Access Bypass

**Current state:** Without RLS, a malicious client could use Supabase client to directly INSERT/UPDATE/SELECT on attempts, answers, results tables. The SECURITY DEFINER functions bypass RLS, but direct table access would be subject to RLS (if enabled) or unrestricted (if not).

---

## 15. Race Condition Audit

### 15.1 Current Start-Attempt Logic

```
1. Check auth.uid()
2. Load test
3. Check access
4. Check lifecycle
5. Check timing
6. Check max participants
7. Check for existing in_progress attempt → resume if found
8. Calculate deadline
9. INSERT attempt (attempt_number defaults to 1)
```

**Race window:** Between step 7 (check existing) and step 9 (insert), another request could complete the same flow.

**Impact:**
- Two concurrent requests both find no existing attempt
- Both attempt to INSERT with attempt_number = 1
- UNIQUE constraint blocks the second insert
- Second request raises an exception

**Severity:** MEDIUM. The UNIQUE constraint provides a safety net, but the user experience is poor (unexplained error).

### 15.2 Required Protections for Repeat Attempts

For a proper repeat attempt implementation:
1. **Atomic calculation:** `attempt_number` must be calculated in a single SQL statement
2. **Unique constraint:** Already exists — `(test_id, user_id, attempt_number)`
3. **Transaction-safe logic:** The function runs in a single transaction (plpgsql default)
4. **Locking:** Not strictly required if UNIQUE constraint is the safety net, but `SELECT ... FOR UPDATE` on existing attempts would prevent the race condition entirely

### 15.3 Recommended Approach

```sql
-- Inside _fn_start_attempt_core, after resume check:
-- Atomic: count + insert in one transaction
SELECT COUNT(*) INTO v_completed_count
FROM public.attempts a
WHERE a.test_id = p_test AND a.user_id = v_uid
  AND a.status IN ('submitted', 'expired');

IF v_completed_count >= v_test.max_attempts THEN
  RAISE EXCEPTION 'MAX_ATTEMPTS_REACHED';
END IF;

v_attempt_number := v_completed_count + 1;

-- The UNIQUE constraint is the final safety net
INSERT INTO public.attempts (test_id, user_id, attempt_number, status, started_at, deadline_at)
VALUES (p_test, v_uid, v_attempt_number, 'in_progress', now(), v_deadline);
```

---

## 16. Proposed Migration Plan

### M1 — Repeat Attempt Backend

**Purpose:** Enable repeat attempts with proper attempt_number increment and max_attempts enforcement.

**Affected tables:** None (schema already supports it)

**Affected functions:** `_fn_start_attempt_core` (modify)

**Changes:**
1. Add attempt_number calculation logic
2. Add max_attempts check
3. Return attempt_number in response JSONB

**Security considerations:** Server-authoritative calculation. UNIQUE constraint prevents duplicates. No security weakening.

**Rollback:** Restore original `_fn_start_attempt_core` from R4.3 migration.

**Existing data affected:** No. Only new attempts are affected.

### M2 — Result/Question Review Backend

**Purpose:** Enable secure post-submission question correctness review.

**Affected tables:** None

**Affected functions:** New function `rpc_get_question_review(p_attempt uuid)`

**Changes:**
1. Create `rpc_get_question_review` that:
   - Verifies user owns the attempt
   - Verifies attempt is submitted/expired
   - Joins answers + questions to compute per-question correctness
   - Returns question_id, selected_option, is_correct, marks_earned, explanation, difficulty, subject, topic
2. Grant EXECUTE to authenticated only
3. SECURITY DEFINER with search_path = ''

**Security considerations:** Never exposes correct_option directly. Computes is_correct server-side. Only available post-submission. Only for attempt owner.

**Rollback:** DROP FUNCTION rpc_get_question_review.

**Existing data affected:** No.

### M3 — Analytics Backend

**Purpose:** Populate subject_breakdown, topic_breakdown, difficulty_breakdown, accuracy, score, max_score in results.

**Affected tables:** `results` (ADD COLUMNS if not exists)

**Affected functions:** Scoring function (to be created or modified)

**Changes:**
1. ALTER TABLE results ADD COLUMN IF NOT EXISTS subject_breakdown jsonb DEFAULT '{}'
2. ALTER TABLE results ADD COLUMN IF NOT EXISTS topic_breakdown jsonb DEFAULT '{}'
3. ALTER TABLE results ADD COLUMN IF NOT EXISTS difficulty_breakdown jsonb DEFAULT '{}'
4. ALTER TABLE results ADD COLUMN IF NOT EXISTS accuracy numeric(5,2) DEFAULT 0
5. ALTER TABLE results ADD COLUMN IF NOT EXISTS score numeric(8,2) DEFAULT 0
6. ALTER TABLE results ADD COLUMN IF NOT EXISTS max_score numeric(8,2) DEFAULT 0
7. ALTER TABLE results ADD COLUMN IF NOT EXISTS rank integer
8. ALTER TABLE results RENAME COLUMN generated_at TO computed_at (or add computed_at)
9. Modify scoring logic to populate all breakdown fields

**Security considerations:** Breakdown data derived from user's own answers. No cross-user exposure.

**Rollback:** ALTER TABLE results DROP COLUMN for each added column.

**Existing data affected:** Existing result rows will have NULL/empty values for new columns. Migration should set defaults.

---

## 17. Exact Blockers

### BLOCKER 1: Missing RPC Source Code
`rpc_save_answers`, `rpc_submit_attempt`, `fn_score_attempt` have no SQL source in any migration file. Flutter code calls these RPCs. Either they exist in the live database (created outside migrations) or the app is non-functional.

### BLOCKER 2: No RLS on Core Tables
`attempts`, `answers`, `results` have no RLS policies. Any authenticated user can query all data. This is a security risk and blocks production deployment.

### BLOCKER 3: Repeat Attempt Always Fails
`_fn_start_attempt_core` does not calculate `attempt_number`. It always defaults to 1. The UNIQUE constraint blocks the second attempt.

### BLOCKER 4: Schema Mismatches Between Migrations and RPCs
`rpc_create_test` (R4.5.1) and `_fn_start_attempt_core` (R4.3) reference columns that do not exist in the R4.1 foundation DDL (`duration_sec`, `marks_per_question`, `test_mode`, `access_code`, `join_code`, `is_soft_deleted`, `allow_late_join`, `max_participants`, `config`, `settings`, `deadline_at`, `ordinal`, `subject_id`, `topic_node_id`, `status` on questions, etc.). These columns may have been added by unrecorded live migrations.

### BLOCKER 5: Analytics Columns Not in DDL
`results.subject_breakdown`, `results.topic_breakdown`, `results.accuracy`, `results.score`, `results.max_score`, `results.rank`, `results.computed_at` are expected by Flutter but not defined in R4.1 DDL.

---

## 18. Recommended Next Phase

### Immediate (Before Any User Testing)

1. **Run live discovery queries** to verify actual database state:
   - Do `rpc_save_answers`, `rpc_submit_attempt`, `fn_score_attempt` exist in pg_proc?
   - Do `attempts`, `answers`, `results` have RLS enabled?
   - Do the extra columns exist on `tests`, `questions`, `results`?
   - What is the actual function body of each RPC?

2. **Document live state** — If RPCs exist but aren't in migrations, extract and document their source code.

3. **If RPCs don't exist** — Create them in a new migration.

4. **Add RLS** to `attempts`, `answers`, `results` tables.

5. **Fix `_fn_start_attempt_core`** for attempt_number calculation.

### Short-Term (Required for Analytics)

6. Create `rpc_get_question_review` for post-submission review.

7. Populate analytics columns in results.

### Deferred

8. Difficulty breakdown support.
9. Rank calculation.

---

## 19. Verification Evidence

### Files Inspected

| File | Lines | Content |
|------|-------|---------|
| `migrations/R4_1_phase_db_foundation.sql` | 669 | Table DDL, enums, views, indexes, triggers |
| `migrations/R4_1_validation.sql` | 242 | Validation queries |
| `migrations/R4_3_discovery.sql` | 281 | Pre-migration discovery |
| `migrations/R4_3_secure_test_entry.sql` | 535 | `_fn_start_attempt_core`, RPCs |
| `migrations/R4_3_security_validation.sql` | 365 | Security verification |
| `migrations/R4_5_discovery.sql` | 404 | R4.5 pre-implementation discovery |
| `migrations/R4_5_1_test_creation_write.sql` | 1435 | Test/question CRUD RPCs |
| `migrations/R4_5_5_group_foundation.sql` | 354 | Groups infrastructure |
| `lib/core/models/result.dart` | 120 | Result model |
| `lib/core/models/attempt.dart` | 95 | Attempt model |
| `lib/core/models/answer.dart` | 77 | Answer model |
| `lib/core/models/question.dart` | 173 | Question model |
| `lib/core/models/test.dart` | 195 | Test model |
| `lib/core/models/result_analytics.dart` | 114 | Analytics models |
| `lib/core/services/attempt_service.dart` | 191 | Attempt service |
| `lib/core/services/answer_service.dart` | 75 | Answer service |
| `lib/core/services/result_service.dart` | 168 | Result service |
| `lib/core/services/question_service.dart` | 360 | Question service |
| `lib/core/services/test_service.dart` | 434 | Test service |
| `lib/features/test/test_result_screen.dart` | 693 | Result screen |
| `lib/features/test/question_review_screen.dart` | 205 | Review screen |
| `lib/features/test/test_taking_screen.dart` | 638 | Test taking screen |
| `lib/features/test/widgets/question_review_card.dart` | 319 | Review card widget |
| `lib/features/test/widgets/difficulty_analysis_extended_card.dart` | 133 | Difficulty analysis widget |
| `lib/features/test/widgets/subject_analysis_card.dart` | 152 | Subject analysis widget |
| `lib/features/test/widgets/topic_analysis_card.dart` | 109 | Topic analysis widget |

### Audit Method

1. Read all migration SQL files line-by-line
2. Cross-referenced DDL definitions against RPC function bodies
3. Compared Flutter model fields against DB column definitions
4. Traced Flutter service calls against available RPC implementations
5. Checked RLS policies across all tables
6. Verified constraints, indexes, and triggers
7. Assessed security implications of each gap

---

## FINAL GATE

**DATABASE MODIFIED: NO**
**RLS MODIFIED: NO**
**RPC MODIFIED: NO**
**FUNCTION MODIFIED: NO**
**FLUTTER MODIFIED: NO**
**DATA MODIFIED: NO**
**AI CALLS: 0**

---

### BLOCKER 1:
`rpc_save_answers`, `rpc_submit_attempt`, `fn_score_attempt` source code absent from all migration files. Flutter depends on these RPCs for core functionality.

### BLOCKER 2:
No RLS on `attempts`, `answers`, `results` tables. Any authenticated user can query all rows. Critical security risk.

### BLOCKER 3:
`_fn_start_attempt_core` always sets `attempt_number = 1` (column default). UNIQUE constraint blocks second attempt. Repeat test always fails.

### BLOCKER 4:
Schema mismatches between R4.1 DDL and R4.3/R4.5.1 RPCs — multiple columns referenced in functions do not exist in foundation DDL.

### BLOCKER 5:
Analytics columns (`subject_breakdown`, `topic_breakdown`, `accuracy`, `score`, `max_score`, `rank`, `computed_at`) expected by Flutter but not in R4.1 DDL.

---

### NEXT SAFE ACTION:
Run live Supabase discovery queries to determine actual database state — specifically: (1) Do the three missing RPCs exist in pg_proc? (2) What columns actually exist on each table? (3) Is RLS enabled on core tables? This will determine whether the RPCs need to be created or merely documented, and whether column additions are needed.

---

**AUDIT STATUS: AUDIT COMPLETE**

# R4.1 IMPLEMENTATION REPORT — DATABASE FOUNDATION

**Date:** 2026-09-12
**Status:** READY FOR R4.2 (pending execution + validation)
**Phase:** R4.1 — Database Foundation
**Author:** Implementation Report

---

## EXECUTIVE SUMMARY

Phase R4.1 creates the database foundation for the Test System. All SQL migration files are prepared and ready for execution via Supabase SQL Editor. No code changes were made — only migration files and this report.

### What Was Created

| File | Purpose | Lines |
|------|---------|-------|
| `migrations/R4_1_phase_db_foundation.sql` | Complete migration SQL | ~350 |
| `migrations/R4_1_validation.sql` | Schema validation queries | ~200 |
| `docs/R4_1_IMPLEMENTATION_REPORT.md` | This report | ~300 |

### What Was NOT Changed

- No existing tables modified (subjects, syllabus_nodes, profiles, etc.)
- No Flutter code modified
- No RLS policies created (Phase R4.2)
- No RPC functions created (Phase R4.3)
- No data seeded

---

## 1. CHANGES MADE

### 1.1 Custom Enum Types Created

| Type | Values | Purpose |
|------|--------|---------|
| `test_status` | draft, published, closed, archived | Test lifecycle |
| `attempt_status` | in_progress, submitted, expired | Attempt lifecycle |
| `question_type` | mcq_single, mcq_multiple, true_false, integer, short_answer | Question types |
| `difficulty_level` | easy, medium, hard | Difficulty classification |

### 1.2 Tables Created (8 total)

| # | Table | Columns | Purpose |
|---|-------|---------|---------|
| 1 | `tests` | 24 | Test metadata and configuration |
| 2 | `questions` | 18 | Reusable question bank |
| 3 | `test_syllabus` | 6 | Junction: tests ↔ syllabus_nodes |
| 4 | `test_invitations` | 7 | Access control for restricted tests |
| 5 | `attempts` | 12 | User test attempts |
| 6 | `answers` | 9 | Per-question answers within attempts |
| 7 | `results` | 15 | Attempt scores and breakdowns |
| 8 | `ai_reports` | 12 | AI-generated analysis (deferred) |

### 1.3 Views Created

| View | Purpose |
|------|---------|
| `questions_safe` | Client-safe view — strips `is_correct` from options |

### 1.4 Triggers Created

| Trigger | Table | Purpose |
|---------|-------|---------|
| `trg_tests_updated_at` | tests | Auto-update `updated_at` |
| `trg_questions_updated_at` | questions | Auto-update `updated_at` |
| `trg_answers_updated_at` | answers | Auto-update `updated_at` |

### 1.5 Orphaned Table Dropped

| Table | Reason |
|-------|--------|
| `test_syllabus` (old) | Orphaned — FK to nonexistent `tests` table, no PK, no constraints, no code references |

### 1.6 Destructive Changes

| Change | Reversible? | Impact |
|--------|-------------|--------|
| DROP test_syllabus | YES — but table was orphaned with no valid data | Zero — no valid data lost |
| CREATE new tables | YES — DROP TABLE reverses | N/A |
| CREATE enums | YES — DROP TYPE reverses | N/A |

---

## 2. CONSTRAINTS

### 2.1 Foreign Keys (15 total)

| Table | Column | References | On Delete |
|-------|--------|------------|-----------|
| tests | created_by | auth.users(id) | CASCADE |
| tests | subject_id | subjects(id) | RESTRICT |
| questions | created_by | auth.users(id) | CASCADE |
| questions | test_id | tests(id) | SET NULL |
| test_syllabus | test_id | tests(id) | CASCADE |
| test_syllabus | syllabus_node_id | syllabus_nodes(id) | CASCADE |
| test_invitations | test_id | tests(id) | CASCADE |
| test_invitations | user_id | auth.users(id) | CASCADE |
| attempts | test_id | tests(id) | CASCADE |
| attempts | user_id | auth.users(id) | CASCADE |
| answers | attempt_id | attempts(id) | CASCADE |
| answers | question_id | questions(id) | CASCADE |
| results | attempt_id | attempts(id) | CASCADE |
| results | test_id | tests(id) | CASCADE |
| results | user_id | auth.users(id) | CASCADE |
| ai_reports | result_id | results(id) | CASCADE |
| ai_reports | user_id | auth.users(id) | CASCADE |
| ai_reports | test_id | tests(id) | CASCADE |

### 2.2 Unique Constraints (5 total)

| Table | Constraint | Columns |
|-------|-----------|---------|
| test_syllabus | uq_test_syllabus_test_node | (test_id, syllabus_node_id) |
| test_invitations | uq_test_invitations_test_user | (test_id, user_id) |
| attempts | uq_attempts_test_user_number | (test_id, user_id, attempt_number) |
| answers | uq_answers_attempt_question | (attempt_id, question_id) |
| results | uq_results_attempt | (attempt_id) |
| ai_reports | uq_ai_reports_result | (result_id) |

### 2.3 CHECK Constraints (8 total)

| Table | Constraint | Rule |
|-------|-----------|------|
| tests | chk_tests_end_after_start | end_at > start_at (when both non-null) |
| tests | chk_tests_passing_lte_total | passing_marks <= total_marks |
| tests | duration_minutes | > 0 AND <= 480 |
| tests | total_marks | >= 0 |
| tests | passing_marks | >= 0 |
| tests | max_attempts | > 0 AND <= 10 |
| questions | marks | > 0 |
| questions | chk_questions_negative_lte_marks | negative_marks < marks |
| attempts | chk_attempts_submitted_after_started | submitted_at >= started_at |
| results | chk_results_percentage_range | percentage >= 0 AND <= 100 |
| results | chk_results_marks_range | marks_obtained >= 0 AND <= total_marks |
| results | chk_results_counts_sum | correct + wrong + unanswered + partial = total |

---

## 3. INDEXES (25 total)

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| tests | idx_tests_created_by | created_by | Creator's tests |
| tests | idx_tests_subject_id | subject_id | Filter by subject |
| tests | idx_tests_status | status | Filter by status |
| tests | idx_tests_start_at | start_at | Scheduled tests |
| tests | idx_tests_end_at | end_at | Deadline filter |
| tests | idx_tests_group_id | group_id | Group tests |
| questions | idx_questions_created_by | created_by | Creator's questions |
| questions | idx_questions_test_id | test_id | Test's questions |
| questions | idx_questions_difficulty | difficulty | Filter by difficulty |
| questions | idx_questions_question_type | question_type | Filter by type |
| questions | idx_questions_is_active | is_active | Active questions |
| questions | idx_questions_tags | tags (GIN) | Tag search |
| test_syllabus | idx_test_syllabus_test_id | test_id | Test's syllabus |
| test_syllabus | idx_test_syllabus_syllabus_node_id | syllabus_node_id | Node's tests |
| test_invitations | idx_test_invitations_test_id | test_id | Test's invitations |
| test_invitations | idx_test_invitations_user_id | user_id | User's invitations |
| attempts | idx_attempts_test_id | test_id | Test's attempts |
| attempts | idx_attempts_user_id | user_id | User's attempts |
| attempts | idx_attempts_test_user | test_id, user_id | User's attempt for test |
| attempts | idx_attempts_status | status | Filter by status |
| answers | idx_answers_attempt_id | attempt_id | Attempt's answers |
| answers | idx_answers_question_id | question_id | Question's answers |
| answers | idx_answers_attempt_question | attempt_id, question_id | Lookup optimization |
| results | idx_results_attempt_id | attempt_id | Attempt's result |
| results | idx_results_test_id | test_id | Test's results |
| results | idx_results_user_id | user_id | User's results |
| results | idx_results_test_user | test_id, user_id | User's result for test |
| results | idx_results_batch_id | batch_id | Batch tracking |
| ai_reports | idx_ai_reports_result_id | result_id | Result's AI report |
| ai_reports | idx_ai_reports_user_id | user_id | User's AI reports |
| ai_reports | idx_ai_reports_test_id | test_id | Test's AI reports |

---

## 4. RLS STATUS

**RLS policies are NOT created in Phase R4.1.** This is intentional.

| Table | RLS Enabled? | Policies |
|-------|-------------|----------|
| tests | UNKNOWN | 0 (none created) |
| questions | UNKNOWN | 0 (none created) |
| test_syllabus | UNKNOWN | 0 (none created) |
| test_invitations | UNKNOWN | 0 (none created) |
| attempts | UNKNOWN | 0 (none created) |
| answers | UNKNOWN | 0 (none created) |
| results | UNKNOWN | 0 (none created) |
| ai_reports | UNKNOWN | 0 (none created) |

**WARNING:** Until Phase R4.2 (RLS Policies) is executed, all new tables are accessible to any authenticated user without restriction. Do NOT deploy to production without RLS.

**Validation Query (run after R4.2):**
```sql
SELECT tablename, policyname FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN ('tests','questions','test_syllabus','test_invitations','attempts','answers','results','ai_reports');
-- Expected: Multiple policies per table
```

---

## 5. VALIDATION RESULTS

Validation queries are provided in `migrations/R4_1_validation.sql`. Execute after running the migration.

### Expected Results Summary

| Check | Expected |
|-------|----------|
| V1: Tables exist | 8 rows |
| V2: Enum types exist | 4 rows |
| V3: Tests columns | 24 columns |
| V4: Questions columns | 18 columns |
| V5: Attempts columns | 12 columns |
| V6: Answers columns | 9 columns |
| V7: Results columns | 15 columns |
| V8: Foreign keys | 18 rows |
| V9: Unique constraints | 6 rows |
| V10: Indexes | 25+ rows |
| V11: Questions safe view | 15 columns |
| V12: RLS policies | 0 rows (expected in R4.1) |
| V13: Triggers | 3 rows |
| V14: CHECK constraints | 12+ rows |
| V15: Existing tables unchanged | 9 rows |
| V16: Subjects row count | 11 |
| V17: test_syllabus PK | 1 PK row |

---

## 6. HUMAN DECISIONS APPLIED

| # | Decision | Implementation |
|---|----------|----------------|
| 1 | Answer-key security | `questions_safe` view strips `is_correct` from options. Clients MUST use this view. |
| 2 | Binary MCQ scoring | `correct_count` / `wrong_count` columns on `results`. Partial scoring deferred. |
| 3 | Groups integration | `tests.group_id` column (uuid, nullable, no FK yet). Designed for future groups table. |
| 4 | AI reports deferred | `ai_reports` table created but population deferred to Phase R4.12. |
| 5 | Manual grading | `short_answer` question type supported. Manual grading via creator UI (Phase R4.8). |
| 6 | Restricted editing | Enforced at application level (Phase R4.5). Published tests restrict field modifications. |
| 7 | Manual batch trigger | `results.batch_id` column tracks batch runs. Batch generation via RPC (Phase R4.9). |

---

## 7. ROLLBACK CONSIDERATIONS

### 7.1 Full Rollback

Execute the ROLLBACK section at the bottom of `R4_1_phase_db_foundation.sql`:

```sql
-- Drops all new tables, types, triggers, and the view
-- Does NOT affect existing tables (subjects, syllabus_nodes, profiles, etc.)
-- Safe to run at any time
```

### 7.2 Partial Rollback

| Change | Rollback Command |
|--------|-----------------|
| Drop a specific table | `DROP TABLE IF EXISTS public.<table_name>;` |
| Drop a specific index | `DROP INDEX IF EXISTS public.<index_name>;` |
| Drop a specific trigger | `DROP TRIGGER IF EXISTS <trigger_name> ON public.<table_name>;` |
| Drop a specific type | `DROP TYPE IF EXISTS public.<type_name>;` |

### 7.3 Data Loss Risk

| Risk | Level | Mitigation |
|------|-------|------------|
| Existing data modified | NONE | No existing tables touched |
| New data lost on rollback | LOW | No data seeded in R4.1 |
| Orphaned test_syllabus data lost | NONE | Table had no valid data (FK to nonexistent table) |

---

## 8. WARNINGS

1. **RLS NOT ENABLED:** Tables are accessible to all authenticated users until Phase R4.2. Do NOT deploy to production.

2. **questions_safe view required:** Flutter clients MUST query `questions_safe` instead of `questions` to prevent answer-key leakage. Enforce this in Phase R4.4 (services).

3. **groups FK pending:** `tests.group_id` is a uuid column without a FK constraint. The FK to `groups(id)` will be added when the groups table is created (future phase).

4. **ai_reports table empty:** Table exists but will have zero rows until Phase R4.12 (AI reports).

5. **Short answer grading:** `short_answer` questions will have `marks_obtained = 0` until manually graded by the test creator.

---

## 9. REMAINING RISKS

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| 1 | No RLS policies yet | Security gap | Execute Phase R4.2 immediately after R4.1 validation |
| 2 | questions_safe view may be bypassed | Answer-key leakage | Enforce in Flutter services (Phase R4.4) |
| 3 | groups table doesn't exist | group_id FK missing | Design-level only; FK added when groups created |
| 4 | No RPC functions yet | Cannot start/submit attempts | Execute Phase R4.3 after R4.2 |
| 5 | Concurrent batch generation | Potential duplicate results | UNIQUE constraint prevents duplicates; idempotent design |

---

## 10. EXECUTION INSTRUCTIONS

### Step 1: Execute Migration

1. Open Supabase Dashboard → SQL Editor
2. Copy contents of `migrations/R4_1_phase_db_foundation.sql`
3. Execute the SQL
4. Verify no errors in the output

### Step 2: Execute Validation

1. Copy contents of `migrations/R4_1_validation.sql`
2. Execute in SQL Editor
3. Verify all checks pass (see Section 5 expected results)

### Step 3: Verify Existing Data

```sql
-- Confirm existing tables unchanged
SELECT COUNT(*) FROM public.subjects;  -- Expected: 11
SELECT COUNT(*) FROM public.syllabus_nodes;  -- Expected: 2
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('subjects', 'syllabus_nodes', 'profiles', 'study_materials', 'node_materials', 'material_chunks', 'progress_snapshots', 'routines', 'routine_logs');
-- Expected: 9 rows (all existing tables present)
```

### Step 4: Report Results

After execution, report:
- Migration success/failure
- Validation results
- Any errors encountered
- Confirmation that existing data is intact

---

## FINAL STATUS

**READY FOR R4.2**

All migration SQL files prepared. Validation queries ready. Rollback script included. Human decisions applied.

**Awaiting:** Execution of migration SQL + validation confirmation.

**HARD STOP AFTER R4.1.** Do not proceed to R4.2 RLS, RPCs, Flutter, UI, Groups, Dashboard, Routine, AI, or syllabus seeding without separate approval.

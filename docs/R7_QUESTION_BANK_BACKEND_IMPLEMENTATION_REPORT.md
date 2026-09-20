# R7 — Question Bank V1: Backend Implementation Report

**Date:** 2026-09-20 · **Role:** R7 backend builder · **Base:** `8483a01` · **Live reference:** Supabase after `ec8f5a0`
**Supersedes** the earlier BLOCKED report of the same name (its "`questions.test_id IS NULL` = reusable" premise is refuted by the live schema).

## Verdict

**PASS (backend prepared and proven; OWNER APPLY REQUIRED)**

- Reusable question → server-side copy → independent test-linked row: **proven** (§3, checks 6–10b).
- Answer-key and authorization boundaries: **proven** (§5, checks 3a/3b/13a–13f/14a/14b/4/5a–5d/12/15a/15b).
- Nothing was applied to the live database; both migrations were executed and rolled back inside one transaction (residue 0).
- One pre-existing live defect found and fixed in a separate migration: `rpc_create_question` fails on every call (§3.3).

## 1. Live schema result (read-only, `r7_inventory.js`)

| Object | Live state |
|---|---|
| `public.questions` | `id, test_id uuid NOT NULL → tests ON DELETE CASCADE, ordinal NOT NULL, question, options jsonb, correct_option int NOT NULL (≥0), explanation, subject_id → subjects, topic_node_id → syllabus_nodes (SET NULL), difficulty (easy/medium/hard), marks numeric, status question_status default pending_review, source_batch int, bank_id uuid → question_bank ON DELETE SET NULL, language (en/hi/hinglish), question_type (mcq/tf/short/num)`; UNIQUE `(test_id, ordinal)`; RLS on; policies `question owner reviewer read/insert/update/delete` (creator, REVIEW_QUESTIONS holder, members read); grants **authenticated INSERT,UPDATE,DELETE — no SELECT**; 47 rows, **0 with `test_id IS NULL` (impossible: NOT NULL)**, 0 with `bank_id`. |
| `public.question_bank` | **exists** (contrary to the checkout): `id, question, options jsonb NOT NULL default '[]', correct_option int NOT NULL (0..3), explanation, subject_id, subject_name, chapter, topic_node_id, difficulty, language, question_type (CHECK = 'mcq'), source (manual/upload/ai/mixed), created_by → profiles (SET NULL), times_used int default 0, created_at, status question_status default pending_review, reviewed_by, reviewed_at, updated_at, archived_at, duplicate_key`; triggers `trg_qb_set_dup` (BEFORE INSERT), `trg_qb_touch` (BEFORE UPDATE); RLS on; policies `auth read bank` (own OR REVIEW/GENERATE_QUESTIONS holder in any group), `auth insert bank` (same), `owner update bank` (author OR created_by IS NULL OR REVIEW holder); grants authenticated INSERT,SELECT,UPDATE; **1 row live**. |
| `questions_safe` view | `security_invoker=true`, no `correct_option`, SELECT to authenticated — unreadable in practice because `questions` has no SELECT grant. |
| `question_status` | pending_review, approved, rejected, needs_revision, archived |
| Functions | `rpc_create_question` (definer, `''`, creator-only via `_fn_can_manage_questions`, **broken: inserts text into the enum column**), `rpc_update_question` (casts correctly), `rpc_delete_question`, `get_test_questions_safe` (key-free), `_fn_get_next_question_ordinal`, `rpc_get_questions_for_pdf`, `rpc_get_live_questions`; **no** `fn_bank_available`, `fn_increment_bank_usage`, `rpc_clone_bank_questions` or any bank list/select function (the legacy web app and the Flutter draft both call names that do not exist). |
| Related | `content_reports` (question_bank_id/question_id), `content_audit_logs` (action enum includes `bank_reused`), `fn_guard_question_status` (no-op body, attached nowhere). |

## 2. Architecture decision — **Option B: the bank table already exists live**

Evidence: `question_bank` is live with RLS, policies, triggers, grants and data; `questions.bank_id` references it; `questions.test_id` is NOT NULL, which rules out Option A; creating a second bank (Option C) would duplicate a live table. Rejected: A (impossible on live schema), C (duplication). No table, column, policy or grant is changed; R7 adds only functions.

## 3. Snapshot proof (`r7_proof.js`, rolled back)

3.1 Existing paths: `rpc_create_question` creates a separate test-linked row from **client-supplied** content; the legacy "use from bank" flow therefore copies on the client and needs `correct_option` from the table. No server-side selection existed.

3.2 New `rpc_clone_bank_questions(p_test_id, p_bank_ids[], p_marks_per_question)`: copies every content field by value into a new `questions` row (status approved, next ordinal, `bank_id` provenance, `times_used` += 1). Proven: [6] creator selects → `cloned=1`; [7] new row is test-linked with copied content, `correct_option=2`, `marks=2`, `bank_id` set; [8]/[9]/[10] editing the bank question text / options / answer+explanation afterwards leaves the test row unchanged; [10b] deleting the bank row keeps the test question (`bank_id` → NULL); [11]/[11b] duplicate selection → `cloned=0, skipped_duplicate=1`, exactly one row remains; [12] pending / archived bank rows → `skipped_unavailable`; [5c] forged bank id → unavailable; [15c] the test with the cloned question publishes via `rpc_publish_test`; [15a] members read it key-free via `get_test_questions_safe`.

3.3 `rpc_create_question` defect: `r7_rpc_check.js` (no migration) — every call fails `column "status" is of type public.question_status but expression is of type text` (default and explicit status); `rpc_update_question` works. Fix = the live body with `p_status::public.question_status` (`migrations/R7_FIX_rpc_create_question_status_cast.sql`); proven [15d].

## 4. Security model / permission matrix (all server-side; proven rows in brackets)

| Actor | Browse / detail (key-free) | Detail with key | Select into test | Bank CRUD (unchanged live policies) |
|---|---|---|---|---|
| Owner (bypass) | all rows [2 via leader; owner implied by bypass] | yes (REVIEW via bypass) | own tests or EDIT_TEST | insert/update per policies |
| Leader (seeded REVIEW+GENERATE, EDIT_TEST) | all rows [2] | yes [13b] | creator [6] or EDIT_TEST on another's test [E1]; **not** into another group's test [4] | yes |
| Moderator (no perms) | 0 rows [3a] | no | no | own rows only |
| Moderator with GENERATE_QUESTIONS only | all rows, key-free [13f] | **no** [13e] | only own tests / EDIT_TEST | insert |
| Member | own-authored rows only [3b]; others → `QUESTION_NOT_FOUND` [13d] | own rows [13c] | own standalone test with own row [E2]; others' rows unavailable [E3]; not into group tests [5a] | own rows |
| Non-member / forged ids | forged test → `TEST_NOT_FOUND` [5b]; forged bank id → unavailable [5c]; ended test → `TEST_LOCKED` [5d] | | | |
| Anon | denied (no EXECUTE) [14a] | denied | denied [14b] | table: no grant |
| Participant (R4) | `get_test_questions_safe` only [15a]; `questions` table `permission denied` [15b] | never | — | — |

All six functions: SECURITY DEFINER, `SET search_path TO ''`, `auth.uid()` checked, no `WITH CHECK true`, no anon/PUBLIC EXECUTE; helpers not executable by `authenticated` [M1/M2].

**Documented residual (pre-existing, unchanged):** the live table grant `SELECT` on `question_bank` returns `correct_option` to every bank reader (authors and REVIEW/GENERATE holders) [X1]. That is the legacy authoring design; the Flutter client must use the RPCs instead. Tightening to column-level grants would break the legacy web app's `select("*")` bank pages and is a product decision (P2 follow-up).

## 5. RLS
No policy added, changed or weakened. The DEFINER RPCs replicate the live `auth read bank` predicate (`_fn_can_read_bank`) and the live `owner update bank` trust set for the key (`_fn_can_see_bank_answer`), so they never widen what the table policies already allow.

## 6. RPCs (see `docs/R7_QUESTION_BANK_BACKEND_CONTRACT.md` for the full contract)
`rpc_list_question_bank` (filters: search/status/subject/topic/difficulty/language/question_type/source; limit 1..50; offset; `total_count` window) · `rpc_get_question_bank_question(id, include_answer)` · `rpc_clone_bank_questions(test, ids[], marks)` · `fn_bank_available(subject_name, chapter, difficulty, language)` · helpers `_fn_can_read_bank`, `_fn_can_see_bank_answer`. Pagination proven [P1–P3].

## 7. Migrations (NOT applied)
- `migrations/R7_QUESTION_BANK_V1.sql` — six functions + grants + `NOTIFY pgrst`; postflight SELECT.
- `migrations/R7_FIX_rpc_create_question_status_cast.sql` — live body + one cast; postflight.
- `docs/R7_QUESTION_BANK_PRECHECK.md`, `docs/R7_QUESTION_BANK_POSTCHECK.md`, `docs/R7_QUESTION_BANK_ROLLBACK.md`.

## 8. Tests / verification
`r7_proof.js` (scratchpad, rolled back, residue `bank_rows=0 tests=0 r7_functions_live=0`): **41/41** covering the required scenarios 1–15 plus filters/pagination, forged ids, cross-group, EDIT_TEST path, GENERATE-only key denial, legacy compat count. `r7_rpc_check.js`: the pre-existing defect. No Flutter file changed in this lane; the Flutter draft under `lib/features/test/*question_bank*` (other agent, uncommitted) must be aligned to the contract (`display_name` → `created_by_name`, no `select('*')`, RPC names as above).

## 9. Rollback
Six `DROP FUNCTION`s (documented); proven by the transaction rollback. The fix migration's rollback is the captured previous body.

## 10. Exact files changed (this lane)
`migrations/R7_QUESTION_BANK_V1.sql` · `migrations/R7_FIX_rpc_create_question_status_cast.sql` · `docs/R7_QUESTION_BANK_PRECHECK.md` · `docs/R7_QUESTION_BANK_POSTCHECK.md` · `docs/R7_QUESTION_BANK_ROLLBACK.md` · `docs/R7_QUESTION_BANK_BACKEND_CONTRACT.md` · this report. No Flutter, no existing SQL object modified except the one-cast re-creation of `rpc_create_question` (unapplied).

## 11. Remaining blockers
1. **Owner apply** of both migrations (precheck → apply → postcheck), then re-run `r7_proof.js` in `live` fashion.
2. Flutter client alignment to the contract (Free Agent lane).
3. Product decision on the legacy table-level `SELECT` of `correct_option` on `question_bank` (P2).
4. `question_bank.question_type` CHECK allows only `mcq`; tf/short/num bank questions are impossible without a schema change (out of scope).

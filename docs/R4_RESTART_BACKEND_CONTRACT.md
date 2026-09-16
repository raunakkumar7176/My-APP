# R4 RESTART — Backend Contract (Flutter ↔ Supabase)

Date: 2026-09-16. Scope: what the Flutter Test System may rely on.
No backend/schema/RLS/RPC changes were made for this document.

## Evidence classes

| Tag | Meaning |
|---|---|
| **VERIFIED** | Observed on the live system (device logcat from the app, 2026-09-15) |
| **REPO-VERIFIED** | Present in repository code/SQL/docs and internally consistent, but not observed live |
| **LIVE-UNVERIFIED** | Repo asserts it, but repo sources contradict each other or are marked "not executed" |
| **UNKNOWN** | Nothing in the repo establishes it |

Live SQL access is not available from the development machine (no CLI, psql, credentials, env file). The only live evidence is the app's own logs on the Moto G31. Migration files in `migrations/` contradict one another (R4_1 DDL vs R4_3/R4_5_1 function bodies vs the R4_7_6 header) and are treated as history only.

## 1. Tables

### tests — VERIFIED (rows parsed by the app on device: 24 drafts, 25 accessible)
Columns the client reads and that were present in live rows: `id, created_by, title, description, status, duration_sec, marks_per_question, negative_marks, starts_at, ends_at, group_id, access_code, join_code, test_mode, max_participants, allow_late_join, is_soft_deleted, deleted_at, archived_at, created_at`. `updated_at` was null on every live row — existence UNKNOWN. Owner-listed columns not exercised by the client: `config, settings, creation_method, deleted_by, deletion_reason` — REPO-VERIFIED as RPC params (`p_config`, `p_settings`, `p_creation_method`), LIVE-UNVERIFIED as returned columns (the client only started parsing `config`/`settings` in R4.11a).
- `status` values handled by the client: draft, scheduled, live, ready, published, completed, ended, evaluated, cancelled, archived, expired. VERIFIED: `draft`, `published`. Others REPO-VERIFIED (R4_3 function text).
- `test_mode` ∈ {self, live, group} — REPO-VERIFIED (`rpc_create_test` validation, R4_5_1). `live` is the DB value for **Challenge with Friends**.
- **No `max_attempts` column** — REPO-VERIFIED (R4_7_6 header), consistent with the owner statement.
- SELECT policies: owner statement + `R4_10_MY_DRAFTS_ROOT_CAUSE_AUDIT.md` name three (`standalone owner read test`, `creator sees soft-deleted`, `member read tests` via `fn_is_member`). VERIFIED behaviourally: own drafts and accessible tests SELECT succeed for the creator. Non-creator/member visibility: UNKNOWN. Coded-test visibility to a non-member: UNKNOWN.

### questions — REPO-VERIFIED shape, LIVE-UNVERIFIED
`id, test_id, ordinal, question, options (jsonb [{id,text}]), correct_option (int), explanation, subject_id, topic_node_id, difficulty, status (question_status enum: pending_review/approved/... per R4_5_1), source_batch, bank_id, language, question_type`. Direct SELECT by clients: expected to be revoked (R4_3 validation V12) — LIVE-UNVERIFIED. **The client never selects this table on any active path** (one unused method remains; see forensic audit). VERIFIED live rule: publishing requires at least one question with `status='approved'` (`VALIDATION_ERROR: Test must have at least one approved question to publish`).

### test_syllabus — REPO-VERIFIED
`test_id, syllabus_node_id, material_ids uuid[]`, UNIQUE(test_id, syllabus_node_id) (R4_1). Read directly by the client (`select *`); written via `rpc_add_test_syllabus` / `rpc_remove_test_syllabus`. Idempotency of add on an existing pair: UNKNOWN.

### attempts — LIVE-UNVERIFIED
Owner-listed: `id, test_id, user_id, status, started_at, deadline_at, submitted_at, integrity_event_count, auto_submit_threshold, attempt_number`.
- `status` ∈ in_progress, submitted, auto_submitted, scored — REPO-VERIFIED (R4_7_6 header "live verified").
- `attempt_number` + UNIQUE(test_id, user_id, attempt_number): R4_7_6 states the migration was **proposed, not executed**, and that the live constraint was UNIQUE(test_id, user_id). The owner statement says uniqueness is the 3-column form. **LIVE-UNVERIFIED — decides whether repeat attempts work at all.**
- `integrity_event_count`, `auto_submit_threshold`: nothing in the repo reads or writes them (no RPC, no policy, no client code). UNKNOWN semantics.
- `deadline_at` nullability: UNKNOWN (matters for untimed Practice).
- The client never reads this table directly (only via RPC responses).

### answers — CONTRACT CONFLICT, LIVE-UNVERIFIED
Owner-listed columns: `attempt_id, question_id, selected_option, marked_for_review, updated_at`.
Client (`Answer` model) sends/reads: `attempt_id, question_id, selected_option_id, text_answer, is_marked_for_review, is_answered` (R4_1 DDL names). If the live columns are the owner-listed ones then:
- `getAnswersForAttempt` (`select *`) parses every row with `selectedOptionId = null` → a resumed attempt shows no saved answers;
- `rpc_save_answers` payload keys may be silently ignored or rejected.
This must be settled before the rebuild's `Answer` model is written (checklist step 7 captures the `rpc_save_answers` response shape; the `answers` row keys need one `select *` on device or in the SQL editor).

### results — VERIFIED by use (submit returned a row the app rendered, per prior device reports); columns REPO-VERIFIED
Client parses: `id, attempt_id, test_id, user_id, batch_id, score, max_score, accuracy, percentage, rank, is_passed, correct_count, wrong_count, unanswered_count, partial_count, total_marks, marks_obtained, total_questions, subject_breakdown (jsonb), topic_breakdown (jsonb), computed_at, generation_method`. The owner list matches the core set. Which optional ones are real columns: LIVE-UNVERIFIED (model tolerates absence). RLS on results: UNKNOWN (client filters history by `user_id` itself).

### ai_reports — CONTRACT CONFLICT, no active client path
Owner-listed: `id, test_id, user_id, batch_id, payload, model, created_at`. Client model parses `result_id, summary, strengths, weaknesses, recommendations, detailed_analysis, model_used, tokens_used, generated_at` — does not match; the service is unused by any screen. The client model is obsolete.

### result_batches — REPO-VERIFIED (client model matches owner list)
`id, test_id, requested_by, status (pending/processing/partially_completed/completed/failed), reports_done, reports_total, totals, created_at, completed_at`. Read directly by the client; created via `rpc_generate_results`.

### subjects, syllabus_nodes — VERIFIED (R3 screens work on device per prior reports)
`subjects(id, name)`, `syllabus_nodes(id, subject_id, parent_id, class_level, name, created_at)`; read-only.

### question_bank — UNKNOWN
Only referenced as `p_bank_id` / `bank_id` pass-through. No client read, no RPC in the repo. Shape UNKNOWN.

### groups / group_members — REPO-VERIFIED (R4_5_5 DDL); behaviour partially VERIFIED
`rpc_get_user_groups()` returns `id, name, created_by, created_at, updated_at, member_count, user_role` — VERIFIED (group tests with `group_id` were created from the device). Roles in the repo: `leader`, `member` only. **`owner` and `moderator` roles do not exist anywhere in the repo.** `group_members` policies are self-referencing (recursion risk) — REPO-VERIFIED text, LIVE-UNVERIFIED state. `fn_is_member(uuid, uuid)`: referenced by the reported live policy, absent from every migration; the R4_5_5 report says it did not exist at that time → LIVE-UNVERIFIED.

### permissions / role_permissions — UNKNOWN
The owner lists `role_permissions` and `fn_has_permission`; neither appears in any migration, doc (except "must be designed for future"), or client code.

## 2. RPC / function contracts

| Function | Params (client sends) | Return (client expects) | Definer / search_path / grants | Evidence |
|---|---|---|---|---|
| `rpc_create_test` | `p_title` + 15 optional (`p_test_mode` default self, `p_config`, `p_settings`, `p_access_code`, `p_join_code`, ...) | jsonb `{test_id, ...}` | DEFINER, `''`, EXECUTE authenticated | **VERIFIED** (tests created on device); body REPO-VERIFIED (R4_5_1). `p_settings` with `test_kind`: LIVE-UNVERIFIED. |
| `rpc_update_test` | `p_test_id` + optional set (no mode/group) | jsonb | as above | VERIFIED (device "Test updated"). COALESCE semantics → whole-jsonb replace for `p_settings`: REPO-VERIFIED. |
| `rpc_publish_test` | `p_test_id` | jsonb | as above | **VERIFIED** incl. the "≥1 approved question" rule. Other rules (duplicate ordinals, syllabus refs, creator-only, draft-only): REPO-VERIFIED. |
| `rpc_create_question` | `p_test_id, p_question, p_options, p_correct_option, p_question_type, p_marks, p_negative_marks, p_status, ...` | `{question_id, ordinal}` | as above | VERIFIED (questions created on device). Default `p_status='pending_review'`: REPO-VERIFIED and consistent with the live publish error. Option-id assignment when the client sends `''`: UNKNOWN. |
| `rpc_update_question` | `p_question_id` + optional (`p_status='approved'` for approval) | jsonb | as above | VERIFIED (approvals succeeded on device before publish). Blocks `correct_option` change on published tests: REPO-VERIFIED. |
| `rpc_delete_question` | `p_question_id` | — | as above | REPO-VERIFIED (delete on draft, archive on published). |
| `rpc_add_test_syllabus` / `rpc_remove_test_syllabus` | `(p_test_id, p_syllabus_node_id[, p_material_ids])` | jsonb | as above | REPO-VERIFIED. |
| `rpc_start_attempt` | `p_test` | **either** jsonb `{attempt_id, test_id, status: started/resumed, started_at, deadline_at[, attempt_number]}` (R4_3) **or** an `attempts` row (R4_7_6) | DEFINER, `''`; grant to authenticated commented out in R4_3 | Shape **LIVE-UNVERIFIED** (client parses both). Deadline formula `LEAST(now() + COALESCE(duration_sec, 3600), ends_at)`: REPO-VERIFIED in both versions. |
| `_fn_start_attempt_core` | `(uuid)` or `(uuid, boolean p_code_verified)` | as above | DEFINER, `''`, revoked from clients | Signature LIVE-UNVERIFIED. Lifecycle: draft/cancelled/archived/expired blocked; completed/ended/evaluated → TEST_ENDED; starts_at/ends_at window; `max_participants`; resume existing `in_progress`; `fn_can_access_test`. Late-join: only R4_7_6 has `LATE_JOIN_NOT_ALLOWED`. Repeat: R4_3 inserts blindly (unique constraint decides); R4_7_6 MAX+1. **Repeat behaviour LIVE-UNVERIFIED.** |
| `rpc_start_attempt_by_code` | `p_code` | as start (+ `entry_method: 'code'`, `test_title` in the R4_3 version) | DEFINER, `''`, EXECUTE authenticated | Errors `TEST_CODE_INVALID`, `TEST_CODE_AMBIGUOUS`: REPO-VERIFIED. Never returns the code. Whether the caller can afterwards SELECT the `tests` row: UNKNOWN. |
| `rpc_save_answers` | `p_attempt`, `p_answers` (array of `Answer.toJson`) | ignored | — | **Body absent from the repo.** Accepted keys, upsert semantics, deadline enforcement, typed-answer handling: UNKNOWN. |
| `rpc_submit_attempt` | `p_attempt`, `p_timed_out` | a `results` row (map or 1-element list) | — | Body absent. Returned a result the app rendered (prior reports) → return shape VERIFIED-by-use only. Deadline grace, idempotency on double submit: UNKNOWN. |
| `fn_score_attempt` | — | — | — | Body absent. Only known fact: scoring is server-side. Per-question correctness is **not** exposed anywhere. |
| `get_test_questions_safe` | `p_test_id[, p_access_code]` | list of question rows **without** `correct_option` | DEFINER, `''` (R4_3 report) | Existence VERIFIED (drafts load questions on device). Returned columns (`status`? `explanation`? `marks`?) LIVE-UNVERIFIED — the client now logs the key set. Archived-question exclusion: UNKNOWN. Behaviour when `p_access_code` is omitted for a coded test: UNKNOWN. |
| `rpc_generate_results` | `p_test_id` | map / string / list (client tolerates all) | — | Body absent. Authorization (owner-only?) and idempotency: UNKNOWN. |
| `fn_can_access_test` | `(uuid)` | boolean | DEFINER, `''` | Rule (creator, group member, uncoded standalone, coded with code) REPO-VERIFIED from the R4_3 report; body absent. |
| `rpc_get_user_groups` | — | table(id, name, created_by, created_at, updated_at, member_count, user_role) | DEFINER (sql) | VERIFIED. |
| `fn_ensure_profile` | — | — | — | VERIFIED (R2). |

RLS interaction: all writes go through DEFINER functions; the client role never writes `tests` / `questions` / `attempts` / `answers` / `results` directly, except the unused `deleteTest` soft-delete and the unused `test_invitations` update (see forensic audit). Reads rely on table policies whose text is not in the repo.

## 3. Lifecycle rules the client may rely on (server-authoritative)
- Publish: draft → published, creator only, ≥1 approved question (VERIFIED).
- Start: allowed only in scheduled/live/ready/published within the time window; draft and terminal statuses rejected (REPO-VERIFIED); server sets `deadline_at` (REPO-VERIFIED); no untimed mode exists (REPO-VERIFIED).
- Resume: an `in_progress` attempt is returned instead of a new one (REPO-VERIFIED, both versions).
- Repeat after submit: LIVE-UNVERIFIED.
- Submit/score: server; result row returned (VERIFIED by use).
- Access code: server matches `access_code` / `join_code` (`LOWER(TRIM())` in R4_7_6 only) — REPO-VERIFIED.
- Group access: via `fn_is_member` / `fn_can_access_test` — LIVE-UNVERIFIED.

## 4. Facts the rebuild must obtain before the corresponding layer is written
1. `answers` column names (blocks the Answer model + autosave/resume).
2. `rpc_start_attempt` return shape and whether `attempt_number` exists (blocks the Attempt model + repeat UX).
3. `get_test_questions_safe` returned keys, esp. `status`, `explanation`, `marks` (blocks the question model + publish readiness).
4. `rpc_save_answers` / `rpc_submit_attempt` handling of typed answers and of `p_timed_out` (blocks typed-question UX claims).
5. `attempts.deadline_at` nullability and the live `_fn_start_attempt_core` body (blocks any Practice backend work).
6. `tests` SELECT visibility for group members and for code-joiners (blocks listing/detail for non-creators).
7. Live text of `rpc_generate_results` authorization (blocks batch UI beyond the owner).

All are obtainable from one device session with the current shape logging plus one `select *` on `answers`; none require schema changes.

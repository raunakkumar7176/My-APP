# R4 — Test Creation / Types / Question Configuration / Timing: Audit (2026-09-17)

Audit only — nothing modified. Labels: **VERIFIED-LIVE** (Chrome/device logs or owner-run SQL), **REPO** (source), **UNKNOWN**.

## A. Exact current behaviour

### A1. `tests` live columns + `settings` usage
- Columns the client reads/writes (VERIFIED-LIVE): `id, created_by, title, description, status, duration_sec, marks_per_question, negative_marks, starts_at, ends_at, group_id, access_code, join_code, test_mode, max_participants, allow_late_join, is_soft_deleted, deleted_at/by, deletion_reason, archived_at, created_at, config, settings`. **No** `max_attempts`, **no** `late_join_minutes`, **no** difficulty/distribution columns. `creation_method` exists (RPC param, values `manual|upload|ai|mixed`, REPO).
- `settings` jsonb is the established per-test config store, round-tripped by `rpc_create_test(p_settings)` / `rpc_update_test(COALESCE(p_settings, settings))` (VERIFIED-LIVE). Keys in use today: `test_kind` (R4.11a), `target_question_count` (Quick), `allow_reattempt`, `max_attempts` (re-attempt, `9ca27ad`). `BackendMapping.settingsFor` + `AttemptSettings.applyTo` preserve unknown keys.

### A2. RPCs (REPO R4_5_1 bodies; publish/update bodies confirmed live by the two hotfixes)
- `rpc_create_test` / `rpc_update_test`: `_fn_validate_test_timing`: only `ends_at > starts_at` (and both optional). `duration_sec` 60..21600. No relation between `ends_at` and `starts_at + duration_sec` is enforced. Group mode requires `group_id`.
- `rpc_create_question` / `rpc_update_question`: `question_type ∈ mcq|tf|short|num`; **options ≥ 2**; `correct_option` integer index within options; status enum (cast hotfix).
- `rpc_publish_test`: ≥1 question, all `approved`, ordinals valid, syllabus refs valid (`test_status` cast hotfix).
- `_fn_start_attempt_core` (R4_7_6 + `R4_REATTEMPT_POLICY.sql` pending): window (`< starts_at` / `>= ends_at`), resume, re-attempt policy, **late-join**: `allow_late_join = false AND test_mode = 'live' AND now() > starts_at → LATE_JOIN_NOT_ALLOWED` (boolean only, no window; `live` mode only; seen on Chrome today).
- `rpc_save_answers` (VERIFIED-LIVE body): validates `selected_option` integer index `< jsonb_array_length(options)`; no text answers. `fn_score_attempt` (owner summary): compares selected index to `correct_option` → **only index-based answers are scorable**.

### A3. Flutter creation flow (REPO)
Wizard: Basic (title/desc/**kind picker over `TestKind.creatable` = self, practice, quick, sectional, challenge, group**) → Configuration (duration, marks, negative, group picker, starts/ends pickers, max participants, access/join code, Allow Late Join switch, Attempt Settings) → Questions (manual editor only) → Syllabus (subject → nodes, `test_syllabus`) → Review (readiness). Same form for every kind; kind only changes defaults (Practice: no window + 3 h; Quick: 10 min + `target_question_count`), guidance text, group requirement, code fields.
- Question editor: type dropdown exposes **MCQ single, MCQ multiple, True/False, Numeric, Short answer**; options ≥ 2; `QuestionDraft.isValid` = options ≥ 2 + correct index. Multiple/Numeric/Short cannot be answered/scored live (A2) — known P0 from the forensic audit, still open. True/False creates a question with **no options** → `rpc_create_question` rejects (<2) or the taking UI cannot answer it.
- No question-source step. Home screen shows "Manual Test" + three "Coming soon" tiles (Via Document / AI Generated / From Books) that do nothing.
- Duration/end: `starts_at`/`ends_at` are two independent pickers; end is never derived; UTC write / local display fixed (`b71c3af`).
- Late join: boolean switch only; default OFF.
- Difficulty: per-question field (easy/medium/hard) only; **no distribution config anywhere**; "Mixed" does not exist as a concept.

### A4. Document / AI / Books infrastructure
- Tables live (R4_1 DDL + services): `study_materials`, `material_chunks`, `node_materials`, `syllabus_nodes`, `subjects` (read-only browsing), `ai_reports` (unused), `test_invitations` (unused). **No** `books`, `question_bank`, document-ingestion job, or AI-generation job table/RPC/edge function in repo or referenced by the app. `questions.bank_id` / `source_batch` columns exist (integer `source_batch` live) but nothing writes them.
- Verdict: Document / AI / Books have **no backend pipeline**. Only truthful "Not configured / Coming soon" states are possible in V1.

## B. Gaps
1. Question types exposed that the backend cannot answer/score (multiple, numeric, short); True/False unanswerable as built.
2. No 4-option rule anywhere (backend minimum is 2).
3. No difficulty distribution / Mixed configuration; no total-question target except Quick's soft target.
4. `ends_at` manually entered; no derivation from duration; inconsistent triples possible.
5. Late join: boolean only, live-mode only, default OFF; no window.
6. Six creatable kinds visible (Sectional must be reserved); forms not kind-specific.
7. No Question Source step; home tiles are dead ends.
8. Pre-test (Detail) shows schedule/access/attempts but not question count, scoring, concept, instructions, late-join window.

## C. Minimal changes required

### C1. Question configuration (Flutter + one backend guard)
- **V1 enabled type: MCQ (single) only.** Hide Multiple/Numeric/Short (backend cannot score) and **True/False** ("Coming soon") — a TF question cannot satisfy the 4-option rule without inventing options, and the live pipeline is index-only. No fake options.
- **4-option rule**: `QuestionDraft.isValid` → options ≥ 4, all non-empty; editor starts with 4 rows and cannot remove below 4; `PublishReadiness` counts drafts with <4 as invalid; server questions with <4 options shown as "needs 4 options" and block publish client-side.
  Backend: `rpc_create_question` / `rpc_update_question` keep `≥ 2` today. Raising to `≥ 4` server-side is a one-line change in two functions **whose full live bodies are not in hand** (both were replaced by hotfixes only where needed). Decision: **Flutter enforces 4 now; server guard added in a follow-up migration once you paste both live bodies** (listed in D). Until then the rule is client-side only and this is stated in the readiness copy.
- **Mixed configuration** (creator intent, stored in `settings.question_config`): `{ total, difficulty: {easy, medium, hard}, types: {mcq: total} }`. Validation: easy+medium+hard = total; Next blocked otherwise. **Truthful scope**: with manual questions this is a *target* the review step checks against the actual questions' difficulties ("Easy 5/8 · Medium 3/7 · Hard 2/5 — 10 more needed"); it does not generate questions (no generator exists). Publish readiness fails while actual ≠ configured.
- **Concept/scope**: reuse the Syllabus step (subject → class → chapter → topic nodes = `test_syllabus`), moved **before** Questions so "Mixed" is defined within the selected scope; readiness requires ≥1 node for Practice/Quick/Sectional-family kinds (Self/Challenge/Group: optional but shown).

### C2. Duration / end time (Flutter only)
- Configuration step: Start Time picker + Duration → **Calculated End Time** (read-only) = start + duration, written as `ends_at = starts_at + duration_sec` (UTC). End picker removed for normal tests. When no start time (Self/Practice/Quick default): `ends_at` null (server deadline = now + duration, unchanged).
- Backend unchanged: `_fn_validate_test_timing` (`ends_at > starts_at`) is satisfied by construction; server deadline `LEAST(now()+duration, ends_at)` unchanged. Existing rows with inconsistent triples keep working; editing recomputes.

### C3. Late joining
- Config: **Allow Late Joining** (default ON for Challenge/Group; Self/Practice/Quick have no window so the control is hidden) + **Late Join Window** minutes (default 10; choices 5/10/15/30). Store `settings.late_join_minutes` (settings jsonb is the established pattern; no index/query need). `allow_late_join` boolean column keeps meaning "late join allowed at all".
- Backend (requires `_fn_start_attempt_core` change — same function the re-attempt migration replaces): after the existing late-join check, add: `IF allow_late_join AND starts_at IS NOT NULL AND now() > starts_at + COALESCE((settings->>'late_join_minutes')::int, 10) * interval '1 minute' THEN RAISE 'LATE_JOIN_WINDOW_CLOSED'`. Apply to `test_mode IN ('live','group')` (Group tests are scheduled participation too; Self-family have no `starts_at`, so unaffected). **Boundary**: consistent with the contract's closed end (`>=` semantics for "closed"): join allowed while `now() <= starts_at + window` → 10:10:00 allowed, 10:10:01 blocked. `ends_at` hard block (`now() >= ends_at`) stays first and unchanged; resume of in_progress stays before both.
  Client mirror in Detail (already mirrors the boolean rule; extend to the window; in_progress unaffected).
- Sequencing: fold this into `R4_REATTEMPT_POLICY.sql` (not yet applied) so core is replaced once — I will produce `R4_REATTEMPT_POLICY.sql` v2 with both blocks, same preflight.

### C4. Five test types (Flutter only)
- `TestKind.creatable` → `[self, practice, quick, challengeWithFriends, group]` (Sectional/Adaptive reserved, still parse from DB).
- Kind-specific Configuration step (one widget, sections toggled by kind — no redesign):

| Section | Self | Practice | Quick | Challenge | Group |
|---|---|---|---|---|---|
| Concept/syllabus | opt | **req** | **req** | opt | opt |
| Question config (total + Mixed distribution) | ✓ | ✓ | ✓ (small counts, ≤ 15) | ✓ | ✓ |
| Duration → calculated end | ✓ | ✓ (default 3 h) | ✓ (default 10 min) | ✓ | ✓ |
| Start time | opt | — | — | **req** | **req** (schedule) |
| Late join + window | — | — | — | ✓ | ✓ |
| Max participants | — | — | — | ✓ | ✓ |
| Access/join code | — | — | — | ✓ (join code required) | — |
| Group picker (real `rpc_get_user_groups`; today it 404s live → shows "No groups available", never fake) | — | — | — | — | **req** |
| Attempt settings | ✓ | ✓ | ✓ | ✓ | ✓ |
| Marks / negative | ✓ | ✓ | ✓ | ✓ | ✓ |

  Backend mapping unchanged (`self`+kind / `live` / `group`). Quick keeps `target_question_count`.
  Note: Group Test creation is **blocked live** until `rpc_get_user_groups` exists — it will be reported as "not configured", not faked.

### C5. Pre-test (Detail) — Flutter only
Add an "About this test" section: type, question count (from `get_test_questions_safe` count — already fetched at start; for the pre-test view a count-only read via the same RPC), duration, start/availability, calculated end, attempts (existing), late-join info (Challenge/Group), scoring (marks/negative), concept (syllabus node names via existing `test_syllabus` + `syllabus_nodes`), instructions (`tests.instructions`). CTA state machine untouched.

### C6. Question Source step (Flutter only, truthful)
New wizard step "Question Source" before Questions: Manual (works) · Via Document (PDF/Word/Excel) · Via AI · Via Books — the last three render a real selection card with an honest "Not configured yet — this source has no processing pipeline in this build" state and a disabled Continue; selection is persisted as `creation_method` (`manual|upload|ai`) for Manual/Document/AI only when the corresponding pipeline exists (so V1 always sends `manual`). Home tiles route to the wizard with that source pre-selected. No fake extraction, no AI calls, no book content.

## D. DB migration required?
- **Yes, one, already pending**: `_fn_start_attempt_core` for the late-join window → merged into `R4_REATTEMPT_POLICY.sql` (v2). No schema change.
- **Follow-up (needs verbatim live bodies)**: `rpc_create_question` / `rpc_update_question` option minimum 2 → 4. Paste:
  ```sql
  select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('rpc_create_question','rpc_update_question');
  ```
- Not required: columns for distribution / late-join window / question count (settings jsonb); Document/AI/Books tables (out of scope, would be speculative).

## E. Flutter files to change
`domain/test_kind.dart` (creatable list), new `domain/question_config.dart` (Mixed config + validation), `domain/publish_readiness.dart` (4 options, distribution vs actual, scope per kind, late-join), `domain/test_lifecycle.dart`/`state/test_detail_controller.dart` (late-join window mirror), `models/question_draft.dart` (≥4), `widgets/question_editor.dart` (MCQ only, 4 rows, TF/others "Coming soon"), `widgets/configuration_step.dart` (kind sections, duration→end, late-join window, question config), new `widgets/question_source_step.dart`, `screens/test_creation_screen.dart` (step order: Basic → Config → Syllabus → Source → Questions → Review), `state/test_creation_controller.dart` (settings keys, derived `ends_at`, validation), `widgets/review_step.dart`, `screens/test_detail_screen.dart` (+ pre-test section), `features/home/home_screen.dart` (tiles → wizard), `domain/test_errors.dart` (`LATE_JOIN_WINDOW_CLOSED`), `data/test_repository.dart` (no signature change), tests + fakes.

## F. Test matrix (to add)
A/B Mixed valid/invalid (8+7+5=20 ✓; 8+7+4 ✗ blocks Next) · C options 4 ✓ / 3 ✗ / 2 ✗ (draft, editor, readiness) · D 10:00 + 30 min → 10:30 local and UTC payload; no independent end · E late join ON+10: 10:05 ✓, 10:09 ✓, 10:10:00 ✓, 10:10:01 ✗ (domain + fake mirroring the SQL) · F late join OFF: blocked after start; in_progress resumes · G `>= ends_at` unchanged · H Self create→start→submit→result (fakes) · I Practice `test_kind` + required scope · J Quick `target_question_count` + short duration · K Challenge: join code required, code join flow, late-join window · L Group: real groups only, required group, "not configured" when `rpc_get_user_groups` missing · M existing re-attempt A–L untouched · N source step: Manual proceeds; Document/AI/Books show "Not configured", cannot proceed, send `creation_method=manual` never `ai/upload` · O grep-guard: no hardcoded demo questions/groups/books/results · P full suite.

## Sequencing proposal
1. Fold the late-join window into `R4_REATTEMPT_POLICY.sql` (v2) → you apply once.
2. Flutter: C1 (types + 4 options + Mixed config + scope), C2, C3 client, C4, C5, C6 + tests.
3. Follow-up migration for the 4-option server guard once the two question-RPC bodies are pasted.

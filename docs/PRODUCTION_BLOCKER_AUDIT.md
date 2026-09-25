# Production Blocker Audit — Auth Signup / Email / Test Creation / Data Cleanup

## Phase 0 — Freeze / Inventory

- **Branch**: `r4-restart`.
- **Uncommitted changes**: ~103 files show as modified/untracked in `git status --short`. The large majority belong to other, concurrently-in-progress sessions (Group Hub/Notifications/Question Bank/Camera work — `lib/features/notifications/**`, `lib/features/group/**`, `lib/core/services/camera_capture_service.dart`, dozens of `docs/*_REPORT.md` files, `node_modules/`, `package.json`). This pass touched **only**: `lib/features/test/data/question_repository.dart` (the already-applied `p_negative_marks` fix, now extended with structured error logging in this pass), `android/app/build.gradle.kts` + `android/app/src/main/AndroidManifest.xml` + the `MainActivity.kt` package move (applicationId/signing/INTERNET-permission work from prior gates this session), and the new migration file `migrations/FINAL_AUDIT_add_rpc_record_integrity_event.sql` (unapplied). Nothing else was touched.
- **Current Flutter auth implementation**: `lib/core/services/auth_service.dart` (static class, `signUp`/`signIn`/`signOut`, friendly error mapping) + `lib/core/services/supabase_service.dart` (`Supabase.initialize`) + `lib/features/auth/auth_screen.dart` (combined login/signup UI) + `lib/app/app_router.dart`'s `redirect` (auth-state-gated routing). All confirmed already complete and correct in prior audits this session — re-verified below for the signup-specific question.
- **Current test creation/publish implementation**: `lib/features/test/screens/*` → `lib/features/test/state/test_creation_controller.dart` → `lib/features/test/data/test_repository.dart` + `lib/features/test/data/question_repository.dart` → Supabase RPCs (`rpc_create_test`, `rpc_update_test`, `rpc_create_question`, `rpc_update_question`, `rpc_add_test_syllabus`, `rpc_remove_test_syllabus`, `rpc_publish_test`).
- **Relevant migrations inspected this pass**: `R4_1_phase_db_foundation.sql` (original schema), `R4_5_1_test_creation_write.sql` (original RPCs), `R4_QUESTION_OPTION_GUARD.sql` (>=4-option guard), `R4_FIX_rpc_update_question_status_cast.sql` (latest live `rpc_update_question` body), `R7_FIX_rpc_create_question_status_cast.sql` (latest live `rpc_create_question` signature), `G10_1_fix_rpc_create_test_permission.sql` (latest live `rpc_create_test`), `R4_FIX_rpc_publish_test_status_cast.sql` (latest live `rpc_publish_test`).
- **No data was deleted or modified.** This entire pass is read/audit plus two narrowly-scoped Flutter code edits (already covered above).

## Phase 1 — Authentication / Signup

Traced `AuthScreen` → `AuthService.signUp` → `_auth.signUp()` (supabase_flutter's GoTrue client) → `AuthStatus` stream → router redirect.

1. **Supabase URL/anon key source**: `AppConfig.fromEnvironment()` reads `String.fromEnvironment('SUPABASE_URL')`/`('SUPABASE_ANON_KEY')` — compile-time constants baked in via `--dart-define-from-file`. Confirmed real values present in both `dart-defines.dev.json` and `dart-defines.prod.json` (same project — no evidence anywhere in this repo of a separate production Supabase project).
2. **`AuthService.signUp` implementation** (`auth_service.dart:67-91`): calls `_auth.signUp(email, password)`, throws only if `response.user == null`, otherwise logs success and returns. **It does not look at `response.session` at all** — this is correct: Supabase's own contract for signup is "user is non-null on success; session is non-null only when email confirmation is OFF (or already auto-confirmed)." The code does not incorrectly assume a session is present (item 12 — not a bug).
3. **Email confirmation**: cannot be checked from this repo — it is a Supabase Dashboard (Authentication → Providers → Email) setting, invisible from any file here.
4. **Signup return shape**: per (2), the code correctly branches on `user` only, never trusts `session`/`identities` for success/failure.
5–6. **Real error / message**: cannot be captured without a live reproduction (no DB/device access this pass — see Phase 4).
7–10. **SMTP / built-in sender / rate limits / spam**: all Supabase Dashboard / mail-provider matters, invisible from this repo.
11. **Site URL / Redirect URLs**: not applicable to a plain email/password signup with no OAuth or magic-link redirect in this code path (`_auth.signUp` here passes no `emailRedirectTo`) — this only matters for the confirmation *link*'s own redirect target, not for whether the email itself is sent.
13–15. **Profile creation / trigger / RLS**: `lib/core/services/profile_service.dart` (`ProfileService.loadProfile()`) **only reads** a profile row — there is no `insert`/`upsert` call anywhere in this file or anywhere else in `lib/`. Profile creation must therefore happen via a **database trigger on `auth.users`** that is entirely out-of-repo: no migration in `migrations/` creates the `profiles` table, an `ALTER TABLE`, or a `handle_new_user`-style trigger (grepped the whole directory). **This cannot be verified or fixed from this repo — BLOCKED, requires Supabase Dashboard/SQL access.**
16. **Does Flutter incorrectly report success as failure?** No — proven false by direct code reading: the only way `signUp()` throws is `response.user == null` or a real `AuthException`/other exception from the network call. There is no logic path that manufactures a false failure.

**Conclusion (Phase 1, proven)**: The signup *code path itself* is correct — it does not misreport success as failure, and it does not wrongly assume a session exists. **The reported "confirmation email is NOT arriving" is a genuinely separate, out-of-repo problem — Supabase email delivery configuration/dashboard, not a Flutter or RPC bug.** Per the task's own instruction, these are explicitly **not called the same problem** here.

**Actionable, non-blind recommendation** (not applied — dashboard-only, cannot be done from this repo): Supabase's own built-in email sending (no custom SMTP configured) is intentionally rate-limited to a handful of emails per hour and is explicitly documented as unsuitable for production — the most common real-world cause of "signup works, email never arrives" for a project still on the default sender. If Authentication → Providers → Email → Confirm email is ON and no custom SMTP is configured under Authentication → Email Templates/SMTP Settings, that is almost certainly the actual cause and requires configuring a real SMTP provider (or disabling forced confirmation for testing) — a dashboard action, not a code fix.

## Phase 2 — Test Creation / Publish

Full parameter-by-parameter cross-check of every write RPC used by `TestCreationController`, against the **latest** version of each RPC's signature in every migration file that redefines it (not just the first one):

| Call | Client params (after this session's fixes) | Live signature (latest file) | Match? |
|---|---|---|---|
| `rpc_create_test` | `p_title, p_description, p_duration_sec, p_marks_per_question, p_negative_marks, p_test_mode, p_creation_method, p_group_id, p_starts_at, p_ends_at, p_max_participants, p_allow_late_join, p_config, p_settings, p_access_code, p_join_code` | `G10_1_fix_rpc_create_test_permission.sql` — identical parameter list | ✅ exact |
| `rpc_update_test` | same list minus `p_test_mode`/`p_creation_method` (not updatable), plus `p_test_id` | `R4_5_1_test_creation_write.sql:383` — identical | ✅ exact |
| `rpc_publish_test` | `p_test_id` only | `R4_FIX_rpc_publish_test_status_cast.sql:27` — `p_test_id uuid` only | ✅ exact |
| `rpc_create_question` | `p_test_id, p_question, p_question_type, p_options, p_correct_option?, p_explanation?, p_subject_id?, p_topic_node_id?, p_difficulty, p_marks, p_language?` | `R7_FIX_rpc_create_question_status_cast.sql:14` — 15 params incl. `p_ordinal, p_status, p_source_batch, p_bank_id` (all have defaults, safely omitted by the client) | ✅ exact — **`p_negative_marks` was the one mismatch, already removed this session** |
| `rpc_update_question` (edit) | `p_question_id` + the same subset as create (no `p_ordinal`/`p_status`/etc.) | `R4_FIX_rpc_update_question_status_cast.sql:35` — 12 params, all optional except `p_question_id` | ✅ exact |
| `rpc_update_question` (approve) | `p_question_id, p_status` only | same function | ✅ exact |
| `rpc_add_test_syllabus` | `p_test_id, p_syllabus_node_id` | `R4_5_1_test_creation_write.sql:989` — same plus optional `p_material_ids` | ✅ exact |
| `rpc_remove_test_syllabus` | `p_test_id, p_syllabus_node_id` | `R4_5_1_test_creation_write.sql:1047` — identical | ✅ exact |

**No further client-vs-live-signature parameter mismatch was found beyond the already-fixed `p_negative_marks`.** Also checked, not just param names but semantics:
- **Option-count guard**: server requires `p_options` to have ≥4 non-empty-text entries (`R4_QUESTION_OPTION_GUARD.sql:117-127`). Client-side, `QuestionDraft.minOptions = 4` and `question_editor.dart`'s `_isValid` getter already blocks Save unless ≥4 options are present *and* none are blank — client and server rules match exactly.
- **`p_correct_option` bounds, `p_difficulty` enum values (`easy|medium|hard`), `p_language` enum (`en|hi|hinglish`), `p_question_type` enum (`mcq|tf|short|num`)**: all cross-checked against the Dart enums/constants that populate them (`DifficultyLevel`, `questionTypeToRpc()`) — all produce values inside the server's allowed sets for a normally-filled-in manual question.
- **Value the client omits (language/subject/topic for a brand-new question)**: `question_editor.dart`'s `_save()` carries these through only from `widget.initial` (null for a new question), so they are correctly omitted rather than sent as an invalid value.

**A documentation-only inconsistency was found and is flagged, not treated as a live bug**: `R4_1_phase_db_foundation.sql`'s original `questions` table DDL only defines `correct_answer text`, but every later migration's `rpc_create_question`/`rpc_update_question` body reads/writes a column literally named `correct_option`. No migration in this repo contains an `ALTER TABLE ... ADD COLUMN correct_option` for `questions`. This is consistent with this project's already-established, repeatedly-proven pattern (documented in prior-session memory) that the live schema has diverged from this repo's migration history via out-of-repo changes — and is **not** treated as evidence of a live bug here, because `R4_QUESTION_OPTION_GUARD.sql`'s own preflight comments explicitly state (from a session that *did* have live verification access) "rpc_update_question — the live body = ... (applied; approvals work live)". Trusting that documented live evidence over re-deriving a contradictory conclusion from static file gaps.

**Which operation actually fails (items A–I)**: Cannot be proven further without a live reproduction — see Phase 4. What **is** provable: the dialog's exact text ("Failed to save. Please try again.") is `TestErrorContext.save`'s generic fallback (`test_errors.dart:148-149`), which is reached only by the question-create/question-update/test-row-save paths, never by `rpc_publish_test` itself (that has its own distinct fallback, "Failed to publish test..."). So **whatever is failing happens before the publish RPC is ever called** — consistent with everything already fixed (`p_negative_marks`) and everything re-verified clean above. **Item H (partial data left behind)**: if `_persistTestRow()`/`_persistQuestions()` succeeds partially before a later step fails, the test row and any already-created questions genuinely exist server-side as a **draft** — `TestCreationController` is explicitly designed for this (`_persisted` is cached after the first successful create, so a retry updates rather than re-creates; `localQuestions.remove(draft)` after each successful create so a retry never double-creates a question). This is correct-by-design partial-progress handling, not silent data corruption — confirmed by reading `_persistTestRow()`/`_persistQuestions()` (`test_creation_controller.dart:530-567`).

## Phase 3 — Error Visibility (fixed this pass)

**Problem found**: `test_repository.dart`'s `_guard` already logged full `PostgrestException` fields (`code`, `message`, `details`, `hint`) — but `question_repository.dart`'s `_guard` logged **only `.message`**, silently discarding `code`/`details`/`hint` for every question create/update/approve/delete failure. Additionally, `TestErrors._detail()` deliberately truncates/drops any raw error text over 140 characters or containing `{`/`}`/`"`/newlines before it would ever reach the UI — by design, to avoid dumping raw Postgrest text on a student's screen, **not** a bug, but it does mean the *user-facing* message alone was never going to be diagnostic. The right fix (per this phase's own framing) is not to widen what students see, but to make sure developers see everything in logs.

**Fix applied**: `lib/features/test/data/question_repository.dart` — the `PostgrestException` catch in `_guard` now logs `code`, `message`, `details`, and `hint`, matching the pattern already used in `test_repository.dart`. No password, token, or credential is ever logged (confirmed: neither repository's catch blocks reference any auth/session object). The user-facing message shown via `TestErrors.map(...)` is completely unchanged — still friendly, still short.

**Why this doesn't solve the release-mode visibility gap by itself**: a prior gate in this session already found `lib/core/logging/app_logger.dart` uses the `logger` package's default filter, which only prints in `kDebugMode`. That is unrelated to this fix and was **not** touched here (Phase 3's own instruction: don't dump secrets, and changing the global logging filter is exactly the kind of change that needs its own explicit review, not a silent bundling into this fix). **For actually diagnosing this bug, use a debug or web build** (see Phase 4) — logs will print there regardless of the release-mode filter question.

## Phase 4 — Chrome / Web Verification

**Web support**: `web/` directory exists (`index.html`, `manifest.json`, icons) and `flutter devices` lists a usable Chrome target. `flutter build web --dart-define-from-file=dart-defines.dev.json` was run this pass and **succeeded** (exit 0, `build/web` produced) — the project genuinely compiles for web, this is not a blocker.

**Hard limitation, reported honestly rather than worked around**: this session's tool access has **no browser-automation or computer-use capability** — there is no way to launch Chrome, click through the signup/create-test/publish flow, and read the resulting UI or browser console from here. A `flutter build web` compile-only check was run as the one verification actually possible without a browser driver (result recorded separately in this pass's terminal output). **Interactive Chrome/web verification of the actual flows (items 1–12) could not be performed and is explicitly marked UNVERIFIED, not assumed-passing.**

**What this means practically**: reproducing the exact `PostgrestException` this bug hunt needs requires a human (or a tool-equipped session) to actually run `flutter run -d chrome --dart-define-from-file=dart-defines.dev.json`, sign in, and attempt Create → Add Question → Publish while watching the browser console/terminal output — the structured logging fix in Phase 3 will surface the real `code`/`message`/`details`/`hint` there the moment it's reproduced.

## Phase 5 — Supabase Data Cleanup / Delete

**Nothing was created against any live database by this session** — every prior "disposable test/attempt" discussion in this conversation (the integrity-event verification gates) was **planning only**: this environment has never had live Supabase access (no CLI, `psql`, `.env`, or credentials anywhere in the repo or dev machine, confirmed repeatedly across this entire session). No cleanup is owed for anything done here.

**For your own past manual testing** (if any disposable tests/users exist from earlier device testing), the safe, non-destructive way to identify and clean them up **without weakening RLS or using a service-role key in Flutter**:
- **Tests**: in the Supabase Dashboard's Table Editor (or SQL Editor, as yourself, subject to your own RLS visibility), filter `tests` by `created_by = <your test user's auth.users id>` and a recognizable disposable title (e.g. anything prefixed `DISPOSABLE` if you used that convention), and note `id, title, status, group_id` plus row counts in `attempts`/`questions`/`results`/`test_invitations` referencing that `test_id` before deleting anything.
- **Safe test deletion**: use the app's own `rpc_delete_test` (already exists, already used by the Flutter "Delete draft" action) rather than a raw `DELETE` — it enforces creator-only, draft-only, not-already-deleted, and is a soft delete (`is_soft_deleted`), never a hard delete, so nothing is unrecoverable.
- **Auth users**: distinguish three different things, only the last of which should ever be considered for cleanup, and only via the Dashboard's Authentication → Users panel (which uses Supabase's own admin API under the hood, never a service-role key embedded in Flutter): (1) the `profiles` row, (2) the `auth.users` row, (3) all application data referencing that user's id (attempts, results, group memberships, etc. — cascades are whatever each table's own FK `ON DELETE` behavior specifies, which is out-of-repo and should be checked in the Dashboard before deleting a user, not assumed).
- **No client-side "delete my account" or admin bulk-delete mechanism exists in this codebase, and none was added** — per the task's own explicit prohibition on a mechanism that lets arbitrary users delete `auth.users` rows.

## Phase 6 — Database Consistency

Already covered by Phase 2's table (every write RPC's live signature vs. client params). RLS/SECURITY DEFINER/search_path status for every table in scope (`tests`, `questions`, `test_syllabus`, `test_invitations`, `attempts`, `answers`, `results`, `result_batches`, `ai_reports`) was already exhaustively audited in a prior gate this session (see `docs/FINAL_PRODUCTION_READINESS_REPORT.md` §3) — not re-derived here to avoid duplicating that work; nothing in this pass's fresh reading contradicts those findings. All RPCs touched in this pass (`rpc_create_test`, `rpc_update_test`, `rpc_publish_test`, `rpc_create_question`, `rpc_update_question`, `rpc_add_test_syllabus`, `rpc_remove_test_syllabus`) are confirmed `SECURITY DEFINER` with `SET search_path TO ''` in their latest migration file versions, and each independently re-derives the acting user via `public._fn_auth_uid()`/`auth.uid()` rather than trusting any client-supplied identity.

## Phase 7 — Auth + Test Permission Check

For the specific reproduction in your screenshot (`Test Type: Self`, i.e. `test_mode = 'self'`, not a group test): `rpc_create_question`'s permission check is `public._fn_can_manage_questions(p_test_id, v_uid)` — for a self-mode test this resolves to creator-only ownership, no group membership or `CREATE_TEST`/`EDIT_TEST` group permission is involved at all. **Group permission checks are not in play for this specific bug** — ruled out as a cause for this reproduction. (They remain relevant for group-mode test creation, already audited in a prior gate this session.)

## Phase 8 — Minimal Fixes Applied This Pass

1. `lib/features/test/data/question_repository.dart` — `_guard`'s `PostgrestException` handler now logs `code`/`message`/`details`/`hint` (previously only `.message`), matching the pattern already present in `test_repository.dart`. This is the only functional change in this pass beyond the audit itself.

Nothing else was changed. No RLS, no grants, no `auth.uid()` bypass, no service-role key, no fabricated success response, no swallowed exception, no UI rewrite, no schema change.

## Phase 9 — Verification Matrix

**AUTH**
- [ ] New signup creates auth user — code path proven correct by reading; not reproduced live (no DB/browser access).
- [ ] Confirmation email behavior — **BLOCKED**, Dashboard-only, cannot be checked from this repo.
- [ ] Login works — re-confirmed via existing passing `auth_screen_test.dart` (client-side validation/flip only, no live network).
- [ ] Logout works — same as above.
- [ ] Existing confirmed user can login — UNVERIFIED, no live reproduction possible.
- [ ] Profile exists correctly — **BLOCKED**, trigger is out-of-repo, cannot be verified.
- [x] Failed signup exposes a meaningful developer diagnostic — `AuthService` already logs `AppLogger.error('Sign in/up AuthException: ${e.message}')`; visible in debug/web builds (release-mode log suppression is a separate, previously-documented issue, not touched here).

**TEST CREATION**
- [x] Create/Save/Publish RPC parameter contracts verified against every live migration — **no code-level mismatch found** beyond the already-fixed `p_negative_marks`.
- [ ] End-to-end Create → Add question → Publish → appears in list → open → start → answer → submit → results — **UNVERIFIED**, no browser-automation or physical-device access this pass. `flutter analyze` clean on all touched files; targeted test suite still passing (60/63, 3 pre-existing unrelated failures, confirmed in the immediately preceding gate).

**SECURITY**
- [x] No service-role credential in Flutter — reconfirmed this pass (none introduced, none found).
- [x] No RLS bypass, no `auth.uid()` bypass, no broad grants — none introduced.
- [ ] Ordinary member cannot create/publish without permission / student cannot read correct answers / user cannot touch another user's attempt or answers — already proven in prior gates this session (see `FINAL_PRODUCTION_READINESS_REPORT.md`), not re-derived here.

**DATA**
- [x] No disposable-cleanup debt from this session — nothing was created (no live access, ever).
- [x] Safe cleanup method documented (Phase 5) — uses existing `rpc_delete_test` and Dashboard-only actions, no new mechanism.
- [x] No orphaned partial-creation data risk from the controller's own logic — `_persisted`/`localQuestions.remove()` retry-safety already exists and was confirmed by reading, not changed.

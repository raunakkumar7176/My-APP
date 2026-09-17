# R4 Test System — Completion Report (2026-09-17)

Branch `r4-restart` · HEAD `85b1b1d` · `flutter test` **471/471** · `flutter analyze` **0 errors, 0 warnings** (58 style infos) · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` **√ Built**.

**This is NOT "100 % complete."** Every backend rule added this week exists only as a migration file until it is run in the Supabase SQL Editor (§8). The Flutter side is complete for V1 and verified by automated tests; device/Chrome E2E was done only for the flows listed in §6.

## 1. Implemented (Flutter complete, backend as noted)

| Area | Status | Where |
|---|---|---|
| Five V1 kinds — Self, Practice, Quick, Challenge with Friends, Group; Sectional/Adaptive reserved | ✅ | `TestKind.creatable`, `TestKindCreation` extension |
| Kind-specific configuration (schedule/late-join/participants only for scheduled kinds; join code for Challenge; group for Group; scope required for Practice/Quick; per-kind attempt defaults) | ✅ | `configuration_step.dart`, `test_creation_controller.dart`, `publish_readiness.dart` |
| MCQ-only, ≥ 4 options — client | ✅ | `QuestionDraft`, `QuestionEditor` (others "Coming soon", no invented TF options), readiness item |
| MCQ-only, ≥ 4 options — server | 📄 migration | `R4_QUESTION_OPTION_GUARD.sql` (create ≥ 4; update validates the FINAL set + correct_option) |
| Mixed difficulty target `settings.question_config` (E+M+H = Total, Quick ≤ 15), truthful actual-vs-target readiness, survives edit | ✅ | `QuestionConfig`, `DistributionCheck` |
| Duration → Calculated End Time; end picker removed; `ends_at = starts_at + duration_sec` written UTC; local display; edit keeps instant | ✅ | `ScheduleMath`, `configuration_step.dart`, `parseTimestamp` |
| Re-attempt policy (`allow_reattempt`, `max_attempts`; explicit intent; Back to Test never creates an attempt) — client | ✅ | `AttemptPolicy`, Detail state machine, Result Re-attempt, code-join confirm |
| Re-attempt policy — server | 📄 migration | `R4_REATTEMPT_POLICY.sql` (v2) |
| Late-join window `settings.late_join_minutes` (default ON, 10 min for Challenge/Group; boundary: exactly `starts_at + window` allowed, after it blocked; `ends_at` untouched) — client | ✅ | `LateJoinSettings`, Detail mirror |
| Late-join window — server | 📄 migration | `R4_REATTEMPT_POLICY.sql` v2 (`LATE_JOIN_WINDOW_CLOSED`) |
| Delete Draft Test (owner + draft + not deleted; soft delete; More → confirm → back to drafts) — client | ✅ | Detail More menu |
| Delete Draft Test — server | 📄 migration | `R4_DELETE_DRAFT_TEST.sql` (`rpc_delete_test`) |
| Group Test: real groups only, "No groups" state, required group | ✅ client · 📄 `R4_GROUPS_RPC.sql` (`rpc_get_user_groups` missing live) |
| Question Source step: Manual works; Document / AI / Books shown as **Not configured** with honest banner, cannot proceed; Home tiles open that step | ✅ | `question_source_step.dart`, `home_screen.dart` |
| Pre-test "About this test" (type, purpose, question count via safe RPC, duration, marks, negative, attempts, late join, scope, group, instructions) | ✅ | Detail |
| Test taking: navigation, answer, autosave, mark for review, resume, timer, submit, auto-submit | ✅ (autosave + submit + result **verified live** in Chrome) | existing R4 |
| Results: server score/max/correct/wrong/unanswered/accuracy/percentage/subject/topic; attempt number; Latest / Best / History; previous-attempt Δ from stored rows only; no fabricated rank/percentile/labels | ✅ | `AttemptHistory`, result screen |
| Batch results: authorized, idempotent, one batch per test — client | ✅ | `rpc_generate_results` consumption |
| Batch results — server reuse of any existing batch | 📄 migration | `R4_HOTFIX_submit_autosubmit_batch_reuse.sql` STEP 3 |
| Publish readiness: title, duration, marks, group, questions, approval, 4 options, draft validity, schedule, start time (scheduled kinds), scope (Practice/Quick), distribution valid + met, attempt settings, late-join window, join code | ✅ | `PublishReadiness` |
| Hotfixes: `rpc_update_question` status cast, `rpc_publish_test` cast, `rpc_save_answers` alias, `rpc_submit_attempt` cast, `fn_auto_submit` | see §8 | |

## 2. Partially implemented
- **Server-side enforcement** of re-attempt, late-join window, 4-option guard, draft delete, batch reuse, group RPC — all coded and committed as migrations; **not applied** by me (no SQL access). Until applied the client rules are UX-only for those items.
- **Mixed distribution** is a creator target checked against manually added questions (no generator exists; stated in UI).
- **Pre-test question count** uses `get_test_questions_safe` — shows "--" when the server refuses before the window opens.

## 3. Not implemented (by design, truthful states shipped)
- Document / AI / Books pipelines (no tables, jobs or RPCs exist; nothing was invented).
- True/False, Multiple, Numeric, Short question types (backend is index-scored only).
- Sectional / Adaptive kinds (reserved).
- Search / filters beyond the existing four listing tabs; offline mode (out of R4 scope, unchanged).

## 4. Backend verified (live evidence this week)
- `rpc_save_answers` alias hotfix — **applied & verified** (autosave works in Chrome).
- `rpc_submit_attempt` cast hotfix — **applied & verified** (submit → `void`, result row created).
- `rpc_publish_test` / `rpc_update_question` cast hotfixes — **applied & verified** (approve + publish succeeded live).
- `results` live columns (no `id`), `questions.source_batch` integer, `test_syllabus` without `id`, `attempts` row shape with `attempt_number`, own-attempts SELECT — verified; models aligned.
- `rpc_get_user_groups` **absent live** (404 on every Create/Edit open) — migration written.
- `fn_auto_submit` absent live, `result_batches UNIQUE(test_id)` collision — migration written; **not yet verified applied** (no log since).
- `LATE_JOIN_NOT_ALLOWED` boolean rule — verified live behaviour.

## 5. Flutter verified (automated)
471 tests: domain, controllers, fakes mirroring server rules, widget smoke, and the completion matrix — A Self, B Practice, C Quick, D Challenge, E Group, F/G 4-option create/update, H invalid count, I correct-option bounds, J Mixed, K duration/end, L late-join window, M attempt limit, N explicit re-attempt, O no silent attempt on Back, P autosave, Q manual submit, R auto submit, S result generation, T batch reuse, U draft delete, V readiness, W unsupported types, X group requirement, Y timezone round trip, plus regression of every earlier R4 suite.

## 6. Device / Chrome E2E verified
Chrome (web debug, live Supabase): login, create/edit test, approve, publish, start attempt, answer → autosave, submit → result row → result screen, Challenge late-join refusal (`LATE_JOIN_NOT_ALLOWED`). Moto G31: earlier R4 device runs (drafts, publish gate). **Not yet run on device/Chrome:** re-attempt policy, late-join window, delete draft, option guard, group RPC, batch reuse — all depend on the unapplied migrations.

## 7. Remaining blockers
1. Apply the migrations in §8 (each has preflight/postflight; STOP if a preflight differs).
2. Legacy questions with < 4 options: count/IDs come from `R4_QUESTION_OPTION_GUARD.sql` preflight (4); they are never modified — creators must fix them before re-saving.
3. `rpc_get_user_groups` must exist before Group Test creation works live.
4. Device E2E of the six areas above after the migrations.

## 8. Migrations — applied / not applied
| File | Content | Status |
|---|---|---|
| `R4_FIX_rpc_update_question_status_cast.sql` | COALESCE enum cast | **applied** (live verified) |
| `R4_FIX_rpc_publish_test_status_cast.sql` | `public.test_status` cast | **applied** (live verified) |
| `R4_HOTFIX_rpc_save_answers_alias.sql` | alias `answer_item` | **applied** (live verified) |
| `R4_HOTFIX_submit_autosubmit_batch_reuse.sql` | STEP 1 submit cast **applied** (verified); STEP 2 `fn_auto_submit`, STEP 3 `rpc_generate_results` reuse | STEP 2/3 **unverified** |
| `R4_DELETE_DRAFT_TEST.sql` | `rpc_delete_test` | **not applied** |
| `R4_REATTEMPT_POLICY.sql` (v2) | core `p_reattempt` + policy + late-join window; `rpc_start_attempt(uuid, boolean)`, `rpc_start_attempt_by_code(text, boolean)` | **not applied** |
| `R4_QUESTION_OPTION_GUARD.sql` | ≥ 4 options create/update | **not applied** |
| `R4_GROUPS_RPC.sql` | `rpc_get_user_groups()` | **not applied** |

## 9. RPCs added / changed (by these migrations)
Added: `fn_auto_submit(uuid)` (internal), `rpc_delete_test(uuid)`, `rpc_get_user_groups()`.
Changed: `rpc_update_question`, `rpc_publish_test`, `rpc_save_answers`, `rpc_submit_attempt`, `rpc_generate_results`, `rpc_create_question`, `_fn_start_attempt_core(uuid, boolean, boolean)`, `rpc_start_attempt(uuid, boolean DEFAULT false)`, `rpc_start_attempt_by_code(text, boolean DEFAULT false)`. No table, column, constraint or RLS change anywhere.

## 10–13. Counts / results
- Tests: **471 passed**, 0 failed, 0 skipped.
- Analyze: **0 errors, 0 warnings**, 58 infos (pre-existing style: prefer_const, deprecated Radio API).
- APK: **√ Built build\app\outputs\flutter-apk\app-debug.apk** with `dart-defines.dev.json`.
- Commit: **`85b1b1d`** (this phase); earlier focused commits `9ca27ad` (re-attempt), `910963a` (option guard), `3ce58b7` (delete draft), `4ab22c0` / `99342b3` / `ef99826` (hotfix SQL).

## Screen audit (Phase 15) — summary
Tests Hub / tabs / Detail / Create entry / Basic / Type / Configuration / Attempt Settings / Late Join / Question Source / Syllabus / Questions / Editor / Review / Approval / Publish / Drafts / Delete / Edit / Join With Code / Instructions (pre-test) / Taking / Navigation / Submit / Result / Analysis / Review Answers / History / Re-attempt / Group & Challenge detail / Generate Results / Batch / Permission-error / Loading / Empty / Resume / Timer / Access denied / Ended / Coming Soon: all render from stored data; no demo data (grep: no hardcoded questions/groups/books/results in `lib/`); no dead buttons (unavailable sources and types are labelled and disabled); no `public.questions` read; no `correct_option` parse; no silent attempt creation (`start()` never sends intent; server rejects after a completed attempt once applied); no timezone shift; no duplicate batch (once applied); no < 4 option drafts; group selection uses live RPC only. **Search / offline** are not R4 features and were not changed.

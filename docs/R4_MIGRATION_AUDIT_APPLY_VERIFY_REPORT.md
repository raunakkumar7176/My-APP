# R4 Migration Audit → Apply → Verify Report

## 1. Baseline
- Commit: `c5c1a4c` (completion report) on top of `85b1b1d` — this work adds one commit (see §11).
- Date: 2026-09-17
- Flutter 3.47.3 (stable); supabase_flutter 2.17.2
- Supabase project ref: `cnwtprexxjrajcdjhfsr` (from `dart-defines.dev.json`, git-ignored)
- Sources: `docs/R4_TEST_SYSTEM_COMPLETION_REPORT.md`, `docs/R4_CREATION_COMPLETION_AUDIT.md`, `docs/R4_REATTEMPT_AUDIT.md`, `migrations/`, git log.

### Execution constraint (stated up front, not hidden)
This development environment has **no live database access**: no `psql`, no `supabase` CLI, no database URL, no service-role key. Only the anon key exists, which cannot read `pg_proc`/`pg_policies` nor execute DDL. Therefore **no migration was applied or live-verified by the agent in this run.** Everything below is (a) static audit of each migration against the last live evidence, (b) a single read-only preflight script for you to run, (c) Flutter contract verification, (d) automated checks. Apply happens in the Supabase SQL Editor; each migration carries its own preflight/postflight that decides APPLIED / STOP.

## 2. Migration Matrix

| Migration | File | Preflight (last live evidence) | Action | Postflight | Status |
|---|---|---|---|---|---|
| A Re-attempt + Late-Join core v2 | `migrations/R4_REATTEMPT_POLICY.sql` | Live core = `(p_test uuid, p_code_verified boolean DEFAULT false)`; behaviour markers (resume, MAX+1, `>= ends_at`, `LATE_JOIN_NOT_ALLOWED`) verified live; no `REATTEMPT_LIMIT_REACHED` / `LATE_JOIN_WINDOW_CLOSED` anywhere | Run file top→bottom (DROP old 3 signatures → CREATE core v3-arg, `rpc_start_attempt(uuid, boolean)`, `rpc_start_attempt_by_code(text, boolean)`, grants) | In-file postflight: exactly 3 rows, args as expected, grants, constraint unchanged | **NOT APPLIED** |
| B Four-option guard | `migrations/R4_QUESTION_OPTION_GUARD.sql` | Live `rpc_update_question` = applied status-cast hotfix body; `rpc_create_question` = R4_5_1 body with live return `{question_id, ordinal, message}`; both still `≥ 2` | Run after A (independent, but same session); in-file preflight (1)–(4) incl. legacy `< 4` count | Markers `at least 4 options` + `every option needs text`, old guard gone, grants unchanged | **NOT APPLIED** |
| C Draft delete | `migrations/R4_DELETE_DRAFT_TEST.sql` | No `rpc_delete_test` in repo/live evidence; soft-delete columns owner-listed | Run; preflight checks columns + no conflicting signature | `rpc_delete_test(uuid)` jsonb, DEFINER, `search_path=`, authenticated-only | **NOT APPLIED** |
| D Groups RPC | `migrations/R4_GROUPS_RPC.sql` | `rpc_get_user_groups` **absent live** (404 on every Create/Edit open, Chrome 09-16/17); `fn_is_member`/`fn_has_permission` live ⇒ tables exist | Run; preflight checks 8 columns | RPC exists, DEFINER, `search_path=`, authenticated-only | **NOT APPLIED** |
| E fn_auto_submit | `migrations/R4_HOTFIX_submit_autosubmit_batch_reuse.sql` STEP 2 | `fn_auto_submit(uuid)` **absent live** (42883 from `rpc_save_answers` deadline branch, Chrome 09-17) | Run STEP 2 (STEP 1 already applied — see §3) | Function present, DEFINER, `search_path=`, no client grants | **NOT APPLIED (unverified since)** |
| F Batch reuse | same file, STEP 3 | Live `rpc_generate_results` reuses only pending/processing; duplicate `result_batches_test_id_key` reproduced live | Run STEP 3 (verbatim live body + lookup filter removed) | Marker: no `status IN ('pending'…'processing')` in lookup; `'reused', true` branch present | **NOT APPLIED (unverified since)** |

Dependency notes: A must run before any live test of re-attempts; B is independent; C, D, E, F are independent of each other. `R4_MASTER_PREFLIGHT.sql` §2 body markers tell you instantly which of the six are already live (in case any were applied outside this session).

## 3. Live Function Verification
Verified **live** earlier this week (Chrome logs against the live project):
- `rpc_save_answers(uuid, jsonb) → void` — alias hotfix applied (autosave returns `null`, no 42702).
- `rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false) → void` — enum-cast hotfix applied (submit succeeds, result row created).
- `rpc_update_question` — `p_status::public.question_status` applied (approvals succeed).
- `rpc_publish_test` — `'published'::public.test_status` applied (publish succeeds).
- `rpc_start_attempt(p_test)` returns an `attempts` row with `attempt_number` (shape logged).
- `get_test_questions_safe` returns 15 columns, no `correct_option` (client asserts).

To be verified by `R4_MASTER_PREFLIGHT.sql` §1–§3 (signature, `prosecdef`, `proconfig`, grants) — **pending your run**. The expected values are annotated in the script; any `f` in a hotfix column is a regression to report before applying anything.

## 4. RLS / Security Verification
- Verified live by behaviour: `tests` own-draft + accessible SELECT; `answers` own-rows SELECT/INSERT/UPDATE (after the owner's GRANT); `attempts` own-rows SELECT (client `mine()` works — reported by the owner as "authenticated users can SELECT their own attempts; creator/group read policy also exists"); `results` own-rows SELECT; `result_batches` SELECT is GENERATE_RESULTS-permission based (owner cannot read → client never reads it).
- **Pending** (`R4_MASTER_PREFLIGHT.sql` §6): policy names/expressions for `questions` (must have no client SELECT path), `attempts`, `answers`, `results`, `result_batches`, `groups`, `group_members`; recursion check on `group_members`.
- None of the six migrations touches RLS, table grants, or schema. All new/changed functions are `SECURITY DEFINER` with `SET search_path TO ''` except the three pre-existing `search_path = 'public'` functions whose bodies are preserved verbatim (`rpc_submit_attempt`, `rpc_generate_results`).

## 5. Constraint Verification
- `attempts UNIQUE (test_id, user_id, attempt_number)` — owner-verified (duplicate-named constraint, same rule; migrations add none).
- `result_batches UNIQUE (test_id)` — owner-verified; preserved by F.
- `questions` ordinal uniqueness — enforced by `rpc_create_question`/`rpc_publish_test` validation (repo); constraint form **pending** §5 of the preflight.
- Four-option guard — server side only after B; client side already enforced (`QuestionDraft.minOptions = 4`).

## 6. Test Type Contract (final)
| Kind | `test_mode` | Group | Schedule / late join | Attempts |
|---|---|---|---|---|
| Self | self (+`settings.test_kind` absent) | not required | none | settings (default 1) |
| Practice Test | self + `test_kind=practice` | not required; syllabus scope required | none | default re-attempt ON ×3 |
| Quick Test | self + `test_kind=quick` | not required; scope required; ≤ 15 questions | none | settings |
| Challenge with Friends | live | **optional** (`group_id` may be null; standalone works via join code; if attached, `fn_is_member` applies in core) | start time required; late join ON 10 min default; window rule (A) | settings |
| Group Test | group | **required** (`rpc_create_test` rejects null) | start time required; late join ON 10 min default; window rule (A) | settings |

Core access branch (unchanged in A): creator → allowed; `group_id` set → `fn_is_member`; else code-verified or `fn_can_access_test`. So a Challenge with a group behaves as group-backed; without one it is standalone. Test types are never conflated with group context.

## 7. Flutter Contract Verification (static, this run)
- `rpc_start_attempt` → `{p_test, p_reattempt (only when true)}`; `rpc_start_attempt_by_code` → `{p_code, p_reattempt (only when true)}`; `rpc_submit_attempt` → `{p_attempt, p_auto}`; no `p_timed_out` anywhere in `lib/` or `test/`.
- `TestDetailController.start()` always sends `reattempt: false`; only `reattempt()` (Detail) and `ResultsController.reattempt()` send `true`; both are gated by `AttemptPolicyState.canReattempt`. "Back to Tests" is pure navigation.
- CTA machine: Start Test (no attempts) / Continue Test (in_progress) / View Result (+ Re-attempt or limit) — 19 policy tests + 22 completion tests.
- No `from('questions')`; `correct_option` only appears as an outbound RPC param and in a security assertion.
- Backward compatibility until A is applied: `p_reattempt` is omitted on plain starts, so the old `rpc_start_attempt(uuid)` keeps resolving; a Re-attempt tap on the old backend behaves as before (MAX+1) — this is why A is first in the apply order.

## 8. Automated Tests
- `flutter test`: **471 passed, 0 failed, 0 skipped**
- `flutter analyze`: **0 errors, 0 warnings** (58 pre-existing style infos)
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`: **√ Built**

## 9. Device E2E
VERIFIED (Chrome, live backend, earlier this week): login, create/edit, approve, publish, start, autosave, submit → result screen, late-join boolean refusal.
PENDING (all depend on the unapplied migrations): 1 Self full flow with policy, 2 Self re-attempt/limit, 3 Practice repeat, 4 Quick, 5 Challenge standalone, 6 Challenge group-backed, 7 Group Test (needs D), 8 late-join boundary (10:10:00 ok / 10:10:01 blocked), 9 timer expiry → auto-submit (needs E), 10 Generate Results, 11 existing batch reuse (needs F), 12 draft delete (needs C), 13 four-option validation (needs B), 14 Mixed readiness (client-only, ready), 15 Question Source truthful states (client-only, ready).
DEVICE E2E: **PENDING**

## 10. Remaining Blockers
1. Run `migrations/R4_MASTER_PREFLIGHT.sql`; paste output. (Decides APPLIED/NOT for each item and surfaces any hotfix regression.)
2. Apply in order A → B → C → D → E → F, each with its in-file preflight/postflight; STOP at the first mismatch and paste the SQLSTATE/error.
3. Legacy questions with `< 4` options (count from preflight §7) must be fixed by their creators; they are never modified automatically.
4. Device E2E list above after the migrations.

## 11. Final R4 Status
**PARTIALLY APPLIED — ACTION REQUIRED**
(Four hotfixes live-verified; six migrations coded, preflighted, statically audited, and waiting for execution in the SQL Editor. The agent cannot execute or live-verify SQL from this environment and has not claimed otherwise.)

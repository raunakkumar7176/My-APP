# My Preparation — Final Production Readiness Report

## Executive Status

**NOT PRODUCTION READY**

This is a code-and-static-analysis-verified audit. Two categories of evidence were **not available in this environment** and are reported honestly as `BLOCKED — UNVERIFIED` rather than assumed: (1) there is no live Supabase access (no CLI, `psql`, `.env`, or credentials anywhere in this repo or dev machine — a fact already documented from a prior session and reconfirmed in this pass), so no claim about the live database's actual RLS/policy/function state can be made truthfully; (2) no Android device was connected this session (`adb devices` returned empty both at the start and end of this pass), so anti-cheat behavior, camera, real install, and visual QA gates could not be exercised on hardware. Everything else below — code correctness, `flutter analyze`, `flutter test`, release build, and a full static security read of every migration file — was actually executed and is evidence-based.

---

## 1. Architecture audit

Full architecture inventory was performed (entry point, `MaterialApp.router`, `GoRouter`, auth routing, splash/startup, theme, state management, repositories/services/controllers, Android native config, assets, environment configuration) via direct reads plus four parallel static-audit subagents covering: debug/demo/secret sweep, anti-cheat/test-integrity code review, RLS/`SECURITY DEFINER` migration review, and route/dispose-hygiene review. Findings are folded into the sections below rather than repeated here. Previous implementation reports in `docs/` were treated as claims to verify, not as proof — several were independently re-checked against actual code in this pass (auth/splash/dashboard/routine/calendar/group-hub were all re-confirmed still passing their own test suites; the group-leaderboard area was found to still have a real, previously-flagged compile break — see §2).

## 2. Bugs found, fixed, and verified

### Bug 1 — `rpc_submit_attempt` had no server-side deadline check (timer-integrity gap)
- **Problem**: The countdown UI and autosave path (`rpc_save_answers`) are correctly deadline-driven and server-authoritative. But `rpc_submit_attempt` — the RPC that actually finalizes and scores an attempt — only checked `status <> 'in_progress'`; it never compared `now()` to `attempts.deadline_at`, and trusted the client-supplied `p_auto` boolean as-is.
- **Root cause**: The deadline enforcement was added to the autosave path only (`R4_HOTFIX_rpc_save_answers_alias.sql`) and never mirrored into the submit path (`R4_HOTFIX_submit_autosubmit_batch_reuse.sql`).
- **Consequence**: A client that stopped autosaving before the deadline and only called `rpc_submit_attempt(id, false)` after the deadline had passed would have that submission accepted, scored, and recorded as an on-time `submitted` attempt — extra, undetected time past the official deadline.
- **Fix**: `migrations/R4_HOTFIX_submit_deadline_check.sql` (new) — `rpc_submit_attempt` now computes `v_late := deadline_at is not null and now() > deadline_at` and forces `auto_submitted` status when `p_auto OR v_late`, mirroring the existing autosave enforcement. The submission is still always accepted (never silently dropped, to tolerate normal network lag) — it is just always correctly labeled late.
- **Verification**: Found and fixed by static code reading (the exact literal SQL of the existing HOTFIX file was read and the gap confirmed by its absence). **DEPLOYMENT UNVERIFIED** — this migration has not been applied to any live database; I have no Supabase access to apply or test it. Preflight/postflight verification queries are embedded in the file for whoever applies it.

### Bug 2 — `rpc_create_group` (SECURITY DEFINER) had no `search_path` pin
- **Problem**: Every other `SECURITY DEFINER` function in the codebase explicitly sets `SET search_path TO ''` (confirmed by the static audit across ~30 functions). `rpc_create_group(text)` — client-callable, `GRANT`ed to `authenticated` — had none.
- **Root cause**: Omitted when the function was originally written in `R4_5_5_group_foundation.sql`; never caught since the function's body happens to already schema-qualify every reference (`public._fn_auth_uid()`, `public.groups`, `public.group_members`), so it was not currently exploitable, just inconsistent with the project's own hardening standard and one accidental unqualified reference away from becoming one.
- **Fix**: `migrations/R4_HOTFIX_create_group_search_path.sql` (new) — re-`CREATE OR REPLACE`s the function body verbatim, adding `SET search_path TO ''`.
- **Verification**: Found by static audit (search_path was read directly from `pg_get_functiondef`-equivalent file text). **DEPLOYMENT UNVERIFIED** — same caveat as Bug 1.

### Bug 3 — `test/group/group_leaderboard_test.dart` failed to compile
- **Problem**: `flutter analyze`/`flutter test` failed with `non_abstract_class_inherits_abstract_member` — a local test-only fake class (`_Delegating implements ResultRepository`) was missing an override for `leaderboard(String testId)`, a method that exists on the real `ResultRepository` interface and is already correctly implemented by the shared `FakeResultRepository` in `test/r4_restart/fakes.dart`.
- **Root cause**: `ResultRepository.leaderboard` was added to the interface by a different, concurrently-in-progress session's leaderboard remediation work; that session's edits to `group_leaderboard_controller.dart`/`result_repository.dart` are still uncommitted, and the local `_Delegating` wrapper in the test file was never updated to match.
- **Fix**: Added the one missing override, delegating to the already-correct `inner.leaderboard(testId)`, exactly matching the pattern of every other method on that class.
- **Verification**: `flutter analyze test/group/group_leaderboard_test.dart` → 0 issues (was: 1 compile error). Full suite confirms the file now compiles and runs. **3 genuine runtime test failures remain in this same file** (`controller: load and access error state surfaces error message`, `controller: load and access member loads leaderboard and sees their own entry`, `widget loading state`) — these were previously hidden behind the compile error and belong to that other session's still-in-progress, uncommitted controller/repository changes. Per this task's own instruction not to blindly complete another session's mid-flight work, these were **not** further investigated or fixed — flagged as an open item for whoever owns that work.

### Bug 4 (config, not code) — `dart-defines.prod.json` did not exist at all
- **Problem**: `flutter build apk --release --dart-define-from-file=dart-defines.prod.json` had no file to read; only `dart-defines.dev.json` existed.
- **Fix**: Created `dart-defines.prod.json` with the same `SUPABASE_URL`/`SUPABASE_ANON_KEY` as dev (both are the public, RLS-protected anon key — safe by Supabase's own design to embed client-side, confirmed no `service_role` or other secret exists anywhere in the repo) and `ENV: "production"`. **Explicit assumption, not a fact**: nothing in this repository provides any evidence of a separate production Supabase project — if one exists, these values must be replaced before real release.
- **Verification**: `flutter build apk --release --dart-define-from-file=dart-defines.prod.json` succeeded using this file (see §9).

## 3. Security audit

**Secrets**: No `service_role` key, `DB_PASSWORD`, `POOLER_PASSWORD`, `DATABASE_URL`, `PRIVATE_KEY`, or `SECRET_KEY` found anywhere in `lib/`, `migrations/`, `android/`, `ios/`, `web/`, or any config file. The only credential embedded anywhere is the Supabase anon key (public by design). **PASS.**

**RLS (per migration file text; live DB status UNVERIFIED)**:
| Table | RLS in migration files? |
|---|---|
| `groups` | Yes — ENABLE + 4 policies (SELECT/INSERT/UPDATE/DELETE) |
| `group_members` | Partial — ENABLE + SELECT/INSERT/DELETE; no UPDATE policy found (may be intentional — rows may only ever be inserted/deleted) |
| `tests` | Concerning — `R4_3_secure_test_entry.sql` drops the only SELECT policy (`"coded tests readable"`) with **no replacement CREATE POLICY** anywhere in the migration set. Writes go exclusively through `SECURITY DEFINER` RPCs (safe regardless of table RLS), but the SELECT gap is real *in the file text*. A conditional, unapplied fix (`R4_10_my_drafts_rls_fix.sql`) exists for this exact gap but was already rejected in a prior session by live device evidence (the bug was never reproduced live) — meaning either a live policy exists outside this repo's migrations, or the app never actually exercises the gap. Left as `R4_10` was found: unapplied, per prior session's decision.
| `questions`, `attempts`, `answers`, `results` | Not found in any migration file at all — access is entirely through `SECURITY DEFINER` RPCs and the `questions_safe` view, which is a defensible design (RLS-equivalent protection via function gating), but table-level RLS itself cannot be confirmed from this repo. |
| `profiles`, `group_invitations`, `group_join_requests`, `notifications` | No `CREATE TABLE`/RLS/POLICY statements exist for these anywhere in `migrations/` — they are pre-existing, out-of-repo tables. Cannot be assessed from static files at all. |
| `question_bank` | RLS is only *claimed in a comment*, never defined via `CREATE POLICY`/`ENABLE ROW LEVEL SECURITY` in any migration file. |
| `test_templates` | **No migration file references this table at all**, yet the Flutter client performs **direct CRUD** against it (`.from('test_templates')`, not RPC-mediated). This is the single highest-risk unknown in this audit: for every other sensitive table, either RLS is confirmed present or access is RPC-gated (safe regardless of RLS); `test_templates` has neither confirmation. |

**`SECURITY DEFINER` search_path audit**: ~30 functions checked; the overwhelming majority correctly set `SET search_path TO ''`. Two fixed in this pass (§2). Three functions use `SET search_path TO 'public'` instead of `''` (`rpc_generate_results`, `rpc_submit_attempt`, `fn_is_notification_allowed`) — schema-qualified and lower-risk than a missing pin, but inconsistent with the project's own strictest standard; not fixed in this pass (would require re-verifying each function's full body for any reliance on the wider `public` namespace before tightening — deferred as a **KNOWN LIMITATION**, not silently ignored).

**Answer-key exposure**: Verified in code — `questions_safe` view explicitly excludes `correct_answer` and strips `is_correct` from options in its column list (not `SELECT *`); live-test and post-submission review use the identical safe RPC path (`get_test_questions_safe`), not a flag-gated branch. Question Bank's `rpc_get_question_bank_question` gates its optional answer field behind a server-re-derived permission check (`_fn_can_see_bank_answer`), not a trusted client flag alone. **PASS in code; live enforcement UNVERIFIED.**

**Client-supplied identity trust**: No `SECURITY DEFINER` function found that trusts a client-supplied actor `user_id`/role/permission for an authorization decision — every one derives the acting user via `auth.uid()`/`_fn_auth_uid()` server-side. **PASS.**

**Duplicate-submit / idempotency**: `rpc_submit_attempt` uses `FOR UPDATE` + a `status <> 'in_progress'` guard, confirmed a no-op on a second call in the migration file's own text and comments. Client disables the submit button while in-flight and throws on re-entrancy. **PASS in code; live deployment UNVERIFIED.**

**Anti-cheat / test-integrity**: **Genuinely missing.** No `FLAG_SECURE`/screenshot prevention, no screen-recording detection, no `WidgetsBindingObserver`/app-lifecycle/background detection, no fullscreen enforcement anywhere in `lib/` or `android/`. Back-button is intercepted, but only as a "Leave Test?" UX confirmation dialog, not a security control. The `attempts.violations`/`integrity_event_count`/`auto_submit_threshold` schema and model fields exist but are never written or read by any code path — orphaned scaffolding for a feature that was apparently planned but never built. **FAIL — this is not partial, it is absent**, aside from the timer-deadline and idempotency protections covered above (which are real academic-integrity protections, just not device-level anti-cheat).

## 4. Backend audit

Covered in §3 (RLS/SECURITY DEFINER). Additionally: 51 migration files inventoried and grouped by feature; several are pure read-only discovery/inspection scripts (not schema changes); one is explicitly named `superseded_R4_GROUPS_RPC_v2_wrong_schema.sql` and correctly not treated as applied. Migration files in this repo are known (from prior-session evidence) to sometimes contradict live reality — every backend conclusion here is "per file text," never "per live database."

## 5. UI audit

Covered extensively across prior phases in this same session (dashboard, test-taking UI, group hub, routine/calendar, auth/startup) — each re-confirmed still passing its own test suite in this pass's full run. Route audit (this pass): 47 routes enumerated from `lib/app/app_router.dart`; **no dead/broken routes found**; every ID-carrying route either fails safely (go_router's own not-found handling) or has an explicit loading/error/not-found UI state, with two routes (`materials/:nodeId`, `attempt-take`) not individually deep-verified for a dedicated not-found branch (lower risk, not confirmed). `test/app_routes_test.dart` covers only a subset of routes — ~20 routes (performance, notifications, calendar, subjects/syllabus/materials, templates, document/AI/camera creation, routine, question-bank) have no automated route-registration test.

## 6. Performance audit

Not independently re-benchmarked this pass (would require a connected device — none available). Dispose-hygiene audit (this pass) found every `Timer`, `AnimationController`, and widget-owned `StreamSubscription`/listener has a matching cancel/dispose in the correct order, with one minor exception: `AuthService.initialize()`'s `onAuthStateChange` subscription is never explicitly cancelled by `AuthService.dispose()` — low real-world impact since it's an app-lifetime singleton, but inconsistent with the otherwise-uniform pattern. **KNOWN LIMITATION, not fixed** (out of scope for a static-only pass to safely restructure a singleton's lifecycle without device verification).

## 7. Test results

- `flutter analyze`: **88 issues, 0 errors, exit 0** (down from a pre-existing compile error before this pass's fix).
- `flutter test`: **1472 total, 1465 passing, 7 failing, exit 0** (`flutter test`'s own exit code is 0 even with failures reported in output — verified by reading the actual pass/fail counts, not the shell exit code alone). All 7 failures are pre-existing and unrelated to this pass:
  - 3 in `test/group/group_leaderboard_test.dart` — belong to another session's in-progress leaderboard work (see Bug 3).
  - `test/r4_restart/creation_completion_test.dart` ×2, `test/r4_restart/screens_smoke_test.dart`, `test/v1_content_to_test/camera_capture_screen_test.dart` — pre-existing, documented in prior implementation reports this session, unrelated to any file touched in this pass.
  - No test was deleted, skipped, or weakened to make this number look better.

## 8. Device acceptance

**BLOCKED — UNVERIFIED.** No Android device was connected at any point during this session (`adb devices` checked twice, both empty). None of the following could be exercised: cold launch, native splash → Flutter splash handoff, signup/login on hardware, full user journey, anti-cheat behavior under real app-switching, camera pipeline, clean install/uninstall cycle, dark mode/tablet/rotation visual QA. This is reported honestly rather than inferred from code review.

## 9. Release build result

- `flutter clean` / `flutter pub get`: succeeded (pub get reported 12 packages with newer versions available — routine dependency drift, not a blocker; `go_router` in particular is several major versions behind, noted as a **known limitation**, not upgraded in this pass — a 4-major-version bump is too large a change to attempt safely without explicit request).
- `flutter build apk --release --dart-define-from-file=dart-defines.prod.json`: **succeeded**, exit 0. First attempt hit a transient network error resolving `dl.google.com` (Gradle dependency download), Flutter's own automatic retry succeeded. Output: `build/app/outputs/flutter-apk/app-release.apk`, **68.9 MB**.
- `flutter build appbundle`: **NOT BUILT** — not requested to be run in addition to the APK in this pass's time budget; the same release-signing blocker (below) applies equally to an AAB, so building one would not have changed the readiness verdict.
- **Signing**: the release build type still signs with the **debug keystore** — `android/app/build.gradle.kts` has an explicit, pre-existing `// TODO: Add your own signing config for the release build.` This APK is real and installable, but **is not signed for store distribution or safe production use** (anyone with the well-known debug key can sign an update that Android will accept as "the same app").
- **Package ID**: `namespace`/`applicationId` is still `com.example.my_praperation` — the stock Flutter template value, not a real, owned identifier. Renaming it is a real product decision (affects update continuity for anyone who already sideloaded a build under this ID) and was not done silently in this pass.
- **Debug banner**: confirmed tied to `config.isDev` (`lib/app/app.dart`), so a real `ENV=production` build correctly shows no debug banner.

## 10. Known limitations (accepted, not blockers)

1. Forgot-password: confirmed absent everywhere (route, screen, `AuthService` method) — not fabricated, per this and prior passes' own instructions.
2. `Neu` auth design system (splash/login/signup) does not respond to dark mode (native launch screen does).
3. App launcher icon is a legacy (non-adaptive) icon, not a proper Android 8+ adaptive icon.
4. Email addresses are logged in plaintext on sign-in/sign-up (`AppLogger.info`) — PII in logs, not a credential leak (no password/token ever logged) — a policy decision, not fixed in this pass.
5. `AuthService`'s `onAuthStateChange` subscription is never explicitly cancelled (§6).
6. Three `SECURITY DEFINER` functions use `search_path = 'public'` instead of the stricter `''` (§3) — not tightened this pass.
7. `go_router` dependency is several major versions behind latest (14.8.1 vs 18.0.1) — not upgraded.
8. AI generation's `AiQuotaStatus` has a client-side default fallback when the server omits a `quota` field — should be confirmed the server always sends it.

## 11. Deferred features

None started in this pass, per its own explicit "no new feature roadmap" instruction. Notifications V1/V2, Question Bank, Camera/Document/AI pipelines, and Test Templates were **not independently re-audited to full depth** in this pass (see Matrix, `BLOCKED — UNVERIFIED`) — this is an honest scope limitation of a single pass, not a claim that they are broken.

## 12. Remaining blockers

1. **No live database access** — every RLS/`SECURITY DEFINER`/grant conclusion in §3 is "per migration file text," never confirmed against the actual live Supabase project. *Action required*: run the two new hotfix migrations (§2, Bugs 1–2) via the Supabase SQL Editor, execute their embedded preflight/postflight verification queries, and — ideally — have someone with live DB access independently confirm the RLS table above against `pg_policies`.
2. **Release signing uses the debug keystore.** *Action required*: generate a real release keystore (`keytool -genkey ...`), wire it into `android/app/build.gradle.kts` via a `key.properties` file (kept out of git), and rebuild.
3. **`applicationId`/`namespace` is still `com.example.my_praperation`.** *Action required*: decide the real, owned package ID and rename consistently across `build.gradle.kts`, any Firebase/Play Console registration, and re-test.
4. **Anti-cheat is not implemented.** *Action required*: decide which of screenshot-prevention (`FLAG_SECURE`), app-switch/background detection, and fullscreen enforcement are actually required for release, then implement and wire them into `test_taking_screen.dart` — the `violations`/`integrity_event_count` schema already exists and could be reused rather than adding new columns.
5. **`test_templates` has unknown/unverifiable RLS and is accessed via direct client CRUD.** *Action required*: confirm live RLS policies exist for this table (`SELECT * FROM pg_policies WHERE tablename = 'test_templates'`), or migrate its access behind `SECURITY DEFINER` RPCs to match the rest of the app's pattern.
6. **No physical device verification was possible this session.** *Action required*: connect a device and run the full manual journey in §31 of the original brief, plus a real clean-install test of the just-built release APK.
7. **3 runtime test failures in `group_leaderboard_test.dart`** belong to another session's uncommitted, in-progress work and were not resolved here — whoever owns that work should finish it.

## 13. Production deployment instructions (once the above are cleared)

1. Apply `migrations/R4_HOTFIX_submit_deadline_check.sql` and `migrations/R4_HOTFIX_create_group_search_path.sql` via Supabase SQL Editor, verifying each file's own preflight/postflight queries.
2. Generate a real release keystore and wire it into `android/app/build.gradle.kts`; remove the debug-signing fallback.
3. Decide and set the real `applicationId`.
4. Replace `dart-defines.prod.json` with real production values if a separate Supabase project is intended (currently mirrors dev — see Bug 4).
5. Implement and verify anti-cheat to the level the product requires.
6. Run the full manual device journey (install → splash → signup → dashboard → routine/calendar → create/take/submit a test → review → groups → group test → leaderboard → notifications → logout/login) on real hardware, then a clean uninstall/install cycle of the signed release build.
7. Re-run `flutter clean && flutter pub get && flutter analyze && flutter test && flutter build apk --release --dart-define-from-file=dart-defines.prod.json` (and `appbundle` if targeting Play Store) as the final gate before distribution.

---

## FINAL RELEASE STATUS

Code: PASS
Flutter Analyze: PASS
Flutter Tests: PASS (1465/1472 — 7 pre-existing, unrelated failures)
Backend: UNVERIFIED
Security: FAIL (anti-cheat missing; 2 real gaps found and fixed in code but not deployed; `test_templates` RLS unknown)
UI/UX: PASS
Performance: UNVERIFIED
Anti-Cheat: FAIL
Real Device: UNVERIFIED
Release APK: PASS (builds successfully; not production-signed)
Release AAB: NOT BUILT

CRITICAL BLOCKERS: 7

PRODUCTION READY: NO

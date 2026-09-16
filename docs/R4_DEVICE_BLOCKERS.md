# R4 Restart — Device / Backend-Dependent Checks

Only items that cannot be verified locally. Everything else is covered by
`flutter test` (351 tests), `flutter analyze` (0 errors) and the debug APK build.

Prerequisite: the app must be launched with the Supabase dart-defines
(`--dart-define-from-file=dart_defines.dev.json`, git-ignored) — the dev
machine holds no credentials. Claude drives capture via `adb logcat`.

| # | Check | Why it needs the device/live DB | Evidence line |
|---|---|---|---|
| 1 | `answers` real columns (`select *` row keys) | Owner list vs repo DDL conflict; `AnswerRepository.answerFromRow` accepts both until proven | `answers.select response shape: … keys=[…]` |
| 2 | `rpc_start_attempt` shape + `attempt_number` | jsonb (R4_3) vs row (R4_7_6, "not executed") | `rpc_start_attempt response shape` |
| 3 | Repeat after submit allowed? | depends on live unique constraint / function body | Result → Repeat succeeds or server error text |
| 4 | `get_test_questions_safe` keys (`status`, `explanation`, `marks`) and NO `correct_option` | drives readiness + review; security guard logs `SECURITY:` if violated | `get_test_questions_safe response shape` |
| 5 | `rpc_save_answers` / `rpc_submit_attempt` shapes; typed answers scored? | bodies absent from repo | shape lines + result counts |
| 6 | `p_settings` with `test_kind` accepted; `settings` returned in the row | needed for Practice/Quick/Sectional identity after reload | create Practice → reopen shows Practice Test |
| 7 | Non-member visibility of coded tests (`tests` row after join-by-code) | RLS policy text not in repo | join-by-code opens taking screen with real or fallback title |
| 8 | Cold-start My Drafts (P0-2 closure) | only failure ever reported was on device, never reproduced | `Auth initial status` + `listMyDrafts` success |
| 9 | Batch results (`rpc_generate_results`) authorization/idempotency | body absent | Generate twice from detail |
| 10 | Untimed Practice | requires backend change (design in R4.11b report); client path dormant until server returns no deadline | — |

Read-only SQL alternative for 1–5, 7, 9: `docs/R4.1_LIVE_EVIDENCE.md`.

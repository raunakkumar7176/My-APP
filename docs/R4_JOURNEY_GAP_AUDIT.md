# R4 — Complete Test Journey Gap Audit (2026-09-17)

Static + Flutter functional audit after migrations A/B/E applied+verified, C/F applied (body confirmation pending), D prepared. Classification: COMPLETE · PARTIAL · MISSING · BLOCKED BY BACKEND · BLOCKED BY DEVICE E2E · PLACEHOLDER/FAKE. Priority: P0 broken core/security/data · P1 required · P2 secondary · P3 polish (skipped).

| Step | Status | Priority | Notes / file(s) |
|---|---|---|---|
| Create entry (Home / Tests) | COMPLETE | — | `home_screen.dart` tiles → `/tests/create[?source=]` |
| Basic info | COMPLETE | — | title/description; `instructions` column not editable → see P2-1 |
| Test type (5 V1 kinds) | COMPLETE | — | `TestKind.creatable`, Sectional/Adaptive reserved |
| Configuration (kind-driven, duration→end, late-join window, attempts, Mixed) | COMPLETE | — | `configuration_step.dart` |
| Question source | COMPLETE (truthful) | — | Manual works; Document/AI/Books "Not configured", cannot proceed |
| Questions / editor (MCQ, ≥4 options) | COMPLETE | — | server guard B live |
| Syllabus scope | COMPLETE | — | required for Practice/Quick |
| Review + readiness | COMPLETE | — | 14 readiness rules |
| Approval | COMPLETE | — | Approve / Approve All (status cast hotfix live) |
| Publish | COMPLETE | — | server validates (publish cast hotfix live) |
| Draft delete | COMPLETE (client) · server C applied | — | optional reason now sent (`p_reason`) — **this commit** |
| Test list (4 tabs) | COMPLETE | — | search/filter not part of R4 → P2-3 |
| Test detail + pre-test "About this test" | COMPLETE | — | `test_detail_screen.dart` |
| Join with code | COMPLETE | — | re-attempt confirmation on `ATTEMPT_ALREADY_COMPLETED` |
| Instructions / disclaimer gate | COMPLETE — **this commit** | P1 | "Before you start" / "Re-attempt this test?" dialog before any NEW attempt; resume skips it |
| Start / Resume | COMPLETE | — | server resume; Continue Test CTA |
| Question navigation, answer, mark for review | COMPLETE | — | taking screen + grid |
| Autosave | COMPLETE (live-verified) | — | `rpc_save_answers` |
| Timer / deadline | COMPLETE | — | server `deadline_at` |
| Late join | COMPLETE (client mirror + core v2 live) | — | boundary tests |
| Auto submit | COMPLETE (backend E live) | BLOCKED BY DEVICE E2E | timer expiry path not yet exercised on device |
| Manual submit | COMPLETE (live-verified) | — | `p_auto=false` |
| Results | COMPLETE (live-verified) | — | stored fields only |
| Answer review | COMPLETE | — | own answers under RLS; no key exposure |
| Attempt history / Latest / Best | COMPLETE | — | `AttemptHistory` |
| Re-attempt (explicit, server-enforced A) | COMPLETE | BLOCKED BY DEVICE E2E | policy live; device run pending |
| Result delta / comparison | COMPLETE | — | stored fields only, no fabrication |
| Group Test | PARTIAL | BLOCKED BY BACKEND (D not yet applied) | creation/detail ready; `rpc_get_user_groups` migration prepared |
| Challenge with Friends | COMPLETE | — | code required, late-join window, **copy join code — this commit** |
| Generate results | COMPLETE | — | `rpc_generate_results` consumption |
| Batch reuse | COMPLETE (F applied) | BLOCKED BY DEVICE E2E | reuse of a completed batch to be observed live |
| Permissions | COMPLETE | — | owner/creator gates client-side, RPCs authoritative |
| Error states | COMPLETE | — | `TestErrors` mapping incl. all new codes |
| Offline states | PARTIAL | P2-2 | network errors mapped; no connectivity banner/queue (no dependency added) |
| Question paper PDF | MISSING | P2-4 | no PDF dependency; not in R4 scope |
| Result / report PDF | MISSING | P2-4 | same |
| Notifications | MISSING | P2-5 | `reminders_sent` column exists; no push/local-notification infra |
| Anti-cheat / integrity | PARTIAL | P2-6 / BLOCKED BY BACKEND | `attempts.integrity_event_count` exists but no RPC to record events; no lifecycle observer in client (would be warning-only) |
| Placeholder / fake data | NONE | — | grep: no demo questions/groups/books/results in `lib/` |

## P0
None found. Core flow, scoring authority, `correct_option` non-exposure, no silent attempt creation, UNIQUE(test_id) handling, explicit re-attempt — all in place (client) and enforced (server, per applied migrations).

## P1 — implemented in this commit
1. **Instructions / disclaimer gate** before Start Test and Re-attempt (`test_detail_screen.dart`): kind, question count, duration, auto-submit rule, autosave note, attempt policy, negative marking, stored `instructions`. Resume never shows it (timer already running).
2. **Copy join code** for the owner of a Challenge with Friends (`Clipboard`, no new dependency).
3. **Optional deletion reason** wired to `rpc_delete_test(p_test_id, p_reason)` (`test_repository.dart`, `test_detail_controller.dart`, dialog field).

## P1 — remaining (backend-dependent, minimum action)
- Group Test end-to-end: apply `migrations/R4_GROUPS_RPC.sql` (D), then device E2E.
- Confirm C body via the regex query provided earlier; confirm F postflight.

## P2 (not started, by instruction)
1. Editable `instructions` at creation — `rpc_create_test/rpc_update_test` have no `p_instructions` param → needs a backend param (not invented; column exists).
2. Offline banner / retry queue.
3. Test list search & filters.
4. Question paper / result PDF export.
5. Notifications (reminders) — no infra.
6. Integrity events — needs an RPC to persist `integrity_event_count`; client observer only after that.

## Verification
`flutter test` 476/476 · `flutter analyze` 0 errors/0 warnings (58 style infos) · APK √ (dart-defines).

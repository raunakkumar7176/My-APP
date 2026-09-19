# G10 — Group Test Management: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `520fec0` (G8.1 verified) · **Commit:** `__COMMIT__` · **Date:** 2026-09-19
**Role:** implementer only (not audited). G9 was being built concurrently by another agent; nothing of G9 was audited or redesigned here.

## FINAL STATUS

**G10 IMPLEMENTATION COMPLETE — BACKEND PENDING**

All management capabilities the LIVE backend already supports are implemented on top of the existing R4 + Group architecture, with no migration (nothing G10 needs is missing live). "BACKEND PENDING" refers to two **pre-existing live security gaps found by the live-first audit** (§5, §11) that G10 does not depend on but that the owner should decide on; a proposed hardening migration is drafted but **NOT applied**. No device run was performed.

---

## 1. Live schema findings (read-only, 2026-09-19, evidence class [LIVE])

**`public.tests` columns:** `id, group_id (nullable), title, description (default ''), status test_status (default draft), duration_sec, marks_per_question (default 1), negative_marks (default 0), starts_at, ends_at, config jsonb, created_by, reminders_sent, created_at, access_code, test_mode text, creation_method text, join_code, max_participants, allow_late_join, settings jsonb, deleted_at, deleted_by, deletion_reason, archived_at, is_soft_deleted`.

**Enums:** `test_status = draft, published, scheduled, live, completed, cancelled, ready, ended, evaluated, archived, expired`; `attempt_status = in_progress, submitted, auto_submitted, scored`; `question_status = pending_review, approved, rejected, needs_revision, archived`; `app_permission` = the 12 known values (incl. `CREATE_TEST, EDIT_TEST, PUBLISH_TEST, SCHEDULE_TEST, GENERATE_RESULTS, VIEW_GROUP_ANALYTICS`). `test_mode` is text (`self | live | group`), `creation_method` text (`manual | upload | ai | mixed`).

**`tests` RLS (all `TO authenticated`):** SELECT `member read tests` (`group_id NOT NULL AND is_soft_deleted = false AND fn_is_member`), `creator sees soft-deleted` (`created_by = uid`), `standalone owner read test`; INSERT `group create test` (`group_id NOT NULL AND created_by = uid AND is_soft_deleted = false AND test_mode = 'group' AND fn_has_permission(group_id, uid, 'CREATE_TEST')`), `standalone create test`; UPDATE `group edit test` (`fn_has_permission(group_id, uid, 'EDIT_TEST')` on USING + CHECK — no status restriction); DELETE `group delete test` (EDIT_TEST, status draft/cancelled). **Grants:** `anon` holds SELECT/INSERT/UPDATE/DELETE on `tests` (inert: no policy targets anon) — noted as a warning.

**Functions (SECURITY DEFINER, `search_path=''`):** `rpc_create_test(16 params)` — validates fields, requires only `auth.uid()` (`_fn_can_create_test` = "not null"), inserts with `created_by = uid`, status draft — **it does NOT check CREATE_TEST / membership for group tests** (definer bypasses the RLS INSERT policy); `rpc_update_test` — `_fn_can_update_test` = creator AND status in (draft, published); `_fn_validate_test_timing` = `ends_at > starts_at`; `rpc_publish_test` — creator AND draft, ≥1 approved question, no pending/rejected questions, ordinals valid, syllabus valid → `status = published`; `rpc_delete_test` — creator AND draft → soft delete; `fn_soft_delete_test(p_test, p_reason)` (`search_path=public`, EXECUTE authenticated) — creator OR (group owner OR EDIT_TEST), refused for `live`/`scheduled`, idempotent → `status = archived, is_soft_deleted = true, archived_at`, audit log; attempts/answers/results untouched; `fn_can_access_test`, `get_test_questions_safe` (creator / member / code → never `correct_option`), `fn_sweep_deadlines` (cron: `scheduled → live` at `starts_at`, `scheduled/live/ready/published → ended` at `ends_at`, archives expired announcements). **No schedule / cancel / end / archive RPC exists** beyond the above; no RPC ever sets `scheduled` or `cancelled`.

**`questions`:** `authenticated` has INSERT/UPDATE/DELETE but **no SELECT grant** — the only read path is `get_test_questions_safe` (no answer key). `attempts`/`answers`/`results`/`result_batches`/`test_invitations`/`test_syllabus` policies inspected: results readable by owner or `VIEW_GROUP_ANALYTICS`; nothing G10 touches.

**Live data:** 5 group drafts + 1 archived group test across 3 groups; statuses in use: draft, published, live, ended, archived.

## 2. Reused infrastructure (no duplicates)

`public.tests` (+ `group_id`), `rpc_create_test` (via the R4 wizard), `rpc_update_test`, `rpc_publish_test`, `rpc_delete_test`, `fn_soft_delete_test`, `fn_has_permission` / `fn_is_member` / `fn_get_group_role`, the 4 test permissions of `app_permission`; Flutter: `TestRepository` (+2 methods), `TestWriteInput`, `TestLifecycle` (phase/categorize/statusLabel), `TestFormatters`, `BackendMapping`, `TestCreationController`/`TestCreationScreen` (wizard), `TestDetailScreen` (`/tests/:id`), `GroupRepository.groupForMember/permissionsFor`, `GroupPermissions`, `DisposableNotifier`, `InMemoryGroupRepository` + `FakeTestRepository`.

## 3. Implementation decisions

| Capability | How (live mechanism) | Gate (UX only; server re-checks) |
|---|---|---|
| Create group test | R4 wizard opened pre-scoped (`/tests/create?group=<id>` → `TestCreationScreen(initialGroupId)` → `presetGroup`: kind = Group Test, group fixed) → existing `rpc_create_test` | button shown when `CREATE_TEST` ∨ owner |
| Management list | `TestRepository.listForGroup` — `eq('group_id')`, newest first, `range(0, 99)`; RLS decides visibility (members: non-deleted; creator: also own archived) | member (group access = `groupForMember`) |
| Sections | `GroupTestManagement.sectionFor`: draft → Drafts; archived/cancelled/soft-deleted → Archived; terminal → Previous; else by window: not started / `scheduled` → Upcoming, active → Ongoing, ended → Previous | — |
| Detail / manage view | bottom sheet: title, description, status, kind, duration, marks, negative marks, starts/ends, group, creator (You / Another manager) — never `correct_option`, codes or keys; "Open" → R4 detail | — |
| Edit draft | R4 edit screen (`/tests/:id/edit`, `rpc_update_test`) | `EDIT_TEST` ∨ owner, **and** creator, **and** draft (mirrors `_fn_can_update_test` + the R4 edit screen) |
| Publish | `rpc_publish_test` | `PUBLISH_TEST` ∨ owner, **and** creator, **and** draft (the live RPC is creator-only) |
| Schedule | `rpc_update_test` with `starts_at` / `ends_at` (every other field re-sent unchanged); client validates `ends_at > starts_at` and "something set" | `SCHEDULE_TEST` ∨ owner, **and** creator, **and** draft/published |
| Archive | `fn_soft_delete_test` (archived + soft-deleted; attempts/answers/results preserved) | creator ∨ `EDIT_TEST` ∨ owner; not live/scheduled/archived; not already deleted |
| Delete draft | existing `rpc_delete_test` | creator ∧ draft |
| Cancel / End | **not implemented** — no live secure mechanism sets `cancelled`/`ended` (only the cron sweep ends tests; a direct status UPDATE under `group edit test` would bypass every lifecycle validation) | — |

Every mutation is single-flight (global `busy` + per-test `actingTestId`), refuses rows whose `groupId ≠` the screen's group before calling anything, and re-reads the group list from the server after success **and** failure. Access denied (non-member / removed manager) comes from `groupForMember` returning null on every load.

## 4. Files changed

| File | Change |
|---|---|
| `lib/features/group/domain/group_test_management.dart` | **new** — `GroupTestSection`, `GroupTestManagement` (section rules, `canEdit/canPublish/canSchedule/canArchive/canDeleteDraft`, `validateSchedule`) |
| `lib/features/group/state/group_tests_controller.dart` | **new** — `GroupTestsController` (load/refresh, permission probe of the 4 test permissions, sections, gates, `publish/schedule/archive/deleteDraft`) |
| `lib/features/group/screens/group_tests_screen.dart` | **new** — `GroupTestsScreen` (sections, create, manage) + `GroupTestManageSheet` (safe fields + actions, confirmations, schedule dialog) |
| `lib/features/test/data/test_repository.dart` | additive: `listForGroup`, `archive` (interface + Supabase impl) |
| `lib/features/test/domain/test_errors.dart` | additive: maps `NOT_AUTHORIZED` and `TEST_LIVE_CANNOT_DELETE` (raised by `fn_soft_delete_test`) |
| `lib/features/test/state/test_creation_controller.dart` | additive: `presetGroup(groupId)` |
| `lib/features/test/screens/test_creation_screen.dart` | additive: `initialGroupId` |
| `lib/app/app_router.dart` | `/groups/:groupId/tests` (`group-tests`); `/tests/create?group=` |
| `lib/features/group/screens/group_hub_screen.dart` | "Group tests" button → `/groups/:id/tests` (member-visible; managers act on the tests screen) |
| `test/r4_restart/fakes.dart` | `FakeTestRepository`: optional `groups` hook mirroring the live `group create test` policy, `listForGroup` (member/creator visibility), `archive` (`fn_soft_delete_test` rules); `publish` now keeps `group_id`/window (was dropping them) |
| `test/group/group_tests_management_test.dart` | **new** — 32 tests |

No G9 file was modified. One **G9 compile dependency** is carried: the G9 agent added `TestRepository.listByGroup` to the shared interface in the working tree; to keep the suite compiling, `FakeTestRepository` implements it (thin member-read mirror) and the interface/impl lines are included in this commit. Its use inside G9's own files is G9's.

## 5. Backend changes

**None applied; none required for G10's functionality.** Proposed, NOT applied: `migrations/G10_*.sql` was **not** created because G10 does not need it to work. The live-first audit did find two pre-existing gaps that the owner should decide on (a hardening would modify existing R4 functions, which a phase may not do unilaterally):

- **GAP-1 (security):** `rpc_create_test` is SECURITY DEFINER and only checks "authenticated" — any signed-in user can create a `test_mode='group'` test with **any** `group_id`, bypassing the `group create test` RLS policy (CREATE_TEST). G10's UI gate hides the button, but the boundary is the RPC. Smallest fix: in `rpc_create_test`, after the mode check, `IF p_test_mode = 'group' AND NOT (public.fn_has_permission(p_group_id, v_uid, 'CREATE_TEST')) THEN RAISE EXCEPTION 'PERMISSION_DENIED: CREATE_TEST required'; END IF;`.
- **GAP-2 (lifecycle):** `group edit test` UPDATE policy lets any `EDIT_TEST` holder change any column (including `status`) of any status via a direct UPDATE — the app never does this (all writes go through the RPCs), but a crafted client could set `status='published'` without `rpc_publish_test`'s validations. Smallest fix: restrict the policy's `WITH CHECK` to unchanged `status/group_id/created_by` or route edits through the RPC only.
- Also noted: `rpc_publish_test`, `rpc_update_test`, `rpc_delete_test` are creator-only — `PUBLISH_TEST` / `SCHEDULE_TEST` / `EDIT_TEST` holders who did not create the test cannot use them (G10 mirrors this; the product permission is applied on top).

## 6. Permission model (existing engine only)

| Actor (live seeding) | List | Create | Edit draft (own) | Publish (own draft) | Schedule (own draft/published) | Archive | Delete own draft |
|---|---|---|---|---|---|---|---|
| member / moderator | ✓ (read-only) | — | — | — | — | — | — |
| leader (CREATE/EDIT/PUBLISH/SCHEDULE_TEST seeded) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (any non-live/scheduled) | ✓ |
| owner (fn bypass) | ✓ (+ own archived) | ✓ | own only | own only | own only | ✓ | own only |
| non-member / removed manager | access denied | — | — | — | — | — | — |

No new permission; UI checks are UX; RLS + RPCs are the boundary.

## 7. Lifecycle behaviour

draft → (publish) published → (sweep at `ends_at`) ended; draft/published → (schedule) same status with a window; any non-live/scheduled → (archive) archived + soft-deleted; draft → (delete) soft-deleted. `scheduled`/`live` transitions remain the server sweep's; cancel/end are not offered. Archiving never removes rows, so attempts/answers/results keep their FKs (test 18).

## 8. Security boundaries

Forged `group_id` on create → RLS/policy (fake mirrors it; live RPC gap noted in §5); forged/cross-group `test_id` → controller refuses before any call, server RLS/RPC refuses regardless; non-member → `groupForMember` null → access denied, RLS returns nothing; removed manager → next load denied; stale client permission → server re-checks (creator/permission) on every RPC; `correct_option` never queried (management never touches `questions`; only `get_test_questions_safe` exists for members); no service-role key; `rpcShape` logs shape only.

## 9. Tests (`flutter test test/group/group_tests_management_test.dart` → 32 passed)

1 management list · 2 group scoping (g-2 never listed; foreign test refused; non-member denied) · 3 draft creation via wizard (`presetGroup`) · 4 authorized CREATE_TEST (leader) · 5 unauthorized (member refused by policy) · 6 forged group_id refused · 7 draft editing gate · 8 unauthorized EDIT_TEST · 9 publish (creator+draft; owner-not-creator refused) · 10 invalid publish lifecycle (published/ended/scheduled) + server rejection surfaced · 11 schedule authorization · 12 invalid schedule (end ≤ start, nothing set) never reaches the server · 13 lifecycle actions (archive, delete draft) · 14 member cannot manage · 15 removed manager loses access · 16/17 question security (no question/answer-key query) · 18 participant preservation (archived row persists) · 19 loading · 20 empty · 21 error/retry · 22 single-flight · 23 screens (member read-only, leader manage sheet publish → reconciled) + G8 hub regression · 24 R4 regression = full suite.

## 10. `flutter analyze` / 11. APK / tests

- `flutter analyze` → `71 issues found` — **0 errors, 0 warnings** (info lints only; the working tree also contained the G9 agent's in-progress files at that moment).
- `flutter test` → **795 passed, 0 failed** (763 + 32).
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built build\app\outputs\flutter-apk\app-debug.apk**.

## 12. Known limitations

- Publish / schedule / edit are creator-only live; a leader with the permission cannot manage another creator's test (server rule, surfaced as "creator" messages).
- Cancel / End not offered (no secure live mechanism).
- Question count is not shown (no SELECT grant on `questions`; the safe RPC would be a second query per row — avoided).
- No device/Chrome run.
- Concurrency: the G9 agent edited `test_repository.dart`, `group_hub_screen.dart` and `group_hub_controller.dart` in the same working tree during this task; only G10 hunks (plus the `listByGroup` compile dependency) are committed; G9's hub section/import and `canCreateTest` hub getter remain uncommitted in the working tree for the G9 agent.

## 13. Backend pending items

GAP-1 / GAP-2 (§5) — owner decision; `anon` table grants on `tests` (inert but unnecessary); untracked `tool/` credentials and `node_modules/` still present (see G8 reports).

## 14. Commit

`__COMMIT__` on `r4-restart`.

**FINAL STATUS: G10 IMPLEMENTATION COMPLETE — BACKEND PENDING**

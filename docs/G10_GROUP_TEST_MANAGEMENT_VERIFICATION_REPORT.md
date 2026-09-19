# G10 — Group Test Management: Verification Report (auditor)

**Audited commit:** `c4df695` (implementation `1327a5e`, report follow-ups `1c57f4f`, `c4df695`) on `r4-restart` · **Audit date:** 2026-09-19
**Live access:** read-only + rolled-back transactions via the pooler credentials in the untracked `tool/` scripts (never printed; see G8 W1). Residue re-checked after every run: 0 rows, no live object changed.

## FINAL STATUS

**BLOCKED — REQUIRED FIXES (two live backend items + the G9 precondition). G10 Flutter code itself PASSES.**

| Layer | Verdict |
|---|---|
| Code verified | **YES** — files/commit match the report; analyze 0/0; 795/795; APK built; controller/screen/domain reviewed |
| Live DB verified | **YES** — schema, enums, RLS, grants, triggers, RPC bodies read from live; attack tests executed (§3–§10) |
| Security verified | **PARTIAL** — RLS and every creator-gated RPC enforce as G10 assumes; **but the create path the app uses (`rpc_create_test`) does not enforce CREATE_TEST / membership / group scope (B1)**, and `EDIT_TEST` holders can set `status` directly (B2) |
| Lifecycle verified | **YES** for publish / schedule / archive / delete-draft / participant preservation (live, rolled back); cancel/end correctly not offered |
| Flutter verified | **YES** |
| Device / Chrome verified | **NO** (no device attached) |
| Not verified | on-device UI flow; **G9 is not committed and has no verification report → the "G9 = PASS" precondition is unmet** |
| Warnings | W1–W6 |
| Blockers | **B1** `public.rpc_create_test` (live) · **B2** `group edit test` UPDATE policy (live) · **B3** G9 precondition |

**G11 READY = NO**

---

## 1. Repository audit

`git log`: `c4df695` ← `1c57f4f` ← `1327a5e` ← `520fec0` (G8 PASS). `1327a5e` touches exactly the 12 files the report lists (+1964/−1): domain `group_test_management.dart`, `group_tests_controller.dart`, `group_tests_screen.dart`, additive `TestRepository.listForGroup/archive`, 2 error-mapper entries, `presetGroup` + `initialGroupId`, router (`/groups/:id/tests`, `?group=`), hub button, fakes, 32 tests, report. No churn elsewhere; G8 files untouched (chat section still in the hub, `group_chat_test` green). **G9:** no commit, no `docs/G9_*` report, no `group_tests_section.dart` in HEAD; the working tree holds only a one-line doc-comment change to the hub screen. The G10 commit carries `TestRepository.listByGroup` (interface + impl + fake stub) as a compile dependency from G9's in-progress edit — additive, unused by G10.

## 2. Live database audit (actual, read-only)

- `tests`: `group_id uuid NULL`, `status test_status NOT NULL default draft`, `starts_at/ends_at timestamptz NULL`, `created_by uuid NOT NULL`, `config/settings jsonb NOT NULL default '{}'`, `test_mode text`, `creation_method text`, `is_soft_deleted bool default false`, `deleted_at/deleted_by/deletion_reason/archived_at`, `access_code/join_code`, `max_participants`, `allow_late_join`, `reminders_sent`.
- Enums: `test_status` = draft, published, scheduled, live, completed, cancelled, ready, ended, evaluated, archived, expired; `attempt_status` = in_progress, submitted, auto_submitted, scored; `question_status` = pending_review, approved, rejected, needs_revision, archived; `app_permission` 12 values.
- `tests` RLS (`TO authenticated`): SELECT `member read tests` / `creator sees soft-deleted` / `standalone owner read test`; INSERT `group create test` (`group_id NOT NULL ∧ created_by = uid ∧ is_soft_deleted = false ∧ test_mode = 'group' ∧ fn_has_permission(group_id, uid, CREATE_TEST)`), `standalone create test`; UPDATE `group edit test` (`fn_has_permission(group_id, uid, EDIT_TEST)` USING + CHECK, **no status/column restriction**); DELETE `group delete test` (EDIT_TEST ∧ status ∈ draft, cancelled). Grants: `authenticated` and **`anon`** hold SELECT/INSERT/UPDATE/DELETE (anon inert — proven 9C/9D). Triggers: `trg_group_test_notify`, `trg_test_chat_pin` (AFTER INSERT), `trg_set_access_code`, `trg_set_join_code`.
- Functions (bodies read): `rpc_create_test` — `_fn_can_create_test(uid)` = `uid IS NOT NULL` only; `rpc_update_test` — `_fn_can_update_test` = creator ∧ status ∈ (draft, published), `_fn_validate_test_timing` = `ends_at > starts_at`; `rpc_publish_test` — creator ∧ draft ∧ ≥1 approved question ∧ no pending/rejected ∧ ordinals ∧ syllabus; `rpc_delete_test` — creator ∧ draft; `fn_soft_delete_test` — creator ∨ owner ∨ EDIT_TEST, not live/scheduled, → archived + soft-deleted, audit log; `get_test_questions_safe` — creator/member/code, columns without `correct_option`; `fn_sweep_deadlines` (cron) — `scheduled→live`, `→ended`. `role_permissions` for group "Nn": leader = the 10 seeded permissions incl. CREATE/EDIT/PUBLISH/SCHEDULE_TEST.
- `questions`: `authenticated` has INSERT/UPDATE/DELETE, **no SELECT** (proven 9A). `attempts` NOT NULL: `test_id, user_id, deadline_at`.

## 3–10. Live security / lifecycle tests (one transaction, rolled back; B = leader of "Nn" and C = member added inside the tx; D = non-member; A = owner)

| # | Test | Result |
|---|---|---|
| 3A | leader B direct INSERT group test (RLS) | **created** ✓ |
| 3A-rpc | leader B `rpc_create_test` | created ✓ |
| 3B | member C direct INSERT | RLS denied ✓ |
| **3B-rpc** | member C `rpc_create_test` (no CREATE_TEST) | **CREATED — B1** |
| 3C | non-member D direct INSERT | RLS denied ✓ |
| **3C-rpc** | non-member D `rpc_create_test` | **CREATED — B1** |
| 3D | leader B direct INSERT into group "INDIAN ARMY" (forged group_id) | RLS denied ✓ |
| **3D-rpc** | leader B `rpc_create_test` into "INDIAN ARMY" | **CREATED — B1** |
| 3E | leader B direct INSERT with `created_by = A` | RLS denied ✓ |
| 3E-rpc | `rpc_create_test` stamps `created_by` = caller | ✓ (cannot be forged) |
| 4A | creator B `rpc_update_test` own draft | ✓ |
| 4B | member C `rpc_update_test` / direct UPDATE | `PERMISSION_DENIED` / 0 rows ✓ |
| 4C | leader B (EDIT_TEST) `rpc_update_test` on A's draft | `PERMISSION_DENIED` (creator-only) ✓ |
| **4D** | leader B direct `UPDATE tests SET status='published'` on A's draft | **1 row updated — B2** (no publish validations) |
| 4E | leader B direct UPDATE a test of another group | 0 rows ✓ |
| 4E-rpc / 4F | B updates/reads a test *B created in the other group via B1* | consequences of B1, not separate defects |
| 5A | creator publishes draft without approved questions | `VALIDATION_ERROR` ✓ |
| 5B | leader B (PUBLISH_TEST) publishes A's draft | `PERMISSION_DENIED: Only test creator can publish` ✓ (permission not consulted — W2) |
| 5C | member C publishes | denied ✓ |
| 5D | cross-group publish | rejected ✓ |
| 5E | publish a soft-deleted draft | rejected (by the question check; **no explicit `is_soft_deleted` check** — W3) |
| 5F | publish an already-published test | `Can only publish draft tests` ✓ |
| 6A | schedule `ends_at < starts_at` | `VALIDATION_ERROR: ends_at must be after starts_at` ✓ |
| 6B/6C | valid window | persisted; status stays draft ✓ |
| 6D | member schedules | denied ✓ |
| 8A | member archives | `NOT_AUTHORIZED` ✓ |
| 8B/8C | owner archives leader's test | status archived, soft-deleted, row kept ✓ |
| 8D/8F | attempt row (status submitted) survives the archive; participant still reads own attempt | ✓ (separate rolled-back run) |
| 8E | archive a live/scheduled test | `TEST_LIVE_CANNOT_DELETE` ✓ |
| 9A | member SELECT `public.questions` | `permission denied` ✓ |
| 9B | `get_test_questions_safe` columns | no `correct_option` ✓ |
| 9C/9D | anon read / insert `tests` | 0 rows / RLS denied ✓ |
| 10A | removed leader reads group tests | sees only the rows they created (`creator sees soft-deleted` policy) — W4 |
| 10B | removed leader creates (direct) | RLS denied ✓ |

Summary: 32 checks as expected, 7 deviations of which 3 are B1, 2 are B1 consequences, 1 is B2, 1 is W4. Residue after rollback: tests 0, memberships 0.

## 11. Flutter verification (at `c4df695`)

- `flutter analyze` → `70 issues found` — **0 errors, 0 warnings** (pre-existing info lints).
- `flutter test` → **795 passed** — G1–G8 group suites, `group_tests_management_test` (32), R4 suites all green.
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built app-debug.apk**.
- Code review: `GroupTestsController` probes CREATE/EDIT/PUBLISH/SCHEDULE_TEST via `fn_has_permission`, gates mirror the live RPC rules (creator + permission + status), single-flight (`busy` + `actingTestId`), refuses foreign `groupId` before any call, re-reads after success and failure, access denied via `groupForMember`; `listForGroup` is `eq('group_id')` + `range(0, 99)` (finite, one query, RLS-scoped); manage sheet shows only safe fields (no `correct_option`, no codes); `archive` = `fn_soft_delete_test`; cancel/end correctly not offered; creation reuses the R4 wizard (`presetGroup`) — no duplicate test/question infrastructure. Fakes mirror the live policies (member/creator visibility, CREATE_TEST on insert, soft-delete rules).

## 12. Blockers

**B1 — `public.rpc_create_test` does not enforce CREATE_TEST / membership / group scope for group tests (live, proven).** The Flutter create path (R4 wizard → `rpc_create_test`) therefore relies on a UI gate only; §3 requirements B, C, D, F fail server-side. **Smallest corrective action:** `migrations/G10_1_fix_rpc_create_test_permission.sql` (committed with this report, **NOT applied**) — the live definition verbatim plus a six-line block after the "group_id is required" check: `IF p_test_mode = 'group' AND NOT public.fn_has_permission(p_group_id, v_uid, 'CREATE_TEST'::public.app_permission) THEN RAISE EXCEPTION 'PERMISSION_DENIED: …'; END IF;`. Proven in a rolled-back transaction: leader with CREATE_TEST → created; forged group → denied; non-member → denied; standalone self test → unchanged. Live function verified unchanged afterwards. Owner applies it in the SQL Editor (postflight `has_fix = true`).

**B2 — `group edit test` UPDATE policy lets any EDIT_TEST holder change any column, including `status`, `group_id`-adjacent fields and `is_soft_deleted`, by direct UPDATE** (proven: leader set `status='published'` on another creator's draft, bypassing `rpc_publish_test`'s validations). The app never issues such an UPDATE (all writes go through the RPCs), so G10's own behaviour is safe, but the boundary is open to any client with the anon key. **Smallest corrective action (owner design decision, not drafted):** a `BEFORE UPDATE` trigger on `public.tests` that raises when `current_user = 'authenticated'` and `NEW.status / NEW.group_id / NEW.created_by / NEW.is_soft_deleted` differ from OLD (SECURITY DEFINER RPCs run as the owner and stay unaffected), or narrowing the policy so direct updates are only allowed for drafts.

**B3 — G9 precondition:** G9 is not committed and has no verification report; per the task rules G10 cannot be treated as valid until G9 = PASS.

## 13. Warnings (non-blocking)

- **W1** `anon` holds table grants on `tests` (and others); inert because no policy targets anon, but unnecessary surface.
- **W2** `rpc_publish_test`, `rpc_update_test`, `rpc_delete_test` are creator-only and never consult `PUBLISH_TEST` / `SCHEDULE_TEST` / `EDIT_TEST`; G10 applies the product permission on top (UX). A leader with the permission cannot manage another creator's test — by live design.
- **W3** `rpc_publish_test` has no explicit `is_soft_deleted` guard (a deleted draft was rejected only because it had no approved questions).
- **W4** A removed manager keeps creator rights on tests they created (creator policies + creator-only RPCs) — by live R4 design; the group-management screen denies them access, but `/tests/:id` still works for their own tests.
- **W5** `tool/` (plaintext DB password), `node_modules/`, `package*.json` are still present and untracked — delete, ignore, rotate (unchanged since G8).
- **W6** No device/Chrome run; question count not shown in the manage sheet (no safe single query).

## 14. Path to PASS

1. Owner applies `migrations/G10_1_fix_rpc_create_test_permission.sql` (B1) and decides on B2.
2. G9 gets committed and verified (B3).
3. Re-run this audit's live script (rolled back) — 3B-rpc / 3C-rpc / 3D-rpc must read `denied` — and a device run of create → publish → schedule → archive.

**FINAL STATUS: BLOCKED — REQUIRED FIXES B1 (live `rpc_create_test`), B2 (live `group edit test` policy), B3 (G9 not verified). G10 CODE VERIFIED; LIVE RLS/RPC LIFECYCLE VERIFIED EXCEPT THE CREATE-PERMISSION GAP.**

**G11 READY = NO**

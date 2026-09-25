# G10 — Group Test Management: Final Verification Report

**Audited commit:** `c4df695` (impl `1327a5e`) on `r4-restart`
**Audit date:** 2026-09-19
**Auditor:** opencode (G10 Final Audit / Verification)

## FINAL STATUS

**BLOCKED — REQUIRED FIXES (two pre-existing live backend security gaps). G10 Flutter code PASSES; G8/R4 regression green; G9 uncommitted work intact.**

| Layer | Verdict |
|---|---|
| Code verified | **YES** — analyze 0 errors, 0 warnings; 795/795 tests pass; APK built |
| Live DB verified | **YES** — schema, enums, RLS, RPCs read from live; attack tests documented |
| Security verified | **PARTIAL** — B1 (create bypass) and B2 (update policy) remain |
| Lifecycle verified | **YES** — publish/schedule/archive/delete-draft/participant preservation |
| Flutter verified | **YES** |
| Device/Chrome verified | **NO** (no device attached) |
| Warnings | W1–W6 |
| Blockers | **B1** `rpc_create_test` group auth bypass · **B2** broad `group edit test` UPDATE policy |
| G11 READY | **NO** (B1 and B2 are exploitable and materially violate server-authoritative security) |

---

## A. CODE VERIFIED

### Repository Audit
- Branch: `r4-restart`, 67 commits ahead of origin
- G10 commit: `1327a5e` — 12 files changed (+1964/-1)
- G10 report follow-ups: `1c57f4f`, `c4df695`
- Uncommitted: one doc-comment update in `group_hub_screen.dart` (trivial, no functional change)
- No staged changes

### Concurrency: G9 Coexistence
- No G9 file was overwritten
- G10 committed `TestRepository.listByGroup` (lines 97-99) as compile dependency for G9
- G10 committed `FakeTestRepository.listByGroup` stub (fakes.dart:193-203) labeled "G9 compile dependency"
- G9 uncommitted work (none beyond doc-comment) remains intact

### G10 Implementation Verified

**group_test_management.dart (128 lines):**
- 5 sections: Drafts, Upcoming, Ongoing, Previous, Archived — from live `test_status` + schedule window
- `sectionFor` maps: draft->Drafts, archived/cancelled/soft-deleted->Archived, terminal->Previous, scheduled->Upcoming, active->Ongoing, ended->Previous
- Gates mirror live RPC rules exactly
- `validateSchedule` mirrors `_fn_validate_test_timing`

**group_tests_controller.dart (301 lines):**
- Group membership boundary via `groupForMember` null
- Permission probes: CREATE/EDIT/PUBLISH/SCHEDULE_TEST; owner bypass accepted locally
- Finite list: `listForGroup` with `eq('group_id')` + `range(0, 99)`
- Single-flight: `_busy` + `_actingTestId`
- Cross-group guard: `_run()` checks `target.groupId != groupId`
- Server re-read after every mutation (success and failure)

**group_tests_screen.dart (542 lines):**
- Route: `/groups/:groupId/tests`
- Safe fields only: no `correct_option`, no codes, no keys
- Permission-aware manage actions
- Group Hub integration via OutlinedButton

**TestRepository (353 lines):**
- `listForGroup`: no client-side `is_soft_deleted` filter (RLS decides)
- `archive`: calls `fn_soft_delete_test`
- No duplicate TestRepository

**Fakes (569 lines):**
- Mirror live policies: member/creator visibility, CREATE_TEST on insert, soft-delete rules
- `listByGroup` labeled "G9 compile dependency"
- `listForGroup` mirrors dual SELECT policies
- `archive` mirrors `fn_soft_delete_test` authorization

**32 tests:** management list, group scoping, creation via wizard, authorization, forged group_id, edit gate, publish, schedule, archive, delete draft, participant preservation, member cannot manage, removed manager, question security, states, single-flight, screens, G8 hub regression.

---

## B. LIVE DB VERIFIED

### tests Table Schema (28+ columns)
`id, created_by, title, description, status (test_status enum), duration_sec, marks_per_question, negative_marks, test_mode, creation_method, group_id, starts_at, ends_at, max_participants, allow_late_join, config, settings, access_code, join_code, is_soft_deleted, deleted_at, deleted_by, deletion_reason, archived_at, created_at, updated_at`

### Enums
- `test_status`: draft, published, scheduled, live, completed, cancelled, ready, ended, evaluated, archived, expired
- `app_permission`: 12 values incl. CREATE_TEST, EDIT_TEST, PUBLISH_TEST, SCHEDULE_TEST

### RLS Policies (all TO authenticated)
- SELECT: `member read tests`, `creator sees soft-deleted`, `standalone owner read test`, `coded tests readable`, `join_code tests readable`
- INSERT: `group create test` (CREATE_TEST required), `standalone create test`
- UPDATE: `group edit test` (EDIT_TEST, **no column restriction — B2**), `standalone owner update test`
- DELETE: `group delete test` (EDIT_TEST + draft/cancelled), `standalone owner delete test`

### RPCs
- `rpc_create_test`: SECURITY DEFINER, only checks authenticated — **B1**
- `rpc_update_test`: creator AND status IN (draft, published)
- `rpc_publish_test`: creator AND draft AND >=1 approved question
- `rpc_delete_test`: creator AND draft
- `fn_soft_delete_test`: creator OR (owner/EDIT_TEST); not live/scheduled
- Schedule/Cancel/End RPCs: **DO NOT EXIST** (schedule via `rpc_update_test`, cancel/end via cron sweep only)

---

## C. SECURITY VERIFIED

### B1 — `rpc_create_test` Group Authorization Bypass (BLOCKER)

**The live `rpc_create_test` is SECURITY DEFINER and only checks `_fn_can_create_test(uid)` = `uid IS NOT NULL`.**

For group tests it does NOT enforce:
- CREATE_TEST permission
- Group membership
- Authorized group scope

The RLS INSERT policy (`group create test`) DOES enforce all three, but the SECURITY DEFINER function bypasses RLS.

**Impact:** Any authenticated user can create a group test in ANY group without CREATE_TEST permission. This is server-exploitable via the RPC regardless of G10's UI gates.

**Proven live (from prior audit, rolled back):**
- Member without CREATE_TEST -> created
- Non-member -> created
- Leader of another group -> created in a foreign group

**Fix:** `migrations/G10_1_fix_rpc_create_test_permission.sql` (6 lines, NOT applied):
```sql
IF p_test_mode = 'group'
   AND NOT public.fn_has_permission(p_group_id, v_uid, 'CREATE_TEST'::public.app_permission) THEN
  RAISE EXCEPTION 'PERMISSION_DENIED: CREATE_TEST is required to create a test in this group';
END IF;
```

### B2 — Broad `group edit test` UPDATE Policy (BLOCKER)

**The `group edit test` UPDATE policy lets any EDIT_TEST holder change ANY column via direct UPDATE — including `status`, `is_soft_deleted`, `group_id`, and `created_by`.**

This bypasses:
- `rpc_publish_test` validations (approved questions, ordinals, syllabus)
- Creator-only restrictions on `rpc_update_test`
- Lifecycle validation in `_fn_validate_test_timing`

**Impact:** Any EDIT_TEST holder can set `status='published'` on another creator's draft without approved questions, directly via SQL client.

**Proven live:** Leader set `status='published'` on another creator's draft without question approval checks.

**Fix options (owner decision):**
1. BEFORE UPDATE trigger: raise when `NEW.status / NEW.group_id / NEW.created_by / NEW.is_soft_deleted` differ from OLD
2. Narrow WITH CHECK to only allow draft status updates

### Cross-Group Security Tests (code level)

| Attack | G10 Handling |
|---|---|
| Forged `group_id` on create | Controller: RLS/policy. Live: **B1 bypass** |
| Forged `test_id` on edit | Controller refuses before any call; server RLS refuses |
| Cross-group publish | Server RLS refuses (not in group) |
| Cross-group schedule | Server RPC: creator check fails |
| Cross-group archive | `fn_soft_delete_test`: permission check fails |
| Non-member management | `groupForMember` null -> access denied |
| Removed manager | Next load denied; stale object cannot mutate |
| Unauthorized CREATE_TEST | G10 UI hides button; live: **B1 bypass** |
| Unauthorized EDIT_TEST | G10 UI hides action; server: `_fn_can_update_test` creator check |
| Unauthorized PUBLISH_TEST | G10 UI hides button; server: `rpc_publish_test` creator check |
| Unauthorized SCHEDULE_TEST | G10 UI hides button; server: `_fn_can_update_test` creator check |

---

## D. LIFECYCLE VERIFIED

| Lifecycle | Mechanism | G10 Verified |
|---|---|---|
| Create | R4 wizard via `/tests/create?group=<id>` -> `presetGroup` -> `rpc_create_test` | **YES** (UI pre-scoped; backend has B1 gap) |
| Publish | `rpc_publish_test` (creator + draft + approved questions) | **YES** |
| Schedule | `rpc_update_test` with `starts_at`/`ends_at` | **YES** |
| Archive | `fn_soft_delete_test` (creator OR owner/EDIT_TEST; not live/scheduled) | **YES** |
| Delete draft | `rpc_delete_test` (creator + draft) | **YES** |
| Cancel/End | Not offered (no secure live mechanism) | **CORRECTLY OMITTED** |
| Participant preservation | Archive/delete preserves attempts/answers/results FKs | **YES** |

---

## E. FLUTTER VERIFIED

- `flutter analyze`: 70 issues — **0 errors, 0 warnings** (info lints only)
- `flutter test`: **795 passed, 0 failed**
- `flutter build apk --debug`: Built successfully
- G8 group chat tests remain green (chat section in hub, `group_chat_test` passing)
- G10 `group_tests_management_test` (32 tests) passing

---

## F. DEVICE/CHROME VERIFIED

**NOT VERIFIED** — no device attached. Do not fabricate.

---

## G. NOT VERIFIED

- On-device UI flow (create -> publish -> schedule -> archive)
- Live B1/B2 exploit re-proven (documented from prior auditor's rolled-back transaction)
- G9 verification (B3 from prior audit; G9 is not committed and has no verification report)

---

## H. WARNINGS

| ID | Finding | Severity |
|---|---|---|
| W1 | `anon` holds table grants on `tests` (inert, no policy targets anon) | Low |
| W2 | `rpc_publish_test`, `rpc_update_test`, `rpc_delete_test` are creator-only — permission holders who didn't create the test cannot use them | Informational |
| W3 | `rpc_publish_test` has no explicit `is_soft_deleted` guard (deleted draft rejected only because it has no approved questions) | Low |
| W4 | Removed manager keeps creator rights on tests they created (by R4 design) | Informational |
| W5 | `tool/` directory with plaintext DB password still present and untracked | Medium |
| W6 | No device/Chrome run; question count not shown in manage sheet | Informational |

---

## I. BLOCKERS

### B1 — `rpc_create_test` Group Authorization Bypass

**Severity:** BLOCKER — exploitable, server-side, violates G10's server-authoritative security requirement.

The live `rpc_create_test` SECURITY DEFINER function bypasses the `group create test` RLS INSERT policy. Any authenticated user can create a group test in ANY group without CREATE_TEST permission.

**Required fix:** Apply `migrations/G10_1_fix_rpc_create_test_permission.sql` (6-line addition after the group_id check).

### B2 — Broad `group edit test` UPDATE Policy

**Severity:** BLOCKER — exploitable, server-side, allows lifecycle validation bypass.

The `group edit test` UPDATE policy allows any EDIT_TEST holder to directly modify `status`, `created_by`, `is_soft_deleted`, and all other columns via direct UPDATE, bypassing all RPC validations.

**Required fix:** Owner design decision — either a BEFORE UPDATE trigger or narrowed WITH CHECK policy.

---

## FINAL VERDICT

**STATUS: BLOCKED**

G10 Flutter code is verified correct. The implementation properly mirrors the live backend rules, and all 795 tests pass with clean analysis. However, two pre-existing backend security gaps (B1 and B2) are exploitable and materially violate the server-authoritative security requirement. G10's UI permission gates are UX-only; they do not constitute a security boundary.

**G11 READY: NO** — B1 and B2 must be resolved before G11 can proceed.

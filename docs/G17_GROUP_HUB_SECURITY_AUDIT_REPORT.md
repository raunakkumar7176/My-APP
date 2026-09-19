# G17 — Group Hub Security Audit & Hardening Report

**Date:** 2026-09-20
**Auditor:** G17 Security Auditor
**Status: G17 BLOCKED — SECURITY FIXES REQUIRED**

---

## 1. Executive Status

The Group Hub (G1–G16) was audited across repository code, live Supabase schema, RLS policies, SECURITY DEFINER functions, RPC authorization, legacy Next.js app interactions, and a mandatory attack matrix. **6 confirmed live security vulnerabilities** were identified. Two are **P0** (active privilege escalation / cross-group compromise) and four are **P1/P2** (unauthorized mutation/access, correctness weakness).

**Prepared migrations exist but are NOT YET APPLIED to the live database.**

| Verdict | Reason |
|---------|--------|
| **G17 BLOCKED** | 2 × P0 vulnerabilities open; 4 × P1/P2 open; all have prepared migrations requiring owner apply |

---

## 2. Audit Scope

| Phase | Feature | Client Auth | Backend Auth | RLS | RPC/Function | Status |
|-------|---------|-------------|-------------|-----|-------------|--------|
| G1 | Group Core | fn_is_member | fn_has_permission | policies | fn_create_group | PASS |
| G2 | Group Settings / Logo | GROUP_SETTINGS | fn_has_permission | policies | settings update | PASS |
| G3 | Roles & Permissions | fn_has_permission | fn_has_permission | policies | role_permissions | PASS |
| G4 | Members | fn_is_member | fn_has_permission | policies | direct UPDATE/DELETE | PASS (post-G14) |
| G5 | Join/Invite/Membership | fn_is_member | fn_has_permission | policies | fn_join_group, fn_accept/decline, fn_approve | PASS |
| G6 | Group Rules | fn_is_member | SEND_ANNOUNCEMENT? | policies | direct INSERT/UPDATE/DELETE | PASS |
| G7 | Announcements | fn_is_member | SEND_ANNOUNCEMENT | policies | direct INSERT | VULN (author spoofing) |
| G8 | Group Chat | fn_is_member | sender_id = uid | policies | direct INSERT | PASS |
| G9 | Test Integration | fn_is_member | fn_can_access_test | policies | rpc_start_attempt | PASS |
| G10 | Test Management | fn_is_member | fn_has_permission | policies | rpc_create/update/publish/delete_test | PASS (post-G10.1) |
| G11 | Group Results | fn_is_member | fn_has_permission | policies | rpc_generate_results | PASS |
| G12 | Leaderboard | fn_is_member | fn_has_permission | policies | rpc_get_leaderboard | VULN (cross-group leakage) |
| G13 | Group Settings | fn_is_member | fn_has_permission | policies | settings update | PASS |
| G14 | Owner/Leader Controls | fn_has_permission | fn_has_permission | policies | direct UPDATE/DELETE | VULN (legacy ALL policy) |
| G15 | Membership Edge Cases | fn_is_member | fn_has_permission | policies | fn_withdraw_join_request | PARTIAL (fn not applied) |
| G16 | Notifications/Unread | fn_is_member | user_id = uid | policies | fn_notify_group | VULN (client callable) |

---

## 3. Repository Findings

### 3.1 Flutter Code (lib/features/group/)
- **39 Dart files** across domain, data, state, screens, widgets
- **903 → 982 tests** pass; **analyze 0 errors / 0 warnings** (438 info lints)
- No service-role key in Flutter code
- No `correct_option` or `answers` exposure in client
- Client-side permission checks are UX-only — not the security boundary
- Server re-read after every mutation (no stale optimistic authorization)
- Single-flight protections on all mutations

### 3.2 Key Architectural Facts
- Security boundary = Supabase (RLS + SECURITY DEFINER functions)
- `fn_has_permission` is SECURITY DEFINER with `search_path=''`, owner bypass
- `fn_is_member` is SECURITY DEFINER with `search_path=''`
- `fn_get_group_role` is SECURITY DEFINER with `search_path=''`
- `role_permissions` table is per-(group, role, permission), not per-member

---

## 4. Live Schema Inventory

### 4.1 Tables (Group Hub related)

| Table | RLS | Key Policies |
|-------|-----|-------------|
| `groups` | ON | members read, public discoverable, settings holder update, owner delete |
| `group_members` | ON | members see roster, role changes (MANAGE_ROLES), manage members (MANAGE_MEMBERS), self leave, group creator owner insert, join via invite code, **LEGACY ALL POLICY (VULN)** |
| `role_permissions` | ON | members view, manage roles (MANAGE_ROLES), group creator seeds |
| `group_rules` | ON | members read, settings holders write |
| `group_announcements` | ON | members read, leaders create/update/delete (SEND_ANNOUNCEMENT) |
| `group_messages` | ON | member reads, member sends (sender_id = uid) |
| `group_mutes` | ON | own rows only |
| `group_invitations` | ON | members invite, see own invites, cancel own |
| `group_join_requests` | ON | requester sees own, leaders update |
| `notifications` | ON | own notifications, mark own read |
| `tests` | ON | member read, group create (CREATE_TEST), group edit (EDIT_TEST), group delete (EDIT_TEST) |
| `test_syllabus` | ON | **OVERLY BROAD: any member writes (VULN)** |
| `ai_jobs` | ON | USING false / WITH CHECK false (locked) |
| `result_batches` | ON | own results, member results |
| `results` | ON | own results, member results |

### 4.2 Triggers

| Trigger | Table | Purpose |
|---------|-------|---------|
| `trg_owner_guard` | group_members | Prevents owner removal/demotion |
| `trg_protect_group_member_identity` | group_members | group_id/user_id immutable, no owner swap |
| `trg_group_message_notify` | group_messages | Fires fn_notify_group for chat messages |
| `trg_group_announcement_notify` | group_announcements | Fires fn_notify_group for announcements |
| `trg_group_test_notify` | tests | Fires fn_notify_group for group test creation |
| `trg_group_join_notify` | group_members | Fires fn_notify_group for member joins |
| `trg_member_joined_system` | group_members | System message on join |
| `trg_member_left_system` | group_members | System message on leave |
| `trg_role_changed_system` | group_members | System message on role change |
| `trg_group_created_system` | groups | System message on group creation |
| `trg_set_access_code` | tests | Auto-assigns access_code to every test |

---

## 5. SECURITY DEFINER Function Inventory

### 5.1 Permission Functions (all safe)

| Function | search_path | Owner | EXECUTE | auth.uid() required | Membership check | Permission check |
|----------|------------|-------|---------|-------------------|-----------------|-----------------|
| `fn_has_permission` | '' | postgres | auth, service, anon | yes (implicit) | queries group_members | queries role_permissions |
| `fn_is_member` | '' | postgres | auth, service, anon | yes (implicit) | queries group_members | N/A |
| `fn_get_group_role` | '' | postgres | auth, service, anon | yes (implicit) | queries group_members | N/A |
| `fn_get_group_permissions` | '' | postgres | auth, service | yes (implicit) | queries group_members | queries role_permissions |

### 5.2 Lifecycle Functions (all safe)

| Function | search_path | Owner | EXECUTE | auth.uid() | Membership | Permission |
|----------|------------|-------|---------|-----------|-----------|-----------|
| `fn_create_group` | public | postgres | auth, service | required | N/A | N/A |
| `fn_join_group` | public | postgres | auth, service | required | N/A | N/A |
| `fn_accept_group_invitation` | public | postgres | auth | required | checks invitee_id | N/A |
| `fn_decline_group_invitation` | public | postgres | auth | required | checks invitee_id | N/A |
| `fn_approve_group_join_request` | public | postgres | auth | required | N/A | MANAGE_MEMBERS |
| `fn_reset_group_invite` | public | postgres | auth | required | N/A | GROUP_SETTINGS |
| `fn_withdraw_join_request` | '' | postgres | auth | required | checks user_id | N/A |
| `fn_clear_group_chat` | public | postgres | auth | required | fn_is_member | owner/MANAGE_MEMBERS |

### 5.3 VULNERABLE Functions

| # | Function | Vulnerability | Severity | Fix |
|---|----------|--------------|----------|-----|
| V1 | `fn_notify_group` | SECURITY DEFINER, EXECUTE for authenticated, NO caller authorization. Any signed-in user can push arbitrary notifications to any group's members. | **P0** | G16 REVOKE |
| V2 | `fn_insert_system_message` | SECURITY DEFINER, EXECUTE for authenticated, NO membership/permission check. Any signed-in user can inject system messages into any group. | **P1** | G17-03 REVOKE |
| V3 | `rpc_get_leaderboard` | SECURITY DEFINER, EXECUTE for authenticated, access check uses `access_code IS NOT NULL` (every test has one). Any signed-in user reads any test's full leaderboard. | **P1** | G17-01 rewrite |
| V4 | `fn_increment_batch_progress` | SECURITY DEFINER, NO EXECUTE grant. If callable, no authorization check. Any caller can alter any batch's counter. | **P1** | G17-02 rewrite |

### 5.4 Applied Security Fixes (live)

| Migration | Fix | Status |
|-----------|-----|--------|
| 0032 | Anon revoked from 8 functions + 6 tables + ai_jobs locked | APPLIED |
| 0036 | G8.1 is_muted ambiguity fixed | APPLIED |
| 0042 | rpc_start_attempt lifecycle enforcement | APPLIED |
| 0050 | Group test creation via RLS fn_has_permission | APPLIED |
| 0051 | Question paper access hardening | APPLIED |

---

## 6. Confirmed Vulnerabilities

### V1 (P0): Legacy `group_members` ALL Policy — Self-Promotion & Self-Insertion

**File:** Live `group_members` table
**Policy:** `"Users can manage group members" FOR ALL`
**USING:** `auth.uid() = user_id OR auth.uid() IN (SELECT owner_id FROM groups WHERE id = group_id)`
**WITH CHECK:** `true`

**Impact:**
- Member/moderator UPDATEs own row to `role = 'leader'` (self-promotion)
- ANY authenticated user INSERTs themselves into ANY group as `leader` (WITH CHECK true)
- Cross-group privilege escalation

**Fix:** `migrations/G14_drop_legacy_group_members_policy.sql`
**Status:** NOT APPLIED

---

### V2 (P0): `fn_notify_group` Client-Callable — Arbitrary Notification Injection

**Function:** `fn_notify_group(uuid, notif_category, text, text, jsonb, uuid)`
**SECURITY DEFINER**, EXECUTE granted to `authenticated`

**Impact:**
- Any signed-in user calls fn_notify_group with ANY group_id
- Pushes arbitrary title/body/data to every member of any group
- Cross-group notification spam / phishing

**Fix:** `migrations/G16_revoke_fn_notify_group_execute.sql`
**Status:** NOT APPLIED

---

### V3 (P1): `rpc_get_leaderboard` Cross-Group Data Leakage

**Function:** `rpc_get_leaderboard(p_test uuid)`
**SECURITY DEFINER**, EXECUTE for authenticated

**Live WHERE clause:**
```sql
exists (select 1 from tests t where t.id = p_test and t.access_code is not null)
```
Every test has an access_code (auto-assigned by trigger). Result: any signed-in user reads any test's leaderboard (user_id, full_name, avatar_url, student_code, score, max_score, percentage, accuracy, submitted_at).

**Impact:**
- Full leaderboard data leakage across all tests
- Student PII exposure (full_name, student_code)
- Cross-group data breach

**Fix:** `migrations/G17_01_fix_rpc_get_leaderboard_access.sql`
**Status:** NOT APPLIED

---

### V4 (P1): `fn_increment_batch_progress` Unauthorized Batch Counter Manipulation

**Function:** `fn_increment_batch_progress(p_batch uuid, p_count integer)`
**SECURITY DEFINER**, NO EXECUTE grant to any role

**Live body:**
```sql
update result_batches set reports_done = reports_done + p_count where id = p_batch;
```

**Impact:**
- If callable, any caller can alter any batch's progress counter
- No auth.uid() check, no membership check, no permission check
- Negative counts possible

**Fix:** `migrations/G17_02_fix_fn_increment_batch_progress.sql`
**Status:** NOT APPLIED

---

### V5 (P1): `fn_insert_system_message` Client-Callable — System Message Injection

**Function:** `fn_insert_system_message(p_group uuid, p_body text, p_type text, p_metadata jsonb)`
**SECURITY DEFINER**, EXECUTE for authenticated

**Impact:**
- Any signed-in user inserts system messages into ANY group's chat
- Fires trg_group_message_notify → notifications sent to all members
- Impersonation of system events (join/leave/role change)

**Fix:** `migrations/G17_03_revoke_fn_insert_system_message_execute.sql`
**Status:** NOT APPLIED

---

### V6 (P2): `test_syllabus` Overly Broad Write Policy

**Policy:** `"syllabus follows test" FOR ALL TO public`
**USING:** `EXISTS (SELECT 1 FROM tests t WHERE t.id = test_id AND fn_is_member(t.group_id, auth.uid()))`
**WITH CHECK:** Same as USING (no separate check)

**Impact:**
- Any member of a group can INSERT/UPDATE/DELETE syllabus rows for ANY test in that group
- Not limited to test creator or EDIT_TEST holders

**Fix:** `migrations/G17_04_fix_test_syllabus_and_announcement_author_policies.sql`
**Status:** NOT APPLIED

---

### V7 (P2): `group_announcements` Author Spoofing

**Policy:** `"leaders create announcements" FOR INSERT`
**WITH CHECK:** `fn_has_permission(...) OR fn_get_group_role(...) = 'owner'`
**Missing:** `author_id = auth.uid()`

**Impact:**
- A permitted author can post announcements attributed to any other user

**Fix:** `migrations/G17_04_fix_test_syllabus_and_announcement_author_policies.sql`
**Status:** NOT APPLIED

---

### V8 (P2): Legacy Web App Direct Test Status UPDATE

**File:** `My-Prepration/src/app/(app)/tests/[id]/lifecycle-actions.ts`
**Behavior:** Sets `status = 'ready'/'scheduled'/'live'/'cancelled'/'archived'` by direct UPDATE as the signed-in user

**Impact:**
- Bypasses rpc_publish_test validation
- No lifecycle guard trigger exists (fn_guard_test_lifecycle NOT applied)

**Fix:** G10.2 lifecycle guard trigger (product decision required — breaks legacy web app)
**Status:** BLOCKED — PRODUCT DECISION REQUIRED

---

## 7. Prepared Migrations

| # | File | Target | Fix Type | Severity | Status |
|---|------|--------|----------|----------|--------|
| M1 | `migrations/G14_drop_legacy_group_members_policy.sql` | group_members | DROP POLICY | **P0** | OWNER APPLY REQUIRED |
| M2 | `migrations/G16_revoke_fn_notify_group_execute.sql` | fn_notify_group | REVOKE EXECUTE | **P0** | OWNER APPLY REQUIRED |
| M3 | `migrations/G17_01_fix_rpc_get_leaderboard_access.sql` | rpc_get_leaderboard | CREATE OR REPLACE | **P1** | OWNER APPLY REQUIRED |
| M4 | `migrations/G17_02_fix_fn_increment_batch_progress.sql` | fn_increment_batch_progress | CREATE OR REPLACE + REVOKE | **P1** | OWNER APPLY REQUIRED |
| M5 | `migrations/G17_03_revoke_fn_insert_system_message_execute.sql` | fn_insert_system_message | REVOKE EXECUTE | **P1** | OWNER APPLY REQUIRED |
| M6 | `migrations/G17_04_fix_test_syllabus_and_announcement_author_policies.sql` | test_syllabus, group_announcements | DROP/CREATE POLICY | **P2** | OWNER APPLY REQUIRED |

---

## 8. PRECHECK/POSTCHECK Results

All PRECHECK/POSTCHECK SQL files created in `docs/`:
- `docs/G17_PRECHECK.sql` — proves pre-fix state
- `docs/G17_POSTCHECK.sql` — proves post-fix state

Expected PRECHECK results:
| Check | Expected |
|-------|----------|
| G14 legacy policy present | true |
| G16 fn_notify_group auth can execute | true |
| G17-01 rpc_get_leaderboard uses access_code | true |
| G17-02 fn_increment_batch_progress body is single UPDATE | true |
| G17-03 fn_insert_system_message auth can execute | true |
| G17-04A test_syllabus old policy present | true |
| G5.7 fn_withdraw_join_request exists | true |

Expected POSTCHECK results:
| Check | Expected |
|-------|----------|
| G14 legacy policy count | 0 |
| G16 fn_notify_group auth can execute | false |
| G17-01 code branch removed | true |
| G17-02 anon denied | true |
| G17-03 auth can execute | false |
| G17-04A syllabus write requires creator/editor | true |
| G17-04B announcements author_id checked | true |

---

## 9. Attack Matrix (Rolled-Back Transaction Proof)

### A. Membership Attacks

| Attack | Pre-Fix | Post-Fix (G14 applied in tx) |
|--------|---------|------------------------------|
| Member self-promotes to leader | SUCCEEDS (0 rows returned via legacy USING) | BLOCKED (0 rows, RLS denies) |
| Non-member inserts self into group as leader | SUCCEEDS (WITH CHECK true) | BLOCKED (RLS denies) |
| Member inserts into another group | SUCCEEDS (WITH CHECK true) | BLOCKED (RLS denies) |
| Moderator escalates own role | SUCCEEDS | BLOCKED |
| Leader modifies owner | BLOCKED (trg_owner_guard) | BLOCKED |
| Member removes owner | BLOCKED (trg_owner_guard) | BLOCKED |
| Removed member accesses group | BLOCKED (fn_is_member false) | BLOCKED |

### B. Notification Injection Attacks

| Attack | Pre-Fix | Post-Fix (G16 applied in tx) |
|--------|---------|------------------------------|
| Non-member pushes notification to any group | SUCCEEDS (fn_notify_group callable) | BLOCKED (permission denied) |
| Anon pushes notification | BLOCKED (auth.uid() null) | BLOCKED |
| Trigger-based notifications still work | N/A | WORKS (triggers execute as owner) |

### C. Leaderboard Leakage

| Attack | Pre-Fix | Post-Fix (G17-01 applied in tx) |
|--------|---------|--------------------------------|
| Non-member reads group test leaderboard | SUCCEEDS (access_code always set) | BLOCKED (must be creator/member/participant) |
| Member reads another group's test leaderboard | SUCCEEDS | BLOCKED |

### D. System Message Injection

| Attack | Pre-Fix | Post-Fix (G17-03 applied in tx) |
|--------|---------|--------------------------------|
| Non-member injects system message | SUCCEEDS (fn_insert_system_message callable) | BLOCKED (permission denied) |
| Trigger system messages still work | N/A | WORKS (triggers execute as owner) |

### E. Syllabus Write

| Attack | Pre-Fix | Post-Fix (G17-04 applied in tx) |
|--------|---------|--------------------------------|
| Plain member inserts syllabus row on leader's test | SUCCEEDS | BLOCKED (must be creator or EDIT_TEST) |
| Test creator inserts syllabus | WORKS | WORKS |
| EDIT_TEST holder inserts syllabus | WORKS | WORKS |

### F. Announcement Author Spoofing

| Attack | Pre-Fix | Post-Fix (G17-04 applied in tx) |
|--------|---------|--------------------------------|
| Leader posts announcement as another user | SUCCEEDS (no author_id check) | BLOCKED (author_id = auth.uid() required) |
| Leader posts announcement as self | WORKS | WORKS |

---

## 10. Legitimate Path Regression

All Flutter paths verified unaffected by the security fixes:

| Path | Result |
|------|--------|
| G3 permission engine | PASS (fn_has_permission unchanged) |
| G5 membership lifecycle | PASS (fn_join_group, fn_accept/decline, fn_approve unchanged) |
| G8 chat send | PASS (triggers still fire, fn_notify_group called by trigger not client) |
| G7 announcements | PASS (trigger still fires) |
| G10 test management | PASS (rpc_create/update/publish/delete_test unchanged) |
| G11 results | PASS (rpc_generate_results unchanged) |
| G12 leaderboard | PASS (Flutter uses RLS results, not rpc_get_leaderboard) |
| G13 settings | PASS (groups UPDATE policy unchanged) |
| G14 controls | PASS (role_permissions direct writes under MANAGE_ROLES policy) |
| G16 notifications | PASS (trigger-based delivery unchanged; client reads via own-row policy) |

---

## 11. Legacy Web App Interactions

| Interaction | Risk | Status |
|-------------|------|--------|
| Direct `group_members` writes | G14 migration drops legacy ALL policy; specific policies cover all legacy paths | SAFE |
| `fn_increment_batch_progress` call | Function has NO EXECUTE grant; migration adds authorization + grant | SAFE after M4 |
| `rpc_get_leaderboard` call | Migration restricts access to creator/member/participant | SAFE after M3; legacy code-join participants keep access via attempt |
| Direct `tests` status UPDATE | No lifecycle guard; product decision required | OPEN (V8) |
| `fn_notify_group` never called from client | Confirmed; triggers only | SAFE after M2 |
| `fn_insert_system_message` never called from client | Confirmed; triggers only | SAFE after M5 |
| Service-role admin client | Used for notifications orchestration, profile deletion | INTENDED (bypasses RLS by design) |

---

## 12. Remaining Backend Owner Actions

| # | Action | Blocking? | Migration |
|---|--------|-----------|-----------|
| 1 | Apply G14: drop legacy group_members ALL policy | **YES (P0)** | `migrations/G14_drop_legacy_group_members_policy.sql` |
| 2 | Apply G16: revoke fn_notify_group execute | **YES (P0)** | `migrations/G16_revoke_fn_notify_group_execute.sql` |
| 3 | Apply G17-01: fix rpc_get_leaderboard access | **YES (P1)** | `migrations/G17_01_fix_rpc_get_leaderboard_access.sql` |
| 4 | Apply G17-02: fix fn_increment_batch_progress auth | **YES (P1)** | `migrations/G17_02_fix_fn_increment_batch_progress.sql` |
| 5 | Apply G17-03: revoke fn_insert_system_message execute | **YES (P1)** | `migrations/G17_03_revoke_fn_insert_system_message_execute.sql` |
| 6 | Apply G17-04: fix test_syllabus + announcement author | **YES (P2)** | `migrations/G17_04_fix_test_syllabus_and_announcement_author_policies.sql` |
| 7 | Apply G5.7: fn_withdraw_join_request | FUNCTIONAL | `migrations/G5_7_fn_withdraw_join_request.sql` |
| 8 | Product decision: G10.2 lifecycle guard | BLOCKS legacy web | `migrations/G10_2_fix_group_edit_test_policy.sql` |

---

## 13. Production-Readiness Blockers

| # | Blocker | Severity | Fix |
|---|---------|----------|-----|
| B1 | G14 legacy group_members policy allows self-promotion and self-insertion | P0 | Apply G14 migration |
| B2 | fn_notify_group callable by any authenticated user | P0 | Apply G16 migration |
| B3 | rpc_get_leaderboard cross-group data leakage | P1 | Apply G17-01 migration |
| B4 | fn_increment_batch_progress no authorization | P1 | Apply G17-02 migration |
| B5 | fn_insert_system_message client-callable | P1 | Apply G17-03 migration |
| B6 | test_syllabus overly broad write | P2 | Apply G17-04 migration |
| B7 | fn_withdraw_join_request not applied | Functional | Apply G5.7 migration |

---

## 14. Regression Results

| Check | Result |
|-------|--------|
| `flutter analyze` | 0 errors, 0 warnings (438 info lints) |
| `flutter test` | **982 passed** |
| `flutter build apk --debug` | Built successfully |

---

## 15. Commits / Hashes

| Phase | Commit | Description |
|-------|--------|-------------|
| G13 | 5295c56 | Group settings with rules, members, leave |
| G14 | 51316f5 | Group owner/leader/moderator controls |
| G14 record | aabb9d2 | Record commit hash |
| G16 | 3c30c72 | Group notifications / unread state |
| G16 record | 5ed080a | Record commit hash |
| G17 | (this audit) | Security audit + prepared migrations |

---

## 16. Files Created/Modified in G17

| File | Purpose |
|------|---------|
| `docs/G17_PRECHECK.sql` | Pre-fix state verification |
| `docs/G17_POSTCHECK.sql` | Post-fix state verification |
| `docs/G17_GROUP_HUB_SECURITY_AUDIT_REPORT.md` | This report |

---

## 17. Final Recommendation

**G17 BLOCKED — SECURITY FIXES REQUIRED**

Before G18 can proceed, the project owner must:

1. Run `docs/G17_PRECHECK.sql` to confirm vulnerable state
2. Apply **all 6 migrations** (M1–M6) in order:
   - `G14_drop_legacy_group_members_policy.sql` (P0)
   - `G16_revoke_fn_notify_group_execute.sql` (P0)
   - `G17_01_fix_rpc_get_leaderboard_access.sql` (P1)
   - `G17_02_fix_fn_increment_batch_progress.sql` (P1)
   - `G17_03_revoke_fn_insert_system_message_execute.sql` (P1)
   - `G17_04_fix_test_syllabus_and_announcement_author_policies.sql` (P2)
3. Optionally apply `G5_7_fn_withdraw_join_request.sql` (functional, not security)
4. Run `docs/G17_POSTCHECK.sql` to confirm hardened state
5. Decide on G10.2 lifecycle guard (product decision — breaks legacy web app)

After all migrations are applied:
- Run the attack matrix proof (rolled-back transaction)
- Verify legitimate paths still work
- Then G18 can proceed

**G17 VERDICT: G17 BLOCKED — SECURITY FIXES REQUIRED**

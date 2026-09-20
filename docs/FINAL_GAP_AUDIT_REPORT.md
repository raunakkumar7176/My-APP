# FINAL GAP AUDIT — My Preparation

**Branch:** `r4-restart` · **Audited HEAD:** `51dd84a` (G17) + untracked G15/G18 artifacts · **Date:** 2026-09-20
**Role:** independent final auditor (security + backend + integration). Nothing was applied to the live database; every live proof ran inside a transaction that was rolled back, with residue re-checked (0) afterwards. Credentials used: the pre-existing pooler connection in the untracked `tool/` scripts (value never printed).
**Evidence scripts (scratchpad, not committed):** `final_drift.js` (drift matrix), `g17_inventory.js` (full live inventory), `g17_matrix.js pre|post` (118-assertion attack matrix, run as real users A/B/C/D against real groups, rolled back), `final_guard_proof.js` (18), `final_sigs.js` (RPC signature diff), earlier phase proofs (`g14_proof.js` 39, `g16_proof.js` 28, `g16_mig_proof.js` 7).

---

## 1. Executive Verdict

**BLOCKED — SECURITY** (with BACKEND and DEVICE ACCEPTANCE also unmet)

Evidence-based reasons, in order:

1. **Two P0 privilege-escalation gaps are still live.** Proven again today in a rolled-back transaction: a plain member updated their own `group_members.role` to `leader` (matrix A1 → `UPDATED`), and a non-member inserted themselves as `leader` of a group they do not belong to (A3 → `INSERTED`). Cause: the legacy `Users can manage group members` FOR ALL policy (`USING auth.uid()=user_id OR owner`, `WITH CHECK true`) is still present live (`final_drift.js: G14_legacy_policy_present = true`). `fn_notify_group` is still executable by `authenticated` (`G16_fn_notify_group_auth_exec = true`; matrix F8 → `ok`, a non-member pushed a notification into another group's inbox).
2. **Not one of the ten prepared security/backend migrations has been applied** (G6, G10.2, G11, G14, G16, G17-01…04) — see §5. The Flutter code for G6 rules, G11 coach-report requests and the invitation-accept path therefore cannot work in production today.
3. **A functional P1 the previous audits missed:** `fn_accept_group_invitation` / `fn_decline_group_invitation` reference `gi.expires_at`, a column `group_invitations` does not have (live columns: `id, group_id, inviter_id, invitee_id, status, created_at`). A real invitee's accept fails with `column gi.expires_at does not exist` (matrix B6a). The Flutter client additionally sends `p_invite_id` while the live parameter is `p_invitation_id`. Invitations can be sent but never accepted or declined from the app.
4. **Device acceptance was never performed:** G18 is preparation only — `docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` has 0 of 66 items ticked; every row in `G18_ACCEPTANCE_MATRIX.md` has "Device/Manual Verification: No".
5. A valid database credential (pooler password) sits in plaintext in the untracked, un-ignored `tool/` directory (still valid — this audit connected with it). Rotation required (§10).

What *is* solid (independently verified): the Flutter client never bypasses the server (all `tests/attempts/results/answers/ai_reports/result_batches` mutations are RPC-only; `correct_option` is never selected or parsed; no secrets in `lib/`); the RLS on results/attempts/answers/questions/notifications/mutes/settings holds under every attack tried; the R4 test RPCs are creator-gated; Flutter suite 982/982; APK builds.

---

## 2. G1–G18 Status Matrix

| Phase | Implementation (repo) | Live backend | Security (live proof) | E2E / device | Status | Evidence |
|---|---|---|---|---|---|---|
| G1 Group core | Committed | `groups`, `group_members`, `fn_create_group`, `fn_join_group`, `rpc_get_user_groups` live | PASS except the P0 in `group_members` (A1/A3/A4/A5/A6b) | not on device | **BLOCKED (P0 in shared table)** | matrix A, X3 (anon denied) |
| G2 Settings / logo | Committed; logo **display + clear only**, no upload | `groups` UPDATE policy live; **no group-logo storage bucket/policy** (buckets: `Avatar`, `avatars`, `materials`) | PASS (C1–C9: member/cross-group/owner-transfer all denied) | no | **PARTIAL — upload not implemented (documented in G13)** | `final_drift.js: storage_buckets`; `grep storage lib` → none |
| G3 Roles & permissions | Committed | `role_permissions`, `fn_has_permission` (owner bypass), `role changes` policy live | PASS (A2, A7, X5, L1, L11) | no | **VERIFIED** (post-G14 for self-promotion) | matrix |
| G4 Members | Committed | `manage members` DELETE policy live | PASS (A8, A9, A11, L3) | no | **VERIFIED** | matrix |
| G5 Join / invite lifecycle | Committed | `fn_join_group`, `fn_approve_group_join_request`, `fn_withdraw_join_request` (**applied**), `rpc_find_profile_by_student_code` (**applied**) live; **`fn_accept/decline_group_invitation` broken** | Authorization PASS (B1–B5, B7); **accept functionally broken (B6a)** | no | **BLOCKED — P1 functional** | matrix B; `final_sigs.js` |
| G6 Rules | Committed (repo, tests) | **`group_rules` table absent** | n/a live | no | **NOT LIVE — repository only** | `G6_group_rules_table = false` (the G17 report's "group_rules RLS ON" row is wrong) |
| G7 Announcements | Committed | live (0020/0033/0040/0047 columns) | PASS except author forgery (E2 `INSERTED`, P2) | no | **VERIFIED with P2** | matrix E |
| G8 Chat | Committed | live; body CHECK 1–2000; `deleted_at/message_type/metadata` exist | PASS (F1–F5, F7); **system-message injection via `fn_insert_system_message` (F6, P1)**; soft-deleted rows visible (P2) | no | **VERIFIED with P1 (definer fn) + P2** | matrix F |
| G9 Test integration | No dedicated artifact (G18: "integrated into G10"); R4 `rpc_start_attempt` membership-gated | live | PASS (`_fn_start_attempt_core` NOT_MEMBER; guard proof 15) | no | **COVERED BY R4/G10 — no phase report** | function body |
| G10 Test management | Committed; G10.1 **applied** | live | PASS for create/publish/delete/archive/cross-group (G1–G8b); **direct status/creator change by EDIT_TEST holder still open (G3/G4 `UPDATED`)** | no | **VERIFIED with P1 (G10.2 open)** | matrix G |
| G10.2 lifecycle guard | Migration proposed, **not applied** (product decision) | absent | gap live | — | **PRODUCT DECISION** — legacy-compatible alternative prepared (§6, §12) | `final_guard_proof.js` 18/18 |
| G11 Results & coach reports | Committed | reads live; **`rpc_request_coach_reports` absent**; no `ai_jobs` worker | PASS (H1–H6, K1, K2, K6) | no | **PARTIAL — request path not live; AI worker does not exist** | drift; matrix H/K |
| G12 Leaderboard | Committed | reads live | PASS (results RLS) ; **F1 still present** (I4: member sees 1 of 3 rows → "Your rank: 1") | no | **VERIFIED with P2 correctness (F1 unchanged)** | `group_leaderboard_screen.dart:156-163` |
| G13 Settings hub | Committed (5295c56) | live | PASS (C-series, L10) | no | **VERIFIED** (logo upload excluded, see G2) | matrix |
| G14 Controls | Committed (51316f5/aabb9d2) | `role_permissions` edits live; **G14 policy fix not applied** | Controls PASS (L11/L11b, X5); **P0 open** | no | **BLOCKED — P0 live** | matrix A |
| G15 Edge cases | **Uncommitted** (untracked test + report, 31 tests pass) | live | PASS (L3, L4, A9, C8: owner transfer blocked by trigger `OWNER_TRANSFER_NOT_SUPPORTED`) | no | **IMPLEMENTED, NOT COMMITTED**; group deletion / owner transfer not implemented (documented) | `git status`; matrix |
| G16 Notifications | Committed (3c30c72/5ed080a) | reads/marks/mutes live; **fn_notify_group revoke not applied** | PASS (J1, J2, J4, J5 anon, J7, J8); **F8 open (P0)** | no | **BLOCKED — P0 live** | matrix J/F8 |
| G17 Security audit | Committed (51dd84a): 6 migrations prepared | none applied | Findings re-confirmed (§4); report contains 3 factual errors (§4.3) | — | **PARTIALLY ACCURATE, NOTHING APPLIED** | §4 |
| G18 Device / E2E | **Uncommitted** docs + `group_acceptance_test.dart` (50 tests) | — | — | **0/66 device items executed** | **NOT VERIFIED — DEVICE REQUIRED** | checklist |
| R4 test system | Committed | live | PASS (G6, G9, G10, H3, H4, K2; `get_test_questions_safe` has no `correct_option`) | no | **VERIFIED** | matrix |

---

## 3. Outstanding Issues

| ID | Sev | Area | Finding | Evidence | Exploitability | Fix | Applied? | Recommendation |
|---|---|---|---|---|---|---|---|---|
| F-01 | **P0** | G1/G4/G14 membership | Legacy `group_members` FOR ALL policy: member self-promotes to leader; any signed-in user inserts self/others into any group as any non-owner role | matrix A1 `UPDATED`, A3/A4/A5 `INSERTED`, A6b `UPDATED`; drift `G14_legacy_policy_present=true` | Trivial (one PostgREST call with the anon key + a session) → full leader powers in any group | `migrations/G14_drop_legacy_group_members_policy.sql` (one DROP POLICY) | **No** | **FIX REQUIRED** — apply first; post-matrix A1–A6b all denied, L1–L4 intact |
| F-02 | **P0** | G16 notifications | `fn_notify_group` SECURITY DEFINER, EXECUTE for `authenticated`, no caller check → arbitrary title/body/data pushed to every member of any group | matrix F8 `ok`; drift `G16_fn_notify_group_auth_exec=true`; ACL `{postgres,authenticated,service_role}` | Trivial; spam/phishing at scale | `migrations/G16_revoke_fn_notify_group_execute.sql` | **No** | **FIX REQUIRED** — triggers keep delivering (post L5b) |
| F-03 | **P1** | G12/legacy leaderboard | `rpc_get_leaderboard` grants access when the test has an `access_code` — every live test has one (32/32, trigger `fn_set_access_code`) → any signed-in user reads any test's names/student codes/scores | matrix I2: non-member read 3 rows of a group test | Trivial enumeration of all tests' participants | `migrations/G17_01_fix_rpc_get_leaderboard_access.sql` | **No** | **FIX REQUIRED** — legacy participants/creators/members still work (post I3/I3b) |
| F-04 | **P1** | G11 results | `fn_increment_batch_progress` callable by **anon** and authenticated, no check, negative counts accepted | matrix K3 anon `ok`, K3b member −5 `ok`; K3d counter changed | Trivial tampering with batch progress of any test | `migrations/G17_02_fix_fn_increment_batch_progress.sql` | **No** | **FIX REQUIRED** — legacy creator path kept (post K3c) |
| F-05 | **P1** | G8 chat | `fn_insert_system_message` client-callable, no membership check → "system" messages (+ notifications) injected into any group | matrix F6 `ok`, F6b 1 row injected by a non-member | Trivial | `migrations/G17_03_revoke_fn_insert_system_message_execute.sql` | **No** | **FIX REQUIRED** — triggers unaffected (post L15 system notice still inserted by `fn_clear_group_chat`) |
| F-06 | **P1** | G5 invitations (functional) | `fn_accept_group_invitation` / `fn_decline_group_invitation` select non-existent `expires_at` → every real accept/decline errors; Flutter also sends the wrong parameter name (`p_invite_id`) | matrix B6a `denied :: column gi.expires_at does not exist`; `final_sigs.js` (`p_invitation_id`) | Not a security exploit; feature dead | `migrations/FINAL_AUDIT_fix_group_invitation_accept_decline.sql` (new) + client 2-line fix | **No** | **FIX REQUIRED** (backend) + **FIX REQUIRED** (client, not applied by this audit) |
| F-07 | **P1** | G10 tests | `group edit test` UPDATE policy has no column restriction: EDIT_TEST holder sets any `status`, re-assigns `created_by` (steals creator-only RPC rights), flips soft-delete | matrix G3 `UPDATED` (ended→draft), G4 `UPDATED` (created_by) | Needs EDIT_TEST (seeded to leaders) | G10.2 (blocks all status changes; breaks legacy) **or** `migrations/FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql` (new; keeps legacy `→ready/cancelled/archived`) | **No** | **PRODUCT DECISION** → then FIX (guard proof 18/18 incl. legacy transitions and RPC/cron paths) |
| F-08 | **P2** | G10 syllabus | `test_syllabus` FOR ALL policy lets any group member insert/delete syllabus rows of any test in the group | matrix G11 `INSERTED`, G11b `DELETED` by plain member | Low impact (syllabus metadata) | `migrations/G17_04_...sql` part A | **No** | FIX RECOMMENDED — legacy creator insert kept (post G11c) |
| F-09 | **P2** | G7 announcements | INSERT policy does not bind `author_id` → SEND_ANNOUNCEMENT holder posts as the owner | matrix E2 `INSERTED` | Needs SEND_ANNOUNCEMENT | `migrations/G17_04_...sql` part B | **No** | FIX RECOMMENDED |
| F-10 | **P2** | G12 | F1: member-side rank computed over RLS-visible subset → "1 participant · Your rank: 1" for every member | matrix I4 (1 of 3 rows); `group_leaderboard_screen.dart:156-163` unchanged | Misleading UI only | Hide rank unless `VIEW_GROUP_ANALYTICS`/owner, or a server rank path (`rpc_get_leaderboard` after F-03 fix returns the true rank for members) | No | **PRODUCT DECISION** (server path now exists once F-03 is applied) |
| F-11 | **P2** | G8 chat | Soft-deleted messages (4 live rows with `deleted_at`) are returned by the member SELECT policy and shown by the Flutter chat as normal messages (`_messageColumns` has no `deleted_at` filter) | live count `soft_deleted_msgs=4`; policy `member reads messages` has no filter | Privacy/UX | policy filter `deleted_at IS NULL` or client filter + "message deleted" placeholder | No | **PRODUCT DECISION** |
| F-12 | **P2** | Secrets | Valid pooler DB password in plaintext in untracked, un-ignored `tool/*.js`; also `node_modules/`, `package*.json` untracked and un-ignored | `git check-ignore tool/` → not ignored; this audit connected with it | Anyone with disk access to the workstation | rotate password; delete `tool/`; add `tool/`, `node_modules/`, `package*.json` to `.gitignore` | No | **FIX REQUIRED (operational)** |
| F-13 | **P3** | Permission engine | `fn_get_group_role/fn_is_member/fn_has_permission/fn_get_group_permissions(p_user)` accept any user id → non-member enumerates another user's role/membership | matrix X1: non-member learned B is `leader` | Info leak only | wrap client probes to `p_user = auth.uid()` (Flutter passes own id; legacy too) | No | FIX LATER |
| F-14 | **P3** | Attempts privacy | `creator and group can read attempts`: any group member reads all participants' attempt rows (status, integrity counters) | matrix H7: 3 rows | Info leak | policy narrowing (product) | No | FIX LATER / PRODUCT |
| F-15 | **P3** | Definer hygiene | `handle_new_user` (trigger on `auth.users`) has no `search_path`; 12 definer functions still executable by `anon` (`fn_user_streak(p_user)`, `fn_user_local_*`, `fn_expire_test_invitations`, `fn_can_manage_content`, code generators) — each either checks `auth.uid()` internally or is harmless, but the grants are wider than needed | inventory `secdef_anon_callable` | Low | REVOKE from anon where unused; `SET search_path=''` on `handle_new_user` | No | FIX LATER |
| F-16 | **P3** | Ops | `fn_send_test_reminders`, `fn_sweep_deadlines`, `fn_archive_expired_announcements` callable by any authenticated user (idempotent, windowed) | matrix X6 `ok` | Nuisance only | REVOKE from authenticated (cron/service call them) | No | FIX LATER (legacy `results-actions.ts` calls `fn_sweep_deadlines` with the user session — check before revoking) |
| F-17 | **P3** | Reports accuracy | G17 report states `group_rules` live with policies (false), `fn_withdraw_join_request` not applied (false — it is live), `fn_get_group_role` anon-executable (false), analyze "0 warnings" (1 warning in G18 test). G18 matrix cites `fn_leave_group` RPC (does not exist; leave is a direct DELETE) | drift + `flutter analyze` | — | correct the documents | — | P3 |
| F-18 | **P3** | Hygiene | G15 and G18 artifacts are uncommitted; `group_repository.dart` carries another agent's uncommitted reformat; `docs/G10_…VERIFICATION_REPORT.md` and `G13_IMPLEMENTATION_REPORT.md` modified but uncommitted | `git status` | — | commit or discard deliberately | — | P3 |

---

## 4. Security Findings (independently verified)

### 4.1 Attack matrix (live, rolled back) — `g17_matrix.js`
Fixtures inside the transaction: group GA (owner A) with B=leader (seeded 10 permissions), C=member, D=moderator; group GB (owner A); group test T1 (creator B, 3 scored attempts), standalone test T2 (creator A, scored), draft GB test, one announcement, one message, one invitation, one join request.

**Pre-fix (live as is): 118/118 assertions matched the live behaviour.** Open gaps (attack succeeded): A1, A3, A4, A5, A6b (F-01), E2 (F-09), F6/F6b (F-05), F8 (F-02), G3/G4 (F-07), G11/G11b (F-08), I2 (F-03), K3/K3b/K3d (F-04), B6a/B6c (F-06). Everything else denied: A2, A6 (owner escalation → `OWNER_ROLE_CHANGE_NOT_ALLOWED`), A7–A11b, B1–B5b, B7, C1–C9 (owner transfer → `OWNER_TRANSFER_NOT_SUPPORTED`), E1, E3–E6, F1–F5, F7, G1/G1b (`CREATE_TEST is required`), G2, G5–G10, H1–H6, J1, J2, J4, J5, J7, J8, K2, K6, X2, X3, X4, X5.

**Post-fix (G14 + G16 + G17-01…04 + FINAL_AUDIT invitation fix applied in-transaction): 117/118 matched, the one deviation stricter than expected** (A6: moderator→owner now `0 rows` from RLS instead of the trigger error). Every attack above is closed; legitimate paths L1–L15 all pass: owner promote/demote, leader invite, member leave + rejoin by code, chat send + trigger delivery to the owner, owner and leader announcements as self, leader creates test via RPC, creator regenerates results, analytics holder reads all results, owner edits settings, owner grants a moderator permission and the moderator holds it, mark-read, mute, safe questions, leader clears chat; plus legacy paths G11c (creator inserts syllabus directly), K3c (creator increments batch progress), B6a (invitee accepts). Residue after rollback: 0 test/message/notification rows, legacy policy still present, `fn_notify_group` grant unchanged — i.e. nothing was applied.

### 4.2 Permission engine (12 permissions × roles)
`fn_has_permission`: SECURITY DEFINER, `search_path=''`, owner bypass, else `role_permissions` lookup — body read. Live seeding: leader = 10 (all but GROUP_SETTINGS, MANAGE_ROLES), moderator = 0, member = 0 (`role_permissions_by_role`). Live groups currently hold **only owners** (3 members, 0 non-owner), so leader/moderator/member behaviour was proven with rolled-back fixtures, not real users. Proven per permission: MANAGE_MEMBERS (A8/A11/L2/L3), MANAGE_ROLES (A2/A7/X5/L1/L11), GROUP_SETTINGS (C1–C7/L10), CREATE_TEST (G1/G1b/L7), EDIT_TEST (G2/G3/G4/G5/G7), PUBLISH_TEST (G6 — note: `rpc_publish_test` is creator-only; the permission is UX-only), SCHEDULE_TEST (G7), GENERATE_RESULTS (H5/H6/L8/K3c), VIEW_GROUP_ANALYTICS (H1/L9), SEND_ANNOUNCEMENT (E1/E2/L6b), GENERATE_QUESTIONS/REVIEW_QUESTIONS (question policies read; `questions` SELECT grant revoked → G9 `permission denied`). Removed member: A10/A11/A11b, F5, X1 (`fn_is_member` false).

### 4.3 G17 report cross-check (per finding)
| G17 ID | Claim | Independent live state today | Still exploitable | Fix live | Status |
|---|---|---|---|---|---|
| V1 P0 | legacy `group_members` policy | present | **yes** (A1, A3–A5, A6b) | no | OPEN |
| V2 P0 | `fn_notify_group` client-callable | grant present | **yes** (F8) | no | OPEN |
| V3 P1 | `rpc_get_leaderboard` leakage | code branch present, 32/32 tests have codes | **yes** (I2) | no | OPEN |
| V4 P1 | `fn_increment_batch_progress` | no guard, anon EXECUTE | **yes** (K3/K3b) | no | OPEN |
| V5 P1 | `fn_insert_system_message` | authenticated EXECUTE | **yes** (F6) | no | OPEN |
| V6 P2 | `test_syllabus` policy | legacy policy present | yes (G11) | no | OPEN |
| V7 P2 | announcement author | policy unchanged | yes (E2) | no | OPEN |
| V8 P2 | legacy direct status update | see F-07 | yes (G3/G4) | no | PRODUCT DECISION |
Errors in the G17 report: `group_rules` listed as a live table with RLS (absent); `fn_withdraw_join_request` "not applied" (it is live); `fn_get_group_role` "anon" grant (anon=false); "0 warnings" (1). Its migrations, however, are correct: all six were re-executed in-transaction today and behaved as documented.

### 4.4 Additional SECURITY DEFINER review (beyond G17)
All 90 public definer functions inventoried (`g17_inventory.json`): owner `postgres` for all; only `handle_new_user` lacks `search_path`; no dynamic SQL found; anon-executable set listed in F-15. Bodies read for every function the client or legacy calls: R4 RPCs are creator-gated via `_fn_can_update_test/_fn_can_manage_questions` (`created_by = uid`, status draft/published); `_fn_start_attempt_core` requires creator/member/`fn_can_access_test`; `rpc_save_answers`/`rpc_submit_attempt`/`rpc_log_integrity`/`rpc_get_live_questions` are own-attempt only; `rpc_get_questions_for_pdf` is gated by `fn_can_download_question_paper` and returns no `correct_option`; `fn_reset_group_invite`, `fn_approve_group_join_request`, `fn_withdraw_join_request`, `fn_delete_group_message`, `fn_clear_group_chat`, `fn_mark_announcement_read`, `fn_soft_delete_test`, `rpc_delete_test`, `fn_invite_to_live_test`, `fn_respond_to_invitation`, `fn_cancel_test_invitation`, `fn_ensure_student_code` all check `auth.uid()` and ownership/permission on the target's own group. No new exploitable definer beyond F-02/F-04/F-05/F-06 was found.

### 4.5 Views
`questions_safe` and `v_tests_distribution` are `security_invoker=true`, SELECT-granted to authenticated, and `questions_safe` has no `correct_option` column; since the `questions` SELECT grant is revoked for authenticated, the view is unreadable by clients (consistent with G9 `permission denied`).

---

## 5. Backend Drift — LIVE_DB_DRIFT_MATRIX (`final_drift.js`, 2026-09-20)

| Migration | Repository | Applied live? | Evidence | Risk if unapplied | Action |
|---|---|---|---|---|---|
| G5_6 `rpc_find_profile_by_student_code` | yes | **YES** | function present | — | none |
| G5_7 `fn_withdraw_join_request` | yes | **YES** | function present (G5.8/G17 reports outdated) | — | update docs |
| G6 `group_rules` table + policies | yes | **NO** | table absent | G6 rules feature and G13 rules summary fail at runtime | owner apply (`docs/G6_GROUP_RULES_PRECHECK/POSTCHECK.sql`) |
| G7 announcements | conditional (table pre-existed) | n/a | 19 columns live | — | none |
| G8 chat | conditional (table pre-existed) | n/a | 9 columns live | — | none |
| G8_1 `fn_is_notification_allowed` fix | yes | **YES** | `group_mutes.is_muted = true` in body | — | none |
| G10_1 `rpc_create_test` CREATE_TEST | yes | **YES** | body contains check; G1b denied | — | none |
| G10_2 lifecycle guard | proposed | **NO** | no function/trigger | F-07 | product decision; alternative prepared |
| G11 `rpc_request_coach_reports` | proposed | **NO** | absent | coach-report request button fails | owner apply (`docs/G11_PRECHECK/POSTCHECK.sql`) |
| G14 drop legacy policy | yes | **NO** | policy present | **P0** | **apply now** |
| G16 revoke `fn_notify_group` | yes | **NO** | grant present | **P0** | **apply now** |
| G17_01 leaderboard | yes | **NO** | `access_code` branch present | P1 | apply |
| G17_02 batch progress | yes | **NO** | no guard; anon EXECUTE | P1 | apply |
| G17_03 system message revoke | yes | **NO** | authenticated EXECUTE | P1 | apply |
| G17_04 syllabus + author policies | yes | **NO** | legacy policies present | P2 | apply |
| FINAL_AUDIT invitation fix | new | **NO** | `expires_at` referenced | P1 functional | apply |
| FINAL_AUDIT lifecycle guard (alt. G10.2) | new | **NO** | — | F-07 | product decision |

Other live facts vs repository: no group-logo bucket exists (`Avatar`, `avatars`, `materials` only); cron = `my-prep-sweep` → `fn_sweep_deadlines()` every minute; `ai_jobs` 0 rows / no consumer; `notifications` not in the realtime publication.

---

## 6. Product Decisions Still Needed
1. **G10.2 vs legacy-compatible guard (F-07):** choose (a) apply G10.2 and retire the legacy direct status writes, or (b) apply `FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql`, which keeps exactly `→ready`, `→cancelled`, `→archived` and schedule edits for clients and blocks status escalation, `created_by`, `group_id`, `test_mode`, soft-delete changes (proven 18/18: RPC publish, attempt start, soft-delete, cron sweep unaffected).
2. **G12 F1:** hide the rank for members, or expose the true rank through `rpc_get_leaderboard` (safe only after G17-01).
3. **Soft-deleted chat messages (F-11):** filter server-side, client-side with a placeholder, or accept.
4. **Owner transfer / group deletion:** not implemented in Flutter; the DB forbids owner transfer (`fn_protect_group_owner`, `fn_protect_group_member_identity`) and the legacy app's transfer action is therefore also dead. Decide whether an RPC is wanted.
5. **Group logo upload:** no bucket/policy; Flutter offers display + remove only.
6. **AI coach reports:** no `ai_jobs` worker exists; applying G11 only enables *queuing*.
7. **Invitation expiry:** `status='expired'` exists but nothing sets it and there is no `expires_at`; the FINAL_AUDIT fix removes the dead branch rather than adding a column.

---

## 7. Device Acceptance Gaps
- **VERIFIED (automated):** `flutter analyze` 0 errors / 1 warning; `flutter test` **982 passed** (incl. untracked G15 31 + G18 50); `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` √ Built; route table contains every Group Hub route (`/groups`, `/groups/create`, `/groups/join`, `/groups/:id`, `/members`, `/settings`, `/notifications`, `/tests`, `/tests/:testId/results`, `/leaderboard`) plus R4 test routes; single-flight guards and server re-reads are covered by the controller tests.
- **NOT VERIFIED — DEVICE REQUIRED:** every item of `docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` (0/66): auth, dashboard, group create/join, hub load, members, invites (which will fail until F-06 is fixed), join requests, rules (will fail: table absent), announcements, chat, notifications, tests create/manage/live/results/leaderboard, settings, leave/remove, back navigation, refresh, stale state, permission-denied states, cross-group behaviour. No device was attached during any G phase after G8.1.

---

## 8. Legacy Compatibility (`My-Prepration/src`)
Still in the repository (last change 2026-09-16); deployment status unknown. User-session operations that interact with the hardening:
| Operation | Table / fn | Current live authorization | Effect of prepared migrations |
|---|---|---|---|
| role change `group_members.update({role})` | `role changes` policy | MANAGE_ROLES | unaffected by G14 (legacy FOR ALL policy dropped only) |
| member remove / leave `group_members.delete` | `manage members` / `self leave` | ok | unaffected |
| owner transfer (`settings/actions.ts:124-129`) | `groups.owner_id` + role updates | **already blocked** by triggers (C8) | unaffected (already dead) |
| createGroup direct owner insert | `group creator adds self as owner` | ok | unaffected (proven G14 L20) |
| lifecycle `tests.update({status: ready/cancelled/archived})` | `group edit test` / standalone owner | ok | **broken by G10.2; kept by the FINAL_AUDIT guard** |
| `test_syllabus.insert` by creator | FOR ALL member policy | ok | kept by G17-04 (creator branch) |
| `rpc_get_leaderboard` pages | code branch | ok | kept for creators/members/participants (G17-01) |
| `fn_increment_batch_progress` inline reports | no check | ok | kept for creator/GENERATE_RESULTS (G17-02) |
| `notifications.insert` (×5, user session), `results.update`, `ai_jobs.insert/update` (user session) | no policies | **already failing live** (no INSERT/UPDATE policies) | unaffected — pre-existing breakage, not caused by hardening |
| `fn_accept/decline_group_invitation` | — | **already failing** (F-06) | fixed by FINAL_AUDIT migration (parameter name unchanged) |
| service-role paths (`profile/actions.ts` account deletion, push, reminders) | service role | ok | unaffected (guards exempt `service_role`/postgres) |

---

## 9. AI / Cost Safety
- Flutter contains **no AI client, key or endpoint** (`grep -i gemini|openai|ai_jobs lib` → only the G11 `rpc_request_coach_reports` call, whose function is absent live → the button fails, nothing is queued).
- Live: `ai_jobs` 0 rows, no worker, no cron touching it; `rpc_generate_results` is deterministic (`fn_score_attempt`), reads on results/leaderboard/notifications/hub screens create no `ai_jobs`/`ai_reports` (matrix K1: counts identical before/after all reads and mutations; G12/G16 proofs the same).
- Only the legacy web app calls Gemini (inline), with the user session; `ai_jobs` direct inserts from it fail under live RLS.
- After G11 is applied: one job per (test, batch) via idempotency key; no client path can create unbounded jobs (proven in G11 verification, still valid — function unchanged since it is not applied).

---

## 10. Secrets / Credential Risk
| Item | State | Risk | Action |
|---|---|---|---|
| Pooler DB password in `tool/*.js` (untracked, **not ignored**) | present, **valid** | HIGH | rotate in Supabase → delete `tool/` → add `tool/`, `node_modules/`, `package.json`, `package-lock.json` to `.gitignore` |
| `dart-defines.dev.json` | ignored (`dart-defines*.json`), untracked | ok | — |
| service-role key | only read from env in legacy `admin.ts`; never in Flutter or git | ok | — |
| git history | no committed `.env`/keys found; legacy docs mention env var *names* only | ok | — |
| APK | debug build; contains anon key + URL by design | expected | — |
| Anthropic/Gemini keys | none in repo | ok | — |

---

## 11. Recommended Fix Order
- **P0:** F-01 (apply G14), F-02 (apply G16)
- **P1:** F-03 (G17-01), F-04 (G17-02), F-05 (G17-03), F-06 (FINAL_AUDIT invitation fix + Flutter `p_invitation_id`), F-07 (decision → G10.2 or FINAL_AUDIT guard), F-12 (rotate credential)
- **P2:** F-08/F-09 (G17-04), F-10 (G12 F1 decision), F-11 (soft-deleted chat decision); apply G6 and G11 backends (functional)
- **P3:** F-13, F-14, F-15, F-16, F-17, F-18

---

## 12. Exact Next Actions
| # | File / migration | Problem | Minimal fix | Precheck | Postcheck | Rollback | Regression |
|---|---|---|---|---|---|---|---|
| 1 | `migrations/G14_drop_legacy_group_members_policy.sql` | F-01 | `DROP POLICY "Users can manage group members"` | `docs/G14_PRECHECK.sql` | `docs/G14_POSTCHECK.sql` | recreate policy (in file) | re-run matrix A + L1–L4 (post run: pass) |
| 2 | `migrations/G16_revoke_fn_notify_group_execute.sql` | F-02 | REVOKE from PUBLIC/anon/authenticated | `docs/G16_PRECHECK.sql` | `docs/G16_POSTCHECK.sql` | GRANT (in file) | chat/announcement delivery (post L5b) |
| 3 | `migrations/G17_01_fix_rpc_get_leaderboard_access.sql` | F-03 | body: creator ∨ member ∨ participant; anon revoked | `docs/G17_PRECHECK.sql` | `docs/G17_POSTCHECK.sql` | previous body (precheck output) | legacy leaderboard pages; post I1–I3b |
| 4 | `migrations/G17_02_fix_fn_increment_batch_progress.sql` | F-04 | authorize creator/GENERATE_RESULTS/service_role; anon revoked | G17 pre | G17 post | previous one-line body | legacy inline reports (post K3c) |
| 5 | `migrations/G17_03_revoke_fn_insert_system_message_execute.sql` | F-05 | REVOKE from authenticated/anon | G17 pre | G17 post | GRANT | system messages via triggers (post L15) |
| 6 | `migrations/FINAL_AUDIT_fix_group_invitation_accept_decline.sql` + `lib/features/group/data/group_repository.dart` lines 617/626 (`p_invite_id` → `p_invitation_id`) | F-06 | remove `expires_at` branch; keep param name; client param rename | `docs/FINAL_AUDIT_fix_group_invitation_accept_decline_PRECHECK.md` | `…_POSTCHECK.md` | previous bodies (precheck §2) | `test/group/incoming_invitations_test.dart`; live accept (post B6a/B6c) |
| 7 | `migrations/FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql` **or** `migrations/G10_2_fix_group_edit_test_policy.sql` | F-07 | BEFORE UPDATE guard (INVOKER) | `docs/FINAL_AUDIT_test_lifecycle_guard_legacy_compatible_PRECHECK.md` | `…_POSTCHECK.md` | drop trigger + function | guard proof 18/18; G10 tests |
| 8 | `migrations/G17_04_fix_test_syllabus_and_announcement_author_policies.sql` | F-08/F-09 | replace two policies | G17 pre | G17 post | verbatim policies in file | legacy syllabus insert (post G11c), announcements (post L6/L6b) |
| 9 | `migrations/G6_GROUP_RULES.sql`, `migrations/G11_rpc_request_coach_reports.sql` | features not live | apply as documented | `docs/G6_*_PRECHECK.sql`, `docs/G11_PRECHECK.sql` | matching postchecks | in files | `group_rules_test`, `group_test_results_test` + live re-proof |
| 10 | Supabase dashboard + `.gitignore` | F-12 | rotate pooler password; ignore `tool/`, `node_modules/`, `package*.json`; delete `tool/` | — | `git check-ignore tool/` | — | re-run any live proof with the new credential |
| 11 | `lib/features/group/screens/group_leaderboard_screen.dart:156-163` | F-10 | show rank only for analytics holders/owner, or use `rpc_get_leaderboard` after #3 | — | — | — | `group_leaderboard_test` |
| 12 | `docs/G17_GROUP_HUB_SECURITY_AUDIT_REPORT.md`, `docs/G18_ACCEPTANCE_MATRIX.md`, `test/group/group_acceptance_test.dart:12` | F-17 | correct the three false claims; remove unused import | — | `flutter analyze` 0 warnings | — | — |
| 13 | `git add` G15/G18 artifacts | F-18 | commit deliberately (both suites pass) | — | — | — | — |
| 14 | Physical device | §7 | execute the 66-item checklist after #1–#8 | — | — | — | — |

**Application order that keeps every proof valid:** 1 → 2 → 3 → 4 → 5 → 6 → 8 (all six were executed together in the post-fix matrix), then 7 after the product decision, then 9. Apply each in the SQL Editor, run its POSTCHECK, then re-run `g17_matrix.js pre` (the expectations for closed gaps flip to the `post` values).

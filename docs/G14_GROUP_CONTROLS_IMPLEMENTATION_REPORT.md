# G14 — Group Owner / Leader / Moderator Controls: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `5295c56` (G13 committed by the other agent) · **Commit:** `51316f5` · **Date:** 2026-09-19
**Role:** implementer only (not audited). G13 (`group_settings_screen.dart`, its report/tests), G12 F1, G10.2, G11 backend, G9 untouched. G15 not started.

## FINAL STATUS

**G14 IMPLEMENTATION COMPLETE — BACKEND PENDING (OWNER APPLY REQUIRED)**

The Flutter control layer works against the live schema as it is today — no new table, function, enum or policy is needed for it. "Backend pending" is a **live security defect found by the G14 live-first audit** (§2, §8): a legacy `group_members` policy lets a member self-promote to leader and lets any signed-in user insert themselves into any group. The one-statement migration that closes it is written, proven in a rolled-back transaction (39/39), and **not applied**.

---

## 1. Scope

Expose the existing owner / leader / moderator management actions in one permission-driven place, on top of the existing engine (`app_permission`, `fn_has_permission` with owner bypass, `role_permissions`, `group_members.role`), and add the one management action the backend already supports but no client offered: editing `role_permissions` per role (the only way a moderator can ever hold a permission). No new permission system, dashboard, repository or engine.

## 2. Live-first schema findings (read-only grids + rolled-back probes, 2026-09-19)

| Object | Live state |
|---|---|
| `group_role` | `owner, leader, moderator, member` |
| `app_permission` | 12 values: GROUP_SETTINGS, MANAGE_MEMBERS, MANAGE_ROLES, CREATE_TEST, EDIT_TEST, GENERATE_QUESTIONS, REVIEW_QUESTIONS, PUBLISH_TEST, SCHEDULE_TEST, GENERATE_RESULTS, VIEW_GROUP_ANALYTICS, SEND_ANNOUNCEMENT |
| `groups` | `id, name, description, logo_url, invite_code, owner_id, created_at, privacy`; UPDATE = GROUP_SETTINGS ∨ owner; DELETE = owner; `trg_protect_group_owner` (no owner transfer) |
| `group_members` | PK `(group_id, user_id)`, `role group_role NOT NULL DEFAULT 'member'`, `joined_at`. Policies: SELECT `members see roster`; INSERT `group creator adds self as owner`, `join via invite code`; UPDATE `role changes` (`role <> 'owner' AND MANAGE_ROLES`, USING+CHECK); DELETE `manage members` (other row, not owner, MANAGE_MEMBERS), `self leave group`; **plus legacy `Users can manage group members` FOR ALL — USING `auth.uid() = user_id OR owner`, WITH CHECK `true`**. Triggers: `trg_owner_guard` (`fn_prevent_owner_removal`: CANNOT_REMOVE_OWNER / CANNOT_DEMOTE_OWNER), `trg_protect_group_member_identity` (group_id/user_id immutable; no row may become or stop being owner), system-message and notify triggers |
| `role_permissions` | PK `(group_id, role, permission)`; policies SELECT `members view perms` (`fn_is_member`), ALL `manage roles perms` (MANAGE_ROLES), INSERT `group creator seeds leader perms`. Live rows: leader × 10 per group (all but GROUP_SETTINGS, MANAGE_ROLES); **0 moderator rows, 0 member rows** |
| `group_member_permissions` / overrides | **do not exist** — `role_permissions` is the only mapping |
| `fn_has_permission(p_group, p_user, p_perm)` | SECURITY DEFINER, `search_path=''`; no row → false; owner → true; else `role_permissions` lookup |
| `fn_get_group_permissions`, `fn_get_group_role`, `fn_is_member` | SECURITY DEFINER, `search_path=''`, EXECUTE to authenticated |
| role update / member removal RPC | **none live** — role change is a direct UPDATE under `role changes`; removal a direct DELETE under `manage members`; the Flutter G3/G4 code already uses exactly these |
| join / invite lifecycle | `fn_join_group`, `fn_accept_group_invitation`, `fn_decline_group_invitation`, `fn_approve_group_join_request` (MANAGE_MEMBERS on the request's own group), `fn_withdraw_join_request`, `fn_reset_group_invite` (GROUP_SETTINGS ∨ owner) — all SECURITY DEFINER, already used by G5 |
| test permissions | `tests` policies + `rpc_create_test` (CREATE_TEST, G10.1 applied) as documented in G10 |
| announcements | INSERT/UPDATE/DELETE = SEND_ANNOUNCEMENT ∨ owner (G7) |
| notifications / mutes | `group_mutes` (own rows), `fn_is_notification_allowed`, `fn_notify_group`, `notification_settings` — untouched |
| roster live | 3 rows, all `owner` (3 groups); no leader/moderator/member rows exist yet |

**Live probe results before any change (rolled back):** a member and a moderator can `UPDATE … SET role='leader'` on their own row (the legacy USING branch matches `auth.uid() = user_id`); a non-member can `INSERT` themselves as `leader` of any group (WITH CHECK `true`). Everything else behaves as intended: a leader without MANAGE_ROLES matches 0 rows; owner row can't be demoted/removed (triggers); no second owner; cross-group targets match 0 rows; group_id change raises; a leader without MANAGE_ROLES can't write `role_permissions`; a removed leader has no permission and is not a member; anon is denied everywhere.

## 3. Existing infrastructure reused

`GroupRepository` / `SupabaseGroupRepository` (single data source), `permissionsFor` (one `fn_has_permission` probe per value, parallel), `GroupHubController` (probes, `_run` single-flight, `load()` re-read), `GroupPermissions`, `GroupRole`, `GroupErrors`, G1 hub, G3 role menu (`MemberTile`), G4 remove / invite sheet / join-request queue / outgoing invitations, G5 lifecycle functions, G6 rules, G7 announcements, G8 chat, G10 tests screen (probes its own CREATE/EDIT/PUBLISH/SCHEDULE_TEST), G11 results (GENERATE_RESULTS / VIEW_GROUP_ANALYTICS), G12 leaderboard, `InMemoryGroupRepository` fake (`roleGrants`), router routes `/groups/:id/{settings,members,tests}`.

## 4. Files changed

| File | Change |
|---|---|
| `lib/features/group/domain/group_controls.dart` | **new** — `GroupControls` (pure gating over server-reported permissions + owner bypass), `RolePermissionRules` (editable roles = leader, moderator; live permission values only), `GroupRolePermissions` (parsed `role_permissions` rows), permission labels |
| `lib/features/group/data/group_repository.dart` | `rolePermissions(groupId)` (select `role, permission` by exact group id) and `setRolePermission(...)` (upsert with `ignoreDuplicates` / delete + `select` — 0 rows ⇒ error) |
| `lib/features/group/domain/group_errors.dart` | `GroupErrorContext.rolePermission` + messages |
| `lib/features/group/state/group_hub_controller.dart` | probes **all 12** live permissions on load; `controls`, `hasManagementControls`, `canManageRolePermissions`, `rolePermissions` state, `loadRolePermissions()` (single-flight, gated), `setRolePermission()` (invariants, `_run`, matrix + own probes re-read); permissions and matrix are cleared when access is denied |
| `lib/features/group/widgets/group_management_section.dart` | **new** — "Manage" card: Settings / Members / Role permissions / Tests / Results & leaderboards / Announcements rows, each gated |
| `lib/features/group/widgets/role_permissions_sheet.dart` | **new** — leader ⟷ moderator matrix of the 12 permissions, one server write per toggle, server re-read |
| `lib/features/group/screens/group_hub_screen.dart` | mounts the section (nothing for a plain member); `_openRolePermissions` |
| `test/group/fakes.dart` | `rolePermissions` / `setRolePermission` mirroring the live policies; seeded leader rows + `roleRevokes`; `hasPermission` now reads the same rows |
| `test/group/group_core_test.dart` | two stubs on `_FailingRepository` |
| `test/group/group_controls_test.dart` | **new** — 29 tests |
| `migrations/G14_drop_legacy_group_members_policy.sql`, `docs/G14_PRECHECK.sql`, `docs/G14_POSTCHECK.sql` | backend (pending) |

Not touched: `group_settings_screen.dart`, G13 report/tests, G9–G12 files, router, any G10/G11/G12 screen.

## 5. Controls implemented

- **Manage section (hub)** — shown only when `GroupControls.hasAnyManagement`:
  - *Group settings* → existing `/settings` (GROUP_SETTINGS ∨ owner)
  - *Members* → existing `/members`; subtitle "invite & remove" (MANAGE_MEMBERS) · "change roles" (MANAGE_ROLES)
  - *Role permissions* → new sheet (MANAGE_ROLES ∨ owner)
  - *Tests* → existing G10 screen; subtitle lists granted capabilities (create · edit · publish · schedule · results)
  - *Results & leaderboards* → G10 screen → per-test G11/G12 (VIEW_GROUP_ANALYTICS ∨ owner)
  - *Announcements* → note pointing to the existing section's controls (SEND_ANNOUNCEMENT ∨ owner)
- **Role permissions sheet** — per role (leader / moderator) a switch per live permission; grant = upsert, revoke = delete; after every toggle the matrix **and the caller's own probes** are re-read from the server (a leader editing the leader row changes themselves).
- Existing controls unchanged: app-bar Invite / Settings icons, member tile role menu / remove, join-request queue, outgoing invitations, leave.

## 6. Permission matrix actually supported (live)

| Capability | Server rule | Owner | Leader (seeded) | Moderator (seeded) | Member |
|---|---|---|---|---|---|
| Group settings / invite code / rules | GROUP_SETTINGS ∨ owner | ✓ | — | — | — |
| Invite / remove / join requests | MANAGE_MEMBERS | ✓ | ✓ | — | — |
| Change roles (not owner, not self, never *to* owner) | MANAGE_ROLES | ✓ | — | — | — |
| **Edit role permissions** (G14) | MANAGE_ROLES (`manage roles perms`) | ✓ | — | — | — |
| Create / edit / publish / schedule tests | CREATE/EDIT/PUBLISH/SCHEDULE_TEST | ✓ | ✓ | — | — |
| Generate results / request reports | GENERATE_RESULTS | ✓ | ✓ | — | — |
| All results / leaderboard | VIEW_GROUP_ANALYTICS | ✓ | ✓ | — | — |
| Announcements | SEND_ANNOUNCEMENT ∨ owner | ✓ | ✓ | — | — |
| Chat, read rules/announcements, own results, leave | member | ✓ | ✓ | ✓ | ✓ |

"—" for moderator is the live seeding, not an assumption: once the owner grants a moderator permission through the new sheet, the corresponding control appears (proven live: L14/L15 — moderator posts an announcement after the grant).

## 7. Owner / leader / moderator safety rules

| Rule | Where enforced |
|---|---|
| owner cannot be removed | `trg_owner_guard`; `manage members` excludes owner rows; client refuses |
| owner cannot be demoted | `trg_owner_guard`, `trg_protect_group_member_identity`, `role changes` USING `role <> 'owner'`; client refuses |
| no second owner / no transfer | `trg_protect_group_member_identity` CHECK; `assignableRoles` never includes owner |
| leader cannot modify owner role | `role changes` USING; proven (A7/A8/L7) |
| moderator / member cannot self-escalate | **after G14 migration**: no policy matches the caller's own row (A1/A2); client never offers self |
| member cannot self-promote / non-member cannot self-insert | **after G14 migration** (A1, A3, A4, A5) |
| invalid role transitions | enum + triggers; client `assignableRoles` |
| cross-group ids | every policy is evaluated on the row's own `group_id` (A12, A13, L7); client only targets users in the loaded roster; probes only against the target group |
| removed users lose management | `fn_has_permission` → false, `fn_is_member` → false (L21/L22); controller clears permissions and matrix on access denial |
| owner never a `role_permissions` row; member role never granted | `RolePermissionRules` (client); the live table would accept both — documented product rule |
| MANAGE_ROLES holder self-edits | can change their **own** row to leader/moderator/member (L7b) — no escalation is possible (owner blocked, L7c); documented |

## 8. Backend changes (PENDING — owner apply)

`migrations/G14_drop_legacy_group_members_policy.sql`:
```sql
DROP POLICY IF EXISTS "Users can manage group members" ON public.group_members;
```
plus a read-only postflight and a verbatim rollback in comments. No table, column, enum, function, trigger, grant or other policy changes. The six specific policies and the SECURITY DEFINER lifecycle functions cover every legitimate path; the legacy web app's direct `group_members` writes (owner self-insert on create, role update, delete) are all covered by the specific policies (proven L18/L20 for the legacy paths).

**Rolled-back proof (39/39, live, residue 0 — legacy policy still present live):** attacks A1–A13 all fail after the drop (self-promotion → 0 rows; non-member / cross-user inserts → RLS error; owner demote/remove → 0 rows, trigger still behind it); legitimate L1–L23 all work (owner role changes, MANAGE_MEMBERS removal, Flutter matrix select/upsert/delete statements, MANAGE_ROLES gained/lost dynamically, self-leave, `fn_join_group`, `join via invite code` insert, `fn_create_group`, legacy direct owner insert, removed leader loses everything, anon denied).

Owner steps: SQL Editor → `docs/G14_PRECHECK.sql` (expect `legacy_present = true`) → run the migration → `docs/G14_POSTCHECK.sql` (expect `legacy_policy_count 0`, `remaining_policy_count 6`, `all_cmd_policies 0`).

## 9. Backend pending items

1. **G14 migration above** (security; owner apply). Until applied, the client-side invariants are UX only and the live self-promotion / self-insert gap remains open to anyone with the anon key.
2. Unchanged from earlier phases: G6 `group_rules` migration, G10.2 (product decision), G11 `rpc_request_coach_reports`, `ai_jobs` worker.
3. Credentials in untracked `tool/` (delete + rotate — unchanged recommendation).

## 10. Tests added (`test/group/group_controls_test.dart`, 29) — unit / UI over the mirrored fake, **not** live proof

1 owner sees every Manage row · 2 owner cannot be demoted/removed/duplicated via controller · 3 leader (seeded) sees tests/analytics/announce/members, not settings/role-permissions; role menu absent without MANAGE_ROLES · 4 leader without MANAGE_ROLES: changeRole and matrix edit refused locally, nothing sent; leader granted MANAGE_ROLES gains the control, revoked leader loses tests · 5 moderator with granted SEND_ANNOUNCEMENT + MANAGE_MEMBERS gets exactly those and can remove · 6 moderator without permission: no section, remove refused by the (fake) server · 7 member sees no management control; non-management navigation intact · 8 forged group id: denied, no probe, no matrix read · 9 cross-group member is not a target; probes only against the target group · 10 nobody can change their own role at any role; MANAGE_ROLES holder cannot grant owner/member role · 11 owner invariants (see 2) · 12 removed member: access denied, controls and matrix cleared, mutation refused · 13 `loadRolePermissions` single-flight and gated; mutations single-flight · 14 grant/revoke re-read matrix and own probes; no-op sends nothing; server refusal re-reads (no optimistic state) · 15/16 G3/G4 keys, G6/G7/G8 sections, G10 button, members entry still render; pure `GroupControls` / `RolePermissionRules` / parsing tests; sheet and section widget tests.

Live verification of the same rules: `g14_probe.js` (before) and `g14_proof.js` (after, with the migration applied inside the rolled-back transaction) — results in §2 and §8; scripts live in the session scratchpad, not the repo.

## 11–13. Validation

`flutter test` → **883 passed** (was 848 + 29 new + 6 from the concurrently committed G13) · `flutter analyze` → **0 errors, 0 warnings** (75 pre-existing info lints) · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built** `build\app\outputs\flutter-apk\app-debug.apk`. Device/Chrome run: not performed (no device attached).

## 14. Security considerations

- No new authorization surface: every new write is a direct `role_permissions` row under the existing `manage roles perms` policy; identity is `auth.uid()`; the client never passes a user id as authorization.
- No service-role key; no `correct_option`; no `questions` read.
- 12 parallel `fn_has_permission` probes per hub load (STABLE, SECURITY DEFINER) — same probe as before, wider list; a failed probe reads as "not granted".
- Revoke is `delete … select` so a policy refusal is an error, never a silent success.
- The Manage section and matrix are cleared the moment `groupForMember` returns null (removed member).
- **Open until the migration is applied:** self-promotion and self-insert into any group (found by this phase, not introduced by it).

## 15. Known limitations

- `role_permissions` is per role, not per member (live design); the sheet edits leader/moderator only.
- A MANAGE_ROLES holder may change their own row to a lower role (live policy); harmless, documented.
- No group-level analytics page exists; "Results & leaderboards" routes to the tests list (per-test G11/G12).
- Live groups currently hold only owners, so leader/moderator behaviour was verified with rolled-back fixtures, not with real leaders.
- Realtime not used (as in G8).

## 16. Commit

`51316f5` — G14 implementation (this report included). Hash recorded in the follow-up commit.

# G3 — Group Roles & Permission Engine: Live Audit Evidence and Closure

**Status: CLOSED (2026-09-18). No backend migration was required or executed.**

The read-only audit `migrations/G3_LIVE_ROLE_PERMISSION_INSPECT.sql` was run by
the project owner in the Supabase SQL Editor (project `cnwtprexxjrajcdjhfsr`)
and the returned grid was verified manually. Every item below is **LIVE**
evidence from that grid, not inference from the legacy migration files.

## Live facts (verbatim from the audit grid)

| # | Object | Live result |
|---|---|---|
| 1 | `app_permission` enum | 12 values: `GROUP_SETTINGS, MANAGE_MEMBERS, MANAGE_ROLES, CREATE_TEST, EDIT_TEST, GENERATE_QUESTIONS, REVIEW_QUESTIONS, PUBLISH_TEST, SCHEDULE_TEST, GENERATE_RESULTS, VIEW_GROUP_ANALYTICS, SEND_ANNOUNCEMENT` |
| 2 | `group_role` enum | `owner, leader, moderator, member` |
| 3 | `role_permissions` rows | **leader** holds 10 permissions in all 3 groups: `CREATE_TEST, EDIT_TEST, GENERATE_QUESTIONS, GENERATE_RESULTS, MANAGE_MEMBERS, PUBLISH_TEST, REVIEW_QUESTIONS, SCHEDULE_TEST, SEND_ANNOUNCEMENT, VIEW_GROUP_ANALYTICS`. Leader does **not** hold `GROUP_SETTINGS` or `MANAGE_ROLES`. No rows for owner / moderator / member. |
| 4 | `group_members` UPDATE policy "role changes" | **USING** `(role <> 'owner') AND fn_has_permission(group_id, auth.uid(), 'MANAGE_ROLES')` · **CHECK** `(role <> 'owner') AND fn_has_permission(group_id, auth.uid(), 'MANAGE_ROLES')` |
| 5 | Triggers on `group_members` | `trg_owner_guard` (fn_prevent_owner_removal), `trg_role_changed_system`, `trg_protect_group_member_identity` — all present and enabled |
| 6 | `fn_has_permission(uuid, uuid, app_permission) → boolean` | SECURITY DEFINER, `search_path=''`, STABLE, `owner_bypass=true` (intentional: owner → true), `self_ref=false` |
| 7 | `fn_get_group_role(uuid, uuid) → group_role` | SECURITY DEFINER, `search_path=''`, STABLE |
| 8 | `fn_is_member(uuid, uuid) → boolean` | SECURITY DEFINER, `search_path=''`, STABLE |
| 9 | `fn_get_group_permissions(uuid, uuid) → app_permission[]` | SECURITY DEFINER, `search_path=''`, STABLE |
| 10 | Role-management RPCs | **none exist** |
| 11 | `multi_owner` | 0 (groups=3, with_owner_row=3) |
| 12 | `owner_row_mismatch` | 0 |

## What this settles

The finding carried from G1/G2 — that the UPDATE policy contained
`OR user_id = auth.uid()` — described the **legacy migration file**, not the
live database. The live policy already:

- blocks self-role escalation (no self branch; `MANAGE_ROLES` required),
- prevents owner rows from being targeted (`role <> 'owner'` in USING),
- prevents any row becoming owner (`role <> 'owner'` in CHECK),
- is backed by `trg_owner_guard` for delete/demote protection.

Consequently the G3 security migration and the proposed `rpc_set_member_role`
are **not needed**. `SupabaseGroupRepository.setMemberRole` remains a direct
`group_members` UPDATE, which the live policy is the security boundary for.

Owner leave: `trg_owner_guard` raises `CANNOT_REMOVE_OWNER` on deleting an
owner row, so the owner cannot leave server-side either; the Flutter client
refuses up front with the same outcome. Ownership transfer remains out of
scope (no live mechanism).

## Flutter state at closure

- `GroupPermission` (12 live labels) / `GroupPermissions` — `lib/features/group/domain/group_permission.dart`
- `permissionsFor()` = one `fn_has_permission` probe per value — `lib/features/group/data/group_repository.dart`
- Hub gating from server-reported `MANAGE_MEMBERS` / `MANAGE_ROLES` / `GROUP_SETTINGS`; `changeRole` invariants (never self, never owner, never to owner, roster-only target, assignable roles only, single in-flight) — `lib/features/group/state/group_hub_controller.dart`
- Role badge + role menu with confirmation — `lib/features/group/screens/group_hub_screen.dart`, `widgets/role_badge.dart`
- Test fakes mirror the **live** policy text above — `test/group/fakes.dart`, `test/group/group_roles_test.dart`

## Carried forward (not G3 defects)

- `moderator` holds no permissions by default; assigning any is a product
  decision for the Members Hub / roles UI (G4+), done through `role_permissions`
  rows, not schema.
- `GROUP_SETTINGS` is granted to no role by default (owner only via bypass).
- `trg_protect_group_member_identity` exists live and was not in the legacy
  files; its body should be read before any phase that updates
  `group_members` columns other than `role`.

## Next phase

**G4 — Members Hub**: full member list (search, role filter, profile embed),
join-request queue (`group_join_requests`, `fn_approve_group_join_request`),
invitations (`group_invitations`, accept/decline RPCs), and the role UI built
on the G3 engine. No schema work is expected; `fn_get_group_permissions` may
replace the per-permission probes once its live return shape is observed.

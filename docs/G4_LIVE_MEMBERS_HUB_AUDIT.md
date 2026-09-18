# G4 — Members Hub: Live Audit (read-only)

**Status: AUDIT PREPARED — awaiting the live grid. No implementation, no SQL writes.**

Run [`migrations/G4_LIVE_MEMBERS_HUB_INSPECT.sql`](../migrations/G4_LIVE_MEMBERS_HUB_INSPECT.sql)
in the Supabase SQL Editor (project `cnwtprexxjrajcdjhfsr`). It is one
`WITH … SELECT`; it contains no `ALTER / CREATE / DROP / INSERT / UPDATE /
DELETE`. It returns one grid `section | object | name | detail`. Paste the
whole grid back; nothing in this document is LIVE until that grid exists.

> If the statement fails with `relation "public.group_join_requests" does not
> exist` (or the same for `group_invitations`), that failure **is** the answer
> to audit items 3/4 for that table: delete the `counts_requests` /
> `counts_invites` / matching `isolation` lines and re-run — the rest of the
> grid still answers everything else.

## 1. What the grid answers, by section

| `section` | What it proves | Audit item |
|---|---|---|
| `exists` | whether `group_members`, `group_join_requests`, `group_invitations`, `profiles`, `groups`, `role_permissions` are real tables | 1, 3, 4 |
| `column` | exact columns, types, nullability, defaults for the three membership tables and `profiles` | 1, 2, 3, 4 |
| `constraint` | PKs, FKs (with `ON DELETE`), UNIQUEs, CHECKs | 1, 3, 4 |
| `fk_to_profiles` | the live FK from `group_members.user_id` (and request/invitation user columns) to `profiles.id` — what makes the PostgREST embed `profiles(...)` legal | 2 |
| `rls` | enabled/forced per table | 1, 3, 4, 6 |
| `policy` | **every** policy with full `USING` / `WITH CHECK` text, including `profiles` (what fields members may read of each other) and `groups` | 1, 2, 3, 4, 6 |
| `table_grant` | anon/authenticated table privileges | 1, 3, 4 |
| `trigger` | every trigger on the three tables with timing and events | 1 |
| `trigger_fn_body` | the **complete live body** of `fn_protect_group_member_identity`, `fn_prevent_owner_removal`, `trg_role_changed_system` and any other attached function | 1 (F, G) |
| `function` | signature/return/definer/config/volatility/grants of every function whose name mentions member/join/invit/request/role/permission/group | 3, 4, 5 |
| `function_body` | complete bodies of the join-request / invitation functions and of `fn_join_group`, `fn_get_group_permissions`, `fn_get_group_role`, `fn_is_member`, `fn_has_permission` | 3, 4, 5 |
| `realtime` | which of these tables are in `supabase_realtime` and their replica identity | 7 |
| `row_count` | members by role; requests and invitations by status | 3, 4 |
| `isolation` | users in >1 group; pending requests/invitations that already belong to members (stale state) | 6 |
| `g3_unchanged` | the current text of the G3 "role changes" policy — must still read `(role <> 'owner') AND fn_has_permission(... 'MANAGE_ROLES')` on both USING and CHECK | 5 |

## 2. Questions A–M and the exact rows that decide them

| Q | Decided by | Decision rule |
|---|---|---|
| **A** list all members | `policy` on `group_members` (SELECT) | must be `fn_is_member(group_id, uid)` or equivalent, not `user_id = uid` |
| **B** search/filter without widening RLS | same SELECT policy + `column` for `profiles` + `policy` on `profiles` | filtering by `full_name` is only safe if the embed columns are all covered by the profiles SELECT policy for fellow members; otherwise filter client-side on the already-returned roster |
| **C** change role via G3 | `g3_unchanged` | text unchanged ⇒ reuse `setMemberRole` as is |
| **D** remove member | `policy` on `group_members` (DELETE, non-self branch) + `trigger_fn_body` | `MANAGE_MEMBERS` and `user_id <> uid`; the trigger body tells whether it is "owner only" or wider |
| **E** leave | `policy` (DELETE self branch) + `fn_prevent_owner_removal` body | self-delete allowed; owner refused by trigger |
| **F** `fn_protect_group_member_identity` | its `trigger_fn_body` row | read the body: expected to refuse changes to `group_id` / `user_id` on UPDATE; confirm whether it touches `role` or `joined_at` |
| **G** `fn_prevent_owner_removal` | its `trigger_fn_body` row | confirm `CANNOT_REMOVE_OWNER` on DELETE and `CANNOT_DEMOTE_OWNER` on UPDATE of an owner row; confirm it does **not** block a second row becoming owner (the G3 policy does) |
| **H** list join requests | `policy` on `group_join_requests` (SELECT) | expected `user_id = uid OR fn_has_permission(group_id, uid, 'MANAGE_MEMBERS')` |
| **I** approve/reject | `function` + `function_body` for `fn_approve_group_join_request` (and any reject/cancel) | read the exact parameter list and status values it writes; `policy` UPDATE branch shows whether a direct update is also permitted |
| **J** accept/decline invitations | `function_body` for `fn_accept_group_invitation` / `fn_decline_group_invitation` + `policy` on `group_invitations` | invitee-only; confirm the status values and whether accept inserts the membership row |
| **K** state without leaking | `policy` SELECT text on both tables | a requester must only see their own rows; managers see the group's rows; nothing wider |
| **L** RPCs to reuse | `function` rows | anything named `*join_request*`, `*invitation*`, `*invite*`, `*member*` |
| **M** backend changes needed | all of the above | expected answer: **none** for list/role/remove/leave/requests/invitations if H–J hold; the only foreseeable gap is a user lookup for *sending* invitations (needs a way to resolve a `student_code` or email to a `profiles.id` without exposing the profiles table) |

## 3. Existing Flutter code — what G4 reuses (inspected, unchanged)

Direct Supabase calls today ([`group_repository.dart`](../lib/features/group/data/group_repository.dart)):

| Call | Backend object | Live status |
|---|---|---|
| `rpc('rpc_get_user_groups')` | RPC (D) | verified |
| `from('group_members').select('role')…` | membership check | verified (G1 Chrome) |
| `from('groups').select('id, name, description, logo_url, owner_id, privacy, created_at')` | explicit columns, no `invite_code` | verified |
| `from('group_members').count(exact)` | member count | verified |
| `from('group_members').select('group_id, user_id, role, joined_at, profiles(full_name, avatar_url)')` | roster + profile embed | verified |
| `rpc('fn_create_group', {p_name, p_description, p_privacy})` | create | signature verified (G1 audit), never executed |
| `rpc('fn_join_group', {p_invite_code})` | join / request | signature verified, never executed |
| `from('group_members').delete()` (self / other) | leave / remove | policy verified (G3 grid) |
| `from('group_members').update({'role'})` | role change | policy verified (G3 grid) |
| `rpc('fn_has_permission', {p_group, p_user, p_perm})` | permission probe | verified live |
| `from('groups').update({...})` | settings / clear logo | policy verified |

Models: [`Group`](../lib/core/models/group.dart) (7-column RPC row + optional profile fields), [`GroupMember`](../lib/core/models/group_member.dart) (assumes `group_id`, `user_id`, `role`, `joined_at`, optional embedded `profiles.full_name` / `avatar_url`). No model yet for join requests or invitations; no assumption about their columns exists in `lib/`.

Controllers/screens reused as-is: `GroupHubController` (roster, permissions, `changeRole`, `removeMember`, `leave`), `GroupListController`, `GroupHubScreen` member tiles (`RoleBadge`, role menu), `JoinGroupSheet`. The G3 permission engine (`GroupPermission`, `GroupPermissions`, `permissionsFor`) is the only permission source G4 may use.

Assumptions G4 must **not** add until the grid confirms them: any join-request / invitation column name, status value, or function parameter name; any `profiles` column beyond `full_name` / `avatar_url`; that `fn_get_group_permissions` returns an array PostgREST decodes as `List<String>`.

## 4. Proposed G4 sub-phases (to be confirmed against the grid)

| Sub-phase | Scope | Backend objects | SQL expected |
|---|---|---|---|
| **G4.1 Members list** | dedicated `/groups/:id/members` screen, role filter, client-side name search, role menu + remove reused from the hub | existing roster query | none |
| **G4.2 Join-request queue** | pending requests badge/list for `MANAGE_MEMBERS` holders; approve/decline; requester's own "pending" state on the join sheet | `group_join_requests`, `fn_approve_group_join_request(p_request_id, p_approve)` (if confirmed) | none |
| **G4.3 Incoming invitations** | "Invitations" section in the group list; accept/decline | `group_invitations`, accept/decline functions (if confirmed) | none |
| **G4.4 Outgoing invitations** | inviting a user by identifier | needs a user-lookup path — **likely the one backend dependency** (see M) | possibly one read-only RPC — not drafted |
| **G4.5 Realtime (optional)** | live roster/request updates | only if `realtime` rows show the tables are published and Realtime RLS authorization is enabled | none |

## 5. Blockers

None known before the grid. Nothing in `lib/` or `test/` was modified for this audit; the last validation (G3 closure) stands: analyze 0/0, 572 tests, APK built.

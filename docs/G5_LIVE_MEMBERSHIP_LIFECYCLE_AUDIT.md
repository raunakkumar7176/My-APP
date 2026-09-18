# G5 — Join / Invite / Membership Lifecycle: Forensic Audit

**G4 CLOSED** at `b66c641` (+ `228540b`). **G5 status: AUDIT PREPARED — no implementation, no SQL writes.**

Evidence classes used below:
- **[LIVE]** — verified against the live database earlier (G0 D postflight, G1 Chrome session, G3 audit grid run by the owner).
- **[LEGACY-SQL]** — from the migration set that built the live database (`My-Prepration/supabase/migrations/0001…0051`); high-confidence but *not* proof. Everything marked this way is confirmed or refuted by one read-only query: [`migrations/G5_LIVE_MEMBERSHIP_LIFECYCLE_INSPECT.sql`](../migrations/G5_LIVE_MEMBERSHIP_LIFECYCLE_INSPECT.sql) (single `WITH … SELECT`, no writes).
- **[UNKNOWN]** — nothing in the repo answers it; only the grid can.

## 1. Live schema findings

### `groups` [LIVE columns; policies LEGACY-SQL except UPDATE, which the G3 grid confirmed]
`id, name(1..80), description, logo_url, invite_code text NOT NULL UNIQUE (8 upper hex, default generated), owner_id → profiles, privacy CHECK(public|private|restricted), created_at`.
Policies: SELECT `fn_is_member(id, uid)` **and** SELECT `privacy = 'public'`; INSERT `owner_id = uid`; UPDATE `fn_has_permission(GROUP_SETTINGS) OR owner`; DELETE owner only.
→ `invite_code` is a column on a row that any member (and, for public groups, any signed-in user) can `SELECT`. The G1/G2 client never selects it; the legacy web client did. The grid's `policy` rows will show whether any column-level restriction exists (none is expected — Postgres RLS is row-level).

### `group_members` [LIVE]
PK `(group_id, user_id)`, `role group_role`, `joined_at`. Policies: SELECT members; INSERT creator-as-owner / "join via invite code" (`current_setting('invite.code')`, unused by Flutter); UPDATE "role changes" `(role <> 'owner') AND MANAGE_ROLES` (G3-verified); DELETE self ("self leave group") and `MANAGE_MEMBERS AND user_id <> uid` ("manage members"). Triggers: `trg_owner_guard` (`fn_prevent_owner_removal`: `CANNOT_REMOVE_OWNER` on DELETE of an owner row, `CANNOT_DEMOTE_OWNER` on UPDATE), `trg_role_changed_system`, `trg_protect_group_member_identity` (**body [UNKNOWN]** — expected to freeze `group_id`/`user_id`; the grid prints it), plus `trg_member_joined_system` / `trg_member_left_system` [LEGACY-SQL 0039] that post system chat messages.

### `group_invitations` [LEGACY-SQL 0010 → 0033]
`id, group_id → groups CASCADE, inviter_id → profiles, invitee_id → profiles, status text CHECK(pending|accepted|declined|expired) DEFAULT 'pending', created_at, UNIQUE(group_id, invitee_id)`. **No `expires_at`, no `updated_at`, no `responded_at`** (the `probe … has_expiry_column` row confirms). Policies: INSERT `inviter_id = uid AND MANAGE_MEMBERS`; SELECT `invitee = uid OR inviter = uid OR fn_is_member`; UPDATE invitee only; DELETE `inviter = uid OR MANAGE_MEMBERS`. Functions: `fn_accept_group_invitation(p_invite_id uuid) → void` (invitee + pending → inserts `group_members` row `ON CONFLICT DO NOTHING`, sets `accepted`; raises `INVITE_NOT_FOUND`), `fn_decline_group_invitation(p_invite_id uuid) → void` (invitee + pending → `declined`; raises `INVITE_NOT_FOUND`). **No create-invitation function** (direct INSERT under the policy), **no cancel function** (direct DELETE under the policy), **no expiry function** (`expired` status exists but nothing sets it — the only `fn_expire_*` is for `test_invitations`).

### `group_join_requests` [LEGACY-SQL 0033]
`id, group_id → groups CASCADE, user_id → profiles CASCADE, status text CHECK(pending|approved|declined) DEFAULT 'pending', created_at, UNIQUE(group_id, user_id)`. Policies: SELECT `user_id = uid OR MANAGE_MEMBERS`; INSERT `user_id = uid`; UPDATE `MANAGE_MEMBERS`; **no DELETE policy** → a requester cannot cancel (withdraw) their own request, and managers cannot delete either — only status changes. Functions: `fn_join_group(p_invite_code text) → uuid` (existing member → returns id; `restricted` → upsert request to `pending`, returns **NULL**; else inserts member), `fn_approve_group_join_request(p_request_id uuid, p_approve boolean) → uuid` (`MANAGE_MEMBERS`; approve → member row `ON CONFLICT DO NOTHING` + `approved`; else `declined`; raises `NOT_AUTHORIZED`).

### `group_mutes` [LEGACY-SQL]
PK `(user_id, group_id)`, `is_muted bool DEFAULT true`, `updated_at`; policy ALL own rows. **This is a notification preference, not a membership state** — it has no FK to membership and survives leaving. Out of G5's lifecycle scope except that leaving a group should not be blocked by it (it is not: no FK from mutes to members).

### Invite-code lifecycle
`fn_reset_group_invite(p_group uuid) → text` [LEGACY-SQL 0033]: `GROUP_SETTINGS OR owner`, generates a fresh unique 8-hex code, returns it. No "disable invites" flag exists; the only way to invalidate a code is to rotate it.

### Enums / statuses
`group_role` [LIVE]; `app_permission` [LIVE]; invitation/request statuses are **text CHECKs**, not enums (grid `constraint` rows confirm).

### Realtime [LEGACY-SQL 0037]
`group_members` is in `supabase_realtime` (REPLICA IDENTITY FULL); `group_invitations` / `group_join_requests` are **not** expected to be. Grid `realtime` rows confirm.

## 2. Existing reusable contracts (Flutter, already wired)

| Flutter call | Backend | Status |
|---|---|---|
| `GroupRepository.joinByCode` → `rpc('fn_join_group', {p_invite_code})` returning `JoinedGroup(id)` / `JoinRequestFiled` on NULL | `fn_join_group` | signature [LEGACY-SQL]; never executed live |
| `GroupRepository.leave` → `group_members.delete()` self | "self leave group" + `trg_owner_guard` | policy [LIVE] |
| `GroupRepository.removeMember` → `group_members.delete()` other | "manage members" | policy [LIVE] |
| `permissionsFor` → `fn_has_permission` | live | [LIVE] |
| `GroupHubController.canLeave` (owner refused client-side; server refuses via trigger) | | [LIVE] |
| `JoinGroupSheet` (code entry, "request sent" state) | | done |
| `GroupErrors.map` knows `INVALID_INVITE_CODE`, `NOT_AUTHORIZED`, `CANNOT_REMOVE_OWNER`, duplicate-key | | done; must add `INVITE_NOT_FOUND` |

## 3. Missing functionality (from the client's point of view)

| Need | Backend today | Gap |
|---|---|---|
| Show / copy / rotate invite code (owner, GROUP_SETTINGS) | column readable; `fn_reset_group_invite` | client only — but a **read must be an explicit single-column select scoped to the caller's permission**, never part of the list/hub reads |
| List my pending join requests (as requester) | SELECT policy `user_id = uid` | client only |
| Manager queue of pending requests + approve/decline | SELECT/UPDATE policies + `fn_approve_group_join_request` | client only |
| **Requester cancels own request** | no DELETE policy, no function | **backend gap** (see §7) |
| Incoming invitations list + accept/decline | SELECT policy + two functions | client only |
| **Send an invitation** | INSERT policy exists, but the client has **no way to resolve a target user to `profiles.id`**: `profiles` SELECT is `own row OR fellow member`, so a not-yet-member cannot be looked up by `student_code` | **backend gap** (see §7) |
| Cancel an outgoing invitation | DELETE policy | client only |
| Invitation expiry | `expired` status, no timer, no column | **not supported live** — do not fake it |
| Re-invite after decline | UNIQUE(group_id, invitee_id) blocks a second row | needs DELETE of the declined row first (inviter/MANAGE_MEMBERS may) — client-only workaround |
| Removed member loses access immediately | RLS is evaluated per request; hub reload returns "not a member" | already true; realtime not needed for correctness |
| Last-owner edge case | trigger prevents the owner row from being deleted or demoted; owner cannot leave; no transfer | already enforced; **group deletion is the only exit** (owner DELETE policy on `groups`, CASCADE to members) — not built in Flutter |

## 4. Security findings

1. **`invite_code` readability** — any member can read the code by selecting the column; for `public` groups, *any signed-in user* can. The privacy model therefore is: public = joinable by anyone who can find the code (and anyone can read it), private = need the code (only members can read it), restricted = code → request. G5 must not display the code to plain members in the UI (mirror `GROUP_SETTINGS`/owner), but must not claim the server hides it either. A stricter server-side rule would be a policy change — **out of scope unless you ask**.
2. **Join request has no withdraw path** and no expiry: a pending request lives until a manager acts. Low risk, poor UX.
3. **Invitation `expired` is dead state** — nothing produces it. Client must not show "expires in…".
4. **`fn_join_group` idempotency** — returns the group id for an existing member (no error); G1 client treats it as `alreadyMember`. Correct.
5. **Cross-group isolation** — every policy is keyed on the row's `group_id`; `fn_approve_group_join_request` reads the group from the request row, so a manager of group A cannot approve a request for group B. `trg_protect_group_member_identity` presumably stops re-pointing a membership row to another group — **confirm its body in the grid**.
6. **Owner protection** — complete for delete/demote/promote (G3). Owner leave: refused by trigger; client already refuses.
7. **Anon grants** — `fn_join_group` / `fn_create_group(3-arg)` / `fn_has_permission` were revoked from `anon` (0034); `fn_accept/decline_group_invitation`, `fn_approve_group_join_request`, `fn_reset_group_invite` grant lists are **[UNKNOWN]** — the grid prints them.

## 5. Proposed G5 phases (implementation only after the grid)

| Phase | Scope | Backend objects | SQL |
|---|---|---|---|
| **G5.1 Invite code (owner/settings)** | show code on the settings screen, copy, rotate via `fn_reset_group_invite`; explicit single-column select gated by `canEditBasics` | `groups.invite_code`, `fn_reset_group_invite` | none |
| **G5.2 Join lifecycle** | join sheet already done; add "your request is pending" state on the hub/list for restricted groups (`group_join_requests` where `user_id = uid`); handle `alreadyMember` and `INVALID_INVITE_CODE` (done) | `group_join_requests` SELECT | none |
| **G5.3 Manager request queue** | pending list with requester profile embed, approve / decline via `fn_approve_group_join_request`, badge count on the hub | `fn_approve_group_join_request` | none |
| **G5.4 Incoming invitations** | list on the Groups screen (invitee), accept → opens the group, decline; `INVITE_NOT_FOUND` mapping | accept/decline functions | none |
| **G5.5 Outgoing invitations (manager)** | list, cancel (DELETE), re-invite after decline (DELETE + INSERT) | policies | none — **but sending needs G5.6** |
| **G5.6 Send invitation** | needs a user lookup | **requires a backend read RPC** (see §7) | **yes — after approval** |
| **G5.7 Cancel own join request** | withdraw button | **requires a DELETE policy or RPC** (see §7) | **yes — after approval** |
| **G5.8 Lifecycle hardening** | removed-member access revocation walkthrough (hub reload → "not a member"), last-owner explanation, G1/G4 regression | none | none |

## 6. Backend changes actually required (design only — not drafted)

1. **User lookup for invitations** — one `SECURITY DEFINER` read function, e.g. `rpc_find_profile_by_student_code(p_code text) RETURNS TABLE(id uuid, full_name text, avatar_url text)`, `search_path=''`, authenticated-only, exact-match on `profiles.student_code`, returning at most one row and **no other profile columns**. Without it the invitation INSERT cannot be targeted. Alternative with zero SQL: invitations only by *invite code* (already works) — i.e. drop G5.6 from scope.
2. **Withdraw join request** — either a DELETE policy `user_id = auth.uid() AND status = 'pending'` on `group_join_requests`, or a tiny RPC. Alternative with zero SQL: no withdraw; the manager declines.

Both are additive; neither touches existing policies, `group_members`, `groups`, `role_permissions`, enums, or the G3 engine. Neither will be written until the grid confirms the tables and you approve the scope.

## 7. Frontend changes required (all reuse `GroupRepository` / `GroupHubController` / `GroupErrors`)

- Models: `GroupInvitation`, `GroupJoinRequest` (columns exactly as the grid prints them).
- Repository: `inviteCode(groupId)` (explicit column), `rotateInviteCode`, `myJoinRequest(groupId)`, `pendingJoinRequests(groupId)`, `decideJoinRequest(id, approve)`, `myInvitations()`, `acceptInvitation`, `declineInvitation`, `groupInvitations(groupId)`, `cancelInvitation(id)`.
- Controllers: extend `GroupHubController` (request queue + counts) and `GroupListController` (incoming invitations); a small `InviteCodeController` or a section in the settings screen.
- Screens: settings (code section), hub (requests badge/queue), groups list (invitations section), join sheet (pending state).
- `GroupErrors`: `INVITE_NOT_FOUND`, `NOT_AUTHORIZED` in the new contexts.

## 8. Blockers

- **Hard:** none for G5.1–G5.5, G5.8 (all live objects expected to exist; the grid confirms).
- **Scope decision needed:** G5.6 (send invitation by student code) and G5.7 (withdraw request) each need one additive backend change — or are dropped.
- **Verification dependency:** the grid must come back before any code, in particular the bodies of `trg_protect_group_member_identity`, `fn_accept_group_invitation`, `fn_approve_group_join_request`, and the grant lists on the lifecycle functions.

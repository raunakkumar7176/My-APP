# G18 Group Hub — Role / Permission Acceptance Matrix

**Flutter + Supabase Educational Platform — Group Hub Feature**
**Generated:** 2026-09-20

---

## Role Definitions

| Role | Description | Seeded Permissions |
|------|-------------|-------------------|
| **OWNER** | Group creator; bypasses all permission checks via `fn_has_permission` | All (bypass) |
| **LEADER** | Elevated role; receives default permissions on group creation | MANAGE_MEMBERS, CREATE_TEST, EDIT_TEST, GENERATE_QUESTIONS, REVIEW_QUESTIONS, PUBLISH_TEST, SCHEDULE_TEST, GENERATE_RESULTS, VIEW_GROUP_ANALYTICS, SEND_ANNOUNCEMENT |
| **MODERATOR** | Customizable role; no default permissions | None (granted individually) |
| **MEMBER** | Default role for all joiners | None |
| **NON-MEMBER** | Not a member of the group | N/A (no access) |
| **REMOVED MEMBER** | Previously a member; lost access | N/A (same as non-member) |
| **ANON** | Not authenticated | N/A (redirected to login) |

---

## Permission Acceptance Matrix

| Feature | OWNER | LEADER | MODERATOR | MEMBER | NON-MEMBER | REMOVED MEMBER | ANON |
|---------|-------|--------|-----------|--------|------------|----------------|------|
| Group Hub Visibility | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Settings Access | ✓ | ✗ (needs GROUP_SETTINGS) | ✗ | ✗ | N/A | N/A | N/A |
| Members View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Members Manage | ✓ | ✓ (MANAGE_MEMBERS) | ✗ (needs MANAGE_MEMBERS) | ✗ | N/A | N/A | N/A |
| Rules View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Rules CRUD | ✓ | ✗ (needs GROUP_SETTINGS) | ✗ | ✗ | N/A | N/A | N/A |
| Announcements View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Announcements CRUD | ✓ | ✓ (SEND_ANNOUNCEMENT) | ✗ (needs SEND_ANNOUNCEMENT) | ✗ | N/A | N/A | N/A |
| Chat Read | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Chat Send | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Tests View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Tests Manage | ✓ | ✗ (needs test perms) | ✗ | ✗ | N/A | N/A | N/A |
| Results View (own) | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Results View (all) | ✓ | ✗ (needs VIEW_GROUP_ANALYTICS) | ✗ | ✗ | N/A | N/A | N/A |
| Leaderboard View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Notifications View | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Notifications Mark Read | ✓ | ✓ | ✓ | ✓ | N/A | N/A | N/A |
| Join Request Queue | ✓ | ✓ (MANAGE_MEMBERS) | ✗ (needs MANAGE_MEMBERS) | ✗ | N/A | N/A | N/A |
| Outgoing Invitations | ✓ | ✓ (MANAGE_MEMBERS) | ✗ (needs MANAGE_MEMBERS) | ✗ | N/A | N/A | N/A |
| Role Permission Matrix | ✓ | ✗ (needs MANAGE_ROLES) | ✗ (needs MANAGE_ROLES) | ✗ | N/A | N/A | N/A |

---

## Detailed Permission Breakdown by Role

### OWNER

The owner bypasses all `fn_has_permission` checks. Every management control is always visible and functional. The owner cannot:
- Leave the group (no ownership transfer exists)
- Be demoted or removed by any role
- Have their role changed by anyone (client guard + RLS)

### LEADER (Default Seeded Permissions)

| Permission | Default | Notes |
|------------|---------|-------|
| MANAGE_MEMBERS | ✓ | Invite, remove, manage join requests |
| CREATE_TEST | ✓ | Create group tests via wizard |
| EDIT_TEST | ✓ | Edit draft tests |
| GENERATE_QUESTIONS | ✓ | Generate questions for tests |
| REVIEW_QUESTIONS | ✓ | Review generated questions |
| PUBLISH_TEST | ✓ | Publish and archive tests |
| SCHEDULE_TEST | ✓ | Set start/end dates |
| GENERATE_RESULTS | ✓ | Generate result batches and coach reports |
| VIEW_GROUP_ANALYTICS | ✓ | View all participant results and analytics |
| SEND_ANNOUNCEMENT | ✓ | Create, edit, delete announcements |
| GROUP_SETTINGS | ✗ | Not seeded; requires explicit grant |
| MANAGE_ROLES | ✗ | Not seeded; requires explicit grant |

### MODERATOR (No Default Permissions)

| Permission | Default | Notes |
|------------|---------|-------|
| All permissions | ✗ | No permissions seeded on creation |

Moderators gain capabilities only through explicit permission grants by the owner or a leader with MANAGE_ROLES.

### MEMBER (No Permissions)

Members have read access to all group content (rules, announcements, chat, tests, results, leaderboard) but cannot perform any management actions.

---

## Client-Side Gating Logic

The `GroupControls` class (`lib/features/group/domain/group_controls.dart`) determines which UI elements are shown:

```
_has(p) => isOwner || permissions.has(p)
```

| Control | Gating Rule |
|---------|-------------|
| `canOpenSettings` | `_has(GROUP_SETTINGS)` |
| `canManageMembers` | `_has(MANAGE_MEMBERS)` |
| `canManageRoles` | `_has(MANAGE_ROLES)` |
| `canManageRolePermissions` | `_has(MANAGE_ROLES)` |
| `canCreateTest` | `_has(CREATE_TEST)` |
| `canEditTest` | `_has(EDIT_TEST)` |
| `canPublishTest` | `_has(PUBLISH_TEST)` |
| `canScheduleTest` | `_has(SCHEDULE_TEST)` |
| `canGenerateResults` | `_has(GENERATE_RESULTS)` |
| `canViewAnalytics` | `_has(VIEW_GROUP_ANALYTICS)` |
| `canSendAnnouncement` | `_has(SEND_ANNOUNCEMENT)` |
| `canManageTests` | `canCreateTest \|\| canEditTest \|\| canPublishTest \|\| canScheduleTest` |
| `hasAnyManagement` | Any of the above is true |

---

## Role Permission Editability

| Target Role | Editable? | Notes |
|-------------|-----------|-------|
| Owner | Never | Owner is permitted by bypass; no `role_permissions` row exists |
| Leader | Yes | Via `RolePermissionRules.editableRoles` |
| Moderator | Yes | Via `RolePermissionRules.editableRoles` |
| Member | Never | Every joiner lands in this role; a grant would hand management to anyone |

---

## Backend Dependencies

| Operation | Backend Function/Policy |
|-----------|------------------------|
| Create group | `fn_create_group` RPC (creates group + owner row + leader permissions) |
| Join group | `fn_join_group` RPC (public: immediate; restricted: join request) |
| Leave group | Direct DELETE on `group_members` (RLS self-leave policy: `user_id = auth.uid()`) |
| Remove member | RLS DELETE on `group_members` (MANAGE_MEMBERS policy) |
| Role change | RLS UPDATE on `group_members` (MANAGE_ROLES policy, `role <> 'owner'` CHECK) |
| Settings update | RLS UPDATE on `groups` (GROUP_SETTINGS policy or owner) |
| Permission probe | `fn_has_permission(group_id, user_id, permission)` |
| Invite code | `fn_get_invite_code` / `fn_rotate_invite_code` RPCs |
| Join request decision | `fn_decide_join_request` RPC |
| Invitation management | `fn_accept_invitation` / `fn_cancel_invitation` RPCs |
| Rules CRUD | RLS on `group_rules` (GROUP_SETTINGS policy or owner) |
| Announcements CRUD | RLS on `group_announcements` (SEND_ANNOUNCEMENT policy or owner) |
| Chat messages | `fn_send_message` RPC + RLS on `group_messages` |
| Test management | RLS on `tests` + lifecycle RPCs (create, publish, schedule, etc.) |
| Results generation | `fn_generate_results` / `fn_request_coach_reports` RPCs |
| Notifications | RLS on `notifications` + read/mute RPCs |
| Owner protection | `trg_owner_guard` trigger prevents owner demotion/removal |
# R4.5.5 — GROUP DISCOVERY REPORT

## STATUS: DB MIGRATION REQUIRED

## Discovery Date
2026-09-13

## Executive Summary

**The `groups` and `group_members` tables do NOT exist in the live Supabase database.** No group model, service, screen, route, RPC, RLS policy, or permission infrastructure exists anywhere in the project. The entire group system is a documented gap with architectural designs but zero implementation.

Without these tables, there is NO WAY to:
- List groups a user belongs to
- Check group membership
- Validate group_id for test creation
- Enforce group-based permissions
- Make Group Test selection functional

**DATABASE MIGRATION IS GENUINELY REQUIRED.**

---

## A. Existing Group Tables

| Table | Status |
|-------|--------|
| `groups` | **DOES NOT EXIST** |
| `group_members` | **DOES NOT EXIST** |
| `role_permissions` | **DOES NOT EXIST** |

### What Exists Instead
- `tests.group_id` column (nullable UUID, no FK constraint) — created in R4.1 migration
- `idx_tests_group_id` index on `tests.group_id WHERE group_id IS NOT NULL`
- Documentation in `R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md` with full DDL designs

---

## B. Important Columns

### `tests.group_id` (ONLY group-related column in live DB)
```sql
-- From R4_1_phase_db_foundation.sql, line 121
group_id uuid, -- FK added after groups table exists (Phase R4.1 groups integration)

-- Line 140
COMMENT ON COLUMN public.tests.group_id IS 'Optional group association. NULL = personal test. FK to groups.id when groups table exists.';

-- Line 421
CREATE INDEX idx_tests_group_id ON public.tests (group_id) WHERE group_id IS NOT NULL;
```

**Note:** No FK constraint exists because the `groups` table doesn't exist yet.

---

## C. Existing Relationships/FKs

| Relationship | Status |
|--------------|--------|
| `tests.group_id` → `groups.id` | **NOT ENFORCED** (FK deferred until groups table exists) |
| `group_members.group_id` → `groups.id` | **TABLE DOES NOT EXIST** |
| `group_members.user_id` → `auth.users.id` | **TABLE DOES NOT EXIST** |

---

## D. Existing Roles

**NONE.** No role system exists.

The architecture spec (`R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md`) defines a future role system:
```sql
-- Future: group_members with role column
role text NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member'))
```

Permission matrix from spec (lines 1303-1316):
| Role | Permissions |
|------|-------------|
| `leader` | CREATE_TEST, EDIT_OWN_TEST, EDIT_ANY_TEST, PUBLISH_TEST, INVITE_USERS, VIEW_TEST, TAKE_TEST, VIEWOWN_ATTEMPT, VIEW_ALL_ATTEMPTS, GENERATE_RESULTS, VIEW_ALL_RESULTS, GENERATE_AI_REPORTS |
| `member` | VIEW_TEST, TAKE_TEST, VIEWOWN_ATTEMPT only |

**These roles do not exist in the database.**

---

## E. Existing Permissions

**NONE.** No permission system exists.

Every service file has a generic permission error handler that maps Supabase RLS "permission denied" errors to user-friendly messages. None of these relate to group permissions:
- `test_service.dart` line 421-422
- `question_service.dart` line 347
- `attempt_service.dart` line 108-109
- (and 9 other service files)

These are simple string-matching error handlers, not a permission system.

---

## F. Existing RPCs/Functions

### Group-Related RPCs
**NONE.** No group-related RPCs exist.

### Existing RPCs with Group Awareness

| RPC Function | Group Support | Notes |
|---|---|---|
| `rpc_create_test` | YES | Accepts `p_group_id` parameter, validates group_id required when test_mode='group' |
| `rpc_update_test` | **NO** | Does NOT accept `p_group_id` — cannot change group after creation |
| `rpc_publish_test` | YES | Validates `group_id IS NOT NULL` when `test_mode='group'` |

### Permission Helper Functions (EXIST but don't check groups)

| Function | Purpose |
|----------|---------|
| `_fn_auth_uid()` | Safe wrapper for `auth.uid()` |
| `_fn_can_create_test(uuid)` | Checks authenticated + is creator |
| `_fn_can_update_test(uuid, uuid)` | Checks authenticated + is creator |
| `_fn_can_manage_questions(uuid, uuid)` | Checks authenticated + is creator |

**None of these check group membership.** They only verify the user is authenticated and owns the test.

### Functions That DO NOT Exist (Referenced in Docs)
- `fn_is_member(uuid, uuid)` — does NOT exist
- `fn_has_permission(uuid, text)` — does NOT exist
- `fn_can_access_test(uuid, uuid)` — does NOT exist

---

## G. Existing RLS Policies

### Current RLS Status
- R4.1 migration (line 606): "Verify RLS is NOT enabled (no policies exist yet)"
- R4.3 migration: Removed a dangerous "coded tests readable" policy
- **No RLS policies exist for any table** (all access is via SECURITY DEFINER RPCs)

### Group RLS Policies
**NONE.** The `groups` table doesn't exist, so no policies can exist.

---

## H. Existing Flutter Group Code

### Group Model
**DOES NOT EXIST.** No `lib/core/models/group.dart` file exists.

### Group Service
**DOES NOT EXIST.** No `lib/core/services/group_service.dart` file exists.

### Group Screens/Routes
**DO NOT EXIST.** No `lib/features/group/` directory exists. No group routes in `app_router.dart`.

### Group-Related UI
The only group-related UI is a **placeholder** in `step_configuration.dart` (line 348):
```dart
'No group service available. Group selection requires a group service.',
```

---

## I. What Can Be Reused

### From Architecture Spec (R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md)
The spec provides complete DDL designs for:
1. `groups` table (lines 1275-1279)
2. `group_members` table (lines 1282-1290)
3. `role_permissions` table (lines 1293-1298)
4. Permission matrix (lines 1303-1316)

### From Existing Code
1. `tests.group_id` column — already exists, nullable UUID
2. `idx_tests_group_id` index — already exists
3. `Test` model — already has `groupId` field (nullable)
4. `rpc_create_test` — already accepts `p_group_id` parameter
5. `rpc_publish_test` — already validates group_id for group tests
6. `StepConfiguration` widget — already has Group Test mode dropdown
7. `TestCreationScreen` — already manages `_groupId` state
8. `TestService` — already passes groupId through to RPC

### Service Pattern to Follow
All existing services follow the same pattern:
```dart
final class GroupService {
  GroupService._();

  static final _db = SupabaseService.client.from('groups');

  static Future<List<Group>> getAvailableGroupsForCurrentUser() async {
    // ... implementation following existing patterns
  }
}
```

---

## J. What Is Genuinely Missing

### Database Layer (BLOCKER)
1. **`groups` table** — does not exist, must be created
2. **`group_members` table** — does not exist, must be created
3. **FK constraint** on `tests.group_id` → `groups.id` — not enforced
4. **RLS policies** for groups — none exist
5. **RPC for listing user's groups** — does not exist

### Flutter Layer
1. **`Group` model** — does not exist
2. **`GroupService`** — does not exist
3. **Group selection UI** — only placeholder exists
4. **Tests for group functionality** — none exist

---

## K. Whether DB Migration Is Actually Required

### YES — DATABASE MIGRATION IS REQUIRED

**Reason:** The `groups` and `group_members` tables do not exist. Without them:
- There is no way to list groups a user belongs to
- There is no way to validate group_id
- There is no way to enforce group-based permissions
- Group Test selection cannot be made functional

**The existing Supabase infrastructure does NOT support the requirement.**

### Proposed Migration

The migration must create:

1. **`groups` table** — minimal viable schema
2. **`group_members` table** — with role support
3. **FK constraint** on `tests.group_id` → `groups.id`
4. **RLS policies** for group access
5. **RPC function** for listing user's groups
6. **Grants** for authenticated users

### Security Requirements

1. Users should only see groups they are members of
2. Only leaders should be able to create tests for their groups
3. Group membership must be verified server-side
4. No anonymous access to group data
5. No service-role key usage in Flutter

### Proposed DDL

```sql
-- 1. Groups table
CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Group members table
CREATE TABLE public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, user_id)
);

-- 3. Add FK constraint to tests.group_id
ALTER TABLE public.tests
  ADD CONSTRAINT fk_tests_group_id
  FOREIGN KEY (group_id) REFERENCES public.groups(id)
  ON DELETE SET NULL;

-- 4. Indexes
CREATE INDEX idx_group_members_user_id ON public.group_members (user_id);
CREATE INDEX idx_group_members_group_id ON public.group_members (group_id);

-- 5. RLS policies
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- Groups: members can read their groups
CREATE POLICY "groups_select_members" ON public.groups
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members
      WHERE group_members.group_id = groups.id
      AND group_members.user_id = auth.uid()
    )
  );

-- Groups: authenticated users can create groups
CREATE POLICY "groups_insert_authenticated" ON public.groups
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Group members: members can read their group's members
CREATE POLICY "group_members_select_members" ON public.group_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
      AND gm.user_id = auth.uid()
    )
  );

-- Group members: leaders can manage membership
CREATE POLICY "group_members_insert_leaders" ON public.group_members
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
      AND gm.user_id = auth.uid()
      AND gm.role = 'leader'
    )
  );

-- 6. RPC for listing user's groups
CREATE OR REPLACE FUNCTION public.rpc_get_user_groups()
RETURNS TABLE (
  id uuid,
  name text,
  created_by uuid,
  created_at timestamptz,
  member_count bigint,
  user_role text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    g.id,
    g.name,
    g.created_by,
    g.created_at,
    (SELECT COUNT(*) FROM public.group_members gm WHERE gm.group_id = g.id) as member_count,
    gm.role as user_role
  FROM public.groups g
  INNER JOIN public.group_members gm ON gm.group_id = g.id
  WHERE gm.user_id = auth.uid()
  ORDER BY g.name;
$$;

-- 7. Grants
GRANT SELECT ON public.groups TO authenticated;
GRANT INSERT ON public.groups TO authenticated;
GRANT SELECT ON public.group_members TO authenticated;
GRANT INSERT ON public.group_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;
```

---

## Recommendation

**STOP implementation of Flutter GroupService until the database migration is executed.**

The migration creates the foundational tables required for any group functionality. Without it, the Flutter layer has nothing to query.

After the migration is executed:
1. Create Flutter `Group` model mapping to the `groups` + `group_members` tables
2. Create `GroupService` with `getAvailableGroupsForCurrentUser()` calling `rpc_get_user_groups()`
3. Integrate into `StepConfiguration` and `TestCreationScreen`
4. Add tests

---

## Appendix: Documentation References

| Document | Line(s) | Statement |
|----------|---------|-----------|
| `R4_TEST_SYSTEM_DISCOVERY_AUDIT.md` | 46-47 | `groups: NOT FOUND`, `group_members: NOT FOUND` |
| `R4_TEST_SYSTEM_DISCOVERY_AUDIT.md` | 1175 | "No group or permission infrastructure exists." |
| `R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md` | 24 | "Groups: Deferred — designed interface only" |
| `R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md` | 93-95 | `groups: DOES NOT EXIST`, `group_members: DOES NOT EXIST` |
| `R4_1_TEST_SYSTEM_ARCHITECTURE_SPEC.md` | 1267 | "No groups infrastructure exists." |
| `R4_5_4_TEST_CREATION_FUNCTIONAL_COMPLETION_REPORT.md` | 64 | "No group service exists in the project — gap reported" |

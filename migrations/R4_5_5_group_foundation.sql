-- =====================================================
-- R4.5.5 GROUP FOUNDATION
-- Creates groups infrastructure for Group Test selection
-- =====================================================
-- Prerequisites: R4.1 (tables), R4.5.1 (test creation RPCs)
-- Tables created: groups, group_members
-- Tables altered: tests (FK constraint added)
-- Functions created: rpc_get_user_groups()
-- RLS: Enabled on groups, group_members
-- =====================================================

-- =====================================================
-- SECTION 1: CREATE TABLES
-- =====================================================

-- 1.1 Groups table
CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.groups IS 'Groups for group-based test assignment and collaboration';
COMMENT ON COLUMN public.groups.id IS 'Unique group identifier';
COMMENT ON COLUMN public.groups.name IS 'Display name of the group';
COMMENT ON COLUMN public.groups.created_by IS 'User who created the group (leader)';
COMMENT ON COLUMN public.groups.created_at IS 'Timestamp when group was created';
COMMENT ON COLUMN public.groups.updated_at IS 'Timestamp when group was last updated';

-- 1.2 Group members table
CREATE TABLE public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, user_id)
);

COMMENT ON TABLE public.group_members IS 'Membership records linking users to groups with roles';
COMMENT ON COLUMN public.group_members.id IS 'Unique membership record identifier';
COMMENT ON COLUMN public.group_members.group_id IS 'Reference to the group';
COMMENT ON COLUMN public.group_members.user_id IS 'Reference to the authenticated user';
COMMENT ON COLUMN public.group_members.role IS 'Role within the group: leader or member';
COMMENT ON COLUMN public.group_members.joined_at IS 'Timestamp when membership was created';

-- =====================================================
-- SECTION 2: ALTER TABLES (FK CONSTRAINTS)
-- =====================================================

-- 2.1 Add FK constraint: tests.group_id → groups.id
-- Existing tests.group_id is nullable UUID with no FK.
-- ON DELETE SET NULL: if group is deleted, test becomes personal (not deleted).
ALTER TABLE public.tests
  ADD CONSTRAINT fk_tests_group_id
  FOREIGN KEY (group_id) REFERENCES public.groups(id)
  ON DELETE SET NULL;

COMMENT ON CONSTRAINT fk_tests_group_id ON public.tests IS
  'FK linking tests to their assigned group. SET NULL if group is deleted.';

-- =====================================================
-- SECTION 3: INDEXES
-- =====================================================

-- 3.1 Index for looking up groups by user (via group_members)
CREATE INDEX idx_group_members_user_id
  ON public.group_members (user_id);

-- 3.2 Index for looking up members by group
CREATE INDEX idx_group_members_group_id
  ON public.group_members (group_id);

-- Note: idx_tests_group_id already exists from R4.1 migration
-- (CREATE INDEX idx_tests_group_id ON public.tests (group_id) WHERE group_id IS NOT NULL;)

-- =====================================================
-- SECTION 4: ROW LEVEL SECURITY (RLS)
-- =====================================================

-- 4.1 Enable RLS on groups
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

-- 4.2 Enable RLS on group_members
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- 4.3 Groups SELECT: members can read groups they belong to
CREATE POLICY "groups_select_members" ON public.groups
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members
      WHERE group_members.group_id = groups.id
      AND group_members.user_id = auth.uid()
    )
  );

-- 4.4 Groups INSERT: authenticated users can create groups
-- (They become the created_by. Adding themselves as leader is handled by app logic.)
CREATE POLICY "groups_insert_authenticated" ON public.groups
  FOR INSERT WITH CHECK (auth.uid() = created_by);

-- 4.5 Groups UPDATE: only the creator (leader) can update group details
CREATE POLICY "groups_update_creator" ON public.groups
  FOR UPDATE USING (auth.uid() = created_by);

-- 4.6 Groups DELETE: only the creator can delete the group
CREATE POLICY "groups_delete_creator" ON public.groups
  FOR DELETE USING (auth.uid() = created_by);

-- 4.7 Group members SELECT: members can read other members in their groups
CREATE POLICY "group_members_select_members" ON public.group_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
      AND gm.user_id = auth.uid()
    )
  );

-- 4.8 Group members INSERT: leaders can add members to their groups
CREATE POLICY "group_members_insert_leaders" ON public.group_members
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
      AND gm.user_id = auth.uid()
      AND gm.role = 'leader'
    )
  );

-- 4.9 Group members DELETE: leaders can remove members, users can remove themselves
CREATE POLICY "group_members_delete_leaders_or_self" ON public.group_members
  FOR DELETE USING (
    auth.uid() = group_members.user_id
    OR
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_members.group_id
      AND gm.user_id = auth.uid()
      AND gm.role = 'leader'
    )
  );

-- =====================================================
-- SECTION 5: SECURITY DEFINER FUNCTIONS
-- =====================================================

-- 5.1 Safe auth.uid() wrapper (consistent with R4.5.1 pattern)
CREATE OR REPLACE FUNCTION public._fn_auth_uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid()
$$;

-- 5.2 Check if user is a member of a group
CREATE OR REPLACE FUNCTION public._fn_is_group_member(
  p_group_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id
    AND user_id = COALESCE(p_user_id, auth.uid())
  )
$$;

COMMENT ON FUNCTION public._fn_is_group_member(uuid, uuid) IS
  'Returns true if the user is a member of the specified group. Private helper.';

-- 5.3 Check if user is a leader of a group
CREATE OR REPLACE FUNCTION public._fn_is_group_leader(
  p_group_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id
    AND user_id = COALESCE(p_user_id, auth.uid())
    AND role = 'leader'
  )
$$;

COMMENT ON FUNCTION public._fn_is_group_leader(uuid, uuid) IS
  'Returns true if the user is a leader of the specified group. Private helper.';

-- =====================================================
-- SECTION 6: PUBLIC RPC FUNCTIONS
-- =====================================================

-- 6.1 Get groups for the current authenticated user
-- Returns groups with member count and the user's role.
-- SECURITY DEFINER: bypasses RLS for reliable data access (consistent with project pattern).
CREATE OR REPLACE FUNCTION public.rpc_get_user_groups()
RETURNS TABLE (
  id uuid,
  name text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
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
    g.updated_at,
    (SELECT COUNT(*) FROM public.group_members gm WHERE gm.group_id = g.id) as member_count,
    gm.role as user_role
  FROM public.groups g
  INNER JOIN public.group_members gm ON gm.group_id = g.id
  WHERE gm.user_id = public._fn_auth_uid()
  ORDER BY g.name;
$$;

COMMENT ON FUNCTION public.rpc_get_user_groups() IS
  'Returns all groups the authenticated user belongs to, with member count and user role.';

-- 6.2 Create a group and automatically add the creator as leader
-- SECURITY DEFINER: uses auth.uid() safely, consistent with project pattern.
CREATE OR REPLACE FUNCTION public.rpc_create_group(
  p_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_group_id uuid;
  v_result jsonb;
BEGIN
  -- Get authenticated user
  v_user_id := public._fn_auth_uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED: You must be logged in to create a group';
  END IF;

  -- Validate input
  IF p_name IS NULL OR trim(p_name) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Group name is required';
  END IF;

  IF length(trim(p_name)) > 100 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Group name must be 100 characters or less';
  END IF;

  -- Create the group
  INSERT INTO public.groups (name, created_by)
  VALUES (trim(p_name), v_user_id)
  RETURNING id INTO v_group_id;

  -- Add creator as leader
  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group_id, v_user_id, 'leader');

  -- Return the created group
  SELECT jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'created_by', g.created_by,
    'created_at', g.created_at,
    'updated_at', g.updated_at,
    'member_count', (SELECT COUNT(*) FROM public.group_members gm WHERE gm.group_id = g.id),
    'user_role', 'leader'
  ) INTO v_result
  FROM public.groups g
  WHERE g.id = v_group_id;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.rpc_create_group(text) IS
  'Creates a new group and adds the authenticated user as leader. Returns the created group.';

-- =====================================================
-- SECTION 7: GRANTS
-- =====================================================

-- 7.1 Table grants
GRANT SELECT ON public.groups TO authenticated;
GRANT INSERT ON public.groups TO authenticated;
GRANT UPDATE ON public.groups TO authenticated;
GRANT DELETE ON public.groups TO authenticated;

GRANT SELECT ON public.group_members TO authenticated;
GRANT INSERT ON public.group_members TO authenticated;
GRANT DELETE ON public.group_members TO authenticated;

-- 7.2 Function grants
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_group(text) TO authenticated;

-- 7.3 Revoke from anon (no anonymous group access)
REVOKE ALL ON public.groups FROM anon;
REVOKE ALL ON public.group_members FROM anon;
REVOKE EXECUTE ON FUNCTION public.rpc_get_user_groups() FROM anon;
REVOKE EXECUTE ON FUNCTION public.rpc_create_group(text) FROM anon;

-- =====================================================
-- SECTION 8: VALIDATION QUERIES
-- =====================================================

-- Run these after migration to verify:

-- 8.1 Verify tables exist
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name IN ('groups', 'group_members');

-- 8.2 Verify FK constraint on tests
-- SELECT conname, contype FROM pg_constraint
-- WHERE conrelid = 'public.tests'::regclass AND conname = 'fk_tests_group_id';

-- 8.3 Verify RLS is enabled
-- SELECT tablename, rowsecurity FROM pg_tables
-- WHERE schemaname = 'public' AND tablename IN ('groups', 'group_members');

-- 8.4 Verify RLS policies
-- SELECT policyname, tablename, cmd FROM pg_policies
-- WHERE schemaname = 'public' AND tablename IN ('groups', 'group_members');

-- 8.5 Verify functions exist
-- SELECT routine_name FROM information_schema.routines
-- WHERE routine_schema = 'public' AND routine_name IN (
--   'rpc_get_user_groups', 'rpc_create_group',
--   '_fn_auth_uid', '_fn_is_group_member', '_fn_is_group_leader'
-- );

-- 8.6 Verify grants
-- SELECT grantee, table_name, privilege_type FROM information_schema.role_table_grants
-- WHERE table_schema = 'public' AND table_name IN ('groups', 'group_members')
-- AND grantee = 'authenticated';

-- =====================================================
-- END R4.5.5 GROUP FOUNDATION MIGRATION
-- =====================================================

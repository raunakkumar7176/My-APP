-- G17 — SECURITY AUDIT PRECHECK (read-only, safe to run)
-- Run BEFORE applying any G17 migrations.
-- Expected: all show the vulnerable pre-fix state.

-- §1. G14: legacy group_members ALL policy still exists
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members'
      AND policyname = 'Users can manage group members') AS g14_legacy_policy_present,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members') AS g14_total_policies;

-- §2. G16: fn_notify_group callable by authenticated
SELECT
  has_function_privilege('authenticated',
    'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)',
    'EXECUTE') AS g16_authenticated_can_execute,
  has_function_privilege('anon',
    'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)',
    'EXECUTE') AS g16_anon_can_execute;

-- §3. G17-01: rpc_get_leaderboard uses access_code (any signed-in user can read any leaderboard)
SELECT
  (p.prosrc ILIKE '%access_code%') AS g17_01_uses_access_code,
  (p.prosrc ILIKE '%created_by = auth.uid()%') AS g17_01_has_creator_check,
  has_function_privilege('anon', 'public.rpc_get_leaderboard(uuid)', 'EXECUTE') AS g17_01_anon_can_execute,
  has_function_privilege('authenticated', 'public.rpc_get_leaderboard(uuid)', 'EXECUTE') AS g17_01_auth_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_leaderboard';

-- §4. G17-02: fn_increment_batch_progress has no authorization
SELECT
  has_function_privilege('anon', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_anon_can_execute,
  has_function_privilege('authenticated', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_auth_can_execute,
  has_function_privilege('service_role', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_service_can_execute,
  (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_increment_batch_progress') AS g17_02_body;

-- §5. G17-03: fn_insert_system_message callable by authenticated (no membership/permission check)
SELECT
  has_function_privilege('authenticated',
    'public.fn_insert_system_message(uuid, text, text, jsonb)',
    'EXECUTE') AS g17_03_authenticated_can_execute,
  has_function_privilege('anon',
    'public.fn_insert_system_message(uuid, text, text, jsonb)',
    'EXECUTE') AS g17_03_anon_can_execute;

-- §6. G17-04A: test_syllabus has overly broad write policy
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'test_syllabus'
      AND policyname = 'syllabus follows test') AS g17_04a_old_policy_present,
  (SELECT array_agg(policyname ORDER BY policyname) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'test_syllabus') AS g17_04a_all_policies;

-- §7. G17-04B: group_announcements INSERT does not check author_id
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_announcements'
      AND policyname = 'leaders create announcements'
      AND cmd = 'INSERT') AS g17_04b_insert_policy_count;

-- §8. G5.7: fn_withdraw_join_request exists
SELECT
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_withdraw_join_request') AS g5_7_fn_exists;

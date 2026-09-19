-- G17 POSTCHECK
-- Run AFTER all G17 migrations applied.

SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname='public' AND tablename='group_members'
      AND policyname='Users can manage group members') AS g14_legacy_policy_count,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname='public' AND tablename='group_members') AS g14_remaining_policies,
  has_function_privilege('authenticated',
    'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)',
    'EXECUTE') AS g16_auth_can_execute,
  has_function_privilege('anon',
    'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)',
    'EXECUTE') AS g16_anon_can_execute,
  has_function_privilege('authenticated',
    'public.fn_insert_system_message(uuid, text, text, jsonb)',
    'EXECUTE') AS g17_03_auth_can_execute,
  has_function_privilege('anon',
    'public.fn_insert_system_message(uuid, text, text, jsonb)',
    'EXECUTE') AS g17_03_anon_can_execute;

SELECT
  (p.prosrc NOT ILIKE '%access_code%') AS g17_01_code_branch_removed,
  has_function_privilege('anon', 'public.rpc_get_leaderboard(uuid)', 'EXECUTE') AS g17_01_anon_denied,
  p.prosrc ILIKE '%created_by = auth.uid()%' AS g17_01_creator_check
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_leaderboard';

SELECT
  has_function_privilege('anon', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_anon_denied,
  has_function_privilege('authenticated', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_auth_can_execute,
  has_function_privilege('service_role', 'public.fn_increment_batch_progress(uuid, integer)', 'EXECUTE') AS g17_02_service_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_increment_batch_progress';

SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('test_syllabus', 'group_announcements')
ORDER BY 1, 2;

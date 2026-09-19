-- G16 PRECHECK (read-only). Run in the Supabase SQL Editor BEFORE
-- migrations/G16_revoke_fn_notify_group_execute.sql.
-- Expected (live 2026-09-20): authenticated_can_execute = true (the gap),
-- the notifications policies are exactly "own notifications" (SELECT) and
-- "mark own read" (UPDATE), no INSERT/DELETE policy; group_mutes is own-row FOR ALL.

-- 1. the gap: clients may execute fn_notify_group
SELECT
  has_function_privilege('authenticated', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('anon', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS anon_can_execute,
  (SELECT prosecdef FROM pg_proc WHERE proname = 'fn_notify_group') AS security_definer;

-- 2. its only callers are the definer trigger functions (owned by postgres)
SELECT p.proname, p.prosecdef, pg_get_userbyid(p.proowner) AS owner
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND p.prosrc ILIKE '%fn_notify_group(%' AND p.proname <> 'fn_notify_group'
ORDER BY 1;
-- expect: trg_notify_group_announcement, trg_notify_group_join, trg_notify_group_message,
--         trg_notify_group_test — all true / postgres

-- 3. the notification tables the G16 client relies on (unchanged by G16)
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('notifications', 'group_mutes')
ORDER BY 1, 2;
-- expect notifications: "mark own read" (UPDATE, user_id = auth.uid()),
--                       "own notifications" (SELECT, user_id = auth.uid())
--        group_mutes:   "own group_mutes" (ALL, user_id = auth.uid())

-- 4. read-state column and group-scope key actually used by live rows
SELECT count(*) AS total,
       count(*) FILTER (WHERE read_at IS NULL) AS unread,
       count(*) FILTER (WHERE data ? 'group_id') AS with_group_id
FROM public.notifications;

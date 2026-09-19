-- G16 POSTCHECK (read-only). Run AFTER migrations/G16_revoke_fn_notify_group_execute.sql.

-- 1. clients can no longer execute fn_notify_group; service_role still can
SELECT
  has_function_privilege('authenticated', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS authenticated_can_execute, -- expect false
  has_function_privilege('anon', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS anon_can_execute,                   -- expect false
  has_function_privilege('service_role', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS service_role_can_execute;   -- expect true

-- 2. the trigger path is intact
SELECT tgrelid::regclass AS tbl, tgname, tgenabled
FROM pg_trigger
WHERE tgname IN ('trg_group_message_notify', 'trg_group_announcement_notify', 'trg_group_test_notify', 'trg_group_join_notify')
ORDER BY 1;
-- expect 4 rows, tgenabled = 'O'

-- 3. nothing else changed
SELECT count(*) AS notification_policies FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notifications'; -- expect 2
SELECT count(*) AS mute_policies FROM pg_policies WHERE schemaname = 'public' AND tablename = 'group_mutes';           -- expect 1
SELECT prosecdef, proconfig FROM pg_proc WHERE proname = 'fn_notify_group';                                             -- expect true, {search_path=public}

-- 4. functional smoke (from the app, as a member): send a chat message in a
--    group with two or more members and confirm the other member's unread
--    badge increments — the trigger still delivers after the revoke.

-- G16 — close direct client execution of fn_notify_group (owner apply required)
--
-- LIVE FINDING (2026-09-20, read-only audit + rolled-back probe):
--   public.fn_notify_group(uuid, notif_category, text, text, jsonb, uuid)
--   is SECURITY DEFINER, performs NO caller authorization, and its ACL is
--   {postgres=X, authenticated=X, service_role=X}. Any signed-in user can
--   therefore call it with ANY group id and push an arbitrary title / body /
--   data payload into every member's inbox of any group (proven: a
--   non-member inserted a "spam" notification for the owner of another
--   group; rolled back). Nothing in the Flutter app or the legacy web app
--   calls the function from a client: its only callers are the four
--   SECURITY DEFINER trigger functions (trg_notify_group_message,
--   trg_notify_group_announcement, trg_notify_group_test,
--   trg_notify_group_join), all owned by postgres, which keep working after
--   the revoke because they execute as their owner.
--
-- NOT CHANGED: function body, triggers, tables, policies, service_role grant.
-- Rollback (only if a legitimate client caller is found):
--   GRANT EXECUTE ON FUNCTION public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- postflight (read-only)
SELECT
  has_function_privilege('authenticated', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS authenticated_can_execute, -- expect false
  has_function_privilege('anon', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS anon_can_execute,                   -- expect false
  has_function_privilege('service_role', 'public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid)', 'EXECUTE') AS service_role_can_execute,   -- expect true
  (SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_group_message_notify', 'trg_group_announcement_notify', 'trg_group_test_notify', 'trg_group_join_notify')) AS notify_triggers; -- expect 4

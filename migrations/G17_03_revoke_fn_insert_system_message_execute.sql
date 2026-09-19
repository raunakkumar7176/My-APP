-- G17-03 — fn_insert_system_message: close direct client execution (owner apply required)
--
-- LIVE FINDING (2026-09-20): public.fn_insert_system_message(p_group uuid,
-- p_body text, p_type text, p_metadata jsonb) is SECURITY DEFINER
-- (search_path=public) with EXECUTE for authenticated and performs NO
-- membership or permission check: it inserts a `group_messages` row into ANY
-- group (actor = caller, or the group owner when the caller is anonymous) with
-- an arbitrary body, message_type in (system, announcement, test, activity) and
-- arbitrary metadata — and the insert fires trg_group_message_notify, so every
-- member of the target group also receives a notification. A non-member can
-- therefore inject "system" messages into any group's chat. Proven in a
-- rolled-back probe. Callers: only the SECURITY DEFINER trigger functions
-- trg_member_joined_system / trg_member_left_system / trg_role_changed_system /
-- trg_group_created_system (owned by postgres); no Flutter or legacy client
-- code calls it.
--
-- NOT CHANGED: function body, triggers, service_role grant.
-- Rollback: GRANT EXECUTE ON FUNCTION public.fn_insert_system_message(uuid, text, text, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_insert_system_message(uuid, text, text, jsonb) FROM PUBLIC, anon, authenticated;

-- postflight (read-only)
SELECT has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,                   -- expect false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute, -- expect false
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute    -- expect true
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_insert_system_message';

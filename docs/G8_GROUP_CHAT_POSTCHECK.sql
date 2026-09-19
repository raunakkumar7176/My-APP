-- ============================================================
-- G8 — POST-CHECK (read-only). Run in the Supabase SQL Editor AFTER the
-- pre-check (and after migrations/G8_GROUP_CHAT.sql only if the pre-check
-- showed the table absent). Paste every grid back into the report.
-- ============================================================

-- ------------------------------------------------------------
-- Statement 1 — structure, grants, RLS. Expected:
--   table_exists=true | rls_enabled=true | has_select_policy=true |
--   has_insert_policy=true | broad_update_or_delete_policy=false |
--   fk_group=true | fk_sender_profiles=true | body_check=true |
--   anon_privileges=0 | authenticated_can_select_insert=true |
--   group_created_index=true
-- ------------------------------------------------------------
SELECT
  to_regclass('public.group_messages') IS NOT NULL AS table_exists,
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'group_messages') AS rls_enabled,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_messages' AND p.cmd IN ('SELECT', 'ALL')) AS has_select_policy,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_messages' AND p.cmd IN ('INSERT', 'ALL')) AS has_insert_policy,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_messages' AND p.cmd IN ('UPDATE', 'DELETE', 'ALL')
            AND coalesce(p.qual, '') NOT ILIKE '%fn_%') AS broad_update_or_delete_policy,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'f' AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'f' AND k.confrelid = 'public.profiles'::regclass) AS fk_sender_profiles,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%body%') AS body_check,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT count(*) = 2 FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages'
       AND g.grantee = 'authenticated' AND g.privilege_type IN ('SELECT', 'INSERT')) AS authenticated_can_select_insert,
  EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname = 'public' AND i.tablename = 'group_messages'
            AND i.indexdef ILIKE '%(group_id, created_at%') AS group_created_index;

-- ------------------------------------------------------------
-- Statement 2 — enforcement as installed (policy text). Expected:
--   read_gated_by_membership=true | insert_pins_sender=true |
--   insert_gated_by_membership=true | all_policies_authenticated_or_default=true |
--   no_anon_policy=true
-- ------------------------------------------------------------
SELECT
  bool_and(CASE WHEN cmd IN ('SELECT', 'ALL') THEN coalesce(qual, '') ILIKE '%fn_is_member%' ELSE true END) AS read_gated_by_membership,
  bool_and(CASE WHEN cmd IN ('INSERT', 'ALL') THEN coalesce(with_check, '') ILIKE '%sender_id = %auth.uid()%' ELSE true END) AS insert_pins_sender,
  bool_and(CASE WHEN cmd IN ('INSERT', 'ALL') THEN coalesce(with_check, '') ILIKE '%fn_is_member%' ELSE true END) AS insert_gated_by_membership,
  bool_and('authenticated' = ANY (roles) OR 'public' = ANY (roles)) AS all_policies_authenticated_or_default,
  bool_and(NOT ('anon' = ANY (roles))) AS no_anon_policy,
  count(*) AS policy_count
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_messages';
-- Note: 0001_init created its policies without `TO authenticated`, i.e. roles =
-- {public}; with anon holding NO table grant (statement 1) that is still safe.
-- If anon_privileges > 0 AND a policy lists public, report it as a finding.

-- ------------------------------------------------------------
-- Statement 3 — definer functions that write group_messages (cross-group
-- review). Expected legacy set: fn_delete_group_message (own or
-- MANAGE_MEMBERS, membership checked), fn_insert_system_message (server
-- notices), fn_clear_group_chat (owner / MANAGE_MEMBERS), trg_* system
-- message triggers. None may insert a row with an arbitrary caller-supplied
-- sender for another user.
-- ------------------------------------------------------------
SELECT p.proname,
       p.prosecdef AS security_definer,
       p.proconfig,
       (pg_get_functiondef(p.oid) ILIKE '%insert into public.group_messages%'
        OR pg_get_functiondef(p.oid) ILIKE '%update public.group_messages%'
        OR pg_get_functiondef(p.oid) ILIKE '%delete from public.group_messages%') AS writes_table
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) ILIKE '%group_messages%'
ORDER BY p.proname;

-- ------------------------------------------------------------
-- Statement 4 — the base columns the Flutter model parses. Expected 5 rows:
--   id uuid NO | group_id uuid NO | sender_id uuid (NO|YES) | body text NO |
--   created_at timestamptz NO
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_messages'
  AND column_name IN ('id', 'group_id', 'sender_id', 'body', 'created_at')
ORDER BY ordinal_position;

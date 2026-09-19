-- ============================================================
-- G8 — PRE-CHECK (read-only). Run in the Supabase SQL Editor BEFORE anything
-- else. Paste the whole file; paste all result grids back into the G8 report.
--
-- Purpose: prove whether the chat infrastructure the legacy migration set
-- defines (0001_init group_messages; 0010/0025/0033 indexes + soft delete;
-- 0038 message_type; 0047 nullable sender_id) is LIVE, so the Flutter
-- client reuses it and no duplicate table is ever created.
-- ============================================================

-- ------------------------------------------------------------
-- Statement 1 — existence + dependencies. Expected when live matches legacy:
--   table_exists=true | rls_enabled=true | fn_is_member=true | definer_fn=true |
--   realtime_published=true (0020/0025/0034 added it; informational only —
--   the client does not subscribe)
-- If table_exists=false → run migrations/G8_GROUP_CHAT.sql (only then).
-- If fn_is_member is false → STOP, report; nothing may be applied.
-- ------------------------------------------------------------
SELECT
  to_regclass('public.group_messages') IS NOT NULL AS table_exists,
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'group_messages') AS rls_enabled,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_is_member' AND p.pronargs = 2) AS fn_is_member,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_is_member' AND p.prosecdef) AS definer_fn,
  EXISTS (SELECT 1 FROM pg_publication_tables t
          WHERE t.pubname = 'supabase_realtime' AND t.schemaname = 'public'
            AND t.tablename = 'group_messages') AS realtime_published;

-- ------------------------------------------------------------
-- Statement 2 — columns. The client selects/inserts ONLY the base five:
--   id uuid NO | group_id uuid NO | sender_id uuid (NO or YES — 0047 drops
--   NOT NULL so system notices can have no sender; the model accepts null) |
--   body text NO | created_at timestamptz NO
-- Extra columns (message_type, metadata, deleted_at, deleted_by) may appear;
-- record them — the client neither reads nor writes them (see report §13).
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_messages'
ORDER BY ordinal_position;

-- ------------------------------------------------------------
-- Statement 3 — the live policies. Expected (0001_init names):
--   "member reads messages"  SELECT  qual: fn_is_member(group_id, auth.uid())
--   "member sends messages"  INSERT  with_check: sender_id = auth.uid() AND fn_is_member(group_id, auth.uid())
--   NO UPDATE / DELETE policy (0025: deletion only via fn_delete_group_message)
-- Any policy permissive to anon/public, or any UPDATE/DELETE policy with a
-- broad USING, must be reported.
-- ------------------------------------------------------------
SELECT policyname, cmd, roles, permissive, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_messages'
ORDER BY cmd, policyname;

-- ------------------------------------------------------------
-- Statement 4 — grants, constraints, triggers, indexes. Expected:
--   anon_privileges=0 | authenticated_privileges includes INSERT,SELECT
--   (0034 grants SELECT,INSERT,UPDATE,DELETE — UPDATE/DELETE are inert without a policy) |
--   fk_group=true | fk_sender_profiles=true | body_check=true |
--   group_created_index=true |
--   triggers: trg_group_message_notify (0021/0035) — informational; the
--             client depends on none
-- ------------------------------------------------------------
SELECT
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages' AND g.grantee = 'authenticated') AS authenticated_privileges,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'f' AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'f' AND k.confrelid = 'public.profiles'::regclass) AS fk_sender_profiles,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_messages')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%body%') AS body_check,
  EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname = 'public' AND i.tablename = 'group_messages'
            AND i.indexdef ILIKE '%(group_id, created_at%') AS group_created_index,
  (SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) FROM pg_trigger t
     WHERE t.tgrelid = to_regclass('public.group_messages') AND NOT t.tgisinternal) AS triggers,
  (SELECT string_agg(i.indexname, ', ' ORDER BY i.indexname) FROM pg_indexes i
     WHERE i.schemaname = 'public' AND i.tablename = 'group_messages') AS indexes;

-- ============================================================
-- G8 — public.group_messages  (STATUS: CONDITIONAL — NOT APPLIED LIVE)
-- ============================================================
-- RUN THIS FILE ONLY IF docs/G8_GROUP_CHAT_PRECHECK.sql statement 1
-- returned table_exists = false.
--
-- Why conditional: the migration set that built the live database defines
-- this table in 0001_init with exactly the policies G8 needs — member
-- SELECT via fn_is_member, INSERT only as oneself and only into a group one
-- belongs to. The Flutter client (G8) reuses that table and touches only
-- its base columns. If the pre-check shows it live, NOTHING here may be
-- run: the CREATE POLICY statements would fail on the existing names or,
-- worse, replace live policies — and existing RLS is never modified.
--
-- What this creates when the table is genuinely absent: the minimal
-- 0001_init-equivalent (no message_type / metadata / soft delete / reads /
-- notification triggers / realtime publication).
-- Security — membership only, no permission needed to chat:
--   READ   : public.fn_is_member(group_id, auth.uid())
--   INSERT : sender_id = auth.uid() AND public.fn_is_member(group_id, auth.uid())
--   no UPDATE / DELETE policy (messages are immutable from the client).
--   fn_is_member is SECURITY DEFINER (live-verified) → no recursion.
--   anon gets nothing.
-- No DO block, no dynamic SQL; idempotent for the table/index/grants.
-- Rollback: DROP TABLE public.group_messages;
-- ============================================================

CREATE TABLE IF NOT EXISTS public.group_messages (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   uuid        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  sender_id  uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  body       text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_messages_group_created_id_desc
  ON public.group_messages (group_id, created_at DESC, id DESC);

ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "member reads messages"
  ON public.group_messages FOR SELECT TO authenticated
  USING (public.fn_is_member(group_id, auth.uid()));

CREATE POLICY "member sends messages"
  ON public.group_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.fn_is_member(group_id, auth.uid())
  );

REVOKE ALL ON TABLE public.group_messages FROM PUBLIC;
REVOKE ALL ON TABLE public.group_messages FROM anon;
GRANT SELECT, INSERT ON TABLE public.group_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.group_messages TO service_role;

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement -> shown by the SQL Editor)
-- Expected: rls_enabled=true | policies=2 | fk_group=true | fk_sender=true |
--           anon_privileges=0 | authenticated_privileges=INSERT,SELECT
-- Then run docs/G8_GROUP_CHAT_POSTCHECK.sql.
-- ------------------------------------------------------------
SELECT
  c.relrowsecurity AS rls_enabled,
  (SELECT count(*) FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'group_messages') AS policies,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.profiles'::regclass) AS fk_sender,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_messages' AND g.grantee = 'authenticated') AS authenticated_privileges
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'group_messages';

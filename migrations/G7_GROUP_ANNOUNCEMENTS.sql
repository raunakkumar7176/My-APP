-- ============================================================
-- G7 — public.group_announcements  (STATUS: CONDITIONAL — NOT APPLIED LIVE)
-- ============================================================
-- RUN THIS FILE ONLY IF docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql statement 1
-- returned table_exists = false.
--
-- Why conditional: the migration set that built the live database already
-- defines this table (0020, re-created by the 0033 repair, extended by 0040
-- and 0047) with exactly the policies G7 needs — member SELECT via
-- fn_is_member, INSERT / UPDATE / DELETE via SEND_ANNOUNCEMENT-or-owner.
-- The Flutter client (G7) reuses that table and selects only its base
-- columns. If the pre-check shows it live, NOTHING here may be run: every
-- CREATE POLICY below would either fail on the existing name or, worse,
-- replace a live policy — and existing RLS is never modified.
--
-- What this creates when the table is genuinely absent: the minimal
-- 0020/0033-equivalent — base columns only (no category / priority /
-- status / pins / attachments / read receipts / notification triggers).
-- Security — the existing engine only, no new permission:
--   READ   : public.fn_is_member(group_id, auth.uid())
--   WRITE  : public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT')
--            OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
--   INSERT additionally requires author_id = auth.uid() (no impersonation).
--   UPDATE: USING + WITH CHECK, so a row cannot be re-pointed to another
--   group. fn_is_member / fn_has_permission / fn_get_group_role are
--   SECURITY DEFINER (live-verified), so no recursion. anon gets nothing.
-- No DO block, no dynamic SQL, plain single-level $$; idempotent.
-- Rollback: DROP TABLE public.group_announcements;
--           DROP FUNCTION public.fn_touch_group_announcement_updated_at();
-- ============================================================

CREATE TABLE IF NOT EXISTS public.group_announcements (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   uuid        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  author_id  uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title      text        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  body       text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_announcements_group_created
  ON public.group_announcements (group_id, created_at DESC);

ALTER TABLE public.group_announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read announcements"
  ON public.group_announcements FOR SELECT TO authenticated
  USING (public.fn_is_member(group_id, auth.uid()));

CREATE POLICY "leaders create announcements"
  ON public.group_announcements FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND (
      public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT')
      OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
    )
  );

CREATE POLICY "leaders update announcements"
  ON public.group_announcements FOR UPDATE TO authenticated
  USING (
    public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  )
  WITH CHECK (
    public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  );

CREATE POLICY "leaders delete announcements"
  ON public.group_announcements FOR DELETE TO authenticated
  USING (
    public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  );

REVOKE ALL ON TABLE public.group_announcements FROM PUBLIC;
REVOKE ALL ON TABLE public.group_announcements FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.group_announcements TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_touch_group_announcement_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_group_announcement ON public.group_announcements;
CREATE TRIGGER trg_touch_group_announcement
  BEFORE UPDATE ON public.group_announcements
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_group_announcement_updated_at();

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement -> shown by the SQL Editor)
-- Expected: rls_enabled=true | policies=4 | fk_group=true | fk_author=true |
--           anon_privileges=0 | authenticated_privileges=DELETE,INSERT,SELECT,UPDATE
-- Then run docs/G7_GROUP_ANNOUNCEMENTS_POSTCHECK.sql.
-- ------------------------------------------------------------
SELECT
  c.relrowsecurity AS rls_enabled,
  (SELECT count(*) FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'group_announcements') AS policies,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.profiles'::regclass) AS fk_author,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'authenticated') AS authenticated_privileges
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'group_announcements';

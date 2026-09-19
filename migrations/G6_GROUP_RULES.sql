-- ============================================================
-- G6 — public.group_rules  (STATUS: PROPOSED — NOT APPLIED LIVE)
-- ============================================================
-- Pre-check first: docs/G6_GROUP_RULES_PRECHECK.sql (read-only).
-- Post-check after: docs/G6_GROUP_RULES_POSTCHECK.sql (read-only).
--
-- Why: no rules table, column, function, trigger or policy exists live
-- (G0 audit: groups has no rules column; G6 audit: no rule objects in the
-- migration set that built the database, none in any branch).
--
-- Design (minimal, additive):
--   one row per rule, scoped to a group; deterministic order by position
--   then created_at; text 1..2000 chars; updated_at maintained by trigger.
-- Security — the existing engine only, no new permission:
--   READ   : public.fn_is_member(group_id, auth.uid())
--   WRITE  : public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS')
--            OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
--            — identical to the live `groups` UPDATE policy, so whoever may
--            change the group's settings may change its rules; leaders and
--            moderators gain nothing new (GROUP_SETTINGS is seeded for no role).
--   Both USING and WITH CHECK on UPDATE: a rule cannot be re-pointed to a
--   group the caller does not manage. fn_is_member / fn_has_permission /
--   fn_get_group_role are SECURITY DEFINER (live-verified), so no recursion.
--   Grants: authenticated + service_role only; anon gets nothing.
-- No DO block, no dynamic SQL, plain single-level $$; idempotent.
-- Rollback: DROP TABLE public.group_rules;  DROP FUNCTION public.fn_touch_group_rule_updated_at();
-- ============================================================

CREATE TABLE IF NOT EXISTS public.group_rules (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   uuid        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  rule_text  text        NOT NULL CHECK (char_length(btrim(rule_text)) BETWEEN 1 AND 2000),
  position   integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_rules_group_position
  ON public.group_rules (group_id, position, created_at);

ALTER TABLE public.group_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read rules" ON public.group_rules;
CREATE POLICY "members read rules"
  ON public.group_rules FOR SELECT TO authenticated
  USING (public.fn_is_member(group_id, auth.uid()));

DROP POLICY IF EXISTS "settings holders insert rules" ON public.group_rules;
CREATE POLICY "settings holders insert rules"
  ON public.group_rules FOR INSERT TO authenticated
  WITH CHECK (
    public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  );

DROP POLICY IF EXISTS "settings holders update rules" ON public.group_rules;
CREATE POLICY "settings holders update rules"
  ON public.group_rules FOR UPDATE TO authenticated
  USING (
    public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  )
  WITH CHECK (
    public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  );

DROP POLICY IF EXISTS "settings holders delete rules" ON public.group_rules;
CREATE POLICY "settings holders delete rules"
  ON public.group_rules FOR DELETE TO authenticated
  USING (
    public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS')
    OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'
  );

REVOKE ALL ON TABLE public.group_rules FROM PUBLIC;
REVOKE ALL ON TABLE public.group_rules FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.group_rules TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_touch_group_rule_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_group_rule ON public.group_rules;
CREATE TRIGGER trg_touch_group_rule
  BEFORE UPDATE ON public.group_rules
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_group_rule_updated_at();

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement -> shown by the SQL Editor)
-- Expected: rls_enabled=true | policies=4 (SELECT,INSERT,UPDATE,DELETE) |
--           fk_to_groups=true | index_present=true | trigger_present=true |
--           anon_privileges=0 | authenticated_privileges=DELETE,INSERT,SELECT,UPDATE
-- ------------------------------------------------------------
SELECT
  c.relrowsecurity AS rls_enabled,
  (SELECT string_agg(p.policyname || ':' || p.cmd, ', ' ORDER BY p.cmd)
     FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = 'group_rules') AS policies,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.groups'::regclass) AS fk_to_groups,
  EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname = 'public' AND i.tablename = 'group_rules'
            AND i.indexname = 'idx_group_rules_group_position') AS index_present,
  EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgname = 'trg_touch_group_rule') AS trigger_present,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_rules' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_rules' AND g.grantee = 'authenticated') AS authenticated_privileges
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'group_rules';

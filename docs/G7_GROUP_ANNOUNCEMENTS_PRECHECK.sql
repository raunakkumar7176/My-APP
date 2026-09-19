-- ============================================================
-- G7 — PRE-CHECK (read-only). Run in the Supabase SQL Editor BEFORE anything
-- else. Paste the whole file; paste all result grids back into the G7 report.
--
-- Purpose: prove whether the announcement infrastructure the legacy
-- migration set defines (0020 → 0033 repair → 0040 → 0047) is LIVE, so the
-- Flutter code reuses it and no duplicate table is ever created.
-- ============================================================

-- ------------------------------------------------------------
-- Statement 1 — existence + dependencies. Expected when live matches legacy:
--   table_exists=true | rls_enabled=true | fn_is_member=true |
--   fn_has_permission=true | fn_get_group_role=true | send_announcement_perm=true |
--   definer_fns=3
-- If table_exists=false → run migrations/G7_GROUP_ANNOUNCEMENTS.sql (only then).
-- If any function/enum check is false → STOP, report; nothing may be applied.
-- ------------------------------------------------------------
SELECT
  to_regclass('public.group_announcements') IS NOT NULL AS table_exists,
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'group_announcements') AS rls_enabled,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_is_member' AND p.pronargs = 2) AS fn_is_member,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_has_permission' AND p.pronargs = 3) AS fn_has_permission,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_get_group_role' AND p.pronargs = 2) AS fn_get_group_role,
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'app_permission' AND e.enumlabel = 'SEND_ANNOUNCEMENT') AS send_announcement_perm,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_is_member', 'fn_has_permission', 'fn_get_group_role')
       AND p.prosecdef) AS definer_fns;

-- ------------------------------------------------------------
-- Statement 2 — columns the Flutter client selects/inserts. Expected 7 rows
-- (base set since 0020); extra 0040/0047 columns may also appear and are fine:
--   id uuid NO | group_id uuid NO | author_id uuid NO | title text NO |
--   body text NO | created_at timestamptz NO | updated_at timestamptz NO
-- Any of these missing/nullable-mismatched → STOP, report.
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_announcements'
ORDER BY ordinal_position;

-- ------------------------------------------------------------
-- Statement 3 — the live policies. Expected (legacy names):
--   "members read announcements"    SELECT  qual contains fn_is_member(group_id, auth.uid())
--                                           (0040 adds: AND status='published' AND publish_at<=now() AND (expires_at IS NULL OR > now()))
--   "leaders create announcements"  INSERT  with_check: fn_has_permission(..,'SEND_ANNOUNCEMENT') OR fn_get_group_role(..)='owner'
--   "leaders manage announcements"  ALL     qual + with_check: same expression
-- roles must be {authenticated}; no policy may mention anon or be permissive to public.
-- ------------------------------------------------------------
SELECT policyname, cmd, roles, permissive, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_announcements'
ORDER BY cmd, policyname;

-- ------------------------------------------------------------
-- Statement 4 — grants, constraints, triggers, indexes. Expected:
--   anon_privileges=0 | authenticated_privileges=DELETE,INSERT,SELECT,UPDATE |
--   fk_group=true | fk_author_profiles=true | title_check=true | body_check=true |
--   triggers: trg_touch_announcement(_pro), trg_group_announcement_notify,
--             trg_announcement_chat_pin, trg_set_announcement_expiry (whichever
--             migrations reached live — record them; the client depends on none)
-- ------------------------------------------------------------
SELECT
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'authenticated') AS authenticated_privileges,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'f' AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'f' AND k.confrelid = 'public.profiles'::regclass) AS fk_author_profiles,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%title%') AS title_check,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%body%') AS body_check,
  (SELECT string_agg(t.tgname, ', ' ORDER BY t.tgname) FROM pg_trigger t
     WHERE t.tgrelid = to_regclass('public.group_announcements') AND NOT t.tgisinternal) AS triggers,
  (SELECT string_agg(i.indexname, ', ' ORDER BY i.indexname) FROM pg_indexes i
     WHERE i.schemaname = 'public' AND i.tablename = 'group_announcements') AS indexes;

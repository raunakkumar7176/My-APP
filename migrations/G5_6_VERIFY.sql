-- ============================================================
-- G5.6 — READ-ONLY pre-check (nothing writes). Run BEFORE the resolver.
-- ONE statement -> ONE grid. Decides PATH A/B and the uniqueness precondition:
--   * profiles columns (identity fields only matter: id, full_name,
--     avatar_url, student_code)
--   * whether student_code is UNIQUE (index/constraint text)
--   * profiles SELECT policies (why a table read cannot resolve a stranger)
--   * any existing function whose name suggests a code/profile resolver
--   * group_invitations INSERT policy text and the accept/decline functions
--   * fn_is_member / fn_has_permission signatures
-- ============================================================
WITH cols AS (
  SELECT 'column' AS section, 'profiles' AS object, c.column_name AS name,
         format('%s | null=%s | default=%s', c.data_type, c.is_nullable, coalesce(c.column_default,'-')) AS detail
  FROM information_schema.columns c
  WHERE c.table_schema = 'public' AND c.table_name = 'profiles'
),
uniq AS (
  SELECT 'unique_check', 'profiles', i.indexname, i.indexdef
  FROM pg_indexes i
  WHERE i.schemaname = 'public' AND i.tablename = 'profiles' AND i.indexdef ILIKE '%student_code%'
  UNION ALL
  SELECT 'unique_check', 'profiles', k.conname, pg_get_constraintdef(k.oid)
  FROM pg_constraint k
  WHERE k.conrelid = 'public.profiles'::regclass AND pg_get_constraintdef(k.oid) ILIKE '%student_code%'
),
dup AS (
  SELECT 'unique_check', 'profiles', 'duplicate_student_codes',
         (SELECT count(*) FROM (SELECT student_code FROM public.profiles
                                WHERE student_code IS NOT NULL GROUP BY student_code HAVING count(*) > 1) d)::text
),
pol AS (
  SELECT 'policy', p.tablename, p.policyname,
         format('cmd=%s | USING %s | CHECK %s', p.cmd, coalesce(p.qual,'-'), coalesce(p.with_check,'-'))
  FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename IN ('profiles','group_invitations')
),
resolvers AS (
  SELECT 'function', p.proname, pg_get_function_identity_arguments(p.oid),
         format('returns=%s | definer=%s | config=%s | grants=%s',
                pg_get_function_result(p.oid), p.prosecdef, coalesce(p.proconfig::text,'-'),
                coalesce((SELECT string_agg(DISTINCT rp.grantee, ',') FROM information_schema.routine_privileges rp
                          WHERE rp.specific_schema = 'public' AND rp.specific_name = p.proname || '_' || p.oid), '-'))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (p.proname ILIKE '%student%' OR p.proname ILIKE '%profile%' OR p.proname ILIKE '%lookup%'
         OR p.proname ILIKE '%find%' OR p.proname ILIKE '%search%' OR p.proname ILIKE '%by_code%'
         OR p.proname IN ('fn_accept_group_invitation','fn_decline_group_invitation','fn_is_member','fn_has_permission'))
)
SELECT section, object, name, detail FROM (
  SELECT * FROM cols UNION ALL SELECT * FROM uniq UNION ALL SELECT * FROM dup
  UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM resolvers
) x
ORDER BY CASE section WHEN 'column' THEN 1 WHEN 'unique_check' THEN 2 WHEN 'policy' THEN 3 ELSE 4 END, object, name;

-- G17-01 — rpc_get_leaderboard: close cross-group leaderboard leakage (owner apply required)
--
-- LIVE FINDING (2026-09-20): public.rpc_get_leaderboard(p_test uuid) is SECURITY
-- DEFINER (search_path=public) with EXECUTE for authenticated. Its WHERE clause
-- grants access when the test has a non-empty access_code OR join_code — and the
-- live trigger fn_set_access_code gives EVERY test an access_code (32/32 live
-- tests). Result: any signed-in user, member or not, can read every test's
-- leaderboard: user_id, full_name, avatar_url, student_code, score, max_score,
-- percentage, accuracy, submitted_at. Proven in a rolled-back probe (non-member
-- read a group test's leaderboard). Callers: legacy web app only
-- (tests/[id]/leaderboard/page.tsx, reports/[testId]/page.tsx); Flutter G12 uses
-- the RLS-protected results table instead.
--
-- FIX: same signature, same ordering, same columns; access requires the caller
-- to be the test creator, a member of the test's group, or a participant
-- (has an attempt). Legacy participants of code-joined standalone tests keep
-- working because they always hold an attempt. Nothing else changes.
-- Rollback: restore the previous body (kept verbatim in docs/G17_PRECHECK.sql §4 output).

CREATE OR REPLACE FUNCTION public.rpc_get_leaderboard(p_test uuid)
 RETURNS TABLE(rank bigint, user_id uuid, full_name text, avatar_url text, student_code text, score numeric, max_score numeric, percentage numeric, accuracy numeric, submitted_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
    SELECT
        row_number() OVER (
            ORDER BY r.score DESC, r.percentage DESC, a.submitted_at ASC, a.id ASC
        ) AS rank,
        a.user_id,
        p.full_name,
        p.avatar_url,
        p.student_code,
        r.score,
        r.max_score,
        r.percentage,
        r.accuracy,
        a.submitted_at
    FROM public.attempts a
    INNER JOIN public.results r ON r.attempt_id = a.id
    LEFT JOIN public.profiles p ON p.id = a.user_id
    INNER JOIN public.tests t ON t.id = a.test_id
    WHERE a.test_id = p_test
      AND auth.uid() IS NOT NULL
      AND (
            t.created_by = auth.uid()
         OR (t.group_id IS NOT NULL AND public.fn_is_member(t.group_id, auth.uid()))
         OR EXISTS (
              SELECT 1 FROM public.attempts mine
              WHERE mine.test_id = t.id AND mine.user_id = auth.uid()
            )
      )
    ORDER BY r.score DESC, r.percentage DESC, a.submitted_at ASC, a.id ASC;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_get_leaderboard(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_leaderboard(uuid) TO authenticated, service_role;

-- postflight (read-only)
SELECT p.prosecdef AS security_definer, p.proconfig AS config,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,           -- expect false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute, -- expect true
       (p.prosrc NOT ILIKE '%access_code%') AS code_branch_removed                       -- expect true
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_leaderboard';

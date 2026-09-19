-- ============================================================
-- G11 — POST-CHECK (read-only). Run after migrations/G11_rpc_request_coach_reports.sql.
-- ============================================================
-- Statement 1 — the RPC as installed. Expected:
--   fn_present=true | security_definer=true | search_path={search_path=} |
--   anon_can_execute=false | authenticated_can_execute=true | gated_by_generate_results=true |
--   requires_finished_batch=true | idempotent_insert=true
SELECT
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'rpc_request_coach_reports') AS fn_present,
  (SELECT p.prosecdef FROM pg_proc p WHERE p.proname = 'rpc_request_coach_reports') AS security_definer,
  (SELECT p.proconfig::text FROM pg_proc p WHERE p.proname = 'rpc_request_coach_reports') AS search_path,
  has_function_privilege('anon', 'public.rpc_request_coach_reports(uuid)', 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', 'public.rpc_request_coach_reports(uuid)', 'EXECUTE') AS authenticated_can_execute,
  (SELECT p.prosrc LIKE '%GENERATE_RESULTS%' FROM pg_proc p WHERE p.proname = 'rpc_request_coach_reports') AS gated_by_generate_results,
  (SELECT p.prosrc LIKE '%RESULTS_NOT_GENERATED%' FROM pg_proc p WHERE p.proname = 'rpc_request_coach_reports') AS requires_finished_batch,
  (SELECT p.prosrc LIKE '%ON CONFLICT (idempotency_key) DO NOTHING%' FROM pg_proc p WHERE p.proname = 'rpc_request_coach_reports') AS idempotent_insert;

-- Statement 2 — no policy/grant on the reused tables changed. Expected: same rows as PRECHECK statement 2.
SELECT tablename, policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('results', 'result_batches', 'ai_reports', 'ai_jobs')
ORDER BY tablename, cmd, policyname;

-- Statement 3 — queue state (informational): pending coach_reports jobs await a worker.
SELECT type, status, count(*) AS n
FROM public.ai_jobs
GROUP BY type, status ORDER BY 1, 2;

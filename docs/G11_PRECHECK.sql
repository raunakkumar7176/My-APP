-- ============================================================
-- G11 — PRE-CHECK (read-only). Proves the live result / AI infrastructure
-- the Flutter client reuses. Run before migrations/G11_rpc_request_coach_reports.sql.
-- ============================================================
-- Statement 1 — tables + RPCs. Expected (live 2026-09-19):
--   results=true | result_batches=true | ai_reports=true | ai_jobs=true |
--   rpc_generate_results=true | fn_score_attempt=true | request_rpc=false (before apply)
SELECT
  to_regclass('public.results') IS NOT NULL AS results,
  to_regclass('public.result_batches') IS NOT NULL AS result_batches,
  to_regclass('public.ai_reports') IS NOT NULL AS ai_reports,
  to_regclass('public.ai_jobs') IS NOT NULL AS ai_jobs,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_generate_results') AS rpc_generate_results,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_score_attempt') AS fn_score_attempt,
  EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_request_coach_reports') AS request_rpc;

-- Statement 2 — the policies the client depends on. Expected:
--   results: "own results" SELECT user_id = auth.uid(); "analytics holders see group results" SELECT VIEW_GROUP_ANALYTICS
--   result_batches: "trigger sees batches" SELECT GENERATE_RESULTS
--   ai_reports: "own reports" SELECT; "report trigger reads" SELECT GENERATE_RESULTS
--   ai_jobs: "no direct ai_jobs access" SELECT false
SELECT tablename, policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('results', 'result_batches', 'ai_reports', 'ai_jobs')
ORDER BY tablename, cmd, policyname;

-- Statement 3 — columns the models parse. Expected to include:
--   results: attempt_id, test_id, user_id, score, max_score, correct_count, wrong_count,
--            unanswered_count, accuracy, percentage, rank, subject_breakdown, topic_breakdown, computed_at
--   ai_reports: id, test_id, user_id, batch_id, payload, model, created_at
--   ai_jobs: id, type, test_id, result_batch_id, idempotency_key, payload, status, ...
SELECT table_name, string_agg(column_name, ', ' ORDER BY ordinal_position) AS columns
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('results', 'result_batches', 'ai_reports', 'ai_jobs')
GROUP BY table_name ORDER BY table_name;

-- Statement 4 — uniqueness the flow relies on. Expected: result_batches UNIQUE(test_id),
--   ai_reports UNIQUE(test_id, user_id), ai_jobs UNIQUE(idempotency_key) + type CHECK incl. 'coach_reports'
SELECT conrelid::regclass AS "table", conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conrelid IN (to_regclass('public.result_batches'), to_regclass('public.ai_reports'), to_regclass('public.ai_jobs'))
  AND contype IN ('u', 'c')
ORDER BY 1, 2;

-- AI_ROUTER_provider_observability_fields.sql  (CORRECTED)
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
--
-- CORRECTION HISTORY: the first version of this migration unconditionally
-- ran `ALTER TABLE public.ai_call_logs ...`, which failed live with
-- `42P01: relation "public.ai_call_logs" does not exist` — that table is
-- referenced in `consolidated_schema.sql` (a historical build-up file, not
-- proof of live state — see this project's standing rule that migration
-- files are history, not live fact) but does not actually exist in this
-- project's live database. The application code already anticipated this:
-- `src/lib/ai-quota.ts`'s `getAiQuotaStatus` has always had an explicit
-- comment/fallback — "Fallback to ai_jobs if ai_call_logs table not yet
-- migrated" — and `logAiCall`'s insert into `ai_call_logs` is already
-- wrapped in a try/catch that only `console.warn`s on failure, never
-- throws. So ai_call_logs is optional, best-effort observability that the
-- app has never depended on for correctness — nothing in the AI Router or
-- Gemini/OpenAI call path reads it to decide behavior.
--
-- Given that, this version does NOT blindly `CREATE TABLE ai_call_logs`
-- (that would silently start a table nothing has provisioned/reviewed) and
-- does NOT unconditionally ALTER it either. Instead EVERY table this
-- migration touches — not just ai_call_logs — is now guarded by an
-- `information_schema` existence check, so this migration can never fail
-- with a missing-relation error again, on this project or a differently
-- -provisioned one, while still adding the columns wherever the table
-- genuinely exists.
--
-- CONTEXT:
-- This adds an AI provider router (gemini = the pre-existing, committed
-- Google Gemini integration lib/ai/gemini.ts already called, + a new
-- OpenAI provider as an optional fallback) in front of the two AI-calling
-- code paths this project's Supabase already backs:
--   - My-Prepration/src/app/api/ai/generate-questions/route.ts  (question_generation)
--   - My-Prepration/src/app/(app)/tests/[id]/results-actions.ts (coach_reports)
-- The router needs somewhere to record which provider/model actually served
-- each request, latency, and whether a fallback/retry happened, for cost
-- tracking and incident debugging. This migration only WIDENS tables that
-- already exist — it creates no new table, no new bucket, no new RLS model.
--
-- RULES:
--   - Additive only: ADD COLUMN IF NOT EXISTS everywhere. No existing
--     column, policy, grant, or row is touched or dropped.
--   - No table is created. A table that doesn't exist is skipped entirely,
--     not altered and not fabricated.
--   - No RLS changes: whatever policies a touched table already has (from
--     0001_init.sql / consolidated_schema.sql) are left exactly as they are.
--   - Idempotent: safe to run more than once, and safe to run against a
--     project where some of these tables don't exist.
--
-- OWNER APPLY REQUIRED

-- ------------------------------------------------------------
-- PREFLIGHT — run this FIRST and read the result before applying anything.
-- This tells you which of the 5 candidate tables actually exist in YOUR
-- project — the migration below will only touch the ones that do.
-- ------------------------------------------------------------
-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('ai_jobs','ai_reports','ai_call_logs','ai_response_cache','ai_usage_metrics')
-- ORDER BY table_name;
--
-- SELECT table_name, column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name IN ('ai_jobs','ai_reports','ai_call_logs','ai_response_cache','ai_usage_metrics')
--   AND column_name IN ('provider','input_tokens','output_tokens','latency_ms','retry_count','fallback_used','error_code')
-- ORDER BY table_name, column_name;
-- expect (columns): NO ROWS (none of these columns exist yet on any table
-- that is present).

-- ------------------------------------------------------------
-- ai_jobs — which provider/model actually processed the job, latency,
-- whether the router had to fall back, and a normalized error code
-- (alongside the existing free-text `last_error`). Core table, referenced
-- by rpc_request_coach_reports and both AI-calling code paths — expected
-- to exist, but still guarded defensively.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ai_jobs') THEN
    ALTER TABLE public.ai_jobs
      ADD COLUMN IF NOT EXISTS provider text,
      ADD COLUMN IF NOT EXISTS model text,
      ADD COLUMN IF NOT EXISTS latency_ms integer,
      ADD COLUMN IF NOT EXISTS fallback_used boolean NOT NULL DEFAULT false,
      ADD COLUMN IF NOT EXISTS error_code text;
  ELSE
    RAISE NOTICE 'Skipped: public.ai_jobs does not exist in this project.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- ai_reports — `model` already existed (used to be stamped with a
-- misleading "gemini-2.0-flash" default in one call site, now fixed in
-- application code to record the real model); add provider + token/latency
-- observability.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ai_reports') THEN
    ALTER TABLE public.ai_reports
      ADD COLUMN IF NOT EXISTS provider text,
      ADD COLUMN IF NOT EXISTS input_tokens integer,
      ADD COLUMN IF NOT EXISTS output_tokens integer,
      ADD COLUMN IF NOT EXISTS latency_ms integer;
  ELSE
    RAISE NOTICE 'Skipped: public.ai_reports does not exist in this project.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- ai_call_logs — CONFIRMED ABSENT in this project's live database (the
-- error this correction fixes). Per Requirement 3/4: not created, not
-- altered. `src/lib/ai-quota.ts` already treats every read/write to this
-- table as optional/best-effort (its own comment: "Fallback to ai_jobs if
-- ai_call_logs table not yet migrated"; its insert is wrapped in a
-- try/catch that only warns), so no application behavior — including
-- Gemini/OpenAI routing, quota enforcement, or report generation —
-- depends on this table existing. Nothing to do here.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- ai_response_cache / ai_usage_metrics — record which provider produced a
-- cached response / usage row (both already have `model` where present).
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ai_response_cache') THEN
    ALTER TABLE public.ai_response_cache
      ADD COLUMN IF NOT EXISTS provider text;
  ELSE
    RAISE NOTICE 'Skipped: public.ai_response_cache does not exist in this project.';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ai_usage_metrics') THEN
    ALTER TABLE public.ai_usage_metrics
      ADD COLUMN IF NOT EXISTS provider text;
  ELSE
    RAISE NOTICE 'Skipped: public.ai_usage_metrics does not exist in this project.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying. Compare against your PREFLIGHT
-- table-existence result: a column only appears here for a table that
-- existed in your PREFLIGHT list.
-- ------------------------------------------------------------
-- SELECT table_name, column_name, data_type FROM information_schema.columns
-- WHERE table_schema='public' AND table_name IN ('ai_jobs','ai_reports','ai_call_logs','ai_response_cache','ai_usage_metrics')
--   AND column_name IN ('provider','input_tokens','output_tokens','latency_ms','retry_count','fallback_used','error_code')
-- ORDER BY table_name, column_name;
-- expect: ai_jobs(provider,model,latency_ms,fallback_used,error_code) IF ai_jobs exists,
--         ai_reports(provider,input_tokens,output_tokens,latency_ms) IF ai_reports exists,
--         ai_response_cache(provider) IF ai_response_cache exists,
--         ai_usage_metrics(provider) IF ai_usage_metrics exists,
--         ai_call_logs: NO ROWS (table not touched — confirmed absent).
--
-- SELECT policyname, tablename FROM pg_policies
-- WHERE schemaname='public' AND tablename IN ('ai_jobs','ai_reports','ai_response_cache');
-- expect: identical policy set to before this migration (unchanged) — this
-- migration never runs CREATE POLICY, ALTER POLICY, or DROP POLICY.
--
-- SELECT count(*) FROM public.ai_jobs;  -- expect: same row count as before applying.
-- SELECT count(*) FROM public.ai_reports;  -- expect: same row count as before applying.

-- ------------------------------------------------------------
-- ROLLBACK SCRIPT
-- ------------------------------------------------------------
-- Uncomment to undo (each guarded the same way, so also safe to run
-- against a project missing some of these tables):
-- DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_usage_metrics') THEN
--   ALTER TABLE public.ai_usage_metrics DROP COLUMN IF EXISTS provider;
-- END IF; END $$;
-- DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_response_cache') THEN
--   ALTER TABLE public.ai_response_cache DROP COLUMN IF EXISTS provider;
-- END IF; END $$;
-- DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_reports') THEN
--   ALTER TABLE public.ai_reports
--     DROP COLUMN IF EXISTS provider, DROP COLUMN IF EXISTS input_tokens,
--     DROP COLUMN IF EXISTS output_tokens, DROP COLUMN IF EXISTS latency_ms;
-- END IF; END $$;
-- DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ai_jobs') THEN
--   ALTER TABLE public.ai_jobs
--     DROP COLUMN IF EXISTS provider, DROP COLUMN IF EXISTS model,
--     DROP COLUMN IF EXISTS latency_ms, DROP COLUMN IF EXISTS fallback_used,
--     DROP COLUMN IF EXISTS error_code;
-- END IF; END $$;

-- ============================================================================
-- END OF AI_ROUTER_provider_observability_fields MIGRATION (CORRECTED)
-- ============================================================================

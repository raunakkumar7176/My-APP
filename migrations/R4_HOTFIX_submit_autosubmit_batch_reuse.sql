-- ============================================================
-- R4 BACKEND HOTFIX (live-evidence only, 2026-09-17)
--   1. rpc_submit_attempt      — 42804 enum cast in CASE
--   2. fn_auto_submit(uuid)    — missing helper called by rpc_save_answers
--   3. rpc_generate_results    — duplicate result_batches (UNIQUE test_id)
-- ============================================================
-- Nothing else is touched: no schema, RLS, grants on existing objects,
-- fn_score_attempt, rpc_save_answers, results/attempts/answers tables.
-- Run in the Supabase SQL Editor top to bottom; read the preflight output
-- before continuing past it.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_submit_attempt', 'fn_auto_submit', 'rpc_generate_results', 'fn_score_attempt')
ORDER BY p.proname;
-- expect: rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false) void, definer, search_path=public
--         rpc_generate_results(p_test_id uuid) jsonb, definer, search_path=public
--         fn_score_attempt(uuid) void
--         fn_auto_submit: NO ROW (if a row exists, STOP and report — do not run STEP 2 blindly)

SELECT conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass
ORDER BY conname;
-- expect: result_batches_pkey PRIMARY KEY (id); result_batches_test_id_key UNIQUE (test_id)

-- ------------------------------------------------------------
-- STEP 1 — rpc_submit_attempt: cast the CASE branches (ONLY change)
-- ------------------------------------------------------------
-- Why: `CASE WHEN p_auto THEN 'auto_submitted' ELSE 'submitted' END`
-- resolves to text (two untyped literals), and there is no text -> enum
-- assignment cast, so `SET status = ...` raises 42804 (proven live, 4x).
-- Body otherwise verbatim: signature/default/void, DEFINER, search_path
-- 'public', ownership check, in_progress early return, submitted_at,
-- fn_score_attempt call.
CREATE OR REPLACE FUNCTION public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a attempts;
begin
  select * into a from attempts where id = p_attempt and user_id = auth.uid() for update;
  if a.id is null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
  if a.status <> 'in_progress' then return; end if;
  update attempts
  set status = case
                 when p_auto then 'auto_submitted'::public.attempt_status
                 else 'submitted'::public.attempt_status
               end,
      submitted_at = now()
  where id = p_attempt;
  perform fn_score_attempt(p_attempt);
end $function$;

-- ------------------------------------------------------------
-- STEP 2 — fn_auto_submit(uuid): the internal helper rpc_save_answers
--          already calls (`PERFORM public.fn_auto_submit(a.id)` on the
--          `now() > a.deadline_at` branch) but which does not exist (42883).
-- ------------------------------------------------------------
-- Why this shape: it is the p_auto = true path of rpc_submit_attempt
-- without the auth.uid() ownership check — the only caller is DEFINER code
-- that has already verified auth, ownership, FOR UPDATE and in_progress.
-- Idempotent: any status other than in_progress returns without touching
-- the row, so an attempt is never re-submitted or double-scored
-- (fn_score_attempt itself also inserts results ON CONFLICT DO NOTHING).
-- search_path '' => every reference fully qualified.
CREATE OR REPLACE FUNCTION public.fn_auto_submit(p_attempt uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a public.attempts;
BEGIN
  SELECT *
    INTO a
    FROM public.attempts
   WHERE id = p_attempt
     FOR UPDATE;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;

  IF a.status <> 'in_progress'::public.attempt_status THEN
    RETURN;
  END IF;

  UPDATE public.attempts
     SET status       = 'auto_submitted'::public.attempt_status,
         submitted_at = now()
   WHERE id = p_attempt;

  PERFORM public.fn_score_attempt(p_attempt);
END
$function$;

-- Internal only: never client-callable. DEFINER callers (rpc_save_answers)
-- execute as the function owner, so no client grant is needed.
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM authenticated;

-- ------------------------------------------------------------
-- STEP 3 — rpc_generate_results: reuse ANY existing batch for the test
-- ------------------------------------------------------------
-- Why: result_batches has UNIQUE (test_id) — exactly one batch per test —
-- but the live body only reuses pending/processing batches and otherwise
-- INSERTs, so a test whose batch is completed/failed hits
-- result_batches_test_id_key (proven live, batch 8c282e91… status completed).
--
-- !! BLOCKED — the live body was supplied with its processing section
-- !! elided ("..."). It must be preserved verbatim, so this step is not
-- !! runnable until the full `pg_get_functiondef` text is pasted in.
-- !! The ONLY change to make is the block below, inserted immediately after
-- !! the GENERATE_RESULTS_FORBIDDEN authorization check and BEFORE the
-- !! existing "pending/processing" lookup + INSERT. Everything else,
-- !! including the processing loop and the final jsonb_build_object,
-- !! stays byte-for-byte. Do not modify the existing batch row.
--
--   -- Reuse: result_batches is UNIQUE (test_id), so at most one row can
--   -- exist. Any existing batch (pending, processing, completed, failed)
--   -- is returned as-is with reused = true; a second INSERT is impossible.
--   SELECT *
--     INTO v_batch
--     FROM public.result_batches
--    WHERE test_id = p_test_id
--    LIMIT 1;
--
--   IF v_batch.id IS NOT NULL THEN
--     RETURN jsonb_build_object(
--       'batch_id',      v_batch.id,
--       'test_id',       v_batch.test_id,
--       'status',        v_batch.status,
--       'reports_done',  v_batch.reports_done,
--       'reports_total', v_batch.reports_total,
--       'errors',        0,
--       'reused',        true
--     );
--   END IF;
--
-- NOTE for the paste: if the live final RETURN builds `errors` from
-- v_errors, keep that expression there; the reuse branch returns 0 because
-- no processing ran in this call. Match the key names exactly to the live
-- final RETURN so the client contract is unchanged.

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_submit_attempt', 'fn_auto_submit', 'rpc_generate_results')
ORDER BY p.proname;
-- expect: fn_auto_submit(p_attempt uuid) void, prosecdef = true, proconfig = {search_path=}

SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: both CASE branches end with ::public.attempt_status
SELECT pg_get_functiondef('public.fn_auto_submit(uuid)'::regprocedure);

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('fn_auto_submit', 'rpc_submit_attempt', 'rpc_generate_results')
ORDER BY 1, 2;
-- expect: fn_auto_submit has NO anon/authenticated/PUBLIC row;
--         rpc_submit_attempt / rpc_generate_results grants unchanged from preflight

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass;
-- expect: unchanged (pkey + UNIQUE (test_id))

-- Behavioural check (as the attempt owner, on an in_progress attempt):
--   SELECT public.rpc_submit_attempt('<attempt-uuid>', false);
--   SELECT id, status, submitted_at FROM public.attempts WHERE id = '<attempt-uuid>';
--     -- expect status = scored (fn_score_attempt) and one results row
--   SELECT public.rpc_submit_attempt('<attempt-uuid>', false);   -- no-op (not in_progress)

-- ============================================================
-- SUPERSEDED — do NOT apply this file.
-- Replaced by migrations/FINAL_AUDIT_fix_rpc_submit_attempt_deadline.sql,
-- which is built against live-audited facts (deadline_at is NOT NULL,
-- live search_path is 'public', explicit >= boundary) rather than this
-- file's static-analysis guesses. Kept only for history.
-- ============================================================
-- R4 BACKEND HOTFIX — rpc_submit_attempt has no deadline check
-- (found by static code audit 2026-09-21, NOT yet proven live — see
--  preflight below; this is a code-review finding, not a reproduced bug)
-- ============================================================
-- Problem: rpc_submit_attempt (as defined in
-- R4_HOTFIX_submit_autosubmit_batch_reuse.sql) checks only
-- `a.status <> 'in_progress'` before finalizing an attempt. It never
-- compares now() to a.deadline_at, and it trusts the client-supplied
-- p_auto boolean as-is. Only rpc_save_answers' autosave path enforces
-- the deadline (forcing fn_auto_submit when now() > a.deadline_at). So
-- a client that stops autosaving before the deadline and only calls
-- rpc_submit_attempt(attempt_id, false) after the deadline has passed
-- gets that submission accepted, scored, and recorded as an on-time
-- 'submitted' attempt (not 'auto_submitted') — i.e. the server-computed
-- deadline is not authoritative at the one call that actually finalizes
-- the attempt. This hotfix makes rpc_submit_attempt itself deadline-aware,
-- mirroring the check already proven in rpc_save_answers.
--
-- Nothing else is touched: no schema, RLS, grants, fn_score_attempt,
-- fn_auto_submit, rpc_save_answers, rpc_generate_results.
-- Run in the Supabase SQL Editor top to bottom; read the preflight output
-- before continuing past it. Do NOT apply until the preflight confirms
-- the function signature matches what this file expects to replace.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: the body from R4_HOTFIX_submit_autosubmit_batch_reuse.sql —
-- if the live body already contains a deadline_at comparison, STOP:
-- this hotfix is unnecessary or a different fix already landed.

-- ------------------------------------------------------------
-- STEP 1 — rpc_submit_attempt: enforce the server deadline at the
--          finalization point, not only at autosave.
-- ------------------------------------------------------------
-- Behaviour: if now() > a.deadline_at, the submission is still accepted
-- (never silently dropped — a legitimate final submit that lands a few
-- seconds late due to network lag must not error out), but it is always
-- recorded as auto_submitted, regardless of the client's p_auto value.
-- An attempt with no deadline (untimed / practice) is unaffected.
CREATE OR REPLACE FUNCTION public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a attempts;
declare v_late boolean;
begin
  select * into a from attempts where id = p_attempt and user_id = auth.uid() for update;
  if a.id is null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
  if a.status <> 'in_progress' then return; end if;
  v_late := a.deadline_at is not null and now() > a.deadline_at;
  update attempts
  set status = case
                 when p_auto or v_late then 'auto_submitted'::public.attempt_status
                 else 'submitted'::public.attempt_status
               end,
      submitted_at = now()
  where id = p_attempt;
  perform fn_score_attempt(p_attempt);
end $function$;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: contains `v_late := a.deadline_at is not null and now() > a.deadline_at`
-- and the CASE now reads `when p_auto or v_late then 'auto_submitted'...`

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'rpc_submit_attempt'
ORDER BY 1, 2;
-- expect: unchanged from before this hotfix (same grantees as rpc_save_answers callers)

-- Behavioural check (requires a real attempt whose deadline_at is already
-- in the past and whose status is still in_progress):
--   SELECT public.rpc_submit_attempt('<attempt-uuid>', false);
--   SELECT id, status, submitted_at FROM public.attempts WHERE id = '<attempt-uuid>';
--     -- expect status = 'scored' or 'auto_submitted' pre-scoring race, never 'submitted'

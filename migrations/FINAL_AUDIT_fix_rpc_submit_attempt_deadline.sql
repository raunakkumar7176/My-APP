-- ============================================================
-- FINAL AUDIT — rpc_submit_attempt: enforce attempts.deadline_at
-- ============================================================
-- Supersedes the earlier speculative draft
-- migrations/R4_HOTFIX_submit_deadline_check.sql (do NOT apply that file —
-- this one replaces it, built against live-audited facts instead of
-- static migration-file text: attempts.deadline_at is `timestamptz NOT
-- NULL`, live rpc_submit_attempt has `search_path=public`, and the
-- explicit boundary chosen below is `now() >= deadline_at`, per this
-- task's own requirement 11).
--
-- WHY: _fn_start_attempt_core computes and stores deadline_at
-- server-side (`LEAST(now() + duration_sec, tests.ends_at)`) — the
-- client never sets it. rpc_save_answers already enforces it on
-- autosave (`IF now() > a.deadline_at THEN PERFORM fn_auto_submit(...)`).
-- But rpc_submit_attempt — the RPC that actually finalizes and scores
-- an attempt — only checks `status = 'in_progress'`; it trusts the
-- client's `p_auto` boolean as-is and never compares now() to
-- deadline_at. A client that stops autosaving before the deadline and
-- calls rpc_submit_attempt(id, false) after the deadline has passed
-- gets that submission accepted, scored, and recorded as an on-time
-- 'submitted' attempt — extra, undetected time past the real deadline.
--
-- SCOPE DISCIPLINE (per task requirements 2-8, 13-16):
--   - No schema change. attempts/tests columns are untouched.
--   - fn_score_attempt is called exactly as before, unchanged, exactly
--     once per successful transition out of in_progress.
--   - rpc_start_attempt / _fn_start_attempt_core are untouched.
--   - No RLS is touched (this RPC's security boundary is entirely
--     SECURITY DEFINER + auth.uid(), no table policy is involved here).
--   - Ownership check (`user_id = auth.uid()`) and `FOR UPDATE` locking
--     are preserved verbatim.
--   - Idempotency is preserved verbatim: `status <> 'in_progress'`
--     returns without touching the row or rescoring.
--   - SECURITY DEFINER is preserved. search_path is tightened from the
--     live `'public'` to `''` with every reference fully schema-
--     qualified (public.attempts, public.attempt_status,
--     public.fn_score_attempt) — strictly safer, never weaker, and
--     brings this function in line with the project's own dominant
--     hardening convention (confirmed by static audit: ~30 of this
--     project's SECURITY DEFINER functions already use search_path='').
--
-- Run in the Supabase SQL Editor top to bottom. Read the preflight
-- output before continuing past it. This migration is NOT applied
-- automatically by this pass — no live database access exists in the
-- environment that authored it.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef,
       p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_submit_attempt';
-- expect (per this task's live audit): args "p_attempt uuid, p_auto
-- boolean DEFAULT false", returns void, prosecdef = true,
-- proconfig = {search_path=public}. If proconfig already shows
-- search_path= (empty) AND the body already references deadline_at,
-- STOP: this fix may already be applied, do not reapply blindly.

SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: the body matches the "OLD BEHAVIOR (for rollback)" block below.

-- ------------------------------------------------------------
-- STEP 1 — rpc_submit_attempt: deadline-aware, tightened search_path
-- ------------------------------------------------------------
-- Behaviour (per requirements 10-12):
--   now() <  deadline_at  → status follows p_auto exactly as before
--                            (false → submitted, true → auto_submitted)
--   now() >= deadline_at  → status is ALWAYS auto_submitted, regardless
--                            of p_auto (the client cannot bypass expiry
--                            by passing p_auto=false)
-- submitted_at is always now() (server clock), never client-supplied.
-- fn_score_attempt still runs exactly once, only on the single UPDATE
-- path that flips status out of in_progress — unchanged call shape.
CREATE OR REPLACE FUNCTION public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a public.attempts;
  v_expired boolean;
BEGIN
  SELECT *
    INTO a
    FROM public.attempts
   WHERE id = p_attempt
     AND user_id = auth.uid()
     FOR UPDATE;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;

  IF a.status <> 'in_progress'::public.attempt_status THEN
    RETURN;
  END IF;

  v_expired := now() >= a.deadline_at;

  UPDATE public.attempts
     SET status = CASE
                     WHEN p_auto OR v_expired
                       THEN 'auto_submitted'::public.attempt_status
                     ELSE 'submitted'::public.attempt_status
                   END,
         submitted_at = now()
   WHERE id = p_attempt;

  PERFORM public.fn_score_attempt(p_attempt);
END
$function$;

-- Grants are unchanged by this migration — CREATE OR REPLACE preserves
-- existing GRANTs on a function. No GRANT/REVOKE statement is needed
-- here; this line is a note, not an executable no-op.

-- ------------------------------------------------------------
-- OLD BEHAVIOR (for rollback) — run this block only to revert
-- ------------------------------------------------------------
-- CREATE OR REPLACE FUNCTION public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)
--  RETURNS void
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- declare a attempts;
-- begin
--   select * into a from attempts where id = p_attempt and user_id = auth.uid() for update;
--   if a.id is null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
--   if a.status <> 'in_progress' then return; end if;
--   update attempts
--   set status = case
--                  when p_auto then 'auto_submitted'::public.attempt_status
--                  else 'submitted'::public.attempt_status
--                end,
--       submitted_at = now()
--   where id = p_attempt;
--   perform fn_score_attempt(p_attempt);
-- end $function$;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_submit_attempt';
-- expect: proconfig = {search_path=}

SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: contains `v_expired := now() >= a.deadline_at` and
-- `WHEN p_auto OR v_expired THEN 'auto_submitted'`

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_submit_attempt'
ORDER BY 1, 2;
-- expect: unchanged from preflight (same grantees, e.g. authenticated)

-- ------------------------------------------------------------
-- TEST MATRIX (manual / staging verification only — NOT run
-- automatically by this migration; requires real attempt rows and is
-- meant to be executed by whoever has live/staging database access)
-- ------------------------------------------------------------
-- Setup for each case: an attempt row owned by the test user, status
-- in_progress, with deadline_at set relative to now() as noted.
--
-- 1. Submit before deadline, p_auto=false:
--      UPDATE attempts SET deadline_at = now() + interval '10 minutes',
--        status = 'in_progress' WHERE id = '<a>';
--      SELECT rpc_submit_attempt('<a>', false);
--      SELECT status, submitted_at FROM attempts WHERE id = '<a>';
--      -- expect: status = 'scored' (post fn_score_attempt), i.e. was
--      -- set to 'submitted' before scoring; never 'auto_submitted'.
--
-- 2. Submit before deadline, p_auto=true:
--      (reset row) SELECT rpc_submit_attempt('<a>', true);
--      -- expect: recorded as auto_submitted before scoring (client
--      -- explicitly said timed out, honored even though not expired).
--
-- 3. Submit exactly at the deadline boundary, p_auto=false:
--      UPDATE attempts SET deadline_at = now(), status = 'in_progress'
--        WHERE id = '<a>';
--      SELECT rpc_submit_attempt('<a>', false);
--      -- expect: auto_submitted — boundary is inclusive (`now() >=
--      -- deadline_at`), per requirement 11's explicit wording.
--
-- 4. Submit after deadline, p_auto=false (the vulnerability this
--    migration closes):
--      UPDATE attempts SET deadline_at = now() - interval '1 minute',
--        status = 'in_progress' WHERE id = '<a>';
--      SELECT rpc_submit_attempt('<a>', false);
--      SELECT status FROM attempts WHERE id = '<a>';
--      -- expect: auto_submitted, NOT submitted — this is the fix.
--
-- 5. Submit after deadline, p_auto=true:
--      (reset row, deadline in the past) SELECT rpc_submit_attempt('<a>', true);
--      -- expect: auto_submitted (both conditions agree).
--
-- 6. Duplicate submit (idempotency):
--      SELECT rpc_submit_attempt('<a>', false); -- first call, terminal state reached
--      SELECT rpc_submit_attempt('<a>', false); -- second call
--      -- expect: second call is a silent no-op (returns void, no
--      -- error); status/submitted_at unchanged by the second call;
--      -- exactly one row in `results` for this attempt (see #9).
--
-- 7. Forged / nonexistent attempt id:
--      SELECT rpc_submit_attempt('00000000-0000-0000-0000-000000000000', false);
--      -- expect: raises ATTEMPT_NOT_FOUND.
--
-- 8. Another user's attempt (as a different authenticated user):
--      SELECT rpc_submit_attempt('<attempt-owned-by-someone-else>', false);
--      -- expect: raises ATTEMPT_NOT_FOUND (the WHERE clause filters on
--      -- user_id = auth.uid(), so a non-owned id simply never matches
--      -- — this correctly avoids confirming the row's existence to a
--      -- non-owner, rather than raising a distinct "forbidden" error).
--
-- 9. Scoring runs exactly once:
--      SELECT count(*) FROM results WHERE attempt_id = '<a>';
--      -- run once right after case 1 or 4, and again after the
--      -- duplicate-submit call in case 6 — expect count = 1 both times.
--
-- 10. Server timestamp is authoritative:
--      -- There is no p_submitted_at parameter on this function at
--      -- all — submitted_at is always `now()` inside the function
--      -- body, so there is no code path by which a client could pass
--      -- a timestamp. Confirm by reading the function signature
--      -- (preflight/postflight query above) rather than a runtime
--      -- test: `pg_get_function_arguments` should show only
--      -- `p_attempt uuid, p_auto boolean DEFAULT false`.

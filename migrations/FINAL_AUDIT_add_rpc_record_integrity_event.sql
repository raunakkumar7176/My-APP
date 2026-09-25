-- ============================================================
-- FINAL AUDIT — additive: server-authoritative integrity events
-- ============================================================
-- This is a NEW function only. No table, column, enum, or existing
-- function is altered. Live-audited facts this migration relies on
-- (per the prior FINAL_AUDIT task in this same series):
--   public.attempts already has integrity_event_count (int, NOT NULL),
--   auto_submit_threshold (int, NOT NULL), and (per R4_1_phase_db_
--   foundation.sql) a `violations jsonb DEFAULT '[]'` column commented
--   "JSONB array of {type, timestamp, details} for integrity events" —
--   i.e. the architecture already provides an event-storage column;
--   this migration is the first thing that actually writes to it. No
--   new event table is created, per this task's own instruction not
--   to invent one if the existing architecture already has it.
--   fn_auto_submit(uuid) already exists (R4_HOTFIX_submit_autosubmit_
--   batch_reuse.sql) — internal-only (REVOKEd from PUBLIC/anon/
--   authenticated), calls fn_score_attempt exactly once, idempotent.
--   rpc_submit_attempt is already deadline-hardened (FINAL_AUDIT_
--   fix_rpc_submit_attempt_deadline.sql) — untouched here.
--
-- Run in the Supabase SQL Editor top to bottom. NOT applied
-- automatically — no live database access exists in the environment
-- that authored this file.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'attempts'
  AND column_name IN ('integrity_event_count', 'auto_submit_threshold', 'violations')
ORDER BY column_name;
-- expect: all three columns exist; violations is jsonb.

SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_record_integrity_event';
-- expect: NO ROW. If a row exists, STOP — this function may already
-- exist under a different design; do not blindly overwrite it.

SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_auto_submit';
-- expect: prosecdef = true, proconfig = {search_path=}. If NO ROW,
-- STOP — this migration depends on fn_auto_submit already existing.

-- ------------------------------------------------------------
-- STEP 1 — rpc_record_integrity_event: record one event, atomically
--          increment the count, and auto-submit if the threshold is
--          reached — all in one server-authoritative transaction.
-- ------------------------------------------------------------
-- Design notes:
--  - Ownership: identical pattern to rpc_submit_attempt — SELECT ...
--    WHERE id = p_attempt AND user_id = auth.uid() FOR UPDATE. A
--    forged/nonexistent/other-user's attempt id simply never matches
--    the WHERE clause, so it raises the same ATTEMPT_NOT_FOUND rather
--    than a distinct "forbidden" error that would confirm the row's
--    existence to a non-owner.
--  - Test-relationship check: p_test_id must equal the locked
--    attempt's own test_id, or the call is rejected — a client cannot
--    record an event against attempt A while claiming it belongs to
--    test B.
--  - Terminal-state handling: once status is not 'in_progress', the
--    call is a silent no-op (mirrors rpc_submit_attempt's own
--    idempotency guard) — it returns a jsonb payload describing that
--    nothing was recorded, rather than raising, so the client doesn't
--    need to special-case "the test just ended" as an error.
--  - Duplicate suppression: if the most recent entry already in
--    `violations` has the SAME event type and is less than 3 seconds
--    old, the count is NOT incremented again — this is server-side
--    defense-in-depth against one physical lifecycle transition
--    firing the client callback twice; the client is still expected
--    to debounce on its own (see Flutter implementation).
--  - Threshold: `auto_submit_threshold IS NOT NULL AND > 0` is treated
--    as "auto-submit is configured" (see the deliverable report for
--    why 0 was NOT treated as "submit on the very first event" — this
--    is flagged as an explicit assumption, not a proven fact, because
--    this environment has no live data showing what value real rows
--    actually carry or what 0 is meant to signal).
--  - Scoring: fn_auto_submit is called at most once per call to this
--    function (inside the `v_count >= threshold` branch only), and
--    fn_auto_submit is itself idempotent (re-checks status ==
--    in_progress before doing anything) — so even if this function
--    were somehow invoked twice in a race, scoring still cannot run
--    twice for the same attempt.
CREATE OR REPLACE FUNCTION public.rpc_record_integrity_event(
  p_attempt uuid,
  p_test_id uuid,
  p_event_type text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  a public.attempts;
  v_count integer;
  v_auto_submitted boolean := false;
  v_last jsonb;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_event_type IS NULL OR length(trim(p_event_type)) = 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: event type is required';
  END IF;

  SELECT *
    INTO a
    FROM public.attempts
   WHERE id = p_attempt
     AND user_id = auth.uid()
     FOR UPDATE;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;

  IF a.test_id <> p_test_id THEN
    RAISE EXCEPTION 'TEST_MISMATCH';
  END IF;

  IF a.status <> 'in_progress'::public.attempt_status THEN
    RETURN jsonb_build_object(
      'event_recorded', false,
      'integrity_event_count', a.integrity_event_count,
      'auto_submit_threshold', a.auto_submit_threshold,
      'auto_submitted', false,
      'reason', 'ATTEMPT_NOT_IN_PROGRESS'
    );
  END IF;

  v_last := CASE
              WHEN jsonb_array_length(coalesce(a.violations, '[]'::jsonb)) > 0
                THEN a.violations -> (jsonb_array_length(a.violations) - 1)
              ELSE NULL
            END;

  IF v_last IS NOT NULL
     AND v_last ->> 'type' = p_event_type
     AND (v_last ->> 'timestamp')::timestamptz > v_now - interval '3 seconds'
  THEN
    RETURN jsonb_build_object(
      'event_recorded', false,
      'integrity_event_count', a.integrity_event_count,
      'auto_submit_threshold', a.auto_submit_threshold,
      'auto_submitted', false,
      'reason', 'DUPLICATE_SUPPRESSED'
    );
  END IF;

  UPDATE public.attempts
     SET integrity_event_count = integrity_event_count + 1,
         violations = coalesce(violations, '[]'::jsonb) || jsonb_build_array(
           jsonb_build_object(
             'type', p_event_type,
             'timestamp', v_now,
             'details', coalesce(p_details, '{}'::jsonb)
           )
         )
   WHERE id = p_attempt
  RETURNING integrity_event_count INTO v_count;

  IF a.auto_submit_threshold IS NOT NULL
     AND a.auto_submit_threshold > 0
     AND v_count >= a.auto_submit_threshold
  THEN
    PERFORM public.fn_auto_submit(p_attempt);
    v_auto_submitted := true;
  END IF;

  RETURN jsonb_build_object(
    'event_recorded', true,
    'integrity_event_count', v_count,
    'auto_submit_threshold', a.auto_submit_threshold,
    'auto_submitted', v_auto_submitted
  );
END
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_record_integrity_event(uuid, uuid, text, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_record_integrity_event(uuid, uuid, text, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_record_integrity_event(uuid, uuid, text, jsonb) FROM PUBLIC;

COMMENT ON FUNCTION public.rpc_record_integrity_event(uuid, uuid, text, jsonb) IS
  'Records one client-observed integrity event against the caller''s own in_progress attempt, atomically increments integrity_event_count, and auto-submits (via fn_auto_submit) exactly once if auto_submit_threshold is reached. Server time and server-held counters are authoritative; the client only reports event occurrences, never a count.';

-- ------------------------------------------------------------
-- ROLLBACK — this migration is purely additive (one new function, no
-- schema/column change), so rollback is a single DROP.
-- ------------------------------------------------------------
-- DROP FUNCTION IF EXISTS public.rpc_record_integrity_event(uuid, uuid, text, jsonb);

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_record_integrity_event';
-- expect: prosecdef = true, proconfig = {search_path=}

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_record_integrity_event'
ORDER BY 1, 2;
-- expect: authenticated has EXECUTE; no anon/PUBLIC row.

-- ------------------------------------------------------------
-- SECURITY TEST MATRIX (manual / staging verification only — NOT run
-- automatically; requires real attempt rows and live/staging access)
-- ------------------------------------------------------------
-- Setup: an attempt row owned by the test user, status in_progress,
-- integrity_event_count = 0, auto_submit_threshold = 3 (example).
--
-- 1. Own active attempt:
--      SELECT rpc_record_integrity_event('<a>', '<test-id-of-a>', 'app_backgrounded');
--      -- expect: event_recorded=true, integrity_event_count=1.
--
-- 2. Another user's attempt (as a different authenticated user):
--      SELECT rpc_record_integrity_event('<attempt-owned-by-someone-else>', '<test-id>', 'app_backgrounded');
--      -- expect: raises ATTEMPT_NOT_FOUND.
--
-- 3. Nonexistent attempt:
--      SELECT rpc_record_integrity_event('00000000-0000-0000-0000-000000000000', '<test-id>', 'app_backgrounded');
--      -- expect: raises ATTEMPT_NOT_FOUND.
--
-- 4. Terminal attempt (already submitted/scored):
--      SELECT rpc_record_integrity_event('<submitted-attempt>', '<test-id>', 'app_backgrounded');
--      -- expect: event_recorded=false, reason='ATTEMPT_NOT_IN_PROGRESS', no error, count unchanged.
--
-- 5. Wrong test relationship:
--      SELECT rpc_record_integrity_event('<a>', '<a-different-test-id>', 'app_backgrounded');
--      -- expect: raises TEST_MISMATCH.
--
-- 6. Forged user_id: impossible by construction — the function has no
--    p_user_id parameter; the actor is always auth.uid() from the JWT.
--
-- 7. Client attempts to set count directly: impossible by
--    construction — there is no p_count/p_integrity_event_count
--    parameter; the only mutation is `integrity_event_count + 1` via
--    UPDATE inside this DEFINER function.
--
-- 8. Repeated valid events (distinct types, or same type >3s apart):
--      SELECT rpc_record_integrity_event('<a>', '<test-id>', 'app_backgrounded');
--      SELECT rpc_record_integrity_event('<a>', '<test-id>', 'multi_window_entered');
--      -- expect: integrity_event_count increments by exactly 1 each call (2 total).
--
-- 9. Threshold reached → exactly one auto-submit:
--      -- with auto_submit_threshold=3 and count already at 2:
--      SELECT rpc_record_integrity_event('<a>', '<test-id>', 'app_backgrounded');
--      SELECT status, submitted_at FROM attempts WHERE id = '<a>';
--      -- expect: auto_submitted=true in the RPC's own return value,
--      -- attempts.status = 'auto_submitted' (then 'scored' once
--      -- fn_score_attempt completes), exactly one row in `results`
--      -- for this attempt.
--
-- 10. Event after auto-submit:
--      SELECT rpc_record_integrity_event('<a>', '<test-id>', 'app_backgrounded');
--      -- (same attempt as #9, now terminal) expect: event_recorded=false,
--      -- reason='ATTEMPT_NOT_IN_PROGRESS', no further mutation.
--
-- 11. Duplicate lifecycle callback (same type, <3s apart):
--      SELECT rpc_record_integrity_event('<a2>', '<test-id>', 'app_backgrounded');
--      SELECT rpc_record_integrity_event('<a2>', '<test-id>', 'app_backgrounded'); -- immediately after
--      -- expect: second call returns event_recorded=false,
--      -- reason='DUPLICATE_SUPPRESSED', count unchanged by the second call.

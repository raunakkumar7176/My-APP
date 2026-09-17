-- ============================================================
-- R4 — ATTEMPT / RE-ATTEMPT POLICY (server-authoritative), 2026-09-17
-- ============================================================
-- Product rule: a completed attempt never silently becomes a new one.
-- Only an explicit re-attempt (p_reattempt = true) may allocate attempt N+1,
-- and only within the test's configured limit:
--   tests.settings.allow_reattempt  boolean, default false
--   tests.settings.max_attempts     integer, default 1  (V1 UI: 1/2/3/5/10)
--   allow_reattempt = false  =>  effective max = 1
-- No schema change (settings jsonb already round-trips through
-- rpc_create_test / rpc_update_test). No RLS change. No new constraint
-- (UNIQUE(test_id,user_id,attempt_number) stays the final guard).
--
-- Baseline bodies: R4_7_6 (signature-verified live:
-- _fn_start_attempt_core(p_test uuid, p_code_verified boolean DEFAULT false)
-- RETURNS public.attempts; behaviour-verified live: resume in_progress,
-- MAX(attempt_number)+1, now() >= ends_at hard block, LATE_JOIN_NOT_ALLOWED).
-- Changes, and nothing else:
--   core   : + p_reattempt param; + policy block after resume / before
--            late-join; INSERT wrapped so a unique_violation surfaces as
--            ATTEMPT_ALLOCATION_CONFLICT instead of a raw constraint error.
--   rpc_start_attempt(p_test uuid, p_reattempt boolean DEFAULT false)
--   rpc_start_attempt_by_code(p_code text, p_reattempt boolean DEFAULT false)
--            pass the flag through. Defaulted params keep existing callers
--            ({p_test} / {p_code}) resolvable by PostgREST; the old
--            signatures are DROPPED first so no ambiguous overload exists.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
SELECT p.proname, pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid) AS returns, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code')
ORDER BY p.proname, args;
-- expect exactly three rows:
--   _fn_start_attempt_core    | p_test uuid, p_code_verified boolean DEFAULT false | attempts | t | {search_path=}
--   rpc_start_attempt         | p_test uuid                                        | attempts | t | {search_path=}
--   rpc_start_attempt_by_code | p_code text                                        | attempts | t | {search_path=}

SELECT
  pg_get_functiondef(p.oid) LIKE '%p_code_verified = true%'                 AS has_code_verified_path,
  pg_get_functiondef(p.oid) LIKE '%now() >= v_test.ends_at%'                AS has_ends_at_hard_block,
  pg_get_functiondef(p.oid) LIKE '%COALESCE(MAX(a.attempt_number), 0) + 1%' AS has_max_plus_one,
  pg_get_functiondef(p.oid) LIKE '%LATE_JOIN_NOT_ALLOWED%'                  AS has_late_join_rule,
  pg_get_functiondef(p.oid) LIKE '%in_progress%'                            AS has_resume
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = '_fn_start_attempt_core';
-- expect: t | t | t | t | t   (the live body is the R4_7_6 baseline)
-- If any is f, paste pg_get_functiondef and STOP — the baseline differs.

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code')
ORDER BY 1, 2;
-- note the current grants; they are re-applied identically below
-- (expected: rpc_* -> authenticated only; core -> no client role)

SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'tests' AND column_name = 'settings';
-- expect: settings | jsonb

-- ------------------------------------------------------------
-- STEP 1 — drop the old signatures (prevents ambiguous overloads)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.rpc_start_attempt(uuid);
DROP FUNCTION IF EXISTS public.rpc_start_attempt_by_code(text);
DROP FUNCTION IF EXISTS public._fn_start_attempt_core(uuid, boolean);

-- ------------------------------------------------------------
-- STEP 2 — _fn_start_attempt_core with the attempt policy
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_start_attempt_core(
  p_test uuid,
  p_code_verified boolean DEFAULT false,
  p_reattempt boolean DEFAULT false
)
RETURNS public.attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
  v_attempt public.attempts%ROWTYPE;
  v_deadline timestamptz;
  v_status text;
  v_next_number integer;
  v_used integer;
  v_allow_reattempt boolean;
  v_max_attempts integer;
BEGIN
  -- ── Auth check ──────────────────────────────────────────
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- ── Load and lock test row ──────────────────────────────
  SELECT t.* INTO v_test
  FROM public.tests t
  WHERE t.id = p_test
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- ── Soft-delete check ───────────────────────────────────
  IF v_test.is_soft_deleted THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  -- ── Access control (restored original branching) ────────
  -- creator → allowed
  -- group test → fn_is_member required
  -- standalone + p_code_verified=true → allowed
  -- standalone + p_code_verified=false → fn_can_access_test
  IF v_test.created_by = v_uid THEN
    NULL;
  ELSIF v_test.group_id IS NOT NULL THEN
    IF NOT public.fn_is_member(v_test.group_id, v_uid) THEN
      RAISE EXCEPTION 'NOT_MEMBER';
    END IF;
  ELSE
    IF p_code_verified = true THEN
      NULL;
    ELSE
      IF NOT public.fn_can_access_test(p_test) THEN
        RAISE EXCEPTION 'TEST_ACCESS_DENIED';
      END IF;
    END IF;
  END IF;

  -- ── Lifecycle check ─────────────────────────────────────
  v_status := v_test.status::text;

  IF v_status IN ('cancelled', 'archived', 'expired') THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  IF v_status IN ('completed', 'ended', 'evaluated') THEN
    RAISE EXCEPTION 'TEST_ENDED';
  END IF;

  IF v_status NOT IN ('scheduled', 'live', 'ready', 'published') THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  -- ── Timing: starts_at check ────────────────────────────
  -- Performed BEFORE scheduled→live so future scheduled tests
  -- remain scheduled and return TEST_NOT_STARTED.
  IF v_test.starts_at IS NOT NULL AND now() < v_test.starts_at THEN
    RAISE EXCEPTION 'TEST_NOT_STARTED';
  END IF;

  -- ── Timing: ends_at check (hard block) ─────────────────
  -- ends_at is always a hard block. allow_late_join does NOT
  -- bypass this check. Late-join behavior is separate.
  IF v_test.ends_at IS NOT NULL AND now() >= v_test.ends_at THEN
    RAISE EXCEPTION 'TEST_ENDED';
  END IF;

  -- ════════════════════════════════════════════════════════
  -- RESUME: Return existing in-progress attempt if one exists.
  -- Only 'in_progress' is a valid non-terminal status.
  -- Do NOT use 'active' (not in enum).
  -- If multiple in_progress exist (data anomaly), return most recent.
  -- ════════════════════════════════════════════════════════
  SELECT a.* INTO v_attempt
  FROM public.attempts a
  WHERE a.test_id = p_test
    AND a.user_id = v_uid
    AND a.status = 'in_progress'
  ORDER BY a.started_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN v_attempt;
  END IF;

  -- ── Attempt policy (R4 re-attempt) ──────────────────────
  -- Runs ONLY when a NEW attempt would be allocated (resume returned above).
  -- Counts this user's attempts on this test in every status. Config lives
  -- in tests.settings: allow_reattempt (bool, default false) and
  -- max_attempts (int, default 1); allow_reattempt=false forces max 1.
  -- A completed attempt never silently becomes a new one: after any prior
  -- attempt, a new one requires the explicit p_reattempt=true intent.
  SELECT count(*) INTO v_used
  FROM public.attempts a
  WHERE a.test_id = p_test
    AND a.user_id = v_uid;

  v_allow_reattempt := COALESCE((v_test.settings->>'allow_reattempt')::boolean, false);
  IF v_allow_reattempt THEN
    v_max_attempts := GREATEST(1, COALESCE((v_test.settings->>'max_attempts')::integer, 1));
  ELSE
    v_max_attempts := 1;
  END IF;

  IF v_used >= v_max_attempts THEN
    RAISE EXCEPTION 'REATTEMPT_LIMIT_REACHED';
  END IF;

  IF v_used > 0 AND NOT COALESCE(p_reattempt, false) THEN
    RAISE EXCEPTION 'ATTEMPT_ALREADY_COMPLETED';
  END IF;

  -- ── Late-join check (restored original logic) ───────────
  -- Blocks new attempts after starts_at unless allow_late_join.
  -- Must run AFTER resume (in-progress user can always resume).
  -- Must run BEFORE max_participants (late-join is independent).
  IF v_test.allow_late_join = false
     AND v_test.test_mode = 'live'
     AND v_test.starts_at IS NOT NULL
     AND now() > v_test.starts_at
  THEN
    RAISE EXCEPTION 'LATE_JOIN_NOT_ALLOWED';
  END IF;

  -- ── Max participants (DISTINCT users) ───────────────────
  IF v_test.max_participants IS NOT NULL THEN
    IF (
      SELECT count(DISTINCT a.user_id)
      FROM public.attempts a
      WHERE a.test_id = p_test
    ) >= v_test.max_participants THEN
      RAISE EXCEPTION 'TEST_FULL';
    END IF;
  END IF;

  -- ════════════════════════════════════════════════════════
  -- ALLOCATE attempt_number
  -- Uses MAX+1 for same (test_id, user_id).
  -- COALESCE handles first attempt (no rows → 0+1 = 1).
  -- ════════════════════════════════════════════════════════
  SELECT COALESCE(MAX(a.attempt_number), 0) + 1
  INTO v_next_number
  FROM public.attempts a
  WHERE a.test_id = p_test
    AND a.user_id = v_uid;

  -- ════════════════════════════════════════════════════════
  -- DEADLINE CALCULATION
  -- Uses duration_sec only (verified live column).
  -- ════════════════════════════════════════════════════════
  IF v_test.ends_at IS NOT NULL THEN
    v_deadline := LEAST(
      now() + (COALESCE(v_test.duration_sec, 3600) || ' seconds')::interval,
      v_test.ends_at
    );
  ELSE
    v_deadline := now() + (COALESCE(v_test.duration_sec, 3600) || ' seconds')::interval;
  END IF;

  -- ════════════════════════════════════════════════════════
  -- CREATE NEW ATTEMPT
  -- attempt_number is set server-side. Never from client.
  -- UNIQUE(test_id,user_id,attempt_number) is the final guard.
  -- ════════════════════════════════════════════════════════
  BEGIN
    INSERT INTO public.attempts (
      test_id,
      user_id,
      attempt_number,
      status,
      started_at,
      deadline_at
    ) VALUES (
      p_test,
      v_uid,
      v_next_number,
      'in_progress',
      now(),
      v_deadline
    )
    RETURNING * INTO v_attempt;
  EXCEPTION WHEN unique_violation THEN
    -- UNIQUE(test_id,user_id,attempt_number) tripped by a concurrent start:
    -- deterministic code instead of a raw constraint error; the caller retries.
    RAISE EXCEPTION 'ATTEMPT_ALLOCATION_CONFLICT';
  END;

  -- ── scheduled → live transition ─────────────────────────
  -- Performed AFTER successful attempt start, not before.
  IF v_status = 'scheduled' THEN
    UPDATE public.tests
    SET status = 'live'
    WHERE id = p_test;
  END IF;

  RETURN v_attempt;
END;
$function$;

REVOKE ALL ON FUNCTION public._fn_start_attempt_core(uuid, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._fn_start_attempt_core(uuid, boolean, boolean) FROM anon;
REVOKE ALL ON FUNCTION public._fn_start_attempt_core(uuid, boolean, boolean) FROM authenticated;

-- ------------------------------------------------------------
-- STEP 3 — rpc_start_attempt (explicit re-attempt intent pass-through)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_start_attempt(p_test uuid, p_reattempt boolean DEFAULT false)
RETURNS public.attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  RETURN public._fn_start_attempt_core(p_test, false, COALESCE(p_reattempt, false));
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_start_attempt(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_start_attempt(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_start_attempt(uuid, boolean) TO authenticated;

-- ------------------------------------------------------------
-- STEP 4 — rpc_start_attempt_by_code (same policy for code entry)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_start_attempt_by_code(p_code text, p_reattempt boolean DEFAULT false)
RETURNS public.attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_normalized text;
  v_test record;
  v_test_count bigint;
  v_attempt public.attempts%ROWTYPE;
BEGIN
  -- Auth check
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- Code normalization
  v_normalized := LOWER(TRIM(p_code));
  IF v_normalized = '' OR v_normalized IS NULL THEN
    RAISE EXCEPTION 'TEST_CODE_INVALID';
  END IF;

  -- Count matching tests
  SELECT count(*) INTO v_test_count
  FROM public.tests t
  WHERE t.is_soft_deleted = false
    AND t.deleted_at IS NULL
    AND (LOWER(TRIM(t.access_code)) = v_normalized OR LOWER(TRIM(t.join_code)) = v_normalized);

  IF v_test_count = 0 THEN
    RAISE EXCEPTION 'TEST_CODE_INVALID';
  END IF;

  IF v_test_count > 1 THEN
    RAISE EXCEPTION 'TEST_CODE_AMBIGUOUS: multiple tests match this code';
  END IF;

  -- Locate the single matching test
  SELECT t.* INTO v_test
  FROM public.tests t
  WHERE t.is_soft_deleted = false
    AND t.deleted_at IS NULL
    AND (LOWER(TRIM(t.access_code)) = v_normalized OR LOWER(TRIM(t.join_code)) = v_normalized)
  LIMIT 1;

  -- Delegate to shared helper with code_verified=true
  v_attempt := public._fn_start_attempt_core(v_test.id, true, COALESCE(p_reattempt, false));

  RETURN v_attempt;
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_start_attempt_by_code(text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_start_attempt_by_code(text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_start_attempt_by_code(text, boolean) TO authenticated;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid) AS returns, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code')
ORDER BY p.proname, args;
-- expect exactly three rows (no leftover overloads):
--   _fn_start_attempt_core    | p_test uuid, p_code_verified boolean DEFAULT false, p_reattempt boolean DEFAULT false
--   rpc_start_attempt         | p_test uuid, p_reattempt boolean DEFAULT false
--   rpc_start_attempt_by_code | p_code text, p_reattempt boolean DEFAULT false

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code')
ORDER BY 1, 2;
-- expect: rpc_* -> authenticated EXECUTE only; core -> no anon/authenticated/PUBLIC

SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.attempts'::regclass;
-- expect: unchanged

-- Behavioural (as a student, on a published test with default settings):
--   SELECT id, attempt_number, status FROM public.rpc_start_attempt('<test>');   -- attempt 1
--   -- submit it, then:
--   SELECT * FROM public.rpc_start_attempt('<test>');            -- ATTEMPT_ALREADY_COMPLETED
--   SELECT * FROM public.rpc_start_attempt('<test>', true);      -- REATTEMPT_LIMIT_REACHED (max 1)
--   -- creator: rpc_update_test(p_test_id => '<test>',
--   --            p_settings => '{"allow_reattempt": true, "max_attempts": 2}'::jsonb)
--   SELECT attempt_number FROM public.rpc_start_attempt('<test>', true);   -- 2
--   SELECT * FROM public.rpc_start_attempt('<test>', true);      -- resumes attempt 2 (in_progress)

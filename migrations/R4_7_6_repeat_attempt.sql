-- ============================================================
-- R4.7.6 — CORRECTED REPEAT ATTEMPT IMPLEMENTATION
-- My Preparation — Flutter + Supabase
-- Date: 2026-09-14
-- Status: PROPOSED — NOT EXECUTED
--
-- LIVE VERIFIED STATE:
-- - attempts has UNIQUE(test_id,user_id) via constraint AND index
-- - attempts has NO attempt_number column
-- - attempts status enum: in_progress, submitted, auto_submitted, scored
-- - _fn_start_attempt_core RETURNS public.attempts (NOT jsonb)
-- - rpc_start_attempt RETURNS public.attempts
-- - rpc_start_attempt_by_code RETURNS public.attempts
-- - tests has duration_sec (NOT duration_minutes)
-- - tests has NO max_attempts column
--
-- RULES:
-- - Do NOT delete or modify any existing attempt or result rows
-- - Do NOT change RPC signatures
-- - Do NOT weaken RLS or expose correct_option
-- - Do NOT reference nonexistent columns
-- - Transaction-safe with prerequisite verification
-- ============================================================

-- ============================================================
-- PREFLIGHT: Capture state before any changes
-- ============================================================

-- Verify attempt_number does not already exist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'attempts'
      AND column_name = 'attempt_number'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: attempt_number column already exists';
  END IF;
END $$;

-- Verify old unique constraint exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.attempts'::regclass
      AND conname = 'attempts_test_id_user_id_key'
      AND contype = 'u'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: constraint attempts_test_id_user_id_key not found';
  END IF;
END $$;

-- Verify old unique index exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'attempts'
      AND indexname = 'idx_attempts_test_user'
      AND indexdef LIKE '%UNIQUE%'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: unique index idx_attempts_test_user not found';
  END IF;
END $$;

-- Verify no duplicate (test_id, user_id) rows exist
DO $$
DECLARE
  v_dup_count integer;
BEGIN
  SELECT count(*) INTO v_dup_count
  FROM (
    SELECT test_id, user_id
    FROM public.attempts
    GROUP BY test_id, user_id
    HAVING count(*) > 1
  ) d;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'DATA_INTEGRITY: % duplicate (test_id,user_id) pairs exist', v_dup_count;
  END IF;
END $$;

-- Verify existing function signature matches expected live state
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND proname = '_fn_start_attempt_core'
      AND pg_get_function_arguments(oid) = 'p_test uuid, p_code_verified boolean DEFAULT false'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: _fn_start_attempt_core signature mismatch';
  END IF;
END $$;

-- Verify RPC signatures
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND proname = 'rpc_start_attempt'
      AND pg_get_function_arguments(oid) = 'p_test uuid'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: rpc_start_attempt signature mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND proname = 'rpc_start_attempt_by_code'
      AND pg_get_function_arguments(oid) = 'p_code text'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE_FAILED: rpc_start_attempt_by_code signature mismatch';
  END IF;
END $$;

-- Capture pre-migration row counts
DO $$
DECLARE
  v_attempts integer;
  v_results integer;
  v_answers integer;
BEGIN
  SELECT count(*) INTO v_attempts FROM public.attempts;
  SELECT count(*) INTO v_results FROM public.results;
  SELECT count(*) INTO v_answers FROM public.answers;

  RAISE NOTICE 'PRE_MIGRATION: attempts=%, results=%, answers=%',
    v_attempts, v_results, v_answers;
END $$;

-- ============================================================
-- STEP 1: ADD attempt_number COLUMN
-- ============================================================

ALTER TABLE public.attempts
  ADD COLUMN attempt_number integer NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.attempts.attempt_number IS
  'Server-calculated sequential attempt number per (test_id, user_id). '
  'Allocated via MAX(attempt_number)+1 inside SECURITY DEFINER function.';

-- Verify no NULL or <1 values after adding column
DO $$
DECLARE
  v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.attempts
  WHERE attempt_number IS NULL OR attempt_number < 1;

  IF v_bad > 0 THEN
    RAISE EXCEPTION 'DATA_INTEGRITY: % rows have invalid attempt_number', v_bad;
  END IF;
END $$;

-- ============================================================
-- STEP 2: DROP old unique constraint
-- ============================================================

ALTER TABLE public.attempts
  DROP CONSTRAINT attempts_test_id_user_id_key;

-- ============================================================
-- STEP 3: DROP old unique index
-- ============================================================

DROP INDEX IF EXISTS public.idx_attempts_test_user;

-- ============================================================
-- STEP 4: ADD new composite unique constraint
-- ============================================================

ALTER TABLE public.attempts
  ADD CONSTRAINT uq_attempts_test_user_number
  UNIQUE (test_id, user_id, attempt_number);

-- ============================================================
-- STEP 5: REBUILD _fn_start_attempt_core
-- ============================================================
--
-- Changes from current live function:
-- 1. Resume logic: only status='in_progress' (removed 'active')
-- 2. New attempt: calculates attempt_number via MAX+1
-- 3. Max participants: counts DISTINCT user_id
-- 4. Return type: remains public.attempts
-- 5. Signature: remains (p_test uuid, p_code_verified boolean DEFAULT false)
-- 6. FOR UPDATE locking: preserved
-- 7. Access control: restored original branching (creator/group/code_verified/can_access)
-- 8. Timing order: lifecycle → starts_at → ends_at → resume → late-join → participants
-- 9. ends_at: restored original hard block (no allow_late_join bypass)
-- 10. scheduled→live: moved to AFTER successful start
-- 11. deadline calculation: uses duration_sec only
-- ============================================================

CREATE OR REPLACE FUNCTION public._fn_start_attempt_core(
  p_test uuid,
  p_code_verified boolean DEFAULT false
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

-- ============================================================
-- STEP 6: REBUILD rpc_start_attempt
-- ============================================================
-- Signature UNCHANGED: (p_test uuid) RETURNS public.attempts
-- Behavior UNCHANGED: delegates to _fn_start_attempt_core

CREATE OR REPLACE FUNCTION public.rpc_start_attempt(p_test uuid)
RETURNS public.attempts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  RETURN public._fn_start_attempt_core(p_test, false);
END;
$function$;

-- ============================================================
-- STEP 7: REBUILD rpc_start_attempt_by_code
-- ============================================================
-- Signature UNCHANGED: (p_code text) RETURNS public.attempts
-- Behavior UNCHANGED: resolves code, delegates to _fn_start_attempt_core

CREATE OR REPLACE FUNCTION public.rpc_start_attempt_by_code(p_code text)
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
  v_attempt := public._fn_start_attempt_core(v_test.id, true);

  RETURN v_attempt;
END;
$function$;

-- ============================================================
-- VALIDATION QUERIES (READ-ONLY — run after migration)
-- ============================================================

-- V1: attempt_number column exists with correct properties
SELECT 'V1: attempt_number column' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'attempts'
  AND column_name = 'attempt_number';

-- V2: old unique constraint is gone
SELECT 'V2: old constraint dropped' AS check_name;
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'public.attempts'::regclass
  AND conname = 'attempts_test_id_user_id_key';
-- Expected: 0 rows

-- V3: old unique index is gone
SELECT 'V3: old index dropped' AS check_name;
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'attempts'
  AND indexname = 'idx_attempts_test_user';
-- Expected: 0 rows

-- V4: new unique constraint exists
SELECT 'V4: new constraint exists' AS check_name;
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'public.attempts'::regclass
  AND conname = 'uq_attempts_test_user_number';
-- Expected: 1 row

-- V5: no duplicate (test_id,user_id,attempt_number)
SELECT 'V5: no duplicates' AS check_name;
SELECT count(*) AS duplicate_count
FROM (
  SELECT test_id, user_id, attempt_number
  FROM public.attempts
  GROUP BY test_id, user_id, attempt_number
  HAVING count(*) > 1
) d;
-- Expected: 0

-- V6: existing attempt IDs preserved
SELECT 'V6: attempt IDs preserved' AS check_name;
SELECT count(*) AS total_attempts FROM public.attempts;
-- Compare with pre-migration count

-- V7: existing result rows preserved
SELECT 'V7: result rows preserved' AS check_name;
SELECT count(*) AS total_results FROM public.results;
-- Compare with pre-migration count

-- V8: function returns attempts type
SELECT 'V8: function return type' AS check_name;
SELECT
  p.proname,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';
-- Expected: returns public.attempts

-- V9: RPC signatures unchanged
SELECT 'V9: RPC signatures' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('rpc_start_attempt', 'rpc_start_attempt_by_code')
ORDER BY p.proname;

-- V10: SECURITY DEFINER on all functions
SELECT 'V10: SECURITY DEFINER' AS check_name;
SELECT
  p.proname,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    '_fn_start_attempt_core',
    'rpc_start_attempt',
    'rpc_start_attempt_by_code'
  )
ORDER BY p.proname;
-- Expected: all true, all have search_path=''

-- V11: anon cannot execute RPCs
SELECT 'V11: anon blocked' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_start_attempt', 'rpc_start_attempt_by_code')
  AND grantee = 'anon';
-- Expected: 0 rows

-- V12: authenticated can execute RPCs
SELECT 'V12: authenticated allowed' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_start_attempt', 'rpc_start_attempt_by_code')
  AND grantee = 'authenticated';
-- Expected: 2 rows (one per function)

-- V13: function source contains attempt_number allocation
SELECT 'V13: attempt_number logic present' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%attempt_number%' THEN 'HAS attempt_number'
    ELSE 'MISSING attempt_number'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V14: function source does NOT reference invalid statuses
SELECT 'V14: no invalid statuses' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%''active''%' THEN 'INVALID: references active'
    WHEN pg_get_functiondef(p.oid) LIKE '%''expired''%' THEN 'INVALID: references expired'
    ELSE 'CLEAN'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V15: function source uses duration_sec
SELECT 'V15: uses duration_sec' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%duration_sec%' THEN 'USES duration_sec'
    WHEN pg_get_functiondef(p.oid) LIKE '%duration_minutes%' THEN 'WRONG: uses duration_minutes'
    ELSE 'MISSING: no duration reference'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V16: existing RLS policies unchanged
SELECT 'V16: RLS policies unchanged' AS check_name;
SELECT
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'attempts'
ORDER BY policyname;

-- V17: access control has original branching (not just fn_can_access_test)
SELECT 'V17: access control branching' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%created_by = v_uid%' THEN 'HAS creator bypass'
    ELSE 'MISSING: creator bypass'
  END AS creator_check,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%fn_is_member%' THEN 'HAS group check'
    ELSE 'MISSING: group check'
  END AS group_check,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%p_code_verified = true%' THEN 'HAS code_verified path'
    ELSE 'MISSING: code_verified path'
  END AS code_check,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%fn_can_access_test%' THEN 'HAS fn_can_access_test'
    ELSE 'MISSING: fn_can_access_test'
  END AS fallback_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V18: ends_at is hard block (no allow_late_join bypass in ends_at check)
SELECT 'V18: ends_at semantics' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%now() >= v_test.ends_at%TEST_ENDED%'
         AND pg_get_functiondef(p.oid) NOT LIKE '%ends_at%allow_late_join%TEST_ENDED%'
    THEN 'CLEAN: ends_at is hard block'
    ELSE 'CHECK MANUALLY: verify ends_at logic'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V19: scheduled→live transition is AFTER insert
SELECT 'V19: scheduled→live ordering' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%RETURN v_attempt%UPDATE%SET status = ''live''%'
    THEN 'CORRECT: transition after insert'
    ELSE 'CHECK MANUALLY: verify transition ordering'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V20: late-join check present and correct
SELECT 'V20: late-join logic' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%LATE_JOIN_NOT_ALLOWED%'
         AND pg_get_functiondef(p.oid) LIKE '%allow_late_join = false%'
         AND pg_get_functiondef(p.oid) LIKE '%test_mode = ''live''%'
    THEN 'HAS late-join check'
    ELSE 'MISSING: late-join check'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V21: code matching uses LOWER(TRIM(...))
SELECT 'V21: code normalization in rpc_start_attempt_by_code' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%LOWER(TRIM(t.access_code))%'
         AND pg_get_functiondef(p.oid) LIKE '%LOWER(TRIM(t.join_code))%'
    THEN 'HAS LOWER(TRIM(...)) matching'
    ELSE 'MISSING: uses exact comparison'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- V22: deleted_at IS NULL present in rpc_start_attempt_by_code
SELECT 'V22: deleted_at check in rpc_start_attempt_by_code' AS check_name;
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%deleted_at IS NULL%'
    THEN 'HAS deleted_at check'
    ELSE 'MISSING: deleted_at check'
  END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- ============================================================
-- POST-MIGRATION ROW COUNT VERIFICATION
-- ============================================================

SELECT 'POST_MIGRATION_COUNTS' AS section;
SELECT 'attempts' AS t, count(*) AS c FROM public.attempts
UNION ALL SELECT 'results', count(*) FROM public.results
UNION ALL SELECT 'answers', count(*) FROM public.answers;
-- All counts must match pre-migration values

-- ============================================================
-- ROLLBACK LIMITATIONS
-- ============================================================
--
-- PRE-MIGRATION ROLLBACK (safe):
--   Drop attempt_number column
--   Drop uq_attempts_test_user_number constraint
--   Restore attempts_test_id_user_id_key UNIQUE(test_id,user_id)
--   Restore idx_attempts_test_user UNIQUE index
--   Restore original _fn_start_attempt_core function
--   Restore original rpc_start_attempt function
--   Restore original rpc_start_attempt_by_code function
--
-- POST-MIGRATION ROLLBACK (UNSAFE if repeat attempts exist):
--   If any user has attempt_number > 1, restoring
--   UNIQUE(test_id,user_id) will fail because multiple rows
--   per user per test now exist.
--
--   Therefore: DO NOT attempt to restore the old single-attempt
--   constraint after any repeat attempts have been created.
--   The new schema is permanent once used.
--
--   If rollback is absolutely required after repeat attempts exist,
--   the only option is to delete the extra attempts and their
--   associated answers/results, which VIOLATES the preservation
--   requirement. This must not be done.
--
-- ============================================================
-- END OF R4.7.6 MIGRATION
-- ============================================================

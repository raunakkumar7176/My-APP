-- ============================================================
-- R4 HOTFIX — rpc_save_answers: 42702 column reference "x" is ambiguous
-- ============================================================
-- Live evidence (2026-09-16, Chrome + device autosave):
--   AnswerRepository PostgrestException: code=42702,
--   message=column reference "x" is ambiguous
--
-- Root cause (from the live pg_get_functiondef body, PL/pgSQL default
-- plpgsql.variable_conflict = error):
--   DECLARE ... x jsonb;                            -- PL/pgSQL variable
--   ...
--   FROM jsonb_array_elements(p_answers) x          -- SQL table alias
-- In the final INSERT ... SELECT, every `x->>'...'` can resolve to either
-- the variable or the alias (whole-row reference), so the planner raises
-- 42702. The validation loop is NOT affected: its query
-- (`SELECT value FROM jsonb_array_elements(p_answers)`) has no alias `x`,
-- so `x` there is unambiguously the loop variable.
--
-- Fix: rename ONLY the final SELECT's alias to `answer_item` and qualify its
-- three JSON references. Everything else is the live body verbatim:
-- signature rpc_save_answers(uuid, jsonb) RETURNS void, SECURITY DEFINER,
-- SET search_path TO '', auth check, own-attempt FOR UPDATE, in_progress
-- check, `now() > a.deadline_at` (unchanged), payload/question/test/option-
-- bounds/review-flag validation, ON CONFLICT upsert. No schema, RLS, grant,
-- submit or scoring change.
--
-- STEP 1 (read-only) — confirm the live body still matches:
-- SELECT pg_get_functiondef('public.rpc_save_answers(uuid, jsonb)'::regprocedure);
--   -- expect: "x jsonb;" in DECLARE and "FROM jsonb_array_elements(p_answers) x"
--
-- STEP 2 — replace (same signature and return type: CREATE OR REPLACE is safe).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_save_answers(p_attempt uuid, p_answers jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    a public.attempts;
    x jsonb;
    v_question_id uuid;
    v_selected_option integer;
    v_marked_for_review boolean;
    v_test_id uuid;
    v_option_count integer;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
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

    IF a.status <> 'in_progress'::public.attempt_status THEN
        RAISE EXCEPTION 'ATTEMPT_CLOSED';
    END IF;

    IF now() > a.deadline_at THEN
        PERFORM public.fn_auto_submit(a.id);
        RAISE EXCEPTION 'ATTEMPT_CLOSED';
    END IF;

    v_test_id := a.test_id;

    IF jsonb_typeof(p_answers) <> 'array' THEN
        RAISE EXCEPTION 'INVALID_ANSWERS_PAYLOAD';
    END IF;

    FOR x IN
        SELECT value
        FROM jsonb_array_elements(p_answers)
    LOOP
        IF x->>'question_id' IS NULL
           OR (x->>'question_id') = '' THEN
            RAISE EXCEPTION 'QUESTION_ID_REQUIRED';
        END IF;

        BEGIN
            v_question_id := (x->>'question_id')::uuid;
        EXCEPTION
            WHEN invalid_text_representation THEN
                RAISE EXCEPTION 'INVALID_QUESTION_ID';
        END;

        IF x ? 'selected_option'
           AND x->>'selected_option' IS NOT NULL
           AND x->>'selected_option' <> '' THEN

            BEGIN
                v_selected_option := (x->>'selected_option')::integer;
            EXCEPTION
                WHEN invalid_text_representation THEN
                    RAISE EXCEPTION 'INVALID_SELECTED_OPTION';
            END;

            SELECT jsonb_array_length(q.options)
            INTO v_option_count
            FROM public.questions q
            WHERE q.id = v_question_id
              AND q.test_id = v_test_id
              AND q.status <> 'archived'::public.question_status;

            IF v_option_count IS NULL THEN
                RAISE EXCEPTION 'QUESTION_NOT_IN_ATTEMPT';
            END IF;

            IF v_selected_option < 0
               OR v_selected_option >= v_option_count THEN
                RAISE EXCEPTION 'INVALID_SELECTED_OPTION';
            END IF;

        ELSE
            PERFORM 1
            FROM public.questions q
            WHERE q.id = v_question_id
              AND q.test_id = v_test_id
              AND q.status <> 'archived'::public.question_status;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'QUESTION_NOT_IN_ATTEMPT';
            END IF;
        END IF;

        IF x ? 'marked_for_review'
           AND x->>'marked_for_review' IS NOT NULL
           AND x->>'marked_for_review' <> '' THEN
            BEGIN
                v_marked_for_review :=
                    (x->>'marked_for_review')::boolean;
            EXCEPTION
                WHEN invalid_text_representation THEN
                    RAISE EXCEPTION 'INVALID_REVIEW_FLAG';
            END;
        END IF;
    END LOOP;

    INSERT INTO public.answers (
        attempt_id,
        question_id,
        selected_option,
        marked_for_review
    )
    SELECT
        p_attempt,
        (answer_item->>'question_id')::uuid,
        NULLIF(answer_item->>'selected_option', '')::integer,
        COALESCE(
            (answer_item->>'marked_for_review')::boolean,
            false
        )
    FROM jsonb_array_elements(p_answers) AS answer_item
    ON CONFLICT (attempt_id, question_id)
    DO UPDATE SET
        selected_option = EXCLUDED.selected_option,
        marked_for_review = EXCLUDED.marked_for_review,
        updated_at = now();

END;
$function$;

-- STEP 3 (read-only) — verify.
-- ------------------------------------------------------------
-- SELECT pg_get_functiondef('public.rpc_save_answers(uuid, jsonb)'::regprocedure);
--   -- expect: "FROM jsonb_array_elements(p_answers) AS answer_item"
-- Grants are untouched by CREATE OR REPLACE; confirm they are still as before:
-- SELECT grantee, privilege_type FROM information_schema.routine_privileges
--  WHERE routine_schema = 'public' AND routine_name = 'rpc_save_answers';
-- Then, as the attempt's owner with an in_progress attempt:
-- SELECT public.rpc_save_answers('<attempt-uuid>',
--   '[{"question_id":"<question-uuid>","selected_option":0,"marked_for_review":false}]'::jsonb);
-- SELECT attempt_id, question_id, selected_option, marked_for_review, updated_at
--   FROM public.answers WHERE attempt_id = '<attempt-uuid>';

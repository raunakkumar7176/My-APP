-- ============================================================
-- R4.1 PHASE: DATABASE FOUNDATION
-- Test System Greenfield Build
-- Date: 2026-09-12
-- Status: APPROVED
--
-- RULES:
-- - This is the ONLY SQL to execute in R4.1
-- - Do NOT modify existing tables (subjects, syllabus_nodes, profiles, etc.)
-- - Do NOT seed syllabus data
-- - Do NOT create RLS policies (Phase R4.2)
-- - Do NOT create RPCs/functions (Phase R4.3)
-- - Do NOT modify Flutter code
--
-- EXECUTION: Run via Supabase SQL Editor
-- ROLLBACK: See ROLLBACK section at end of file
-- ============================================================

-- ============================================================
-- SECTION 1: CUSTOM ENUM TYPES
-- ============================================================

-- Test status lifecycle
DO $$ BEGIN
  CREATE TYPE public.test_status AS ENUM (
    'draft',
    'published',
    'closed',
    'archived'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Attempt lifecycle
DO $$ BEGIN
  CREATE TYPE public.attempt_status AS ENUM (
    'in_progress',
    'submitted',
    'expired'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Question types
DO $$ BEGIN
  CREATE TYPE public.question_type AS ENUM (
    'mcq_single',
    'mcq_multiple',
    'true_false',
    'integer',
    'short_answer'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Difficulty levels
DO $$ BEGIN
  CREATE TYPE public.difficulty_level AS ENUM (
    'easy',
    'medium',
    'hard'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- SECTION 2: DROP ORPHANED test_syllabus
-- ============================================================
-- The existing test_syllabus table is orphaned:
--   - test_id references nonexistent tests table
--   - No primary key
--   - No unique constraints
--   - No references in Flutter code (51 doc-only references)
--   - Safe to drop

DROP TABLE IF EXISTS public.test_syllabus;

-- ============================================================
-- SECTION 3: TABLES
-- ============================================================

-- ------------------------------------------------------------
-- 3.1 tests
-- Purpose: Test metadata, configuration, scheduling
-- ------------------------------------------------------------
CREATE TABLE public.tests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         text NOT NULL,
  description   text,
  instructions  text,
  subject_id    uuid NOT NULL REFERENCES public.subjects(id) ON DELETE RESTRICT,
  class_level   text,
  status        public.test_status NOT NULL DEFAULT 'draft',

  -- Timing
  duration_minutes    integer NOT NULL CHECK (duration_minutes > 0 AND duration_minutes <= 480),
  start_at            timestamptz,
  end_at              timestamptz,

  -- Scoring
  total_marks         integer NOT NULL DEFAULT 0 CHECK (total_marks >= 0),
  passing_marks       integer NOT NULL DEFAULT 0 CHECK (passing_marks >= 0),
  negative_marking    boolean NOT NULL DEFAULT false,
  negative_marks      numeric(4,2) NOT NULL DEFAULT 0.00 CHECK (negative_marks >= 0),

  -- Question selection
  total_questions     integer NOT NULL DEFAULT 0 CHECK (total_questions >= 0),
  shuffle_questions   boolean NOT NULL DEFAULT false,
  show_answers_after  boolean NOT NULL DEFAULT false,

  -- Access control
  is_public           boolean NOT NULL DEFAULT true,
  max_attempts        integer NOT NULL DEFAULT 1 CHECK (max_attempts > 0 AND max_attempts <= 10),

  -- Group association (human decision #3: integrate at architecture level)
  group_id            uuid,  -- FK added after groups table exists (Phase R4.1 groups integration)

  -- Metadata
  difficulty          public.difficulty_level,
  tags                text[] DEFAULT '{}',
  language            text NOT NULL DEFAULT 'en',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  -- Temporal constraints
  CONSTRAINT chk_tests_end_after_start CHECK (
    start_at IS NULL OR end_at IS NULL OR end_at > start_at
  ),
  CONSTRAINT chk_tests_passing_lte_total CHECK (
    passing_marks <= total_marks
  )
);

COMMENT ON TABLE public.tests IS 'Test metadata and configuration. Created by authorized users.';
COMMENT ON COLUMN public.tests.group_id IS 'Optional group association. NULL = personal test. FK to groups.id when groups table exists.';
COMMENT ON COLUMN public.tests.is_public IS 'true = all authenticated users can see/attempt. false = invited users only.';
COMMENT ON COLUMN public.tests.show_answers_after IS 'If true, correct answers shown after submission (for practice). If false, answers hidden (for exams).';

-- ------------------------------------------------------------
-- 3.2 questions
-- Purpose: Reusable question bank
-- Design: Questions can be bank-wide (test_id IS NULL) or test-specific
-- Security: is_correct field exists but is NEVER exposed to clients
--           via the questions_safe view (created in Section 4)
-- ------------------------------------------------------------
CREATE TABLE public.questions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  test_id         uuid REFERENCES public.tests(id) ON DELETE SET NULL,

  -- Content
  question_text   text NOT NULL,
  question_type   public.question_type NOT NULL DEFAULT 'mcq_single',
  options         jsonb NOT NULL DEFAULT '[]',
  correct_answer  text,

  -- Scoring
  marks           integer NOT NULL DEFAULT 1 CHECK (marks > 0),
  negative_marks  numeric(4,2) NOT NULL DEFAULT 0.00 CHECK (negative_marks >= 0),
  difficulty      public.difficulty_level NOT NULL DEFAULT 'medium',

  -- Metadata
  explanation     text,
  source          text,
  language        text NOT NULL DEFAULT 'en',
  tags            text[] DEFAULT '{}',
  is_active       boolean NOT NULL DEFAULT true,
  version         integer NOT NULL DEFAULT 1 CHECK (version > 0),

  -- Timestamps
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- Scoring constraint
  CONSTRAINT chk_questions_negative_lte_marks CHECK (
    negative_marks < marks
  )
);

COMMENT ON TABLE public.questions IS 'Reusable question bank. Questions can be bank-wide or test-specific.';
COMMENT ON COLUMN public.questions.options IS 'JSONB array of options. Each: {id: string, text: string, is_correct: boolean}. is_correct is NEVER exposed to clients before submission.';
COMMENT ON COLUMN public.questions.test_id IS 'NULL = bank question (reusable). Non-NULL = test-specific question.';
COMMENT ON COLUMN public.questions.correct_answer IS 'For integer: numeric string. For short_answer: expected text. NULL for MCQ types.';

-- ------------------------------------------------------------
-- 3.3 test_syllabus (RECREATED)
-- Purpose: Junction table linking tests to syllabus nodes
-- Replaces: Orphaned table with same name (dropped above)
-- ------------------------------------------------------------
CREATE TABLE public.test_syllabus (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id           uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  syllabus_node_id  uuid NOT NULL REFERENCES public.syllabus_nodes(id) ON DELETE CASCADE,
  material_ids      uuid[] DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Prevent duplicate syllabus entries per test
  CONSTRAINT uq_test_syllabus_test_node UNIQUE (test_id, syllabus_node_id)
);

COMMENT ON TABLE public.test_syllabus IS 'Junction table linking tests to syllabus nodes. Defines test coverage.';

-- ------------------------------------------------------------
-- 3.4 test_invitations
-- Purpose: Access control for restricted tests (is_public = false)
-- ------------------------------------------------------------
CREATE TABLE public.test_invitations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id     uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  invited_at  timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,

  -- One invitation per user per test
  CONSTRAINT uq_test_invitations_test_user UNIQUE (test_id, user_id)
);

COMMENT ON TABLE public.test_invitations IS 'Access control for restricted tests. Only used when tests.is_public = false.';

-- ------------------------------------------------------------
-- 3.5 attempts
-- Purpose: Record each user attempt at a test
-- Security: owner-based (user sees only own attempts)
-- ------------------------------------------------------------
CREATE TABLE public.attempts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id       uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
  status        public.attempt_status NOT NULL DEFAULT 'in_progress',

  -- Timing (server-authoritative)
  started_at    timestamptz NOT NULL DEFAULT now(),
  submitted_at  timestamptz,
  time_spent_seconds integer,

  -- Violations tracking
  violations    jsonb DEFAULT '[]',

  -- Metadata
  ip_address    inet,
  user_agent    text,

  created_at    timestamptz NOT NULL DEFAULT now(),

  -- One attempt number per user per test
  CONSTRAINT uq_attempts_test_user_number UNIQUE (test_id, user_id, attempt_number),

  -- Submission timing
  CONSTRAINT chk_attempts_submitted_after_started CHECK (
    submitted_at IS NULL OR submitted_at >= started_at
  )
);

COMMENT ON TABLE public.attempts IS 'User test attempts. One row per attempt. Server-authoritative timing.';
COMMENT ON COLUMN public.attempts.violations IS 'JSONB array of {type, timestamp, details} for integrity events.';

-- ------------------------------------------------------------
-- 3.6 answers
-- Purpose: Per-question answers within an attempt
-- Security: owner-based (via attempt ownership)
-- ------------------------------------------------------------
CREATE TABLE public.answers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id      uuid NOT NULL REFERENCES public.attempts(id) ON DELETE CASCADE,
  question_id     uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,

  -- Answer content
  selected_option_id text,
  text_answer       text,

  -- State
  is_marked_for_review boolean NOT NULL DEFAULT false,
  is_answered         boolean NOT NULL DEFAULT false,

  -- Timestamps
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- One answer per question per attempt
  CONSTRAINT uq_answers_attempt_question UNIQUE (attempt_id, question_id)
);

COMMENT ON TABLE public.answers IS 'Per-question answers within an attempt. One row per question per attempt.';
COMMENT ON COLUMN public.answers.selected_option_id IS 'For MCQ: the selected option ID string.';
COMMENT ON COLUMN public.answers.text_answer IS 'For integer/short_answer: the typed answer text.';
COMMENT ON COLUMN public.answers.is_marked_for_review IS 'User-flagged for review. Independent of is_answered.';

-- ------------------------------------------------------------
-- 3.7 results
-- Purpose: Calculated scores for each attempt
-- Security: owner-based (user sees only own results)
-- Immutability: Once created, never modified (except manual grading)
-- ------------------------------------------------------------
CREATE TABLE public.results (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id        uuid NOT NULL REFERENCES public.attempts(id) ON DELETE CASCADE,
  test_id           uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  batch_id          uuid,

  -- Score breakdown
  total_marks       integer NOT NULL DEFAULT 0,
  marks_obtained    numeric(8,2) NOT NULL DEFAULT 0,
  percentage        numeric(5,2) NOT NULL DEFAULT 0,
  is_passed         boolean NOT NULL DEFAULT false,

  -- Counts
  total_questions   integer NOT NULL DEFAULT 0,
  correct_count     integer NOT NULL DEFAULT 0,
  wrong_count       integer NOT NULL DEFAULT 0,
  unanswered_count  integer NOT NULL DEFAULT 0,
  partial_count     integer NOT NULL DEFAULT 0,

  -- Metadata
  generated_at      timestamptz NOT NULL DEFAULT now(),
  generation_method text NOT NULL DEFAULT 'deterministic',

  -- One result per attempt (idempotent generation)
  CONSTRAINT uq_results_attempt UNIQUE (attempt_id),

  -- Score constraints
  CONSTRAINT chk_results_percentage_range CHECK (
    percentage >= 0 AND percentage <= 100
  ),
  CONSTRAINT chk_results_marks_range CHECK (
    marks_obtained >= 0 AND marks_obtained <= total_marks
  ),
  CONSTRAINT chk_results_counts_sum CHECK (
    correct_count + wrong_count + unanswered_count + partial_count = total_questions
  )
);

COMMENT ON TABLE public.results IS 'Calculated scores for each attempt. Immutable once generated.';
COMMENT ON COLUMN public.results.batch_id IS 'Links results to a batch generation run. UUID, not a FK.';
COMMENT ON COLUMN public.results.generation_method IS 'deterministic = server-calculated. ai_assisted = AI-enhanced (deferred).';

-- ------------------------------------------------------------
-- 3.8 ai_reports (DEFERRED - table created, population deferred)
-- Purpose: AI-generated post-test analysis
-- Note: Table structure created for forward compatibility.
--       Population is DEFERRED to Phase R4.12.
-- ------------------------------------------------------------
CREATE TABLE public.ai_reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id     uuid NOT NULL REFERENCES public.results(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  test_id       uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,

  -- AI content
  summary       text,
  strengths     jsonb DEFAULT '[]',
  weaknesses    jsonb DEFAULT '[]',
  recommendations jsonb DEFAULT '[]',
  detailed_analysis text,

  -- Metadata
  model_used    text,
  tokens_used   integer,
  generated_at  timestamptz NOT NULL DEFAULT now(),

  -- One AI report per result
  CONSTRAINT uq_ai_reports_result UNIQUE (result_id)
);

COMMENT ON TABLE public.ai_reports IS 'AI-generated test analysis. DEFERRED - table created for forward compatibility.';

-- ============================================================
-- SECTION 4: SECURITY VIEW — ANSWER-KEY PROTECTION
-- ============================================================
-- Human decision #1: Never expose correct answers to students before submission.
-- This view strips is_correct from options before client access.
-- Clients MUST query questions_safe, NOT questions directly.

CREATE OR REPLACE VIEW public.questions_safe AS
SELECT
  q.id,
  q.created_by,
  q.test_id,
  q.question_text,
  q.question_type,
  -- Strip is_correct from options
  (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object('id', opt->>'id', 'text', opt->>'text')
    ), '[]'::jsonb)
    FROM jsonb_array_elements(q.options) AS opt
  ) AS options,
  q.marks,
  q.negative_marks,
  q.difficulty,
  q.source,
  q.language,
  q.tags,
  q.is_active,
  q.version,
  q.created_at,
  q.updated_at
FROM public.questions q
WHERE q.is_active = true;

COMMENT ON VIEW public.questions_safe IS 'Client-safe view of questions. Strips is_correct from options. Clients MUST use this view.';
COMMENT ON VIEW public.questions IS 'Base table contains is_correct. NEVER expose directly to clients before submission.';

-- ============================================================
-- SECTION 5: INDEXES
-- ============================================================

-- tests
CREATE INDEX idx_tests_created_by ON public.tests (created_by);
CREATE INDEX idx_tests_subject_id ON public.tests (subject_id);
CREATE INDEX idx_tests_status ON public.tests (status);
CREATE INDEX idx_tests_start_at ON public.tests (start_at) WHERE start_at IS NOT NULL;
CREATE INDEX idx_tests_end_at ON public.tests (end_at) WHERE end_at IS NOT NULL;
CREATE INDEX idx_tests_group_id ON public.tests (group_id) WHERE group_id IS NOT NULL;

-- questions
CREATE INDEX idx_questions_created_by ON public.questions (created_by);
CREATE INDEX idx_questions_test_id ON public.questions (test_id) WHERE test_id IS NOT NULL;
CREATE INDEX idx_questions_difficulty ON public.questions (difficulty);
CREATE INDEX idx_questions_question_type ON public.questions (question_type);
CREATE INDEX idx_questions_is_active ON public.questions (is_active) WHERE is_active = true;
CREATE INDEX idx_questions_tags ON public.questions USING gin(tags);

-- test_syllabus
CREATE INDEX idx_test_syllabus_test_id ON public.test_syllabus (test_id);
CREATE INDEX idx_test_syllabus_syllabus_node_id ON public.test_syllabus (syllabus_node_id);

-- test_invitations
CREATE INDEX idx_test_invitations_test_id ON public.test_invitations (test_id);
CREATE INDEX idx_test_invitations_user_id ON public.test_invitations (user_id);

-- attempts
CREATE INDEX idx_attempts_test_id ON public.attempts (test_id);
CREATE INDEX idx_attempts_user_id ON public.attempts (user_id);
CREATE INDEX idx_attempts_test_user ON public.attempts (test_id, user_id);
CREATE INDEX idx_attempts_status ON public.attempts (status);

-- answers
CREATE INDEX idx_answers_attempt_id ON public.answers (attempt_id);
CREATE INDEX idx_answers_question_id ON public.answers (question_id);
CREATE INDEX idx_answers_attempt_question ON public.answers (attempt_id, question_id);

-- results
CREATE INDEX idx_results_attempt_id ON public.results (attempt_id);
CREATE INDEX idx_results_test_id ON public.results (test_id);
CREATE INDEX idx_results_user_id ON public.results (user_id);
CREATE INDEX idx_results_test_user ON public.results (test_id, user_id);
CREATE INDEX idx_results_batch_id ON public.results (batch_id) WHERE batch_id IS NOT NULL;

-- ai_reports
CREATE INDEX idx_ai_reports_result_id ON public.ai_reports (result_id);
CREATE INDEX idx_ai_reports_user_id ON public.ai_reports (user_id);
CREATE INDEX idx_ai_reports_test_id ON public.ai_reports (test_id);

-- ============================================================
-- SECTION 6: TRIGGER — AUTO-UPDATE updated_at
-- ============================================================

-- Function to auto-update updated_at
CREATE OR REPLACE FUNCTION public.fn_update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Apply to tables with updated_at
CREATE TRIGGER trg_tests_updated_at
  BEFORE UPDATE ON public.tests
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_updated_at();

CREATE TRIGGER trg_questions_updated_at
  BEFORE UPDATE ON public.questions
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_updated_at();

CREATE TRIGGER trg_answers_updated_at
  BEFORE UPDATE ON public.answers
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_updated_at();

-- ============================================================
-- SECTION 7: VALIDATION QUERIES
-- ============================================================
-- Run these after migration to verify schema correctness.

-- 7.1 Verify all tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
ORDER BY table_name;

-- 7.2 Verify all enum types exist
SELECT typname
FROM pg_type
WHERE typname IN ('test_status', 'attempt_status', 'question_type', 'difficulty_level')
ORDER BY typname;

-- 7.3 Verify foreign keys on tests
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'tests'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 7.4 Verify foreign keys on questions
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'questions'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 7.5 Verify foreign keys on attempts
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'attempts'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 7.6 Verify foreign keys on answers
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'answers'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 7.7 Verify foreign keys on results
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'results'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 7.8 Verify unique constraints
SELECT
  tc.table_name,
  tc.constraint_name,
  string_agg(kcu.column_name, ', ') AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'UNIQUE'
  AND tc.table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
GROUP BY tc.table_name, tc.constraint_name;

-- 7.9 Verify indexes exist
SELECT
  indexname,
  tablename
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
ORDER BY tablename, indexname;

-- 7.10 Verify questions_safe view exists and works
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'questions_safe'
ORDER BY ordinal_position;

-- 7.11 Verify RLS is NOT enabled (no policies exist yet)
SELECT
  schemaname,
  tablename,
  policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports');

-- 7.12 Verify triggers exist
SELECT
  trigger_name,
  event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_%'
ORDER BY event_object_table;

-- 7.13 Verify CHECK constraints
SELECT
  tc.table_name,
  tc.constraint_name,
  cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
WHERE tc.constraint_type = 'CHECK'
  AND tc.table_name IN ('tests', 'questions', 'attempts', 'answers', 'results');

-- 7.14 Verify test_syllabus was dropped and recreated
SELECT
  tc.table_name,
  tc.constraint_type,
  tc.constraint_name
FROM information_schema.table_constraints tc
WHERE tc.table_name = 'test_syllabus'
ORDER BY tc.constraint_type;

-- ============================================================
-- ROLLBACK SCRIPT
-- ============================================================
-- Execute this to undo all R4.1 changes.
-- WARNING: This drops all new tables, types, and the view.

-- DROP TRIGGER IF EXISTS trg_answers_updated_at ON public.answers;
-- DROP TRIGGER IF EXISTS trg_questions_updated_at ON public.questions;
-- DROP TRIGGER IF EXISTS trg_tests_updated_at ON public.tests;
-- DROP FUNCTION IF EXISTS public.fn_update_updated_at();
-- DROP VIEW IF EXISTS public.questions_safe;
-- DROP TABLE IF EXISTS public.ai_reports;
-- DROP TABLE IF EXISTS public.results;
-- DROP TABLE IF EXISTS public.answers;
-- DROP TABLE IF EXISTS public.attempts;
-- DROP TABLE IF EXISTS public.test_invitations;
-- DROP TABLE IF EXISTS public.test_syllabus;
-- DROP TABLE IF EXISTS public.questions;
-- DROP TABLE IF EXISTS public.tests;
-- DROP TYPE IF EXISTS public.difficulty_level;
-- DROP TYPE IF EXISTS public.question_type;
-- DROP TYPE IF EXISTS public.attempt_status;
-- DROP TYPE IF EXISTS public.test_status;

-- ============================================================
-- END OF R4.1 MIGRATION
-- ============================================================

-- ============================================================================
-- R8 / 0057 — Study & Learning Content System V1 (Phase 1 Database Foundation)
-- My Preparation — Flutter + Supabase
--
-- ARCHITECTURE CONTRACT:
--  - 100% Additive: preserves all existing tables, foreign keys, and RPCs.
--  - Extends existing public.subjects and public.question_bank with optional columns.
--  - Introduces normalized, multilingual content hierarchy:
--      subjects -> chapters (+ chapter_translations)
--               -> topics   (+ topic_translations)
--               -> content_blocks (structured rich-text/formula/examples)
--  - Introduces student study progress tracking (user_study_progress).
--  - Adds 'content-media' storage bucket for educational diagrams and media.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_status') THEN
    CREATE TYPE public.content_status AS ENUM ('draft', 'published', 'archived');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_block_type') THEN
    CREATE TYPE public.content_block_type AS ENUM (
      'heading',
      'paragraph',
      'definition',
      'formula',
      'example',
      'important_point',
      'note',
      'table',
      'image',
      'common_mistake'
    );
  END IF;
END $$;

-- ============================================================================
-- 2. EXTEND EXISTING public.subjects TABLE (ADDITIVE)
-- ============================================================================

ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS slug text;
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS icon text;
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS order_index integer DEFAULT 0;
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS status public.content_status DEFAULT 'published';
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.subjects ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Backfill default values for existing rows
UPDATE public.subjects
SET status = 'published'
WHERE status IS NULL;

UPDATE public.subjects
SET is_active = true
WHERE is_active IS NULL;

CREATE INDEX IF NOT EXISTS idx_subjects_active_status
  ON public.subjects (is_active, status, order_index);

-- ============================================================================
-- 3. SUBJECT TRANSLATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.subject_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  language varchar(5) NOT NULL, -- 'en', 'hi'
  name text NOT NULL,
  description text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_subject_translations UNIQUE(subject_id, language)
);

CREATE INDEX IF NOT EXISTS idx_subject_translations_lookup
  ON public.subject_translations (subject_id, language);

-- ============================================================================
-- 4. CHAPTERS & CHAPTER TRANSLATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  chapter_key text NOT NULL,
  order_index integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  status public.content_status NOT NULL DEFAULT 'published',
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_chapters_subject_key UNIQUE(subject_id, chapter_key)
);

CREATE TABLE IF NOT EXISTS public.chapter_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
  language varchar(5) NOT NULL,
  title text NOT NULL,
  description text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_chapter_translations UNIQUE(chapter_id, language)
);

CREATE INDEX IF NOT EXISTS idx_chapters_subject_order
  ON public.chapters (subject_id, order_index);

CREATE INDEX IF NOT EXISTS idx_chapters_status_active
  ON public.chapters (is_active, status);

CREATE INDEX IF NOT EXISTS idx_chapter_translations_lookup
  ON public.chapter_translations (chapter_id, language);

-- ============================================================================
-- 5. TOPICS & TOPIC TRANSLATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
  topic_key text NOT NULL,
  order_index integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  status public.content_status NOT NULL DEFAULT 'published',
  estimated_minutes integer DEFAULT 5,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_topics_chapter_key UNIQUE(chapter_id, topic_key)
);

CREATE TABLE IF NOT EXISTS public.topic_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  language varchar(5) NOT NULL,
  title text NOT NULL,
  summary text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_topic_translations UNIQUE(topic_id, language)
);

CREATE INDEX IF NOT EXISTS idx_topics_chapter_order
  ON public.topics (chapter_id, order_index);

CREATE INDEX IF NOT EXISTS idx_topics_status_active
  ON public.topics (is_active, status);

CREATE INDEX IF NOT EXISTS idx_topic_translations_lookup
  ON public.topic_translations (topic_id, language);

-- ============================================================================
-- 6. CONTENT BLOCKS
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.content_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  block_type public.content_block_type NOT NULL,
  language varchar(5) NOT NULL, -- 'en', 'hi'
  order_index integer NOT NULL DEFAULT 0,
  content jsonb NOT NULL, -- structured payload: {"text": "...", "latex": "...", "points": [...]}
  is_active boolean NOT NULL DEFAULT true,
  status public.content_status NOT NULL DEFAULT 'published',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_content_blocks_topic_lang_order
  ON public.content_blocks (topic_id, language, order_index);

CREATE INDEX IF NOT EXISTS idx_content_blocks_status_active
  ON public.content_blocks (is_active, status);

-- ============================================================================
-- 7. EXTEND EXISTING public.question_bank (ADDITIVE)
-- ============================================================================

ALTER TABLE public.question_bank
  ADD COLUMN IF NOT EXISTS chapter_id uuid REFERENCES public.chapters(id) ON DELETE SET NULL;

ALTER TABLE public.question_bank
  ADD COLUMN IF NOT EXISTS topic_id uuid REFERENCES public.topics(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_question_bank_chapter_diff
  ON public.question_bank (chapter_id, difficulty);

CREATE INDEX IF NOT EXISTS idx_question_bank_topic
  ON public.question_bank (topic_id);

-- ============================================================================
-- 8. USER STUDY PROGRESS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_study_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
  topic_id uuid REFERENCES public.topics(id) ON DELETE CASCADE,
  is_completed boolean NOT NULL DEFAULT false,
  last_studied_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT uq_user_study_progress_user_topic UNIQUE(user_id, topic_id)
);

CREATE INDEX IF NOT EXISTS idx_user_study_progress_user_chapter
  ON public.user_study_progress (user_id, chapter_id);

CREATE INDEX IF NOT EXISTS idx_user_study_progress_user_topic
  ON public.user_study_progress (user_id, topic_id);

-- ============================================================================
-- 9. TRIGGER: AUTO-UPDATE updated_at TIMESTAMPS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_touch_content_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  new.updated_at := now();
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_subjects ON public.subjects;
CREATE TRIGGER trg_touch_subjects BEFORE UPDATE ON public.subjects
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_subject_translations ON public.subject_translations;
CREATE TRIGGER trg_touch_subject_translations BEFORE UPDATE ON public.subject_translations
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_chapters ON public.chapters;
CREATE TRIGGER trg_touch_chapters BEFORE UPDATE ON public.chapters
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_chapter_translations ON public.chapter_translations;
CREATE TRIGGER trg_touch_chapter_translations BEFORE UPDATE ON public.chapter_translations
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_topics ON public.topics;
CREATE TRIGGER trg_touch_topics BEFORE UPDATE ON public.topics
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_topic_translations ON public.topic_translations;
CREATE TRIGGER trg_touch_topic_translations BEFORE UPDATE ON public.topic_translations
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_content_blocks ON public.content_blocks;
CREATE TRIGGER trg_touch_content_blocks BEFORE UPDATE ON public.content_blocks
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

DROP TRIGGER IF EXISTS trg_touch_user_study_progress ON public.user_study_progress;
CREATE TRIGGER trg_touch_user_study_progress BEFORE UPDATE ON public.user_study_progress
  FOR EACH ROW EXECUTE FUNCTION public.fn_touch_content_updated_at();

-- ============================================================================
-- 10. ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE public.subject_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chapter_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topic_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_study_progress ENABLE ROW LEVEL SECURITY;

-- 10.1 subject_translations
DROP POLICY IF EXISTS "Public read subject translations" ON public.subject_translations;
CREATE POLICY "Public read subject translations"
  ON public.subject_translations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.subjects s
      WHERE s.id = subject_translations.subject_id
        AND s.is_active = true
        AND (s.status IS NULL OR s.status = 'published')
    )
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.2 chapters
DROP POLICY IF EXISTS "Public read published chapters" ON public.chapters;
CREATE POLICY "Public read published chapters"
  ON public.chapters
  FOR SELECT
  USING (
    (status = 'published' AND is_active = true)
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.3 chapter_translations
DROP POLICY IF EXISTS "Public read chapter translations" ON public.chapter_translations;
CREATE POLICY "Public read chapter translations"
  ON public.chapter_translations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.chapters c
      WHERE c.id = chapter_translations.chapter_id
        AND c.status = 'published'
        AND c.is_active = true
    )
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.4 topics
DROP POLICY IF EXISTS "Public read published topics" ON public.topics;
CREATE POLICY "Public read published topics"
  ON public.topics
  FOR SELECT
  USING (
    (status = 'published' AND is_active = true)
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.5 topic_translations
DROP POLICY IF EXISTS "Public read topic translations" ON public.topic_translations;
CREATE POLICY "Public read topic translations"
  ON public.topic_translations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.topics t
      WHERE t.id = topic_translations.topic_id
        AND t.status = 'published'
        AND t.is_active = true
    )
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.6 content_blocks
DROP POLICY IF EXISTS "Public read published content blocks" ON public.content_blocks;
CREATE POLICY "Public read published content blocks"
  ON public.content_blocks
  FOR SELECT
  USING (
    (status = 'published' AND is_active = true)
    OR (
      auth.uid() IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.user_id = auth.uid()
          AND public.fn_has_permission(gm.group_id, auth.uid(), 'GENERATE_QUESTIONS')
      )
    )
  );

-- 10.7 user_study_progress (Strictly user-scoped)
DROP POLICY IF EXISTS "Users read own study progress" ON public.user_study_progress;
CREATE POLICY "Users read own study progress"
  ON public.user_study_progress
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users insert own study progress" ON public.user_study_progress;
CREATE POLICY "Users insert own study progress"
  ON public.user_study_progress
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users update own study progress" ON public.user_study_progress;
CREATE POLICY "Users update own study progress"
  ON public.user_study_progress
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users delete own study progress" ON public.user_study_progress;
CREATE POLICY "Users delete own study progress"
  ON public.user_study_progress
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- ============================================================================
-- 11. STORAGE BUCKET: content-media
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'content-media',
  'content-media',
  true,  -- PUBLIC: accessible via public URL for educational diagrams
  10485760,  -- 10 MB
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/svg+xml'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/svg+xml'
  ];

-- Storage Policies
DROP POLICY IF EXISTS "Public read content media" ON storage.objects;
CREATE POLICY "Public read content media"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'content-media');

DROP POLICY IF EXISTS "Authenticated upload content media" ON storage.objects;
CREATE POLICY "Authenticated upload content media"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'content-media');

DROP POLICY IF EXISTS "Authenticated update content media" ON storage.objects;
CREATE POLICY "Authenticated update content media"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (bucket_id = 'content-media')
  WITH CHECK (bucket_id = 'content-media');

DROP POLICY IF EXISTS "Authenticated delete content media" ON storage.objects;
CREATE POLICY "Authenticated delete content media"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'content-media');

-- ============================================================================
-- 12. GRANTS
-- ============================================================================

GRANT SELECT ON public.subjects TO anon, authenticated;
GRANT SELECT ON public.subject_translations TO anon, authenticated;
GRANT SELECT ON public.chapters TO anon, authenticated;
GRANT SELECT ON public.chapter_translations TO anon, authenticated;
GRANT SELECT ON public.topics TO anon, authenticated;
GRANT SELECT ON public.topic_translations TO anon, authenticated;
GRANT SELECT ON public.content_blocks TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_study_progress TO authenticated;

COMMIT;


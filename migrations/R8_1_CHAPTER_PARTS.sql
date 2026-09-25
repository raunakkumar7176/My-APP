-- ============================================================================
-- R8.1 / 0058 — Study Content System: Part/Section Grouping Support
-- My Preparation — Flutter + Supabase
--
-- ARCHITECTURE CONTRACT:
--  - 100% Additive: preserves all existing columns, constraints, and data.
--  - Adds optional part_key and part_order_index to public.chapters.
--  - Adds optional localized part_title to public.chapter_translations.
--  - Single-tier subjects (e.g., Mathematics) remain null without breaking.
-- ============================================================================

BEGIN;

-- 1. Add optional Part grouping columns to public.chapters
ALTER TABLE public.chapters
  ADD COLUMN IF NOT EXISTS part_key text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS part_order_index integer DEFAULT 0;

-- 2. Add localized Part Title to public.chapter_translations
ALTER TABLE public.chapter_translations
  ADD COLUMN IF NOT EXISTS part_title text DEFAULT NULL;

-- 3. Composite index for fast part-ordered listing
CREATE INDEX IF NOT EXISTS idx_chapters_subject_part_order
  ON public.chapters (subject_id, part_order_index, order_index);

COMMIT;


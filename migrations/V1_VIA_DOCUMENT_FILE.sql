-- V1 — Via Document/File: uploaded_documents table + storage bucket policies
-- My Preparation — Flutter + Supabase
-- Date: 2026-09-20
--
-- PREREQUISITES:
--   - R4.5.1 executed (tests/questions tables and RPCs exist)
--   - Supabase Storage enabled
--
-- RULES:
--   - Additive only: no existing table/column/policy/grant changes
--   - RLS on uploaded_documents: creator reads own rows; no public access
--   - Storage bucket: private, authenticated-only, user-scoped paths
--   - No service-role keys in Flutter client
--
-- OWNER APPLY REQUIRED

-- ============================================================
-- SECTION 1: uploaded_documents TABLE
-- Tracks files uploaded for document-based test creation.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.uploaded_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  mime_type text NOT NULL,
  file_size integer NOT NULL CHECK (file_size > 0 AND file_size <= 20971520),
  uploaded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'uploaded'
    CHECK (status IN ('uploaded', 'parsing', 'parsed', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Index for efficient lookups by uploader.
CREATE INDEX IF NOT EXISTS idx_uploaded_documents_uploaded_by
  ON public.uploaded_documents (uploaded_by);

-- Index for group-scoped queries.
CREATE INDEX IF NOT EXISTS idx_uploaded_documents_group_id
  ON public.uploaded_documents (group_id)
  WHERE group_id IS NOT NULL;

-- ============================================================
-- SECTION 2: RLS POLICIES
-- Creator can read/update their own uploads. No public access.
-- ============================================================

ALTER TABLE public.uploaded_documents ENABLE ROW LEVEL SECURITY;

-- Policy: creator can read their own uploads.
DROP POLICY IF EXISTS "creator read own uploads" ON public.uploaded_documents;
CREATE POLICY "creator read own uploads"
  ON public.uploaded_documents
  FOR SELECT
  TO authenticated
  USING (uploaded_by = auth.uid());

-- Policy: authenticated users can insert their own uploads.
DROP POLICY IF EXISTS "auth insert own upload" ON public.uploaded_documents;
CREATE POLICY "auth insert own upload"
  ON public.uploaded_documents
  FOR INSERT
  TO authenticated
  WITH CHECK (uploaded_by = auth.uid());

-- Policy: creator can update their own uploads (status transitions).
DROP POLICY IF EXISTS "creator update own uploads" ON public.uploaded_documents;
CREATE POLICY "creator update own uploads"
  ON public.uploaded_documents
  FOR UPDATE
  TO authenticated
  USING (uploaded_by = auth.uid())
  WITH CHECK (uploaded_by = auth.uid());

-- Policy: creator can delete their own uploads.
DROP POLICY IF EXISTS "creator delete own uploads" ON public.uploaded_documents;
CREATE POLICY "creator delete own uploads"
  ON public.uploaded_documents
  FOR DELETE
  TO authenticated
  USING (uploaded_by = auth.uid());

-- ============================================================
-- SECTION 3: GRANTS
-- Only authenticated role; no anon, no public.
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.uploaded_documents TO authenticated;
REVOKE ALL ON public.uploaded_documents FROM anon;
REVOKE ALL ON public.uploaded_documents FROM PUBLIC;

-- ============================================================
-- SECTION 4: STORAGE BUCKET
-- Private bucket for test document files.
-- ============================================================

-- Create the bucket if it doesn't exist.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'test-documents',
  'test-documents',
  false,  -- PRIVATE: no public access
  20971520,  -- 20 MB
  ARRAY[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 20971520,
  allowed_mime_types = ARRAY[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel'
  ];

-- ============================================================
-- SECTION 5: STORAGE POLICIES
-- Authenticated users can only access their own files.
-- ============================================================

-- Policy: authenticated users can upload to their own folder.
DROP POLICY IF EXISTS "auth upload own files" ON storage.objects;
CREATE POLICY "auth upload own files"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'test-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: authenticated users can read their own files.
DROP POLICY IF EXISTS "auth read own files" ON storage.objects;
CREATE POLICY "auth read own files"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'test-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: authenticated users can delete their own files.
DROP POLICY IF EXISTS "auth delete own files" ON storage.objects;
CREATE POLICY "auth delete own files"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'test-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================================
-- SECTION 6: UPDATED_AT TRIGGER
-- Auto-update updated_at on row changes.
-- ============================================================

CREATE OR REPLACE FUNCTION public._fn_update_uploaded_documents_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS update_uploaded_documents_timestamp
  ON public.uploaded_documents;
CREATE TRIGGER update_uploaded_documents_timestamp
  BEFORE UPDATE ON public.uploaded_documents
  FOR EACH ROW
  EXECUTE FUNCTION public._fn_update_uploaded_documents_timestamp();

-- ============================================================
-- SECTION 7: VALIDATION QUERIES
-- ============================================================

-- V1: Table exists with correct columns.
SELECT 'V1: uploaded_documents table' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'uploaded_documents'
ORDER BY ordinal_position;

-- V2: RLS is enabled.
SELECT 'V2: RLS enabled' AS check_name;
SELECT
  relname,
  relrowsecurity AS rls_enabled,
  relforcerowsecurity AS force_rls
FROM pg_class
WHERE relname = 'uploaded_documents';

-- V3: Policies exist.
SELECT 'V3: RLS policies' AS check_name;
SELECT
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE tablename = 'uploaded_documents';

-- V4: Bucket exists and is private.
SELECT 'V4: Storage bucket' AS check_name;
SELECT
  id,
  name,
  public,
  file_size_limit
FROM storage.buckets
WHERE id = 'test-documents';

-- V5: Storage policies exist.
SELECT 'V5: Storage policies' AS check_name;
SELECT
  name,
  command,
  roles
FROM storage.policies
WHERE definition LIKE '%test-documents%';

-- ============================================================
-- ROLLBACK SCRIPT
-- ============================================================
-- Uncomment to undo:
-- DROP TRIGGER IF EXISTS update_uploaded_documents_timestamp ON public.uploaded_documents;
-- DROP FUNCTION IF EXISTS public._fn_update_uploaded_documents_timestamp();
-- DROP POLICY IF EXISTS "auth delete own files" ON storage.objects;
-- DROP POLICY IF EXISTS "auth read own files" ON storage.objects;
-- DROP POLICY IF EXISTS "auth upload own files" ON storage.objects;
-- DELETE FROM storage.buckets WHERE id = 'test-documents';
-- DROP POLICY IF EXISTS "creator delete own uploads" ON public.uploaded_documents;
-- DROP POLICY IF EXISTS "creator update own uploads" ON public.uploaded_documents;
-- DROP POLICY IF EXISTS "auth insert own upload" ON public.uploaded_documents;
-- DROP POLICY IF EXISTS "creator read own uploads" ON public.uploaded_documents;
-- DROP TABLE IF EXISTS public.uploaded_documents;

-- ============================================================
-- END OF V1 VIA DOCUMENT MIGRATION
-- ============================================================

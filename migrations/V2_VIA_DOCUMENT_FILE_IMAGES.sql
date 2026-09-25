-- V2 — Via Document/File: widen the existing 'test-documents' bucket to
-- accept legacy DOC and JPG/JPEG/PNG uploads.
-- My Preparation — Flutter + Supabase
-- Date: 2026-09-22
--
-- PREREQUISITE: V1_VIA_DOCUMENT_FILE.sql already applied (creates the
-- 'test-documents' bucket, uploaded_documents table, RLS and storage
-- policies referenced below).
--
-- RULES:
--   - Additive only. Same bucket id ('test-documents') as V1 — this does
--     NOT create a second bucket. No table/column/policy changes: the
--     existing uploaded_documents schema and RLS policies from V1 already
--     accept any file_name/mime_type/storage_path, so nothing there needs
--     to change for new file types.
--   - Idempotent: safe to run multiple times.
--
-- WHAT THIS DOES:
--   Updates storage.buckets.allowed_mime_types for 'test-documents' to add
--   legacy Word (.doc) and image (JPG/JPEG/PNG) MIME types alongside the
--   PDF/DOCX/XLSX/XLS types V1 already allowed. file_size_limit (20 MB)
--   and public=false are unchanged.
--
-- OWNER APPLY REQUIRED — this environment has no live Supabase access (no
-- CLI/psql/.env); a human with project access must run this in the
-- Supabase SQL editor.

-- ------------------------------------------------------------
-- PREFLIGHT — verify current state before applying
-- ------------------------------------------------------------
-- SELECT id, public, file_size_limit, allowed_mime_types
-- FROM storage.buckets WHERE id = 'test-documents';
-- expect: ONE ROW; allowed_mime_types missing 'application/msword',
-- 'image/jpeg', 'image/png'.

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'image/jpeg',
  'image/png'
]
WHERE id = 'test-documents';

-- Defensive: if V1 was never applied in this project, create the bucket now
-- (same id/config V1 uses, widened) rather than leaving this migration a
-- no-op — ON CONFLICT means this is safe to run whether or not V1 already
-- ran, and it never creates a second/duplicate bucket.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'test-documents',
  'test-documents',
  false,
  20971520,
  ARRAY[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'image/jpeg',
    'image/png'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 20971520,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying
-- ------------------------------------------------------------
-- SELECT id, public, file_size_limit, allowed_mime_types
-- FROM storage.buckets WHERE id = 'test-documents';
-- expect: allowed_mime_types now includes 'application/msword',
-- 'image/jpeg', 'image/png' alongside the original four V1 types.
--
-- SELECT policyname, cmd, roles FROM pg_policies
-- WHERE schemaname = 'storage' AND tablename = 'objects'
--   AND policyname IN ('auth upload own files', 'auth read own files', 'auth delete own files');
-- expect: all three rows still present (V1's storage policies are
-- bucket-scoped by id, not by MIME type, so nothing there needs to change
-- for the new file types to work).

-- ============================================================
-- END OF V2 VIA DOCUMENT / IMAGES MIGRATION
-- ============================================================

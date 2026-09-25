-- AVATAR_STORAGE_bucket_and_policies.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- CONTEXT:
-- The Profile screen now supports uploading/replacing/removing a profile
-- photo. `public.profiles.avatar_url` already exists (0001_init.sql) but no
-- Storage bucket for user-uploaded avatars has ever existed in this
-- project (confirmed by inspection — no CREATE bucket for 'avatars' or
-- similar anywhere in migrations/consolidated_schema.sql/fresh_setup.sql).
-- This migration creates exactly one new bucket for it. No existing
-- bucket, table, column, or policy is touched.
--
-- WHY PUBLIC (unlike the private `test-documents` bucket from the Via
-- Document/File feature): `profiles.avatar_url` is already read by OTHER
-- users today — `fellow members read profiles` and `test participants
-- read profiles` policies (0026/0033/0043) let group-mates and fellow
-- test participants SELECT each other's `profiles` row including
-- avatar_url, and the Flutter app already renders it directly via
-- `Image.network(url)` in group member lists / leaderboards (see
-- GroupAvatar). A private, owner-only-read bucket would break those
-- existing features (other users' avatars would fail to load). A public
-- bucket is therefore the correct, minimal choice here, not a security
-- downgrade — the underlying `profiles` row is already effectively
-- shared with group-mates/participants.
--
-- Write access (INSERT/UPDATE/DELETE) stays strictly owner-only via a
-- user-id-prefixed path, same pattern as `test-documents`.
--
-- RULES:
--   - Additive only: no existing table/column/policy/grant changes.
--   - Storage path convention: `{user_id}/profile.jpg` (one file per user;
--     every upload is re-encoded to JPEG client-side and upserted in
--     place — see `lib/core/services/avatar_service.dart` for why this
--     can never leave an orphaned object).
--   - No service-role keys in Flutter client.
--
-- OWNER APPLY REQUIRED

-- ------------------------------------------------------------
-- PREFLIGHT — verify current state before applying
-- ------------------------------------------------------------
-- SELECT id, public, file_size_limit, allowed_mime_types
-- FROM storage.buckets WHERE id = 'avatars';
-- expect: NO ROWS.
--
-- SELECT policyname FROM pg_policies
-- WHERE schemaname = 'storage' AND tablename = 'objects'
--   AND policyname LIKE '%own avatar%';
-- expect: NO ROWS.

-- ------------------------------------------------------------
-- SECTION 1: STORAGE BUCKET
-- Public read (see WHY PUBLIC above); owner-only write.
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,  -- PUBLIC: avatars are already shown to other users via profiles.avatar_url
  10485760,  -- 10 MB raw-upload ceiling (client compresses to a few hundred KB before upload)
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- ------------------------------------------------------------
-- SECTION 2: STORAGE POLICIES
-- A user may only write/replace/delete objects inside their own folder
-- (first path segment = their auth.uid()). No SELECT policy is required
-- for reads — a `public` bucket serves objects via Storage's public URL
-- endpoint without going through RLS — but one is added anyway as
-- defense-in-depth in case the bucket is ever toggled private.
-- ------------------------------------------------------------

DROP POLICY IF EXISTS "auth upload own avatar" ON storage.objects;
CREATE POLICY "auth upload own avatar"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "auth update own avatar" ON storage.objects;
CREATE POLICY "auth update own avatar"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "auth delete own avatar" ON storage.objects;
CREATE POLICY "auth delete own avatar"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "auth read avatars" ON storage.objects;
CREATE POLICY "auth read avatars"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'avatars');

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying
-- ------------------------------------------------------------
-- SELECT id, public, file_size_limit, allowed_mime_types
-- FROM storage.buckets WHERE id = 'avatars';
-- expect: ONE ROW, public = true.
--
-- SELECT policyname, cmd, roles FROM pg_policies
-- WHERE schemaname = 'storage' AND tablename = 'objects'
--   AND policyname IN ('auth upload own avatar','auth update own avatar','auth delete own avatar','auth read avatars');
-- expect: all four rows present.
--
-- SELECT policyname FROM pg_policies
-- WHERE schemaname='public' AND tablename='profiles';
-- expect: identical to before this migration (unchanged) — this
-- migration never touches public.profiles or its policies.

-- ------------------------------------------------------------
-- SECURITY / BEHAVIOR TEST MATRIX (manual, run against a live project)
-- ------------------------------------------------------------
-- 1. User A uploads to `{A_uid}/profile.jpg` -> succeeds.
-- 2. User A attempts to upload to `{B_uid}/profile.jpg` -> denied by RLS.
-- 3. User A attempts to delete `{B_uid}/profile.jpg` -> denied by RLS.
-- 4. Any authenticated user can GET the public URL of `{A_uid}/profile.jpg`
--    (matches the existing profiles-read-sharing behavior).
-- 5. Anonymous (no session) request to the public URL -> succeeds (public
--    bucket), matching how avatar_url is already rendered without an
--    authenticated fetch anywhere in the app today.

-- ------------------------------------------------------------
-- ROLLBACK SCRIPT
-- ------------------------------------------------------------
-- Uncomment to undo:
-- DROP POLICY IF EXISTS "auth read avatars" ON storage.objects;
-- DROP POLICY IF EXISTS "auth delete own avatar" ON storage.objects;
-- DROP POLICY IF EXISTS "auth update own avatar" ON storage.objects;
-- DROP POLICY IF EXISTS "auth upload own avatar" ON storage.objects;
-- DELETE FROM storage.buckets WHERE id = 'avatars';

-- ============================================================================
-- END OF AVATAR_STORAGE MIGRATION
-- ============================================================================

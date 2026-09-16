-- ============================================================
-- R4.10 FIX: My Drafts RLS Policy
-- Bug 2: getMyDrafts() fails with RLS violation
-- Date: 2026-09-14
-- Status: CONDITIONAL - verify before applying
--
-- ROOT CAUSE:
-- The only SELECT policy on public.tests ("coded tests readable")
-- was dropped in R4_3 with no replacement. RLS is enabled on
-- tests (Supabase default). Authenticated users cannot SELECT
-- from tests, causing getMyDrafts() to fail.
--
-- SECURITY IMPACT:
-- Adds a minimal SELECT policy that allows authenticated users
-- to read ONLY their own non-soft-deleted tests.
-- Does NOT expose other users' drafts.
-- Does NOT change existing group access rules.
-- Does NOT expose access_code or join_code columns.
-- ============================================================

-- 1. Verify current state (run these first to confirm the issue)
SELECT 'VERIFICATION: Current tests RLS policies' AS step;
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
ORDER BY policyname;

-- 2. Create the minimal policy (only if it doesn't exist)
-- This policy allows authenticated users to SELECT their own
-- non-soft-deleted tests. It is the MINIMUM required fix.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tests'
      AND policyname = 'creator_select_own_drafts'
  ) THEN
    CREATE POLICY "creator_select_own_drafts" ON public.tests
      FOR SELECT
      TO authenticated
      USING (
        auth.uid() = created_by
        AND is_soft_deleted = false
      );
    RAISE NOTICE 'Policy "creator_select_own_drafts" created successfully';
  ELSE
    RAISE NOTICE 'Policy "creator_select_own_drafts" already exists - skipping';
  END IF;
END $$;

-- 3. Verify the new policy
SELECT 'VERIFICATION: Updated tests RLS policies' AS step;
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
ORDER BY policyname;

-- 4. SECURITY VERIFICATION
-- Verify that the policy does NOT expose:
-- - Other users' private drafts
-- - access_code or join_code (columns exist but are not in SELECT policy)
-- - Soft-deleted tests
SELECT 'SECURITY CHECK: Policy should only allow own non-deleted tests' AS step;
SELECT
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
  AND policyname = 'creator_select_own_drafts';

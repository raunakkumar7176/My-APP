-- G17-04 — two policy corrections (owner apply required)
--
-- LIVE FINDING A (2026-09-20): public.test_syllabus has a single policy
--   "syllabus follows test" FOR ALL TO public
--   USING (EXISTS (SELECT 1 FROM tests t WHERE t.id = test_id AND fn_is_member(t.group_id, auth.uid())))
--   with no WITH CHECK (so the USING expression doubles as the INSERT check).
-- Any member of a group can INSERT / UPDATE / DELETE the syllabus rows of every
-- test in that group — not only the creator or an EDIT_TEST holder. Proven in
-- a rolled-back probe (plain member inserted and deleted a syllabus row of a
-- leader's test). Writers live: rpc_add_test_syllabus / rpc_remove_test_syllabus
-- (SECURITY DEFINER, creator-gated, unaffected by policies) and the legacy web
-- app's group test creation (direct INSERT by the test creator).
--
-- FIX A: read stays member-wide (plus the creator, so standalone tests keep
-- reading their own syllabus); writes require the test creator or EDIT_TEST in
-- the test's group. The legacy creator INSERT keeps working.
--
-- LIVE FINDING B: public.group_announcements INSERT policy checks only
-- SEND_ANNOUNCEMENT / owner, not author_id, so a permitted author can post an
-- announcement attributed to any other user (proven). Flutter and the legacy
-- app both send author_id = auth.uid().
-- FIX B: add author_id = auth.uid() to the INSERT check. Nothing else changes.

-- A. test_syllabus
DROP POLICY IF EXISTS "syllabus follows test" ON public.test_syllabus;

CREATE POLICY "syllabus read for members and creator" ON public.test_syllabus
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.tests t
    WHERE t.id = test_syllabus.test_id
      AND (t.created_by = auth.uid()
           OR (t.group_id IS NOT NULL AND public.fn_is_member(t.group_id, auth.uid())))
  ));

CREATE POLICY "syllabus write for creator or editor" ON public.test_syllabus
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.tests t
    WHERE t.id = test_syllabus.test_id
      AND (t.created_by = auth.uid()
           OR (t.group_id IS NOT NULL AND public.fn_has_permission(t.group_id, auth.uid(), 'EDIT_TEST'::public.app_permission)))
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.tests t
    WHERE t.id = test_syllabus.test_id
      AND (t.created_by = auth.uid()
           OR (t.group_id IS NOT NULL AND public.fn_has_permission(t.group_id, auth.uid(), 'EDIT_TEST'::public.app_permission)))
  ));

-- B. group_announcements author
DROP POLICY IF EXISTS "leaders create announcements" ON public.group_announcements;

CREATE POLICY "leaders create announcements" ON public.group_announcements
  FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND (public.fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT'::public.app_permission)
         OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'::public.group_role)
  );

-- postflight (read-only)
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('test_syllabus', 'group_announcements')
ORDER BY 1, 2;
-- expect test_syllabus: "syllabus read for members and creator" (SELECT), "syllabus write for creator or editor" (ALL)
--        group_announcements: 4 policies incl. "leaders create announcements" (INSERT)

-- ROLLBACK (verbatim previous policies):
-- DROP POLICY "syllabus read for members and creator" ON public.test_syllabus;
-- DROP POLICY "syllabus write for creator or editor" ON public.test_syllabus;
-- CREATE POLICY "syllabus follows test" ON public.test_syllabus FOR ALL TO public
--   USING (EXISTS (SELECT 1 FROM tests t WHERE t.id = test_syllabus.test_id AND fn_is_member(t.group_id, auth.uid())));
-- DROP POLICY "leaders create announcements" ON public.group_announcements;
-- CREATE POLICY "leaders create announcements" ON public.group_announcements FOR INSERT TO authenticated
--   WITH CHECK (fn_has_permission(group_id, auth.uid(), 'SEND_ANNOUNCEMENT'::app_permission) OR fn_get_group_role(group_id, auth.uid()) = 'owner'::group_role);

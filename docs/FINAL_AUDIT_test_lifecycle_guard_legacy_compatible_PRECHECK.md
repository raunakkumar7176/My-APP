# FINAL AUDIT — PRECHECK: legacy-compatible test lifecycle guard (G10.2 replacement)

**Product decision required before applying.** This guard keeps the legacy web app's direct
`tests` transitions (`→ ready`, `→ cancelled`, `→ archived`, schedule edits) and blocks
everything else for client sessions. Run in the SQL Editor before
`migrations/FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql`. Read-only.

## 1. The gap (live)

```sql
SELECT policyname, cmd, qual, with_check FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'tests' AND policyname = 'group edit test';
-- expect: UPDATE, USING/CHECK = (group_id IS NOT NULL) AND fn_has_permission(group_id, auth.uid(), 'EDIT_TEST')
--         (no column restriction)
SELECT count(*) AS guard_present FROM pg_trigger WHERE tgname = 'trg_guard_test_lifecycle';  -- expect 0
SELECT count(*) AS g10_2_fn FROM pg_proc WHERE proname = 'fn_guard_test_lifecycle';           -- expect 0
```

## 2. Who updates `tests` directly today

- Flutter: **nobody** — `grep -rn "from('tests')" lib` shows reads only; mutations go through
  `rpc_create_test`, `rpc_update_test`, `rpc_publish_test`, `rpc_delete_test`, `fn_soft_delete_test`.
- Legacy web app (`My-Prepration/src/app/(app)/tests/[id]/lifecycle-actions.ts`, user session):
  `status='ready'` (line 148), schedule/edit updates restricted to
  `status in (draft, ready, published, scheduled)` (line 212), `status='cancelled'` (292),
  `status='archived'` from `ended|completed|evaluated|cancelled` (308).
- Legacy profile deletion uses the **service role** (`admin.from("tests").update({created_by:null})`) — unaffected.

## 3. Live rolled-back proof of the gap (optional)

```sql
BEGIN;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '<leader with EDIT_TEST>', true);
UPDATE public.tests SET status = 'live', created_by = '<leader>' WHERE id = '<group test id>';  -- expect UPDATE 1 (the gap)
ROLLBACK;
```

## 4. Enum values the guard reasons about

```sql
SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'test_status' ORDER BY enumsortorder;
-- expect: draft, published, scheduled, live, completed, cancelled, ready, ended, evaluated, archived, expired
```

# FINAL AUDIT — POSTCHECK: legacy-compatible test lifecycle guard

Run after `migrations/FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql`.

## 1. Objects

```sql
SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'public.tests'::regclass AND tgname = 'trg_guard_test_lifecycle'; -- 1 row, 'O'
SELECT prosecdef, proconfig FROM pg_proc WHERE proname = 'fn_guard_test_lifecycle';  -- false (INVOKER), {search_path=}
SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='tests';     -- unchanged (9)
```

## 2. Rolled-back behaviour proof (as an EDIT_TEST holder, e.g. a leader)

```sql
BEGIN;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '<leader>', true);
UPDATE public.tests SET status='live'      WHERE id='<draft group test>';   -- expect ERROR LIFECYCLE_LOCKED
UPDATE public.tests SET created_by='<leader>' WHERE id='<draft group test>'; -- expect ERROR OWNERSHIP_LOCKED
UPDATE public.tests SET is_soft_deleted=true WHERE id='<draft group test>'; -- expect ERROR DELETE_LOCKED
UPDATE public.tests SET status='ready'     WHERE id='<draft group test>';   -- expect UPDATE 1 (legacy path)
UPDATE public.tests SET status='cancelled' WHERE id='<draft group test>';   -- expect UPDATE 1 (legacy path)
UPDATE public.tests SET status='archived'  WHERE id='<ended group test>';   -- expect UPDATE 1 (legacy path)
RESET ROLE;
ROLLBACK;
```

## 3. RPC / cron paths unaffected

- `rpc_publish_test` (creator) still moves draft → published (definer, runs as postgres).
- `rpc_start_attempt` still moves scheduled → live.
- `fn_soft_delete_test` / `rpc_delete_test` still soft-delete.
- `fn_sweep_deadlines` (cron, postgres) still transitions live → ended.
Rolled-back proof of all four is recorded in the FINAL_GAP_AUDIT_REPORT (§4, guard proof 18/18).

## 4. Rollback

```sql
DROP TRIGGER IF EXISTS trg_guard_test_lifecycle ON public.tests;
DROP FUNCTION IF EXISTS public.fn_guard_test_lifecycle();
```

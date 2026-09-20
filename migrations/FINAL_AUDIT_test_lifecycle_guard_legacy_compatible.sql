-- FINAL AUDIT — legacy-compatible replacement for G10.2 (owner apply required; PRODUCT DECISION)
--
-- LIVE FINDING (re-verified 2026-09-20, rolled back): the live UPDATE policy
-- "group edit test" (USING/CHECK = group_id IS NOT NULL AND EDIT_TEST) has no column
-- restriction, so an EDIT_TEST holder can, by direct UPDATE:
--   * set status to any value (draft <-> live/ended/evaluated/published ...),
--   * re-assign created_by (taking over creator-only RPC rights: publish, delete,
--     question management),
--   * change test_mode, or flip is_soft_deleted / deleted_at.
-- G10.2 proposed fn_guard_test_lifecycle() blocking every status change for
-- authenticated/anon. It was parked because the legacy web app
-- (My-Prepration/src/app/(app)/tests/[id]/lifecycle-actions.ts) still sets
-- status = 'ready' | 'cancelled' | 'archived' and schedule fields by direct
-- UPDATE with the user session.
--
-- THIS VERSION keeps those legacy transitions and blocks everything else:
--   * created_by, group_id, test_mode, is_soft_deleted, deleted_at, deleted_by are
--     immutable for authenticated/anon (SECURITY DEFINER RPCs and service_role are
--     unaffected: they run as postgres / service_role);
--   * status may only move along the legacy lifecycle edges by direct UPDATE:
--       draft|ready|published|scheduled  -> ready | cancelled
--       ended|completed|evaluated|cancelled -> archived
--     every other direct status change (incl. any move to draft, live, published,
--     ended, evaluated, completed, expired) raises LIFECYCLE_LOCKED — those states
--     are owned by rpc_publish_test, _fn_start_attempt_core and fn_sweep_deadlines;
--   * ends_at > starts_at is re-validated when either changes.
-- Flutter never updates `tests` directly (all mutations are RPCs), so it is unaffected.
-- Rollback: DROP TRIGGER trg_guard_test_lifecycle ON public.tests; DROP FUNCTION public.fn_guard_test_lifecycle();

CREATE OR REPLACE FUNCTION public.fn_guard_test_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $$
declare
  v_old text := old.status::text;
  v_new text := new.status::text;
begin
  -- SECURITY INVOKER on purpose: the function only inspects OLD/NEW, and
  -- current_user must reflect the caller — authenticated/anon for PostgREST
  -- client sessions, postgres inside SECURITY DEFINER RPCs, service_role for
  -- the service key. (A DEFINER trigger would always see postgres.)
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'OWNERSHIP_LOCKED';
  end if;
  if new.group_id is distinct from old.group_id then
    raise exception 'GROUP_LOCKED';
  end if;
  if new.test_mode is distinct from old.test_mode then
    raise exception 'MODE_LOCKED';
  end if;
  if new.is_soft_deleted is distinct from old.is_soft_deleted
     or new.deleted_at is distinct from old.deleted_at
     or new.deleted_by is distinct from old.deleted_by then
    raise exception 'DELETE_LOCKED';
  end if;
  if v_new is distinct from v_old then
    if not (
      (v_old in ('draft', 'ready', 'published', 'scheduled') and v_new in ('ready', 'cancelled'))
      or (v_old in ('ended', 'completed', 'evaluated', 'cancelled') and v_new = 'archived')
    ) then
      raise exception 'LIFECYCLE_LOCKED: % -> % is not a client transition', v_old, v_new;
    end if;
  end if;
  if (new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at)
     and new.starts_at is not null and new.ends_at is not null and new.ends_at <= new.starts_at then
    raise exception 'VALIDATION_ERROR: ends_at must be after starts_at';
  end if;
  return new;
end
$$;

DROP TRIGGER IF EXISTS trg_guard_test_lifecycle ON public.tests;
CREATE TRIGGER trg_guard_test_lifecycle
  BEFORE UPDATE ON public.tests
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_test_lifecycle();

-- postflight (read-only)
SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'public.tests'::regclass AND tgname = 'trg_guard_test_lifecycle'; -- expect 1 row, 'O'

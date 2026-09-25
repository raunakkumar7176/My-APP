-- PUSH_notifications_pushed_at.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access.
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- CONTEXT: adds the one column the push-dispatch webhook (Phase 6/12) needs
-- for atomic, race-safe idempotency — "has this notification row already
-- had a push dispatch attempted for it?" A Supabase Database Webhook can
-- retry on a non-2xx response; without a claim column, a retry (or two
-- webhook deliveries racing) could send the same push twice. This makes the
-- notification row's own id the dedupe key (Phase 12: "use stable
-- notification IDs / dedupe keys") instead of inventing a second table.
--
-- RULES: additive only — one nullable column, no data touched, no RLS
-- change (this column is set only by the service-role dispatch route).
--
-- OWNER APPLY REQUIRED

-- PREFLIGHT:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='notifications' AND column_name='pushed_at';
-- expect: NO ROWS.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS pushed_at timestamptz;

COMMENT ON COLUMN public.notifications.pushed_at IS
  'Set once, atomically, by the push-dispatch route (service-role only) when it claims this row for delivery. NULL means push has not been attempted yet. Never set by client code or by fn_notify_group/rpc_publish_results — those only ever insert the row with pushed_at left NULL.';

-- POSTFLIGHT:
-- SELECT column_name, is_nullable FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='notifications' AND column_name='pushed_at';
-- expect: one row, is_nullable = YES.

-- ROLLBACK:
-- ALTER TABLE public.notifications DROP COLUMN IF EXISTS pushed_at;

-- ============================================================================
-- END OF PUSH_notifications_pushed_at MIGRATION
-- ============================================================================

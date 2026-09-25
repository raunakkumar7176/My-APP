-- PUSH_user_device_tokens.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- CONTEXT (live-proven by inspection, not live query — see this project's
-- standing rule that migration files are history/proposal, not live fact):
-- The Flutter app has a mature IN-APP notification system (`public.
-- notifications`, `notification_settings`, `fn_notify_group`, 27 categories)
-- but ZERO mobile push delivery — no Firebase, no device-token table, no
-- AndroidManifest permission (confirmed: AndroidManifest.xml has only
-- android.permission.INTERNET). A parallel, separate Next.js/Capacitor build
-- of this same backend (`My-Prepration/`) already has real web-push (VAPID)
-- infrastructure with its own `push_subscriptions` table — but that table's
-- schema (endpoint/p256dh/auth) is Web Push Protocol-shaped, and its one
-- attempt to also carry native FCM tokens (storing a fake `fcm://platform/
-- TOKEN` string as `endpoint`) is not actually deliverable through that
-- table's sender (`web-push` npm library, which POSTs to `endpoint` as a
-- real HTTPS Web Push service URL — `fcm://...` is not one). Per this
-- migration's task instructions ("if a PROPER user-device token table
-- already exists, reuse it") — `push_subscriptions` is not that: it is the
-- wrong shape for FCM and its FCM path is provably non-functional. This
-- migration adds the clean, purpose-built table instead, alongside (not
-- replacing) push_subscriptions.
--
-- RULES:
--   - Additive only. No existing table/column/policy/grant touched.
--   - RLS: a user may only read/write their OWN device-token rows.
--   - A user may have multiple active devices (unique per user+token, not
--     per user — logging in on a second device does not evict the first).
--   - No service-role/secret exposure — this table itself carries no
--     provider credentials, only opaque tokens the device generated.
--
-- OWNER APPLY REQUIRED

-- ------------------------------------------------------------
-- PREFLIGHT — verify current state before applying
-- ------------------------------------------------------------
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema='public' AND table_name = 'user_device_tokens';
-- expect: NO ROWS.

-- ------------------------------------------------------------
-- SECTION 1: user_device_tokens TABLE
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_device_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token     text NOT NULL,
  platform      text NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios', 'web')),
  device_id     text,
  app_version   text,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  -- One row per physical token. A device that re-registers (token refresh)
  -- upserts onto this constraint rather than accumulating duplicate rows;
  -- a second device logging in gets its OWN row (different token), so the
  -- first device's row is never touched, let alone evicted.
  UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user_active
  ON public.user_device_tokens (user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_token
  ON public.user_device_tokens (fcm_token);

ALTER TABLE public.user_device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own device tokens read" ON public.user_device_tokens;
CREATE POLICY "own device tokens read"
  ON public.user_device_tokens FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens insert" ON public.user_device_tokens;
CREATE POLICY "own device tokens insert"
  ON public.user_device_tokens FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens update" ON public.user_device_tokens;
CREATE POLICY "own device tokens update"
  ON public.user_device_tokens FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "own device tokens delete" ON public.user_device_tokens;
CREATE POLICY "own device tokens delete"
  ON public.user_device_tokens FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_device_tokens TO authenticated;
-- service_role needs UPDATE too: the server-side push dispatcher (Phase 13)
-- marks a token is_active=false when FCM reports it invalid/unregistered —
-- that happens outside the owning user's own session.
GRANT SELECT, UPDATE ON public.user_device_tokens TO service_role;
REVOKE ALL ON public.user_device_tokens FROM anon;
REVOKE ALL ON public.user_device_tokens FROM PUBLIC;

CREATE OR REPLACE FUNCTION public._fn_touch_device_token_timestamp()
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

DROP TRIGGER IF EXISTS touch_device_token_timestamp ON public.user_device_tokens;
CREATE TRIGGER touch_device_token_timestamp
  BEFORE UPDATE ON public.user_device_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public._fn_touch_device_token_timestamp();

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying
-- ------------------------------------------------------------
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='user_device_tokens' ORDER BY ordinal_position;
--
-- SELECT policyname, cmd, roles FROM pg_policies
-- WHERE schemaname='public' AND tablename='user_device_tokens';
-- expect: 4 rows (select/insert/update/delete), each scoped to auth.uid().

-- ------------------------------------------------------------
-- ROLLBACK SCRIPT
-- ------------------------------------------------------------
-- DROP TRIGGER IF EXISTS touch_device_token_timestamp ON public.user_device_tokens;
-- DROP FUNCTION IF EXISTS public._fn_touch_device_token_timestamp();
-- DROP TABLE IF EXISTS public.user_device_tokens;

-- ============================================================================
-- END OF PUSH_user_device_tokens MIGRATION
-- ============================================================================

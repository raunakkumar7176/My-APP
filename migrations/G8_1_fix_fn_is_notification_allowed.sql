-- ============================================================
-- G8.1 — LIVE DEFECT FIX (PROPOSED — NOT APPLIED): fn_is_notification_allowed
-- ============================================================
-- Found by the G8 live audit (2026-09-19, read-only, rolled-back transaction):
--   select public.fn_is_notification_allowed(<uid>, 'GROUP_MESSAGE', <group>, ...)
--   → ERROR: column reference "is_muted" is ambiguous
-- Cause: the plpgsql variable `is_muted` (DECLARE) shadows the column
-- `group_mutes.is_muted` inside `AND is_muted = true`.
-- Impact (live, verified): fn_notify_group() calls this function for every
-- recipient, so every AFTER INSERT notify trigger raises and ROLLS BACK the
-- insert whenever a group has ≥ 2 members:
--   * group_messages INSERT  (G8 chat send)           → fails
--   * group_announcements INSERT (G7 post)            → fails
--   * group_members INSERT (fn_join_group / accept invitation / approve
--     request — G5 lifecycle)                          → fails
-- Fix: the ONE-token change below (qualify the column). Everything else is
-- the live definition verbatim (pg_get_functiondef), so nothing else moves.
-- Rollback: re-run the previous definition (this file minus the fix).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_is_notification_allowed(p_user uuid, p_type text, p_group_id uuid DEFAULT NULL::uuid, p_priority text DEFAULT 'medium'::text, p_require_push boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    s public.notification_settings%ROWTYPE;
    is_muted boolean := false;
    upper_type text;
BEGIN

    IF p_user IS NULL THEN
        RETURN false;
    END IF;


    -- Load user notification preferences.

    SELECT *
    INTO s
    FROM public.notification_settings
    WHERE user_id = p_user;


    -- Safe defaults when settings row does not exist.

    IF s.user_id IS NULL THEN

        s.notifications_enabled := true;
        s.push_enabled := false;
        s.test_reminders := true;
        s.routine_reminders := true;
        s.group_messages := true;
        s.group_announcements := true;
        s.test_invitations := true;
        s.test_results := true;
        s.quiet_hours_enabled := false;

    END IF;


    -- Master switch.

    IF COALESCE(
        s.notifications_enabled,
        true
    ) = false THEN
        RETURN false;
    END IF;


    -- Push-specific gate.

    IF p_require_push
       AND COALESCE(
           s.push_enabled,
           false
       ) = false THEN
        RETURN false;
    END IF;


    upper_type := upper(
        coalesce(p_type, '')
    );


    -- ========================================================
    -- GROUP MESSAGE
    -- ========================================================

    IF upper_type = 'GROUP_MESSAGE' THEN

        IF COALESCE(
            s.group_messages,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- GROUP ANNOUNCEMENT
    -- ========================================================

    ELSIF upper_type = 'GROUP_ANNOUNCEMENT' THEN

        IF COALESCE(
            s.group_announcements,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- TEST INVITATIONS / ASSIGNMENTS
    -- ========================================================

    ELSIF upper_type IN (
        'TEST_INVITATION',
        'GROUP_TEST_ASSIGNED'
    ) THEN

        IF COALESCE(
            s.test_invitations,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- TEST REMINDERS / LIFECYCLE
    -- ========================================================

    ELSIF upper_type IN (
        'TEST_REMINDER',
        'TEST_LIVE',
        'TEST_SCHEDULED',
        'TEST_STARTING_SOON',
        'TEST_STARTED',
        'TEST_ENDED',
        'GROUP_TEST_REMINDER'
    ) THEN

        IF COALESCE(
            s.test_reminders,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- ROUTINE EVENTS
    -- ========================================================

    ELSIF upper_type IN (
        'ROUTINE_REMINDER',
        'ROUTINE_DUE',
        'ROUTINE_MISSED',
        'ROUTINE_COMPLETED'
    ) THEN

        IF COALESCE(
            s.routine_reminders,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- RESULT / REPORT EVENTS
    -- ========================================================

    ELSIF upper_type IN (
        'REPORT_READY',
        'TEST_COMPLETED',
        'RESULTS_AVAILABLE',
        'LEADERBOARD_UPDATED',
        'CONTENT_REVIEW_RESULT'
    ) THEN

        IF COALESCE(
            s.test_results,
            true
        ) = false THEN
            RETURN false;
        END IF;


    -- ========================================================
    -- STREAK / SYSTEM
    -- ========================================================

    ELSIF upper_type IN (
        'STREAK_MILESTONE',
        'SYSTEM_NOTIFICATION',
        'SYSTEM'
    ) THEN

        -- Master notification switch was already checked.
        NULL;

    END IF;


    -- ========================================================
    -- GROUP MUTE
    -- ========================================================

    IF p_group_id IS NOT NULL
       AND upper_type IN (
           'GROUP_MESSAGE',
           'GROUP_ANNOUNCEMENT',
           'TEST_REMINDER',
           'TEST_LIVE',
           'TEST_SCHEDULED',
           'TEST_STARTING_SOON',
           'TEST_STARTED',
           'GROUP_TEST_ASSIGNED',
           'GROUP_TEST_REMINDER'
       ) THEN

        SELECT EXISTS (
            SELECT 1
            FROM public.group_mutes
            WHERE user_id = p_user
              AND group_id = p_group_id
              AND group_mutes.is_muted = true   -- G8.1 fix: qualified (was ambiguous with the plpgsql variable)
        )
        INTO is_muted;

        IF is_muted THEN
            RETURN false;
        END IF;

    END IF;


    -- ========================================================
    -- QUIET HOURS
    -- ========================================================

    IF public.fn_is_quiet_hours(
        p_user,
        lower(
            COALESCE(
                p_priority,
                'medium'
            )
        )
    ) THEN
        RETURN false;
    END IF;


    RETURN true;

END;
$function$
;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement). The function is STABLE, so this
-- call writes nothing. Before the fix it raises "is_muted is ambiguous";
-- after the fix it returns a boolean (true with default settings).
-- ------------------------------------------------------------
SELECT public.fn_is_notification_allowed(
  gen_random_uuid(), 'GROUP_MESSAGE', gen_random_uuid(), 'medium', false
) AS allowed_after_fix;

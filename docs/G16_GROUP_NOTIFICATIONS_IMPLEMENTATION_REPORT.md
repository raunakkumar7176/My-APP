# G16 — Group Notifications / Unread State: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `aabb9d2` (G14) · **Commit:** `3c30c72` · **Date:** 2026-09-20
**Role:** implementer only (not audited). G15 files (`group_membership_edge_cases_test.dart`, in progress by the other agent), G14 backend, G12 F1, G10.2, G11 backend: untouched. G17 / G18 not started.

## FINAL STATUS

**G16 IMPLEMENTATION COMPLETE — BACKEND PENDING (OWNER APPLY REQUIRED, security hardening only)**

The whole unread / inbox / mark-read / mute experience runs on the live schema **as it is** — no new table, column, function, policy or counter. "Backend pending" is one pre-existing live security gap found by the live-first audit (§7): `fn_notify_group` is executable by any signed-in user with no caller check. The one-statement `REVOKE` that closes it is written, proven in a rolled-back transaction (7/7), and **not applied**.

---

## 1. Live-first findings (read-only grids + rolled-back probes, 2026-09-20)

| Object | Live state |
|---|---|
| `public.notifications` | `id, user_id → profiles, category notif_category, title, body, data jsonb, read_at timestamptz NULL, created_at, priority (low/medium/high/urgent + upper variants), dedupe_key`; partial unique `(user_id, dedupe_key)`; indexes on `(user_id, created_at DESC)` and `(user_id, read_at) WHERE read_at IS NULL`. RLS on; policies: **SELECT `own notifications`** (`user_id = auth.uid()`), **UPDATE `mark own read`** (`user_id = auth.uid()`, WITH CHECK defaults to USING so `user_id` cannot be re-pointed) — **no INSERT, no DELETE policy** (table grants exist for anon/authenticated but no policy ⇒ denied). 39 rows live, 9 unread. |
| `notif_category` enum | 23 values; live rows use only `GROUP_MESSAGE` (34), `GROUP_ANNOUNCEMENT` (4), `TEST_INVITATION` (1) |
| `data` payload (live rows) | always `group_id` + `type`; per type `message_id` / `announcement_id` / `test_id` / `user_id` |
| `fn_notify_group(p_group, p_category, p_title, p_body, p_data, p_exclude)` | SECURITY DEFINER, `search_path=public`; one row per member except `p_exclude`, **skipping `group_mutes.is_muted`** and anything `fn_is_notification_allowed` refuses; priority by category; dedupe by message/announcement/test id; `ON CONFLICT DO NOTHING`. **EXECUTE granted to `authenticated`** (§7). |
| triggers → `fn_notify_group` | `trg_group_message_notify` (AFTER INSERT `group_messages` → `GROUP_MESSAGE` / `group_message`, excludes sender), `trg_group_announcement_notify` (→ `GROUP_ANNOUNCEMENT` / `group_announcement`, excludes author), `trg_group_join_notify` (AFTER INSERT `group_members` → `GROUP_ANNOUNCEMENT` / `group_join`, excludes joiner), `trg_group_test_notify` (AFTER INSERT `tests` with `group_id` → `TEST_INVITATION` / `group_test`, excludes creator). System messages (`trg_member_joined_system` / `_left_system` / `_role_changed_system` → `fn_insert_system_message` → `group_messages`) therefore also arrive as `GROUP_MESSAGE` notifications. |
| `fn_is_notification_allowed` | master switch, per-category switches (`notification_settings`), group mute, quiet hours (G8.1 fix in place) |
| `notification_settings` | per-user row (own-row FOR ALL); auto-created by `trg_ensure_notif_settings` on profile insert; `group_messages`, `group_announcements`, `test_invitations`, `badge_enabled`, `push_enabled`, quiet hours… |
| `group_mutes` | PK `(user_id, group_id)`, `is_muted bool DEFAULT true`, `updated_at`; policy `own group_mutes` (FOR ALL, `user_id = auth.uid()`); honoured by `fn_notify_group` |
| `message_reads` + `fn_get_group_unread_counts(uuid[])` + `fn_mark_group_read(uuid)` | the **chat** unread system (G8): per-group `last_read_at` vs `group_messages` — separate from `notifications.read_at`; **not touched, not duplicated** |
| `group_announcement_reads` + `fn_mark_announcement_read` | announcement read receipts (G7) — separate, untouched |
| `push_subscriptions` / `push_deliveries` | exist; no Flutter push integration (out of scope) |
| realtime | `notifications` not in the `supabase_realtime` publication → no realtime; pull/refresh model (as G8) |
| mark-read RPC | **none live** — the sanctioned path is the own-row UPDATE under `mark own read` |
| `group_notifications` table | does not exist (not invented) |

## 2. Existing infrastructure reused

`notifications` (read + `read_at`), `group_mutes` (mute), `fn_notify_group` + the four triggers (delivery — nothing added), `fn_is_notification_allowed` / `notification_settings` (preferences — untouched, still enforced server-side), `GroupRepository.groupForMember` (membership guard, same rule as every group screen), `GroupErrors` (+ one context), `DisposableNotifier`, `GroupHubController` / hub app bar, router subtree, `TestFormatters.dateTime`, the `InMemoryGroupRepository` test pattern.

## 3. Notification types supported (exactly what the live triggers write)

| `category` | `data.type` | Source | Screen action on tap |
|---|---|---|---|
| `GROUP_MESSAGE` | `group_message` | G8 chat message (and system timeline messages) | mark read → back to the hub (chat section) |
| `GROUP_ANNOUNCEMENT` | `group_announcement` | G7 announcement | mark read → back to the hub (announcements section) |
| `GROUP_ANNOUNCEMENT` | `group_join` | G5 member joined | mark read → back to the hub |
| `TEST_INVITATION` | `group_test` | G10 test created in the group | mark read → `/groups/:id/tests` |
| any other enum value | any | none live today (results/leaderboard/role-change/removal events are **not** emitted by any live trigger) | listed with a generic icon; mark read only — nothing invented |

## 4. Unread / read design

- **Authoritative state:** live `notifications.read_at` (`NULL` = unread). No local flag, no cache.
- **Group scope:** live `data->>'group_id'` (set by `fn_notify_group` on every row) — filter `eq('data->>group_id', groupId)`.
- **Unread count:** one `count(*)` HEAD request (`user_id = uid AND data->>group_id = g AND read_at IS NULL`) — backed by the live partial index. Shown as a badge on the hub bell; re-read on every hub `load()`/`refresh()`, so returning from the inbox never leaves a stale count.
- **List:** `select … order by created_at desc, id desc limit 30`, keyset pagination on `created_at` (`lt`), "Load older" until a short page. One request per page; no N+1 (no per-row lookups — titles/bodies are already server-rendered).
- **Mark one:** `update read_at=now() where id=? and user_id=uid and read_at is null … select id` — idempotent (0 rows for already-read / not-own). **Mark all:** same with the group filter instead of the id. Both single-flight via the controller's `_run`, followed by a **server re-read** of page + count + mute; the mutation's error message survives the re-read.
- **Mute:** `group_mutes` upsert (`onConflict user_id,group_id`), read on load; the server (`fn_notify_group`) decides delivery — the client changes nothing else.
- **Removed member:** the inbox screen is membership-guarded (`groupForMember` → denied), like every group screen; the user's own old rows remain readable under the live own-row policy (documented, §11).

## 5. Files changed

| File | Change |
|---|---|
| `lib/core/models/app_notification.dart` | **new** — live row model (`groupId`, `type`, `isRead`, ids) |
| `lib/features/group/data/notification_repository.dart` | **new** — `NotificationRepository` + `SupabaseNotificationRepository`: `forGroup`, `unreadCount`, `markRead`, `markAllRead`, `isMuted`, `setMuted`; `notificationPageSize = 30` |
| `lib/features/group/state/group_notifications_controller.dart` | **new** — load / refresh / loadOlder / markRead / markAllRead / setMuted; membership guard; single-flight; server re-read |
| `lib/features/group/screens/group_notifications_screen.dart` | **new** — list newest first, unread dot/bold, title "(n unread)", mark-all action, mute switch, load older, loading/error/empty/denied states |
| `lib/features/group/state/group_hub_controller.dart` | optional `notifications` repository; `unreadNotifications` / `hasUnreadNotifications` / `hasNotifications`; count loaded in `load()` (failure ⇒ no badge, never an error state); cleared on access denial |
| `lib/features/group/screens/group_hub_screen.dart` | wires `SupabaseNotificationRepository`; bell `IconButton` with `Badge.count`; `_openNotifications` → push + `refresh()` |
| `lib/app/app_router.dart` | `/groups/:groupId/notifications` (`group-notifications`) |
| `lib/features/group/domain/group_errors.dart` | `GroupErrorContext.notification` + messages |
| `test/group/fakes.dart` | `FakeNotificationRepository` (own rows, `read_at`, group scope, mutes, `notifyGroup` mirror of `fn_notify_group`) |
| `test/group/group_notifications_test.dart` | **new** — 20 tests |
| `migrations/G16_revoke_fn_notify_group_execute.sql`, `docs/G16_PRECHECK.sql`, `docs/G16_POSTCHECK.sql` | backend (pending) |

Not touched: G15 files, `group_repository.dart` (the other agent's uncommitted reformat stays in the working tree), G13/G12/G11/G10 screens, chat/announcement code, any notification trigger or function.

## 6. Backend changes / pending

`migrations/G16_revoke_fn_notify_group_execute.sql`:
```sql
REVOKE EXECUTE ON FUNCTION public.fn_notify_group(uuid, public.notif_category, text, text, jsonb, uuid) FROM PUBLIC, anon, authenticated;
```
plus a read-only postflight and the verbatim rollback grant in comments. Function body, triggers, tables, policies and the `service_role` grant are unchanged. Nothing in the Flutter app or the legacy web app calls the function from a client; its only callers are the four SECURITY DEFINER trigger functions owned by `postgres`, which keep working (proven M4–M7).

**Rolled-back proof (7/7, residue 0, live still `authenticated_can_execute = true`):** after the revoke a signed-in non-member and anon get `permission denied for function`; a chat message and an announcement still produce notifications for the other members through the triggers.

Owner steps: `docs/G16_PRECHECK.sql` (expect `authenticated_can_execute = true`) → run the migration → `docs/G16_POSTCHECK.sql` (expect `false, false, true`, 4 triggers, 2 + 1 policies).

Everything else the G16 UI needs is already live: **no other G16 backend migration is required.**

Still pending from earlier phases (unchanged): G14 `group_members` legacy policy drop, G6 rules table, G10.2 (product decision), G11 coach-report RPC, `ai_jobs` worker, credentials in untracked `tool/`.

## 7. Security considerations (live, rolled back: `g16_proof.js` 28/28)

| Requirement | Result |
|---|---|
| read another user's notifications | 0 rows (own-row SELECT policy) — [3] |
| mark another user's row read (forged id, no user filter) | 0 rows — [8] |
| re-point own rows to another `user_id` | RLS CHECK error — [9] |
| forge rows (INSERT for self / for another user) | RLS error, no INSERT policy — [12, 13] |
| delete own rows | 0 rows, no DELETE policy — [14] |
| non-member reads a group's notifications | 0 rows — [24]; screen: access denied |
| removed member | group access denied ([22]); own old rows still readable by the live policy ([23]) — the screen denies, documented (§11) |
| anon | 0 rows on `notifications` (policy on `{public}`), `permission denied` on `group_mutes` — [25, 26] |
| mute forgery (mute another user) | RLS error — [17]; other users' mute rows unreadable — [21] |
| mute semantics | muted member receives nothing for a new message, unmuted owner does — [18, 19] |
| actor exclusion | the sender/creator gets no row for their own message/test — [5] |
| mark one / mark all (client statements) | 1 row → 0-row no-op; group-scoped mark-all; count 0 afterwards — [6, 7, 10, 11] |
| **`fn_notify_group` callable by any authenticated user** | **GAP** — a non-member pushed a row into another group's owner inbox — [15, 15b] → migration §6 |
| loose `mark own read` UPDATE policy | a user may edit any column of their **own** rows (title/body/data), not others'. Non-blocking; no migration proposed. |
| table grants to `anon` on `notifications` | policy still yields 0 rows; noted only |

No service-role key; no `questions`/`correct_option`; identity is `auth.uid()` in every statement; the client adds `user_id = uid` only as an index hint, never as authorization.

## 8. AI side-effect verification

Client: `group_notifications_test.dart` "opening, refreshing and paging perform reads only" — no `markRead`/`markAllRead`/`setMuted` call and no group mutation on load/refresh/page. Live: `ai_jobs` and `result_batches` counts identical before and after every read and mark in the proof ([27]); the repository has no path to any RPC.

## 9. Tests (`test/group/group_notifications_test.dart`, 20) — client tests, not live proof

1 unread count & 3 newest-first order · 2 empty state (mark-all disabled) · 4 pagination (full page → Load older; keyset; single-flight; no duplicates; finite) · 5 mark one (one update; page+count re-read; no-op when read) · 6 mark all (group-scoped; other groups untouched; no-op when none) · server refusal surfaces with re-read (no optimistic state) · 7/14 hub badge from the server count, hidden after mark-all + refresh; hub without repository shows no bell; failing count never breaks the hub · 8 other user's rows never read/marked · 9/10 non-member / forged group / removed member → denied, no notification read, actions refused · 11 mute read/toggle/no-op and delivery skip (fn_notify_group mirror) · 12 load single-flight; second mutation refused while busy · 13 covered in 5/6 · 15/16 G8 chat, G7 announcement, G5 join, G10 test rows listed, typed and scoped · 17 reads only · 18 one contract (own rows, `read_at`, `data.group_id`, `group_mutes`) · UI: read/unread rendering, tap marks read, mark-all disabled at 0, error + retry, denied state · model parsing.

## 10–12. Validation

`flutter test` → **903 passed** (883 + 20) · `flutter analyze` → **0 errors, 0 warnings** (75 pre-existing info lints) · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built**. Device/Chrome: not run.

## 11. Known limitations

- No realtime: badge and list refresh on hub load/refresh and on return from the inbox (same model as G8 chat).
- Group-scoped inbox only (`/groups/:id/notifications`); no cross-group inbox screen in this phase (the same repository can serve one — rows are per user).
- Chat unread (`message_reads` / `fn_get_group_unread_counts`) is a separate live system; the hub badge counts **notifications**, not unread chat messages. `fn_mark_group_read` is not called by the Flutter chat yet (pre-existing).
- System timeline messages (joined/left/role changed) also produce `GROUP_MESSAGE` notifications — live behaviour, not changed.
- A removed member's old rows remain in their inbox under the live own-row policy; the group screen denies them, a cross-group inbox would show them.
- `notification_settings` (per-category switches, quiet hours) are enforced server-side but have no Flutter UI yet; only the per-group mute is exposed here.
- `mark own read` allows editing any column of one's own rows (harmless, noted).

## 13. Notification infrastructure reused (summary)

`notifications` · `group_mutes` · `fn_notify_group` + 4 triggers · `fn_is_notification_allowed` · `notification_settings` — zero new tables, functions, enums, policies or counters.

## 14. Commit

`3c30c72` — G16 implementation (this report included); hash recorded in the follow-up commit.

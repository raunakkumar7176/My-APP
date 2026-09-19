# G8 — Group Chat: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `ce577fd` (G7 verification) · **Commit:** `4299fe8` · **Date:** 2026-09-19

## FINAL STATUS

**G8 IMPLEMENTATION COMPLETE — BACKEND PENDING**

Flutter, fakes, tests, pre/post-check SQL and a *conditional* migration are delivered and verified locally (analyze 0 errors / 0 warnings, 763/763 tests, debug APK built). The backend is **reused, not created**: `public.group_messages` with member-read / send-as-yourself policies has been in the migration set since `0001_init`. Whether it is live as described has not been proven from this environment. **BACKEND MIGRATION: NOT APPLIED LIVE** — and it must only be applied if the pre-check shows the table absent. No live or device end-to-end evidence is claimed.

---

## 1. Live-schema audit (repository + legacy migration set)

Flutter before G8: no chat model, method, state, widget, route, test or realtime code anywhere (`grep .channel(|.stream(|RealtimeChannel lib/` → none). The hub already renders announcements (G7) and rules (G6) from the single `GroupHubController`.

Legacy SQL (`My-Prepration/supabase/migrations/`, evidence class **[LEGACY-SQL]**):

| Migration | Chat-relevant content |
|---|---|
| `0001_init` | **`group_messages(id uuid PK, group_id → groups cascade, sender_id → profiles NOT NULL, body 1..2000, created_at)`**; index `(group_id, created_at desc)`; RLS; policies `member reads messages` (SELECT `fn_is_member`) and `member sends messages` (INSERT `sender_id = auth.uid() AND fn_is_member`); `message_reads(group_id,user_id,last_read_at)` with own-row policy |
| `0008` | `fn_latest_group_messages(uuid[])` (hub previews) |
| `0010` / `0033` | more indexes: `(group_id, created_at desc, id desc)`, `(group_id, sender_id, created_at desc)` |
| `0021` / `0035` | `trg_group_message_notify` AFTER INSERT → `fn_notify_group(...)` (notifications rows for other members) |
| `0025` / `0033` | soft delete: `deleted_at`, `deleted_by`; `fn_delete_group_message(uuid)` (own message, else MANAGE_MEMBERS); **intentionally no UPDATE/DELETE policy** |
| `0020` / `0025` / `0034` / `0037` | realtime publication `supabase_realtime` includes `group_messages`; replica identity full |
| `0027` | `fn_mark_group_read`, unread counts |
| `0038` | `message_type text default 'text' CHECK (text/system/announcement/test/activity)`, `metadata jsonb`, indexes |
| `0039` / `0047` | `fn_insert_system_message` (system notices), `fn_clear_group_chat` (owner / MANAGE_MEMBERS); **`sender_id` NOT NULL dropped** so notices can have no sender |

## 2. Existing infrastructure found / 3. Reuse decision

**REUSED:** `public.group_messages` (table, both policies, indexes, grants), `fn_is_member`. Nothing is created unless the pre-check proves the table absent. No duplicate table, no chat permission (chat is membership-gated, as the live policy already says), no membership architecture.

**NOT used (out of G8 scope, left intact):** soft delete RPC, clear-chat RPC, read tracking, previews, notification triggers, realtime publication, `message_type`/`metadata`.

Client contract = base columns only: `id, group_id, sender_id (nullable), body, created_at`. The client never names `message_type / metadata / deleted_at / deleted_by`, so it reads and inserts correctly whether or not 0025/0038 reached live.

## 4. Database changes

None required if the table is live. `migrations/G8_GROUP_CHAT.sql` is **conditional** (run only on `table_exists=false`): minimal `0001_init`-equivalent — base columns (sender nullable with `ON DELETE SET NULL`, body CHECK 1..2000), index `(group_id, created_at DESC, id DESC)`, RLS, the same two policies (`TO authenticated`), `REVOKE … FROM PUBLIC, anon`, `GRANT SELECT, INSERT` to authenticated, full grant to service_role, `NOTIFY pgrst`, read-only postflight. No DO / dynamic SQL, no trigger, no SECURITY DEFINER.

- `docs/G8_GROUP_CHAT_PRECHECK.sql` (4 read-only statements): existence + `fn_is_member` (arity, DEFINER) + realtime publication membership (informational); column list; policy texts; grants / FKs / body CHECK / `(group_id, created_at)` index / triggers / indexes.
- `docs/G8_GROUP_CHAT_POSTCHECK.sql` (4 read-only statements): structure + grants + "no broad UPDATE/DELETE policy"; enforcement flags (read gated by membership, insert pins `sender_id = auth.uid()`, insert gated by membership, no anon policy); every function whose body mentions the table with a `writes_table` flag; base column shape.

## 5. RLS / security model

- READ: `fn_is_member(group_id, auth.uid())` — a member sees only their group's rows; the client additionally filters `eq('group_id')` and never reads across groups.
- WRITE: INSERT requires `sender_id = auth.uid() AND fn_is_member(group_id, auth.uid())`. The repository API has **no sender parameter** — impersonation cannot even be expressed by the client; the repository sets `sender_id` to the signed-in uid and refuses without a session (`AuthError`). A forged `group_id` fails membership on the server.
- No UPDATE/DELETE from the client (no policy, nothing implemented) — messages are immutable in G8.
- anon: no grant / no `TO anon` policy in legacy (0001's policies were created without `TO`, i.e. role `public`; with anon holding no table grant that is inert — the post-check flags the combination if it ever changes).
- No recursion (policies call only the DEFINER `fn_is_member`); no new SECURITY DEFINER; no service-role key; `rpcShape` logs shape only (never message text).
- Removed member: next refresh returns nothing and send is refused (membership re-evaluated server-side on every call; the client caches no authorization).

## 6. Flutter changes

| File | Change |
|---|---|
| `lib/core/models/group_message.dart` | **new** — `GroupMessage{id, groupId, senderId?, body, createdAt}`, `isSystem`, `maxBodyLength = 2000`, `fromJson`/`toJson`/`==` |
| `lib/features/group/domain/group_errors.dart` | additive `GroupErrorContext.chat` + two messages |
| `lib/features/group/data/group_repository.dart` | interface + impl: `messages(groupId, {limit = messagePageSize (50), before})` — exact `group_id`, `created_at DESC, id DESC`, `limit`, optional `lt(created_at)` page; `sendMessage({groupId, body})` — inserts `{group_id, sender_id: uid, body}`; `const messagePageSize = 50` |
| `lib/features/group/state/group_hub_controller.dart` | chat state (`messages` oldest→newest, `messagesLoading`, `olderMessagesLoading`, `messagesError`, `sending`, `hasOlderMessages`, `hasMessages`), `messageSenderLabel` (You / roster name / System / Former member — from the roster already loaded, no profile query), `_loadMessages()` in `load()` for every member (failure never blocks the hub), `refreshMessages()` (single-flight), `loadOlderMessages()` (single-flight, dedup by id, keeps window on failure), static `validateMessage`, `sendMessage()` (single-flight, trim, 1..2000, re-read after success **and** failure — no optimistic row) |
| `lib/features/group/widgets/group_chat_section.dart` | **new** — `StatefulWidget` (owns and disposes the input controller); keys `group_chat_section, messages_count, messages_refresh, messages_loading, messages_error, messages_retry, messages_empty, messages_load_older, messages_action_error, message_<id>, message_sender_<id>, message_field, send_message_button`; bubbles right-aligned for own messages, centered for system notices; field disabled and spinner while sending; field cleared only after server success |
| `lib/features/group/screens/group_hub_screen.dart` | `GroupChatSection(controller: _c)` after the rules section |
| `test/group/fakes.dart` | `FakeGroup.messages`; `seedMessage`; `messages` gated on membership, newest-first with `before`/`limit`; `sendMessage` → `insertMessageAs(senderId: currentUser)`; `insertMessageAs` mirrors the INSERT policy (`sender == currentUser AND member`, CHECK 1..2000) so forged senders can be tested |
| `test/group/group_core_test.dart` | `_FailingRepository` gains two stubs; one hub widget test gets a tall viewport (the leave button now sits below three sections in the lazy ListView) — minimal additive |
| `test/group/group_chat_test.dart` | **new** — 23 tests |

No route added (chat is a hub section). No second data layer.

## 7. Chat behaviour

Open hub → latest 50 messages load (oldest→newest) with sender, text, timestamp; "Load earlier messages" appears only when a full page came back; refresh icon and pull-to-refresh re-read the window; type → Send (button or keyboard action) → trim → reject empty / >2000 without a server call → single in-flight send (field + button disabled, spinner) → server confirms → window re-read from the server → field cleared → new message appears last. Failure: snackbar with the mapped error, field content kept, window re-read anyway. States: loading, loaded, empty ("No messages yet. Say hello!"), error + Retry, older-page loading, inline action error.

## 8. Realtime status

**Not implemented.** The app has no Supabase Realtime usage anywhere; adding a channel subscription would introduce new architecture (auth-aware channel lifecycle, reconnection, dispose handling) for the first time. The legacy publication reportedly includes `group_messages` (pre-check records it), so a later phase can add it safely. G8 baseline: server-backed chat with controlled refresh (after send, refresh icon, pull-to-refresh). Nothing fakes realtime.

## 9. Tests (`flutter test test/group/group_chat_test.dart` → 23 passed)

| # | Spec item | Test(s) |
|---|---|---|
| 1 | Model parsing | `fromJson maps the five base columns; sender nullable`; `validation mirrors the live CHECK` |
| 2 | List loading | `member reads own group window, oldest → newest, no other group`; `window is finite: newest page only, older on demand, deterministic` |
| 3 | Empty | `empty chat`; widget `empty state` |
| 4 | Error / retry | `load error surfaces messagesError; retry recovers`; widget `error + retry` |
| 5 | Member reads own chat | test 2 + widget `member: list, senders, field and send button` |
| 6 | Member sends | `member sends → trimmed, sender = caller, window re-read`; `owner sends too` |
| 7 | Empty rejected | `empty / whitespace / too long rejected before any server call`; widget `empty send is rejected without a server call` |
| 8 | Single-flight | `second send while first in flight is dropped`; `refresh and older-page are single-flight` |
| 9 | Sender handling | `sender labels: System / display name / You / Former member`; sender asserted = caller in 6 |
| 10 | Cross-group denied | `member of g-1 forging group_id g-2 is refused`; `non-member reads nothing and cannot send` |
| 11 | Forged sender | `forged sender_id is refused by the (fake) policy` (+ API has no sender parameter) |
| 12 | Removed member | `removed member loses read and send` |
| 13 | Refresh after send | asserted in 6 (`messages:g-1` called twice) and `server rejection is mapped and the window is re-read`; widget `type → send → field cleared → message appears` |
| 14 | Hub regression | widget asserts announcements, rules, roster heading and leave button still render; `section uses the hub controller, not a second source`; full suite below |

## 10. `flutter analyze`

`68 issues found` — **0 errors, 0 warnings** (the 68 pre-existing `info` lints, unchanged set).

## 11. `flutter test` / APK

- `flutter test`: **763 passed, 0 failed** (740 after G7 + 23 G8).
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`: **√ Built build\app\outputs\flutter-apk\app-debug.apk** (exit 0).

## 12. Backend live status

**BACKEND MIGRATION: NOT APPLIED LIVE.** Owner steps:

1. SQL Editor → `docs/G8_GROUP_CHAT_PRECHECK.sql` → paste all four grids.
2. `table_exists=true` → do **not** run the migration; `false` → run `migrations/G8_GROUP_CHAT.sql`, paste its postflight.
3. `docs/G8_GROUP_CHAT_POSTCHECK.sql` → paste all four grids.
4. Device (Moto G31, `adb logcat` for `group_messages.select response shape`) or Chrome: two members exchange messages; a non-member cannot open the hub; a removed member's refresh returns nothing.
5. Request the G8 verification pass.

## 13. Known limitations

- **Soft-deleted messages** (0025 `deleted_at`) are not filtered by the client because the column is not selected (it may not exist live); if the pre-check shows the column, a one-line follow-up (`is('deleted_at', null)`) hides them.
- **System notices** (`sender_id NULL` or `message_type='system'`) render as centered text when the sender is null; notices inserted with an actor's `sender_id` (0038 era) render as that member's message.
- No realtime (see §8); no delete/clear/read-receipt/unread UI (legacy RPCs untouched).
- Pagination uses `created_at <` of the oldest loaded row; two messages with an identical timestamp across a page boundary could be skipped (mitigated by the secondary `id DESC` order within a page).
- Legacy INSERT fires the notification trigger server-side; the client does not surface it.
- Untracked files not part of G8 and not committed: `docs/G5_8_FINAL_LIFECYCLE_HARDENING_REPORT.md`, and `node_modules/`, `package.json`, `package-lock.json` (created by another tool in the project root during this session; not referenced by the Flutter build).

## 14. Commit

`4299fe8` on `r4-restart` (recorded by the follow-up report commit).

**FINAL STATUS: G8 IMPLEMENTATION COMPLETE — BACKEND PENDING**

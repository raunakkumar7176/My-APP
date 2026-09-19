# G7 — Group Announcements: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `0fe0139` (G6 report) · **Commit:** `ee3392e` · **Date:** 2026-09-19

## FINAL STATUS

**G7 IMPLEMENTATION COMPLETE — BACKEND PENDING**

Flutter, fakes, tests, pre/post-check SQL and a *conditional* migration are delivered and verified locally (analyze 0 errors / 0 warnings, 740/740 tests, debug APK built). The backend is **reused, not created**: the migration set that built the live database already defines `public.group_announcements` with the SEND_ANNOUNCEMENT-or-owner policies G7 needs. Whether that table is live as described has not been proven from this environment (no live DB access). **BACKEND MIGRATION: NOT APPLIED LIVE** — and it must only be applied if the pre-check shows the table absent. Nothing below claims live or device end-to-end evidence.

---

## 1. Live-schema audit (repository + legacy migration set)

Repository search (`announcement`, `group_messages`, `notification`, `SEND_ANNOUNCEMENT`): before G7 the Flutter app had **no** announcement model, repository method, controller state, widget, route or test — only the `SEND_ANNOUNCEMENT` enum label in `GroupPermission` and a doc comment in the hub. No G-phase touched announcements.

Legacy SQL (`My-Prepration/supabase/migrations/`, evidence class **[LEGACY-SQL]**; no live grid exists yet):

| Migration | What it defines for announcements |
|---|---|
| `0001_init` | `notif_category` includes `GROUP_ANNOUNCEMENT`; `notifications`, `group_messages` (chat, member-insert) — not announcements |
| `0020_group_features` | **`public.group_announcements(id, group_id → groups, author_id → profiles, title 1..120, body 1..2000, pinned, created_at, updated_at)`**; RLS; policies `members read announcements` (SELECT, `fn_is_member`), `leaders create announcements` (INSERT, `SEND_ANNOUNCEMENT` OR owner), `leaders manage announcements` (FOR ALL, same, USING+CHECK); grants authenticated/service_role; `trg_touch_announcement` |
| `0021` / `0035` | `trg_group_announcement_notify` AFTER INSERT → `fn_notify_group(...)` writes `notifications` rows for members (respects mutes/settings) |
| `0033_groups_comprehensive_repair` | re-creates the same table + policies idempotently (`if not exists`, `drop policy if exists`) |
| `0037` | replica identity full + realtime publication |
| `0038` / `0040_group_announcements_pro` | adds `category, priority, status(draft\|published\|archived\|scheduled\|expired), is_pinned, publish_at, expires_at, attachment_*, link_*`; SELECT policy narrowed to `fn_is_member AND status='published' AND publish_at<=now() AND (expires_at IS NULL OR expires_at>now())`; manage/create policies re-stated with `'owner'::group_role`; `group_announcement_reads` table + `fn_mark_announcement_read`, `fn_announcement_seen_count`; `trg_touch_announcement_pro` |
| `0039` | `trg_announcement_chat_pin` AFTER INSERT → system message in `group_messages` |
| `0047` / `0048` | `trg_set_announcement_expiry` BEFORE INSERT (30/90-day `expires_at`), `fn_archive_expired_announcements` run by the sweep cron |

Conclusion of STEP 0: suitable infrastructure exists in the migration set → **REUSE**; no duplicate table, function, policy or permission is created. `SEND_ANNOUNCEMENT` is live in `app_permission` and seeded for **leader** (G3 live audit, [LIVE]); the owner passes via `fn_has_permission`'s owner branch and the explicit `fn_get_group_role = 'owner'` term.

## 2. Existing infrastructure reused

- Table `public.group_announcements` — the client selects and writes only the **base columns present since 0020**: `id, group_id, author_id, title, body, created_at, updated_at`. It never names `category / priority / status / is_pinned / publish_at / expires_at`, so it reads and inserts correctly whether or not 0040/0047 reached live (defaults fill them when they exist).
- Policies as listed above (member SELECT; SEND_ANNOUNCEMENT-or-owner INSERT and FOR ALL manage).
- Functions `fn_is_member`, `fn_has_permission`, `fn_get_group_role` (SECURITY DEFINER, `search_path=''`, [LIVE]).
- Flutter: the existing `GroupRepository`, `GroupHubController`, `GroupHubScreen`, `InMemoryGroupRepository`, `GroupErrors`.

## 3. Final design

- **Model:** `GroupAnnouncement{id, groupId, authorId, title, body, createdAt, updatedAt}`; `wasEdited = updatedAt > createdAt`; constants `maxTitleLength=120`, `maxBodyLength=2000` mirroring the live CHECKs.
- **Ordering:** newest first (`created_at DESC`), matching the legacy index and the chat-style convention.
- **Author information:** resolved **client-side from the roster the hub already loaded** (`announcementAuthorLabel` → "You" / member display name / null when the author is no longer a member). No extra `profiles` read and no embed, so an unreadable profile can never fail the announcement query; when unknown, nothing is shown rather than a guess.
- **Edit / delete:** implemented, because the legacy `leaders manage announcements` (FOR ALL) policy already grants UPDATE/DELETE to any SEND_ANNOUNCEMENT holder or the owner (not author-only). The client follows that exactly.
- **Server side effects are left as they are:** an INSERT may fire the legacy notify / chat-pin / expiry triggers. G7 builds no notification delivery.

## 4. Migration — `migrations/G7_GROUP_ANNOUNCEMENTS.sql` (CONDITIONAL, not executed)

Run **only** when `docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql` statement 1 reports `table_exists = false`. It creates the minimal 0020-equivalent: base columns with FK to `groups` (cascade) and `profiles`, CHECKs (title 1..120, body 1..2000), index `(group_id, created_at DESC)`, RLS, four policies (SELECT `fn_is_member`; INSERT `author_id = auth.uid() AND (SEND_ANNOUNCEMENT OR owner)`; UPDATE same on USING+CHECK; DELETE same), `REVOKE … FROM PUBLIC, anon`, grants to `authenticated, service_role`, `updated_at` trigger fn with `SET search_path TO ''`, `NOTIFY pgrst`, read-only postflight. Plain `$$`, no DO / dynamic SQL, prose only in comments. If the table is live, **nothing is run** — existing RLS is never modified (the file's `CREATE POLICY` statements would otherwise fail on the legacy names by design).

**Pre-check** (`docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql`, 4 read-only statements): existence + dependencies (`fn_is_member/fn_has_permission/fn_get_group_role` arity + SECURITY DEFINER count = 3, `SEND_ANNOUNCEMENT` enum label), the 7 base columns, the policy texts, grants/FKs/CHECKs/triggers/indexes.
**Post-check** (`docs/G7_GROUP_ANNOUNCEMENTS_POSTCHECK.sql`, 4 read-only statements): table/RLS/policy coverage per command/FK/CHECK/grants/index; permission-enforcement grid (every write policy references `SEND_ANNOUNCEMENT` + `fn_get_group_role`, SELECT references `fn_is_member`, all policies `authenticated` only, none for anon/public); every function whose body mentions the table with a `writes_table` flag (cross-group write review); base column shape.

## 5. RLS / security

- Server-authoritative: the table policies are the boundary; the controller's `canSendAnnouncement` is UX only and is bypassed in tests to prove the (fake) policy still refuses.
- Non-member: no rows (SELECT gated by `fn_is_member`); mutations refused.
- Member / moderator: read only. Leader / SEND_ANNOUNCEMENT grantee / owner: create, edit, delete.
- Forged cross-group id: UPDATE/DELETE `USING` evaluates the existing row's `group_id` → 0 rows → the client reports "could not be updated/deleted. It may have been removed." (no existence oracle).
- `author_id` is sent as the caller's uid (NOT NULL, FK → profiles). Legacy INSERT policy does not pin `author_id = auth.uid()`; the conditional migration does. Recorded as a known limitation of the legacy policy (see §13).
- No new permission, no enum change, no `role_permissions` change, no modification of any existing policy/grant/function/trigger. No SECURITY DEFINER added. No service-role key; anon key never printed; `correct_option` / `public.questions` untouched (grep-verified).

## 6. Permission model

| Actor | Read | Create | Edit / Delete (any author) |
|---|---|---|---|
| Non-member | — | — | — |
| member, moderator | ✓ | — | — |
| leader (seeded SEND_ANNOUNCEMENT) | ✓ | ✓ | ✓ |
| role with explicit `role_permissions(SEND_ANNOUNCEMENT)` | ✓ | ✓ | ✓ |
| owner (function bypass / `fn_get_group_role='owner'`) | ✓ | ✓ | ✓ |

Flutter mirror: `GroupHubController.canSendAnnouncement = permissions.has(sendAnnouncement) || isOwner`; the probe list in `load()` gained `GroupPermission.sendAnnouncement` (one more `fn_has_permission` call, additive).

## 7. Flutter files

| File | Change |
|---|---|
| `lib/core/models/group_announcement.dart` | **new** — model, `fromJson`/`toJson`/`copyWith`/`==`, `wasEdited`, length constants |
| `lib/features/group/domain/group_errors.dart` | additive `GroupErrorContext.announcement` + two messages |
| `lib/features/group/data/group_repository.dart` | interface + `SupabaseGroupRepository`: `announcements(groupId)`, `createAnnouncement`, `updateAnnouncement` (0 rows ⇒ error), `deleteAnnouncement` (0 rows ⇒ error); `_announcementColumns`; `rpcShape` log (shape only) |
| `lib/features/group/state/group_hub_controller.dart` | `canSendAnnouncement`; announcements state (`announcements, announcementsLoading, announcementsError, actingAnnouncementId, announcementSaving, hasAnnouncements`), `announcementAuthorLabel`, `_loadAnnouncements()` in `load()` for every member, `retryAnnouncements()`, static `validateAnnouncement`, `_announcementMutationAllowed()`, `_runAnnouncementMutation()` (single-flight, re-read after success **and** failure, mapped errors), `createAnnouncement / updateAnnouncement / deleteAnnouncement` |
| `lib/features/group/widgets/group_announcements_section.dart` | **new** — keys `group_announcements_section, announcements_count, add_announcement_button, announcements_loading, announcements_error, announcements_retry, announcements_empty, announcements_action_error, announcement_<id>, announcement_meta_<id>, edit_announcement_<id>, delete_announcement_<id>, announcement_title_field, announcement_body_field, confirm_post_announcement, confirm_edit_announcement, confirm_delete_announcement` |
| `lib/features/group/screens/group_hub_screen.dart` | `GroupAnnouncementsSection(controller: _c)` above the rules section |
| `test/group/fakes.dart` | `FakeGroup.announcements`; read gated on membership; create/update/delete gated on `hasPermission(sendAnnouncement)` (owner ✓, leader ✓ by seeding, moderator/member ✗, `roleGrants` honoured); CHECKs mirrored; non-writable rows not matched |
| `test/group/group_core_test.dart` | `_FailingRepository` gains the four stubs (compile only) |
| `test/group/group_roles_test.dart`, `test/group/group_members_test.dart` | tall test viewport for two hub widget tests (the lazy `ListView` now has two more sections above the roster) — minimal additive dependency, no behaviour change |
| `test/group/group_announcements_test.dart` | **new** — 26 tests |

## 8. Functional behaviour

Member view: list newest-first with title, body, `author · timestamp[ · edited]`, loading bar, "No announcements yet.", error + Retry, access-denied handled by the hub (non-member never reaches the section). Manager view: Post button → dialog (title ≤120, body ≤2000, `maxLength` counters) → trim → reject empty → single submit (button disabled while saving) → server re-read; Edit → same dialog pre-filled; Delete → confirmation → in-flight spinner + disabled controls → re-read. Errors are shown in a snackbar and kept in `controller.error`.

## 9. Tests (`flutter test test/group/group_announcements_test.dart` → 26 passed)

| # | Spec item | Test(s) |
|---|---|---|
| 1 | Model parsing | `fromJson maps the base columns; updated_at falls back`; `validation mirrors the live CHECKs` |
| 2 | List loading | `member reads only this group, newest first`; `author label comes from the roster; "You" for own posts` |
| 3 | Empty | `empty state: loaded, no error, no rows`; widget `empty state for member` |
| 4 | Error / retry | `load error surfaces announcementsError; retry recovers`; widget `error + retry` |
| 5 | Member read-only | widget `member: read-only — list shown, no controls`; `moderator (no SEND_ANNOUNCEMENT): read-only` |
| 6 | Authorized create | `u-owner` / `u-lead: create → trimmed, author = caller…`; `explicit SEND_ANNOUNCEMENT grant for a moderator role works`; `leader edits another author's announcement`; `owner deletes → row gone` |
| 7 | Unauthorized create | `u-me` / `u-mod: controller refuses and server refuses; nothing changes` (also bypasses the UI guard) |
| 8 | Cross-group | `owner of g-1 cannot touch a forged id from g-2`; `non-member gets no rows`; `server rejection is mapped and the list is re-read` |
| 9 | Input validation | `create/update reject empty title or body before any server call`; widget `leader: empty post is rejected without a server call` |
| 10 | Single-flight | `second create while first in flight is dropped`; `delete twice on the same announcement runs once` |
| 11 | Refresh after mutation | asserted in 6 and in widget `leader: post → edit → delete with confirmation, list refreshes` |
| 12 | Hub regression | read-only widget test asserts rules section, roster heading and leave button still render; `section uses the hub controller, not a second source`; full suite below |

## 10. `flutter analyze`

`68 issues found` — **0 errors, 0 warnings**; all 68 are the pre-existing `info` lints (unchanged set).

## 11. `flutter test` / APK

- `flutter test`: **740 passed, 0 failed** (714 after G6 + 26 G7).
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`: **√ Built build\app\outputs\flutter-apk\app-debug.apk** (exit 0).

## 12. Backend live status

**BACKEND MIGRATION: NOT APPLIED LIVE.** No live grid for `group_announcements` exists in this repository; the design rests on [LEGACY-SQL] plus the [LIVE] facts of G3. Owner steps:

1. SQL Editor → `docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql` → paste all four grids.
2. If statement 1 shows `table_exists=true`: **do not run the migration.** If `false`: run `migrations/G7_GROUP_ANNOUNCEMENTS.sql`, paste its postflight.
3. `docs/G7_GROUP_ANNOUNCEMENTS_POSTCHECK.sql` → paste all four grids.
4. Device (Moto G31, `adb logcat` for `group_announcements.select` rpcShape lines) or Chrome: owner/leader posts, edits, deletes; plain member sees the list without controls.
5. Request the G7 verification pass; only then does the status change.

## 13. Known limitations

- If the live table carries the 0040 columns, members only see `status='published'`, `publish_at <= now()`, non-expired rows, and 0047's trigger sets `expires_at` to 30 days (90 for pinned/important) → announcements disappear from members after that window and are archived by the sweep. The client never filters; this is the live product rule, recorded here so the verifier does not read it as a bug.
- Legacy INSERT policy does not force `author_id = auth.uid()`; the client always sends its own uid, and the conditional migration adds that check for a fresh table. Hardening the legacy policy is a separate, owner-decided migration (not G7: existing RLS is not modified).
- Author label is null for authors who left the group (no profile read is attempted).
- No realtime subscription, no read receipts, no pinning/category/priority UI, no push — out of scope by instruction.
- The untracked `docs/G5_8_FINAL_LIFECYCLE_HARDENING_REPORT.md` (another agent's file) is again **not** included.

## 14. Commit

`ee3392e` on `r4-restart` (the hash is recorded by the follow-up report commit).

**FINAL STATUS: G7 IMPLEMENTATION COMPLETE — BACKEND PENDING**

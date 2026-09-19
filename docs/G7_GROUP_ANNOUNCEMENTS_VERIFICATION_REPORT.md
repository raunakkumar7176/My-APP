# G7 — Group Announcements: Verification Report (auditor)

**Audited commit:** `09de9e1` (implementation `ee3392e`, report-hash follow-up) on `r4-restart` · **Audit date:** 2026-09-19 · **Auditor environment:** repository + Flutter toolchain only; **no live Supabase access** (no SQL can be executed from here; the anon key is the only credential in the tree).

## Final status

**G7 VERIFIED — PASS WITH NON-BLOCKING WARNINGS**

| Layer | Verdict |
|---|---|
| CODE PRESENT | **YES** — committed at `ee3392e`, working tree clean |
| CODE VERIFIED | **YES** — analyze 0/0, 740/740 tests, APK built, code review below |
| DATABASE PRESENT | **NOT VERIFIED** — `public.group_announcements` is defined by the legacy migration set (0020/0033/0040/0047) but no live grid has been pasted |
| DATABASE SECURITY VERIFIED | **NOT VERIFIED** — policy texts known only from [LEGACY-SQL] |
| END-TO-END VERIFIED | **NO** — no device/Chrome run against the live table |

**G7 CODE VERIFIED · G7 BACKEND PENDING.** Nothing here claims the live table, its policies or its grants exist as described; the owner steps in §11 produce that evidence.

---

## 1. Repository evidence

`git show --stat ee3392e`: 15 files, +1784/−1 — `migrations/G7_GROUP_ANNOUNCEMENTS.sql` (122), `docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql` (85), `docs/G7_GROUP_ANNOUNCEMENTS_POSTCHECK.sql` (94), `docs/G7_GROUP_ANNOUNCEMENTS_IMPLEMENTATION_REPORT.md` (142), `lib/core/models/group_announcement.dart` (86), `lib/features/group/widgets/group_announcements_section.dart` (264), `test/group/group_announcements_test.dart` (553), plus additive edits to `group_repository.dart` (+102), `group_hub_controller.dart` (+190), `group_errors.dart` (+5), `group_hub_screen.dart` (+6/−1), `test/group/fakes.dart` (+108), `group_core_test.dart` (+18), `group_members_test.dart` (+5), `group_roles_test.dart` (+5). All present on disk at HEAD; `git status` shows only the pre-existing untracked `docs/G5_8_FINAL_LIFECYCLE_HARDENING_REPORT.md`. No route was added (none needed: the section lives in the hub).

## 2. Live DB evidence

None available from this environment. What the audit could establish:

- **[LIVE] (G3 audit, closed):** `app_permission` contains `SEND_ANNOUNCEMENT`; `role_permissions` seeds it for **leader** only; `fn_has_permission(uuid,uuid,app_permission)`, `fn_is_member(uuid,uuid)`, `fn_get_group_role(uuid,uuid)` are SECURITY DEFINER with `search_path=''`, STABLE; owner bypass is inside `fn_has_permission`.
- **[LEGACY-SQL]:** `public.group_announcements` created in `0020_group_features.sql`, re-created idempotently in `0033_groups_comprehensive_repair.sql`, extended in `0038/0040` (category, priority, status, is_pinned, publish_at, expires_at, attachments, links; SELECT policy narrowed to published/unexpired), triggers added in `0021/0035` (notify), `0039` (chat pin), `0047` (expiry), archival wired into the sweep in `0048`. Policies: `members read announcements` (SELECT, `fn_is_member`), `leaders create announcements` (INSERT, `SEND_ANNOUNCEMENT` OR owner), `leaders manage announcements` (FOR ALL, same expression on USING and WITH CHECK). Grants: `authenticated, service_role`.
- The builder's pre-check (`docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql`) is read-only and, when run, proves or refutes every one of these points (existence, RLS flag, the 7 base columns, policy texts, grants, FKs, CHECKs, triggers, indexes, definer count = 3, enum label). Reviewed: it uses `to_regclass` so it does not error if the table is absent. ✓

## 3. Schema verification (of what the client depends on)

Client contract = base columns only: `id uuid PK`, `group_id uuid NOT NULL → groups`, `author_id uuid NOT NULL → profiles`, `title text NOT NULL CHECK 1..120`, `body text NOT NULL CHECK 1..2000`, `created_at`, `updated_at`. Present identically in 0020 and the 0033 repair; 0040 only adds columns with defaults. The repository never names any 0040/0047 column, so a partially-migrated live table still reads and inserts. ✓ Group scoping: `group_id` NOT NULL with FK; reads filter `eq('group_id')`; update/delete never touch `group_id`, so a row cannot be re-pointed. ✓ Conditional migration (for the absent-table case only): same base shape, index `(group_id, created_at DESC)`, no extra infrastructure. ✓

## 4. RLS / security verification

Evaluated on the legacy policy text + the client:

- READ member ✓ (`fn_is_member`); non-member ✗ ✓. No `privacy='public'` branch — private announcements never leak.
- WRITE: INSERT/UPDATE/DELETE require `SEND_ANNOUNCEMENT` OR owner; UPDATE has USING + WITH CHECK (FOR ALL policy) so cross-group re-pointing is refused; DELETE/UPDATE of a foreign id → USING fails on the existing row → 0 rows → client reports "may have been removed" (no existence oracle). ✓
- anon: no grant in 0020/0033 (grants only to `authenticated, service_role`); all policies `TO authenticated`. ✓ (live confirmation pending)
- Recursion: policies call only the three DEFINER functions; none reads `group_announcements`. ✓
- SECURITY DEFINER: G7 adds none. Legacy trigger functions (`trg_notify_group_announcement`, `trg_announcement_chat_pin`, `fn_set_announcement_expiry`, `fn_mark_announcement_read`) are DEFINER with `search_path = public` (not `''`) — pre-existing, not G7 objects (**W1**). The conditional migration's `fn_touch_group_announcement_updated_at` is not DEFINER and pins `search_path TO ''`. ✓
- `auth.uid()`: repository refuses to insert without a session (`AuthError`); `author_id` is always the caller's uid. The **legacy INSERT policy does not enforce `author_id = auth.uid()`** — a SEND_ANNOUNCEMENT holder with a crafted client could attribute a post to another member (**W2**, legacy object, not modifiable by G7). The conditional migration adds that check for a fresh table. ✓
- Flutter: no service-role key (`grep service_role lib/` → none); anon key never printed; `AppLogger.rpcShape` logs runtime type / length / sorted keys only (verified in `app_logger.dart:36-53`), no announcement text. ✓ No `public.questions` read, no `correct_option`. ✓

## 5. Permission verification

Existing engine only: `GroupPermission.sendAnnouncement` (pre-existing enum mirror) is added to the hub's `permissionsFor(of:)` probe list; `canSendAnnouncement = has(sendAnnouncement) || isOwner`. No new permission, no enum change, no `role_permissions` change, no hardcoded role names in SQL or Dart gating (the only `isOwner` term mirrors the live policy's own `fn_get_group_role = 'owner'` clause and is UX-only). UI visibility is **not** the boundary: `_announcementMutationAllowed()` is a pre-check; tests bypass it and the fake policy still refuses (§7). ✓

## 6. Flutter verification

- **Model** (`group_announcement.dart`): exact snake_case mapping of the 7 columns, `updated_at` null-tolerant, timestamps `toLocal()`, `toJson` round-trip, `copyWith`, equality on (id, title, body, updatedAt), `wasEdited`. ✓
- **Repository**: single `GroupRepository` extended (no second repository); `announcements` = one query, exact `group_id`, `created_at DESC`; `create` = one insert; `update`/`delete` = exact `id`, `.select('id')`, 0 rows ⇒ error; all under `_guard` with the new `GroupErrorContext.announcement` (additive enum value + 2 messages). No N+1: author names come from the roster already in memory. ✓
- **Controller**: state isolated (`_announcements*`), `_loadAnnouncements()` runs inside `load()` for every member and its failure never blocks the hub (own try/catch); `retryAnnouncements`; static `validateAnnouncement` (trim; title 1..120; body 1..2000) mirrors the CHECKs; `_runAnnouncementMutation` sets `actingAnnouncementId`/`announcementSaving`, re-reads after success **and** failure, maps `AppError` and unknowns, resets in `finally`; global `_busy` also respected; `DisposableNotifier` makes post-dispose `notifyListeners` safe. ✓
- **Widget**: keys for every state (`announcements_loading/error/retry/empty/action_error`, per-row `announcement_<id>`, `edit_/delete_announcement_<id>`, dialog fields and confirm keys); manager controls gated on `canSendAnnouncement`; buttons disabled while saving/acting; delete confirmation; `context.mounted` checks after every await. ✓
- **Hub**: `GroupAnnouncementsSection(controller: _c)` shares the hub controller (asserted by test `section uses the hub controller, not a second source`). ✓
- Stale authorization: a revoked permission after load is still refused by the (fake) server — verified by an auditor-run ad-hoc test (§7 TEST K). ✓

## 7. Security attack results (evidence = executed tests against the fake that mirrors the legacy policies; **not** live)

| Test | Evidence | Result |
|---|---|---|
| A member reads own group | `member reads only this group, newest first` | allowed ✓ |
| B non-member reads another group | `non-member gets no rows (fn_is_member gate)` — `accessDenied`, `repo.announcements('g-2')` empty | denied ✓ |
| C member creates | `u-me: controller refuses and server refuses…` incl. direct `repo.createAnnouncement` → `DataError` | denied ✓ |
| D unauthorized edit | same test, `repo.updateAnnouncement(... 'a-old')` → `DataError`, rows unchanged | denied ✓ |
| E unauthorized delete | same test, `repo.deleteAnnouncement('a-old')` → `DataError` | denied ✓ |
| F SEND_ANNOUNCEMENT manager creates | `u-lead: create → trimmed, author = caller…`; `explicit SEND_ANNOUNCEMENT grant for a moderator role works` | allowed ✓ |
| G manager modifies only permitted group | `leader edits another author's announcement`; `owner deletes → row gone` (g-1 only) | allowed ✓ |
| H forged id from another group | `owner of g-1 cannot touch a forged id from g-2` — update/delete refused, g-2 row intact | denied ✓ |
| I forged group id in create | auditor ad-hoc test (run, passed, not committed): owner of g-1 → `createAnnouncement(groupId: 'g-2')` → `DataError`, g-2 unchanged; update never carries `group_id` | denied ✓ (**W3**: no committed test) |
| J anonymous access | repository throws `AuthError` without a session; legacy grants exclude anon — **live grant not verified** | denied at client; server pending |
| K privilege escalation via stale client flag | auditor ad-hoc test: leader demoted server-side after load → `canSendAnnouncement` still true, create refused by fake policy, nothing written | denied ✓ |

All 26 committed G7 tests pass (`flutter test test/group/group_announcements_test.dart` → `+26: All tests passed!`). They cover the important behaviour (read scoping, all three unauthorized mutations with UI-guard bypass, cross-group forgery, validation before any server call, single-flight for create and delete, refresh after mutation, widget gating for member and moderator, dialog flows, error/retry, hub regression) — not merely a count.

## 8. Test / build verification (run by the auditor at `09de9e1`)

- `flutter analyze` → `68 issues found` — **0 errors, 0 warnings** (68 pre-existing `info` lints, same set as before G7).
- `flutter test` → **`+740: All tests passed!`** (714 at G6 + 26 G7).
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **`√ Built build\app\outputs\flutter-apk\app-debug.apk`**.

## 9. Regression

Full suite green: G1 core (`group_core_test`), G2 settings (`group_settings_test`), G3 roles (`group_roles_test`), G4 members (`group_members_test`), G5.1 (`invite_code_test`), G5.2 (`pending_join_test`), G5.3 (`join_request_queue_test`), G5.4 (`incoming_invitations_test`), G5.5 (`outgoing_invitations_test`), G5.6 (`send_invitation_test`), G5.7 (withdraw tests inside `pending_join_test`), G6 (`group_rules_test`, 24), R4 (`test/r4_*`, `test/features/test/*`, `r4_restart/*`). Diff inspection: no R4 or G3 source file touched; G6 sources untouched (only the hub gained one section above the rules section). The only edits to earlier-phase files are two test-viewport enlargements (`group_roles_test.dart`, `group_members_test.dart`) and four interface stubs in `group_core_test.dart`'s `_FailingRepository` — mechanical consequences of the hub growing and the interface widening; no behaviour assertion changed. G6's backend remains separately pending and is not reopened.

## 10. Code quality

No duplicate repository/controller; one query per load; no unrestricted queries (every read is `eq('group_id')`, every write is by exact `id`); no private data logged; no swallowed exceptions (every catch records a message or logs); no dead code; async lifecycle safe. Warnings only (below).

## 11. Backend status and owner steps

**BACKEND MIGRATION: NOT APPLIED LIVE — and must only be applied if the pre-check shows the table absent.**

1. SQL Editor → `docs/G7_GROUP_ANNOUNCEMENTS_PRECHECK.sql` → paste the four grids.
2. `table_exists=true` → do **not** run the migration; `false` → run `migrations/G7_GROUP_ANNOUNCEMENTS.sql` and paste its postflight.
3. `docs/G7_GROUP_ANNOUNCEMENTS_POSTCHECK.sql` → paste the four grids (RLS, per-command policy coverage, permission-enforcement flags, definer functions that write the table, base columns).
4. Device (Moto G31, `adb logcat` for `group_announcements.select response shape`) or Chrome: owner/leader posts, edits, deletes; member sees the list without controls; non-member cannot open the hub.
5. Re-request this audit with the grids; only then can DATABASE / END-TO-END move to VERIFIED.

## 12. Non-blocking warnings

- **W1** Legacy announcement trigger functions (`trg_notify_group_announcement`, `trg_announcement_chat_pin`, `fn_set_announcement_expiry`, `fn_mark_announcement_read`, `fn_archive_expired_announcements`) are SECURITY DEFINER with `search_path = public`, not `''`. Pre-existing objects; G7 neither created nor changed them. Owner decision for a separate hardening migration.
- **W2** Legacy INSERT policy does not pin `author_id = auth.uid()`; the client always sends its own uid, and the conditional migration enforces it for a fresh table. Hardening the live policy would be a separate owner-approved migration (existing RLS is never modified by a phase).
- **W3** TEST I (forged `group_id` on create) is proven only by an auditor ad-hoc run; add it to `group_announcements_test.dart` when convenient.
- **W4** If the 0040 columns are live, SEND_ANNOUNCEMENT holders (FOR ALL policy) also read drafts/archived rows while members read only published, unexpired ones (30/90-day expiry set by 0047's trigger). The client shows whatever the server returns; managers may therefore see items members no longer see. Product behaviour of the live schema, recorded so it is not mistaken for a client bug.
- **W5** `TextEditingController`s created inside the compose dialog are not disposed (same pattern as the G6 rules dialogs). Negligible leak; fix together with G6 if desired.
- **W6** Legacy INSERT fires notification + chat-pin triggers server-side; the client does not surface those side effects. Expected; noted for the E2E run.

## 13. Known limitations

No live DB access from the audit environment; DATABASE and END-TO-END verification depend on the owner-run grids and a device/Chrome run.

## 14. Audited commit

`09de9e1` (G7 implementation `ee3392e`).

---

**G7 VERIFIED — PASS WITH NON-BLOCKING WARNINGS** (G7 CODE VERIFIED · G7 BACKEND PENDING)

**NEXT PHASE = G8 — GROUP CHAT** (do not start until the G7 backend grids are on record).

STOP.

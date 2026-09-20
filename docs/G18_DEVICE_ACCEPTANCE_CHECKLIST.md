# G18 — Group Hub Device Acceptance Checklist (66 items)

**Status: PENDING — not executed on a real Android device.** Every item below is unverified until a tester fills the PASS/FAIL column on a physical device. Nothing in this file may be marked PASS from automated tests, emulators or reports.

**Build:** debug APK from `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` at commit _(fill in)_ · **Backend:** live Supabase after `ec8f5a0` (all security/drift migrations applied) · **Runbook:** `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md`.

## Prerequisites (fill before starting)

| Item | Value |
|---|---|
| Owner account (O) | |
| Leader account (L) — promoted by O during D03 | |
| Moderator account (M) — promoted by O during D05 | |
| Member account (P) | |
| Non-member account (N) | |
| Device model / Android version | |
| APK commit hash | |
| Tester / date | |

Legend — **Sec** = security expectation (server-enforced; the UI hiding a control is not sufficient). Result column: PASS / FAIL / BLOCKED (with observation).

## A. Auth & entry

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| A01 | `/login` | App installed, signed out | Sign in with O's email/password | Lands on `/home`; no error | Wrong password is rejected by the server | | |
| A02 | Session | Signed in as O | Kill and reopen the app | Still signed in, `/home` shown without re-login | Session token is device-local; no credentials on screen | | |
| A03 | `/home` → Groups | Signed in | Open Groups | `/groups` lists O's groups (or empty state) | Only groups O owns/belongs to are listed (`rpc_get_user_groups`) | | |

## B. Group creation & discovery

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| B01 | `/groups/create` | O signed in | Create group "Device QA", privacy public | Redirect to the hub; header shows "1 member · Owner · Public" | Owner row created server-side by `fn_create_group` | | |
| B02 | `/groups/:id/settings` (O) | Group exists | Open settings, read the invite code, copy it | Code shown only here (never on hub/list) | Only GROUP_SETTINGS/owner can read `invite_code` | | |
| B03 | `/groups/join` (P) | P signed in on a second device/session, has the code | Join by invite code | P lands in the hub as Member; O's hub shows 2 members after refresh | Membership inserted by `fn_join_group` only | | |
| B04 | `/groups/join` (P) | — | Enter a wrong code | "does not match any group" message; no membership | `INVALID_INVITE_CODE` from the server | | |
| B05 | `/groups/:id` (N) | N is not a member; N knows the group id (deep link) | Open the hub URL as N | "Group not available" — no name, roster or content leaked | RLS: non-member gets no group/member rows | | |

## C. Invitations & join requests (F-06 now live)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| C01 | Hub → Invite (O) | O in hub; knows P2's student code | Look up P2 by student code and send | "Invitation sent"; row appears under Outgoing invitations | INSERT requires MANAGE_MEMBERS and `inviter_id = self` | | |
| C02 | `/groups` incoming card (P2) | Invitation pending | P2 opens Groups | Incoming invitation card shows the group; Accept / Decline enabled | Only P2 (invitee) sees it | | |
| C03 | Accept (P2) | C02 | Tap Accept once | Card disappears, group appears in P2's list, hub opens as Member | `fn_accept_group_invitation(p_invitation_id)`: invitee-only; status → accepted | | |
| C04 | Accept twice (P2) | Double-tap Accept quickly | Second tap ignored (single-flight); no error, one membership | Server rejects reuse (`INVITATION_NOT_PENDING`) | | |
| C05 | Stale invitation (P3) | O cancels the invitation after P3 loaded the card | P3 taps Accept | "This invitation is no longer available."; list refreshed; no membership | `INVITATION_NOT_FOUND` | | |
| C06 | Decline (P4) | Invitation pending | Tap Decline | Card disappears; no membership; O sees status "declined" and can re-invite | Invitee-only | | |
| C07 | Restricted join request (P5) | O sets privacy = restricted; P5 has the code | P5 joins by code | "Request sent" state; P5 cannot open the hub; O's hub shows the request in the queue | `fn_join_group` files a request instead of membership | | |
| C08 | Approve (O) | C07 | Approve the request | P5 becomes Member; queue empties; P5 can open the hub | `fn_approve_group_join_request` checks MANAGE_MEMBERS on that group | | |
| C09 | Decline (O) | Another pending request (P6) | Decline | Request marked declined; P6 still cannot enter; P6 can request again | same function | | |
| C10 | Withdraw (P7) | P7 has a pending request | Withdraw from the pending card | Request removed; card gone | `fn_withdraw_join_request`: own pending row only | | |

## D. Members, roles, permissions (G3/G4/G14)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| D01 | `/groups/:id/members` (O) | ≥3 members | Open Members; search by name; filter by role | List, search and chips work; counts match the hub | Roster readable by members only | | |
| D02 | Member detail (P) | — | Tap a member | Sheet shows name, student code, bio only (no email/phone) | Profile policy exposes public fields only | | |
| D03 | Promote (O) | P is Member | Role menu → Leader → confirm | Badge changes to Leader after server re-read; P's hub (refresh) now shows the Manage section | `role changes` policy: MANAGE_ROLES; owner via bypass | | |
| D04 | Demote (O) | L is Leader | Role menu → Member | Badge Member; L's Manage section disappears on refresh | same | | |
| D05 | Moderator (O) | P is Member | Role menu → Moderator | Badge Moderator; M's hub shows **no** Manage section (no seeded permissions) | moderator has 0 seeded permissions | | |
| D06 | Owner protection (L with MANAGE_ROLES granted via D09) | L opens Members | No role menu / remove icon on O's row; O's own row cannot be changed | RLS excludes owner rows; triggers block owner changes | | |
| D07 | Remove member (O) | P is Member | Remove → confirm | P disappears; count decrements; P's app shows "Group not available" on refresh | `manage members` DELETE: MANAGE_MEMBERS, not owner, not self | | |
| D08 | Remove as Member (P) | P is Member | Open Members | No remove icons, no role menus | UI gate mirrors `fn_has_permission` | | |
| D09 | Role permissions (O) | Hub → Manage → Role permissions | Toggle "Manage roles & permissions" ON for Leader | Switch stays ON after server re-read; L's Members screen (refresh) now shows role menus | `role_permissions` policy: MANAGE_ROLES / owner | | |
| D10 | Moderator grant (O) | Role permissions → Moderator tab | Toggle "Send announcements" ON | M's hub (refresh) now shows the announcement composer | `fn_has_permission` reads the new row | | |
| D11 | Removed leader (O removes L) | L had permissions | L refreshes hub | "Group not available"; no management controls | `fn_is_member` false ⇒ all permissions false | | |

## E. Settings, rules (G2/G6/G13)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| E01 | `/groups/:id/settings` (O) | — | Edit name, description; save | Hub header updates after return | `groups` UPDATE: GROUP_SETTINGS or owner | | |
| E02 | Settings (O) | — | Change privacy public → private → restricted | Header meta updates; join behaviour changes (C07) | CHECK constraint | | |
| E03 | Settings (P) | Member opens `/groups/:id/settings` via back-stack/deep link | Read-only / "Only the group owner…" message; no save control | Server rejects member UPDATE (0 rows) | | |
| E04 | Rotate invite code (O) | — | Rotate | New 8-char code shown; old code no longer joins (B04 with the old code) | `fn_reset_group_invite`: GROUP_SETTINGS/owner | | |
| E05 | Rules (O) | Hub → Rules | Add a rule, edit it, delete it | Each change visible after server re-read; order by position | `group_rules` policies: GROUP_SETTINGS/owner write, members read (live since `ec8f5a0`) | | |
| E06 | Rules (P) | Rules exist | Open hub | Rules visible; no add/edit/delete controls | member INSERT/UPDATE/DELETE rejected server-side | | |

## F. Announcements (G7)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| F01 | Hub → Announcements (O) | — | Post title + body | Appears at top; author "You"; P sees it after refresh with O's name | INSERT: SEND_ANNOUNCEMENT/owner **and** `author_id = self` (F-09 live) | | |
| F02 | Announcements (L) | L seeded SEND_ANNOUNCEMENT | Post | Succeeds, author shows L | same | | |
| F03 | Edit / delete (O) | Announcement exists | Edit title, then delete | Changes reflected after re-read | UPDATE/DELETE policies | | |
| F04 | Notification (P) | F01 posted | P opens hub bell | Unread badge ≥1; inbox shows "📢 …" GROUP_ANNOUNCEMENT row | delivered by trigger → `fn_notify_group` (client can no longer call it) | | |

## G. Chat (G8, F-11)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| G01 | Hub → Chat (P) | — | Send "hello" | Appears as "You"; O sees "hello" from P after refresh | INSERT: `sender_id = self` and member | | |
| G02 | Chat (O) | ≥50 messages (seed by sending) | Load older | Older page appends; no duplicates; order preserved | — | | |
| G03 | Deleted message (any) | A message soft-deleted (via legacy web `fn_delete_group_message` or SQL) | Refresh chat | Row shows "Message deleted" placeholder; original text never shown | client never renders `body` when `deleted_at` set (F-11) | | |
| G04 | System notices | After D03/D07 | Chat shows "X is now leader" / "X left the group" notices as System | inserted only by triggers (`fn_insert_system_message` client EXECUTE revoked) | | |
| G05 | Removed member (P after D07) | — | P's chat cannot load/send | "Group not available" | RLS member-only | | |
| G06 | Chat notification (O) | G01 | O's bell | Unread badge increments; inbox row "Device QA — new message" | trigger delivery | | |

## H. Tests, results, leaderboard (G9–G12, F-10)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| H01 | Hub → Group tests (L) | L seeded CREATE_TEST | Create test (2 approved MCQs), save draft | Draft listed with "Draft" status | `rpc_create_test` requires CREATE_TEST | | |
| H02 | Group tests (P) | — | No "Create test" control; can view list | — | server: `CREATE_TEST is required` | | |
| H03 | Publish (L, creator) | H01 | Publish | Status Published; members get a TEST_INVITATION notification | `rpc_publish_test` creator-only | | |
| H04 | Schedule (L) | Draft/published | Set start/end, save | Status/time shown; end before start rejected | `ends_after_starts` CHECK; lifecycle guard | | |
| H05 | Take test (P) | Published/live | Start → answer → submit | Result screen shows score; questions never show the correct option before submit | `rpc_start_attempt` membership; `get_test_questions_safe` strips `correct_option` | | |
| H06 | Take test (N) | Deep link to the test | N cannot start | "not a member" error | `NOT_MEMBER` | | |
| H07 | Generate results (L) | ≥2 submissions | Group tests → Results → Generate results | Batch status completed; participant rows listed | `rpc_generate_results`: creator/GENERATE_RESULTS; deterministic, no AI | | |
| H08 | Results (P) | H07 | Open own results | Own score, breakdown, insights; no other participant rows | RLS own row | | |
| H09 | Leaderboard (P) | H07 | Results → View Leaderboard | **F-10:** ordinary member sees only permitted result/leaderboard information (for this client: "Your result: X/Y"), with no unauthorized participant count or full ranking; owner / `VIEW_GROUP_ANALYTICS` may see the server-authorized full leaderboard | `rpc_get_leaderboard` remains the authorization boundary; no client-side ranking or count inference | | |
| H10 | Request coach reports (L) | H07 | Tap Request AI coach reports twice | First: "queued/pending"; second: same job (no duplicate); no report content appears (no worker) | `rpc_request_coach_reports`: idempotent; `ai_jobs` unreadable to clients | | |
| H11 | Archive / delete (L) | Draft test | Delete draft; archive ended test | Draft removed; ended test archived | `rpc_delete_test` creator; `fn_soft_delete_test` | | |

## I. Notifications (G16)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| I01 | Hub bell (P) | Unread rows exist | Open bell | Inbox newest first with unread dots; title "(n unread)" | own rows only | | |
| I02 | Mark one (P) | I01 | Tap a row | Dot clears; navigates (message/announcement → hub; test → tests) | own-row UPDATE `read_at` | | |
| I03 | Mark all (P) | Unread > 0 | Mark all read | Title loses "(n unread)"; back on hub the badge is gone | group-scoped own-row UPDATE | | |
| I04 | Mute (P) | — | Toggle "Mute this group" ON; O posts an announcement | P receives **no** new notification; O/others do | `group_mutes` honoured by `fn_notify_group` | | |
| I05 | Removed member (P after D07) | — | Open `/groups/:id/notifications` | "Group not available" | membership guard | | |

## J. Leave, owner protection, navigation, resilience (G15 / cross-cutting)

| ID | Screen / flow | Precondition | Action | Expected result | Sec | Result | Observation |
|---|---|---|---|---|---|---|---|
| J01 | Leave (P) | Member | Leave → confirm | Snack, redirected to `/groups`; group gone from list | `self leave group` DELETE | | |
| J02 | Owner leave (O) | Owner | Leave button hidden; menu item disabled; note shown | — | `CANNOT_REMOVE_OWNER` trigger | | |
| J03 | Back navigation | Any sub-screen | Hardware back from members/settings/tests/results/leaderboard/notifications | Returns to the previous screen; hub refreshes (badge/roster) | — | | |
| J04 | Double-tap guards | Any mutation button | Double-tap quickly | One request; button disabled while busy | single-flight | | |
| J05 | Airplane mode | — | Toggle airplane mode, open hub / send chat | Error state with Retry; retry recovers | — | | |

## Summary (fill after execution)

| Metric | Count |
|---|---|
| Total items | 66 |
| PASS | |
| FAIL | |
| BLOCKED / N/A | |

Sign-off: Tester ______ · Date ______ · Device ______ · APK commit ______

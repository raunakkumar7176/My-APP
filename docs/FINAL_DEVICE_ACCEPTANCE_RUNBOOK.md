# Final Device Acceptance Runbook

**Purpose:** Human-executable steps for a tester to verify all 66 acceptance items on a real Android device.

**Important:** Device acceptance does NOT prove backend security. It only verifies client-side behaviour under live server conditions.

---

## Prerequisites

### Accounts Required

| Role | Email | Purpose |
|---|---|---|
| Owner (O) | _(fill)_ | Group creator, full control |
| Leader (L) | _(fill)_ | Promoted by O during D03 |
| Moderator (M) | _(fill)_ | Promoted by O during D05 |
| Member (P) | _(fill)_ | Joined via invite code |
| Non-member (N) | _(fill)_ | Never joined any test group |
| Invitee (P2) | _(fill)_ | Receives invitation in C02 |

### Device Requirements

- Real Android device (not emulator)
- Android 8.0+ (API 26+)
- Stable internet connection
- APK built from: `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`

### Test Data Setup

1. O creates group "Device QA" (public) — note the invite code
2. O promotes L to Leader
3. O promotes M to Moderator
4. O invites P2 by student code
5. L creates a test with 2+ questions, publishes it
6. P takes the test and submits

---

## Execution Order

Execute sections A through J in order. Each section builds on previous state.

### Section A: Auth & Entry (A01-A03)

| Step | Action | Expected |
|---|---|---|
| A01 | Sign in with O's credentials | Lands on `/home` |
| A02 | Kill and reopen app | Still signed in |
| A03 | Open Groups | Lists O's groups |

### Section B: Group Creation (B01-B05)

| Step | Action | Expected |
|---|---|---|
| B01 | Create "Device QA" (public) | Hub opens, "1 member · Owner" |
| B02 | Open settings, copy invite code | Code shown only in settings |
| B03 | P joins by code | P lands in hub as Member |
| B04 | P enters wrong code | Error message, no membership |
| B05 | N opens group deep link | "Group not available" |

### Section C: Invitations (C01-C10)

| Step | Action | Expected |
|---|---|---|
| C01 | O invites P2 by student code | "Invitation sent" |
| C02 | P2 opens Groups | Incoming card with Accept/Decline |
| C03 | P2 taps Accept | Card disappears, group in list |
| C04 | P2 double-taps Accept | Second tap ignored |
| C05 | O cancels, P2 taps Accept | "No longer available" |
| C06 | O invites P4, P4 declines | Card disappears, no membership |
| C07 | Set restricted, P5 joins by code | "Request sent" state |
| C08 | O approves P5 | P5 becomes Member |
| C09 | O declines P6 | P6 cannot enter |
| C10 | P7 withdraws request | Request removed |

### Section D: Members & Roles (D01-D11)

| Step | Action | Expected |
|---|---|---|
| D01 | O opens Members, searches | List works, counts match |
| D02 | P taps a member | Name/student code/bio only |
| D03 | O promotes P to Leader | Badge changes, Manage appears |
| D04 | O demotes L to Member | Badge changes, Manage disappears |
| D05 | O promotes P to Moderator | Badge shows, no Manage section |
| D06 | L cannot change O's role | No menu on O's row |
| D07 | O removes P | P disappears, P sees "not available" |
| D08 | P opens Members | No controls visible |
| D09 | O grants Leader "Manage roles" | L sees role menus |
| D10 | O grants Moderator "Send announcements" | M sees announcement composer |
| D11 | O removes L | L refreshes → "not available" |

### Section E: Settings & Rules (E01-E06)

| Step | Action | Expected |
|---|---|---|
| E01 | O edits name/description | Hub updates |
| E02 | O changes privacy | Join behaviour changes |
| E03 | P opens settings via deep link | Read-only, no save |
| E04 | O rotates invite code | New code works, old fails |
| E05 | O adds/edits/deletes rules | Each change reflected |
| E06 | P views rules | Read-only, no controls |

### Section F: Announcements (F01-F04)

| Step | Action | Expected |
|---|---|---|
| F01 | O posts announcement | Appears, P sees it |
| F02 | L posts announcement | Succeeds, author shows L |
| F03 | O edits/deletes announcement | Changes reflected |
| F04 | P checks bell after F01 | Unread badge, inbox row |

### Section G: Chat (G01-G06)

| Step | Action | Expected |
|---|---|---|
| G01 | P sends "hello" | Appears as "You"; O sees it |
| G02 | Load 50+ messages | Older page appends, no dupes |
| G03 | Refresh after soft-delete | "Message deleted" shown |
| G04 | After D03/D07 | System notices visible |
| G05 | Removed P sends | "Group not available" |
| G06 | O checks bell after G01 | Badge increments |

### Section H: Tests & Results (H01-H11)

| Step | Action | Expected |
|---|---|---|
| H01 | L creates test, saves draft | Draft listed |
| H02 | P views test list | No "Create" control |
| H03 | L publishes test | Status Published, notification |
| H04 | L schedules test | Time shown, validation works |
| H05 | P takes test, submits | Score shown, no correct option before submit |
| H06 | N tries to start test | "not a member" error |
| H07 | L generates results | Batch completed, rows listed |
| H08 | P opens own results | Score, breakdown; no other rows |
| H09 | P views leaderboard | **F-10:** "Your result: X/Y · Z%" only |
| H10 | L requests coach reports twice | First queued, second same job |
| H11 | L deletes/archives test | Draft removed, ended archived |

### Section I: Notifications (I01-I05)

| Step | Action | Expected |
|---|---|---|
| I01 | P opens bell | Inbox with unread dots |
| I02 | P taps a row | Dot clears, navigates |
| I03 | P marks all read | Badge gone |
| I04 | P mutes group, O posts | P gets no notification |
| I05 | Removed P opens notifications | "Group not available" |

### Section J: Navigation & Resilience (J01-J05)

| Step | Action | Expected |
|---|---|---|
| J01 | P leaves group | Redirected to /groups |
| J02 | O tries to leave | Button hidden/disabled |
| J03 | Back from sub-screens | Returns to hub, refreshes |
| J04 | Double-tap mutation buttons | One request only |
| J05 | Airplane mode on, retry | Error + Retry works |

---

## Evidence Collection

For each section:
1. Screenshot the start state
2. Screenshot the action
3. Screenshot the result
4. Note any deviation in the Observation column

## Failure Recording

If any item fails:
1. Record FAIL in the checklist
2. Take screenshot of the failure
3. Note the exact error message
4. Continue to next item (do not stop)

## Cleanup

After all tests:
1. Sign out of all accounts
2. Delete test group "Device QA"
3. Clear app data if on shared device

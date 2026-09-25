# G15 — Group Membership Edge Cases

**Status:** PASS  
**Date:** 2026-09-20  
**Commits:** (test file added this session)

---

## Summary

G15 covers edge cases around group membership lifecycle: leave (all roles), remove member, owner protection, stale-state clearance, and confirmation flows. A full live-first audit confirmed that **all edge cases A–I are already implemented** in existing production code. G15's deliverable is comprehensive test coverage (29 tests) and this report.

---

## Audit Results

| Edge Case | Implemented? | Location |
|-----------|-------------|----------|
| A. Member leave | ✅ | `group_hub_controller.dart:618` (`leave()`), `group_hub_screen.dart` (dialog, snack, navigation) |
| B. Leader leave | ✅ | Same as member — `canLeave` only blocks owners |
| C. Moderator leave | ✅ | Same as member |
| D. Owner leave protection | ✅ | `canLeave` → false, `leaveBlockedReason` text, UI hides button |
| E. Remove member | ✅ | `removeMember()` with self-removal guard, owner protection, `MANAGE_MEMBERS` permission check |
| F. Role + removal interaction | ✅ | `load()` re-reads after mutation |
| G. Join request / invitation | ✅ | Server-side lifecycle; client doesn't manage these rows during leave/remove |
| H. Group deletion | ❌ (correctly) | No safe backend path; server would reject |
| I. Owner transfer | ❌ (correctly) | No safe backend path; `assignableRoles` excludes owner |

---

## Test Coverage (29 tests)

### A. Member leave (5 tests)
- `member can leave; state clears; group gone from list`
- `leave flow: dialog, confirm, snack, navigate to /groups` (widget)
- `leave flow: cancel does nothing` (widget)
- `leave failure surfaces error, membership intact`
- `leave busy guard: second call dropped`

### B. Leader leave (2 tests)
- `leader can leave; permissions gone after re-read`
- `leader leave: same dialog flow as member` (widget)

### C. Moderator leave (1 test)
- `moderator can leave; membership clears`

### D. Owner leave protection (3 tests)
- `owner cannot leave; canLeave is false; error is set`
- `owner hub: leave button hidden, blocked reason shown` (widget)
- `owner hub: popup menu leave is disabled` (widget)

### E. Remove member (9 tests)
- `owner can remove a member; roster and count refresh`
- `owner cannot remove themselves via removeMember`
- `owner cannot be removed by anyone`
- `unauthorized member cannot remove anyone`
- `cross-group target: removing a user not in this group succeeds silently`
- `remove failure surfaces error, target stays`
- `remove flow: confirm dialog` (widget)
- `remove flow: cancel does nothing` (widget)
- `plain member: no remove buttons offered` (widget)

### F. Role + removal interaction (2 tests)
- `after removing a leader, controls refresh from server`
- `after demoting a leader to member, their permissions gone`

### G. Join request / invitation interaction (2 tests)
- `pending join request survives member leaving`
- `pending invitation survives member leaving`

### H. Group deletion (1 test)
- `no deleteGroup on GroupRepository interface`

### I. Owner transfer (2 tests)
- `assignableRoles excludes owner`
- `changeRole cannot set anyone to owner`

### Stale state clearance (2 tests)
- `after leave, all local state is cleared`
- `after removeMember, roster is refreshed from server`

---

## Verification

| Check | Result |
|-------|--------|
| `flutter test test/group/group_membership_edge_cases_test.dart` | 29/29 pass |
| `flutter test` (full suite) | 932/932 pass |
| `flutter analyze` | 0 errors, 0 warnings, 75 info hints |
| No G12/G10.2/G14/G16/G17/G18 touched | ✅ |

---

## Key Implementation Details

### Leave (`group_hub_controller.dart:618–648`)
- Guard: `canLeave` → `false` for owners (`isOwner`)
- On success: clears `_group`, `_members`, sets `_leftGroup = true`
- After `leave()`: `load()` → sees no membership → sets `accessDenied = true`
- Busy guard: second concurrent call returns `false`

### Remove (`group_hub_controller.dart:683–701`)
- Self-removal guard: returns `false` with "Use Leave group" message
- Owner protection: targets with `GroupRole.owner` → "The group owner cannot be removed"
- Permission: requires `MANAGE_MEMBERS` (owner, leader)
- After success: `load()` re-reads from server

### Owner transfer: NOT IMPLEMENTED
- `GroupHubController.assignableRoles` excludes `GroupRole.owner`
- `changeRole` rejects any assignment to `GroupRole.owner`

### Group deletion: NOT IMPLEMENTED
- `GroupRepository` interface has no `deleteGroup` method
- No safe backend path exists

---

## Notes

- The InMemoryGroupRepository `removeMember` does not guard against non-existent targets (silent no-op), which is acceptable for test infrastructure
- The server's actual `removeMember` RPC would reject a target not in the group, but the client never sends that request (UI only shows remove buttons for actual members)

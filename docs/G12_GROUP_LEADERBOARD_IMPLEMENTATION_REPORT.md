# G12 — GROUP TEST LEADERBOARD IMPLEMENTATION REPORT

**Date:** 2026-09-19
**Branch:** r4-restart
**Status:** G12 IMPLEMENTATION COMPLETE — BACKEND PENDING

---

## 1. Live Schema Inspected

The following live schema objects were inspected (from the migration set and existing Flutter models):

- `results` table: `attempt_id` (PK), `test_id`, `user_id`, `score`, `max_score`, `percentage`, `accuracy`, `correct_count`, `wrong_count`, `unanswered_count`, `rank`, `subject_breakdown`, `topic_breakdown`, `computed_at`, `generation_method`, `total_marks`, `marks_obtained`, `is_passed`, `partial_count`, `total_questions`, `batch_id`
- `result_batches` table: `id`, `test_id` (UNIQUE), `requested_by`, `status`, `reports_done`, `reports_total`, `totals`, `created_at`, `completed_at`, `errors`
- `tests` table: `id`, `created_by`, `status`, `group_id`, `is_soft_deleted`, `negative_marks`, and other fields
- `group_members` table: `(group_id, user_id)` composite PK, `role`, with embedded `profiles(full_name, avatar_url, student_code)`
- RLS on `results`: SELECT own row OR VIEW_GROUP_ANALYTICS in the test's group

## 2. Result Source Used

The leaderboard is derived **entirely** from the existing `results` table via the existing `resultsForTest(testId)` repository method. This method:

- Reads all `results` rows for a test under RLS
- Members see only their own row
- VIEW_GROUP_ANALYTICS holders see all participants
- Returns results ordered by `score` descending

No new backend objects, RPCs, or tables are created. The leaderboard is a pure client-side sort of server-authorized data.

## 3. Ranking Rule

**Primary**: `score` descending (higher score = better rank)
**Secondary**: `computed_at` ascending (earlier submission wins ties — a proxy for "submitted first" since the schema provides no attempt-order column)

The `fromResults` factory on `LeaderboardEntry` performs the sort and rank assignment.

## 4. Tie Handling

Standard competition ranking:
- Participants with the **same score** receive the **same rank**
- The next distinct score receives `rank = 1 + count of entries above it`
- This means ranks are NOT dense — if two participants tie at rank 1, the next rank is 3 (not 2)

**Limitation**: The tie-breaker uses `computed_at` only for ordering within ties, but tied participants always share the same rank number. The `computed_at` secondary sort determines display order only, not a separate rank.

If the schema provided an `attempt_number` column on results, a more precise tie-breaker could be used. This limitation is documented.

## 5. Access Control

| Audience | Access | Mechanism |
|----------|--------|-----------|
| MEMBER | See own row only | RLS `own results` policy |
| AUTHORIZED (VIEW_GROUP_ANALYTICS) | See all participants | RLS `analytics holders see group results` policy |
| OWNER | See all results | `fn_has_permission` owner bypass |
| NON-MEMBER | Denied | `groupForMember` returns null → accessDenied |
| REMOVED MEMBER | Denied on refresh | `groupForMember` returns null after removal |
| CROSS-GROUP | Denied | Test's group_id must match the opened group |
| FORGED IDs | Denied | RLS + controller group_id validation |
| ANON | Denied | No auth → no group membership |

No new permission is created. The leaderboard uses the same `VIEW_GROUP_ANALYTICS` / membership semantics as the existing results screen.

## 6. UI/Navigation

**Flow:**
```
Group Hub → Group Tests → Previous/Completed Test → Results → View Leaderboard
```

**Route:** `/groups/:groupId/tests/:testId/results/leaderboard`
**Route name:** `group-test-leaderboard`

**UI Elements:**
- AppBar: `{test title} · Leaderboard`
- Header: status label, group name, participant count, user's rank summary
- List: each participant as a `Card` with rank, name, score/%, accuracy, C/W/U counts
- Medal icons for top 3 (🥇🥈🥉)
- Current user's row highlighted with `primaryContainer` color
- Empty state: "No results yet" with context message
- Denied state: lock icon with "not available" message
- Error state: error icon + retry button
- Loading state: centered `CircularProgressIndicator`
- Pull-to-refresh support

**Integration:** "View Leaderboard" button added to `GroupTestResultsScreen`, visible when results exist.

## 7. Backend Changes

**None.** G12 is entirely frontend. No new migrations, RPCs, views, or tables.

## 8. Security Tests

30 tests covering:

1. Leaderboard loads for authorized group/test (leader, member, owner)
2. Correct ordering by score descending
3. Deterministic tie handling (same rank, secondary sort by computed_at)
4. Current user's row flagged
5. Empty results → empty list
6. Unfinished/un-evaluated test → loads whatever RLS returns
7. Non-member denied
8. Removed member loses access on refresh
9. Cross-group denied
10. Forged group/test ID denied
11. Anon denied (no auth → groupForMember returns null)
12. No correct_option exposure (results table has no correct_option column)
13. Archived/deleted test behavior (soft-deleted test → getById returns null → accessDenied)
14. G11 results remain intact (G11 controller works alongside G12)
15. Error state surfaces error message
16. Loading state renders spinner
17. Widget: leader sees all participants
18. Widget: member sees own entry
19. Widget: non-member sees denied state
20. Widget: empty results shows message

## 9. Test Count

- **G12 tests:** 30 (all passing)
- **G11 tests:** 23 (all passing, no regression)
- **Full suite:** 848 (all passing, no regression)

## 10. Flutter Analyze Result

```
76 issues found. (ran in 16.0s)
```

All issues are pre-existing `info`-level diagnostics (prefer_const_constructors, deprecated_member_use, curly_braces_in_flow_control_structures, etc.). **Zero errors, zero warnings** in G12 files.

## 11. APK Build Result

```
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

Build succeeded with `--debug --dart-define-from-file=dart-defines.dev.json`.

## 12. Migrations

**None.** G12 creates no new backend objects. The leaderboard is derived from existing stored results.

## 13. Limitations

1. **Tie-breaker**: `computed_at` is used as secondary sort, but tied participants always share the same rank number. A more precise tie-breaker (e.g., attempt_number) would require schema changes.

2. **No pagination**: The current implementation loads all results for a single test. For tests with very many participants (100+), this could be optimized with server-side pagination in a future iteration.

3. **No real-time updates**: The leaderboard does not auto-update when new results are generated. Users must pull-to-refresh.

4. **Profile resolution**: Display names come from the `group_members` embedded profile (already loaded for the roster). No additional profile queries are made. Former members show as "Former member".

## 14. Files Changed

| File | Change |
|------|--------|
| `lib/features/group/domain/group_test_results.dart` | Added `canSeeLeaderboard` gate and `LeaderboardEntry` class |
| `lib/features/group/state/group_leaderboard_controller.dart` | New file: `GroupLeaderboardController` |
| `lib/features/group/screens/group_leaderboard_screen.dart` | New file: `GroupLeaderboardScreen` |
| `lib/features/group/screens/group_test_results_screen.dart` | Added leaderboard button |
| `lib/app/app_router.dart` | Added leaderboard route + import |
| `test/group/group_leaderboard_test.dart` | New file: 30 tests |
| `docs/G12_PRECHECK.sql` | New file: schema verification |
| `docs/G12_POSTCHECK.sql` | New file: no-backend verification |

## 15. Commit Hash

`348e338`

## 16. Final Status

**G12 IMPLEMENTATION COMPLETE — BACKEND PENDING**

(No backend changes required for G12. The "backend pending" designation matches G11's status for the `rpc_request_coach_reports` migration which remains unapplied.)

# G12 — Group Test Leaderboard: Verification Report (auditor)

**Audited commits:** `348e338` (implementation), `33cc280` (report hash) on `r4-restart` · **Audit date:** 2026-09-19 · **This report:** `__COMMIT__`
**Live access:** read-only + one rolled-back transaction via the pooler credentials in the untracked `tool/` scripts (never printed). No live object changed; residue re-checked (0).

## FINAL VERDICT

**G12 VERIFIED — PASS** (security and the live RLS it depends on are proven; no backend object is required. One non-security correctness finding, F1 in §12, must be fixed before the leaderboard is shown to plain members.)

| Layer | Verdict |
|---|---|
| Repository | **YES** — the 9 files of `348e338` match the report; no G9/G10.2/G13/G11-backend file touched |
| Live schema / RLS | **YES** — `results` policies re-read; attack tests executed against live RLS (§3) |
| Ranking / ties | **YES** — independently re-tested (§4–5), incl. 100/90/90/80 → 1,2,2,4 |
| Privacy | **YES** — members receive only their own row; no `correct_option`, answers or AI payload reachable through the leaderboard path |
| G11 regression | **YES** — reads only; no `rpc_generate_results`, no `ai_jobs`, no `results` mutation (proven live) |
| G10 / G8 / R4 regression | **YES** — full suite 848/848 |
| Flutter | analyze 0 errors / 0 warnings · **848 tests** · APK built |
| Device / Chrome | NOT run (no device) — UX only |

---

## 1. Repository audit

`348e338`: new `lib/features/group/state/group_leaderboard_controller.dart` (134), `lib/features/group/screens/group_leaderboard_screen.dart` (266), `test/group/group_leaderboard_test.dart` (381, 30 tests), `docs/G12_PRECHECK.sql`, `docs/G12_POSTCHECK.sql`, `docs/G12_GROUP_LEADERBOARD_IMPLEMENTATION_REPORT.md`; modified `lib/features/group/domain/group_test_results.dart` (+106: `GroupResultsAccess.canSeeLeaderboard`, `LeaderboardEntry` + `fromResults`), `lib/features/group/screens/group_test_results_screen.dart` (+19: "Leaderboard" button when results exist), `lib/app/app_router.dart` (+12: `/groups/:groupId/tests/:testId/leaderboard`). `33cc280`: report hash only. No repository / service / migration added; `ResultRepository.resultsForTest` (G11) reused. Working tree: only the pre-existing uncommitted G10-report rewrite by another agent (untouched).

## 2. Live schema audit (read-only, actual)

`public.results`: PK `attempt_id`; `test_id, user_id, score numeric, max_score, correct_count, wrong_count, unanswered_count, accuracy, percentage, rank (NULL — never set by the live scorer), subject_breakdown, topic_breakdown, computed_at`. Policies (SELECT only, no client write): `own results` (`user_id = auth.uid()`), `analytics holders see group results` (`fn_has_permission(test.group_id, uid, 'VIEW_GROUP_ANALYTICS')`, owner via bypass). Membership: `fn_is_member` (SECURITY DEFINER); route-level access uses `groupForMember` + `tests` RLS (`member read tests`). `rpc_generate_results` / `fn_score_attempt` unchanged and deterministic (score = marks − wrong × negative_marks). `docs/G12_PRECHECK.sql` reviewed: read-only, consistent with these facts.

**Can `resultsForTest()` safely back the leaderboard?** Yes: it is a plain `SELECT … WHERE test_id = ? ORDER BY score DESC` and the server returns only what the two policies allow. It never widens access; it selects the `results` columns only (no `questions`, `answers`, `ai_reports`). No new backend object is needed. (Product consequence in W1.)

## 3. RLS / security audit — LIVE (rolled back; fixtures: B leader, C member, D non-member, A owner; three scored attempts incl. one wrong answer under 0.5 negative marking; a second scored test in another group)

| # | Proof | Result |
|---|---|---|
| 1 | non-member reads results / the test row | 0 rows / 0 rows → screen shows "access denied" |
| 2 | cross-group: leader of group A reads a group-B test's results / row | 0 rows / 0 rows |
| 3 | forged test id under group A's route | `getById` returns nothing (RLS) → controller `accessDenied`; also `test.groupId != groupId` guard |
| 4 | removed member | `fn_is_member` false → no group access (screen denied); the stored own `results` row is still readable by design of the live `own results` policy (W3) |
| 5 | anon | `permission denied` on `results` |
| 6 | member sees other participants | **own row only** (1 of 3) |
| 7 | member mutates a result row | 0 rows (no UPDATE policy) |
| 8 | `correct_option` | direct `questions` read denied; leaderboard never queries questions |
| 9 | AI side effects | `ai_jobs` 0 before and after every read; member cannot read others' `ai_reports` |
| 10 | result-generation side effects | `result_batches` count unchanged by reads; the screen/controller contain no `generateResults` / `requestCoachReports` call |
| — | analytics holder / owner | leader (VIEW_GROUP_ANALYTICS) and owner read all 3 rows |

## 4. Ranking verification (independent ad-hoc test run against `LeaderboardEntry.fromResults`, not committed)

- `[100, 90, 90, 80]` → ranks **1, 2, 2, 4** ✓ (standard competition ranking: rank = 1 + number of strictly better scores).
- one result → `[1]`; no results → `[]`; identical scores `[7,7,7]` → `[1,1,1]`; `[7,7,7,1]` → `[1,1,1,4]`.
- Negative marking: `[−1.5, 0, null, 2]` → order `2, 0, −1.5, null`, ranks `1,2,3,4` (null score last). Live proof: C's stored score `0.5` (1 right, 1 wrong × 0.5) sorts below B's `1.0` and A's `2.0` — the server order `score DESC, computed_at ASC` matches the client order.
- Fractional scores compared numerically (`10 > 9.75 > 9.5`).
- Unanswered questions: not penalised by the scorer (live `fn_score_attempt`), so they only lower `score` via missing marks — reflected correctly (B: 1 right + 1 unanswered = 1.0).
- Completed/evaluated only: rows exist only after scoring; the screen shows "results not generated" / "not over yet" otherwise (no invented rows).

## 5. Tie verification

Secondary key `computed_at ASC` orders tied participants (earlier scoring first) **without** changing the shared rank (`[95, 90(late), 90(early)]` → `top, early, late`, ranks `1, 2, 2`). This is a presentation order only; no product rule about tie priority exists live (`results.rank` is never populated), so the choice is acceptable and documented (W2).

## 6. Privacy verification

Entry fields: rank, label (roster name / "You" / "Former member"), score, max, percentage, accuracy, C/W/U. No answer data, no `correct_option`, no AI payload, no attempt ids beyond what `results` already carries. Members' leaderboard is their own row only (live policy); analytics holders/owner see everyone — identical exposure to the G11 manager list, i.e. no new data path.

## 7. G11 regression

`group_test_results_screen.dart` gained only a navigation button; `GroupTestResultsController`, `ResultRepository`, migrations and G11 tests are unchanged (23/23 still pass). Opening the leaderboard: reads `groupForMember`, `getById`, `members`, `resultsForTest` — nothing else (controller reviewed; live side-effect counters unchanged).

## 8. G10 / G8 / R4 regression

Full suite green: `group_tests_management_test` (32), `group_chat_test` (23), G1–G7 suites, `r4_restart/*` and `features/test/*` (attempts, answers, deterministic scoring mirrors, safe questions). No file outside the nine listed changed.

## 9–11. Flutter / APK / commit

`flutter analyze` → 0 errors, 0 warnings (info lints only) · `flutter test` → **848 passed** · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built**. Audited HEAD before this report: `33cc280`.

## 12. Findings

**F1 (correctness, non-security — fix before the leaderboard is shown to plain members):** ranks are computed over the RLS-visible subset. A plain member receives only their own `results` row, so the screen renders "1 participant" and **"Your rank: 1"** for every member regardless of their real standing (`group_leaderboard_screen.dart:156-163`). The number is consistent with the data the client has, but it is not a group rank and reads as one. Smallest fix (screen/controller only, no backend): show "Your rank" and the rank column only when the caller can see every participant (`VIEW_GROUP_ANALYTICS` or owner — the probe already exists in `GroupTestResultsController`), and label the single-row view as "Your result" / "n of the group's results are visible to you". A true member-wide rank needs the server-side path described in W1.

No security finding: the implementation is read-only, reuses live RLS exactly, and computes nothing the server did not store except that display rank.

## 13. Warnings (non-blocking)

- **W1 (product):** under the live policies a plain member's "leaderboard" contains only themselves; the full ranking is visible to `VIEW_GROUP_ANALYTICS` holders and the owner. A member-wide leaderboard would need a server-side RPC/view exposing only `(user, score, rank)` — a product decision, not a G12 defect.
- **W2:** tie order `computed_at ASC` is a presentation choice; `results.rank` is never populated live, so nothing conflicts.
- **W3:** a removed member keeps reading their own stored `results` row (live `own results` policy) even though the group screens deny them — by live design.
- **W4:** `results.rank` is NULL live and ignored by the client (see F1 for the consequence of ranking over the visible subset).
- **W5:** credentials in untracked `tool/` remain (unchanged since G8).

**FINAL: G12 VERIFIED — PASS**

# R4.11b — Combined Device Verification Checklist

Build: current `flutter build apk --debug` (626 tests, analyze 0 errors).
Device: Moto G31 (ZD22257XV4). Claude drives capture via adb; no SQL needed.

Capture command (run after each block, before the buffer rotates):

    adb logcat -d | grep -E "response shape|SECURITY|Auth initial|getMyDrafts|getAccessibleTests|publishTest|Question [0-9]+ (created|approved)|Test (created|updated|published)|PostgrestException|_loadDrafts|Join with code"

All diagnostics are keys/shape only. Never log answer values, tokens or correct_option.

| # | Step | What to do on the phone | Evidence line(s) to look for | Proves |
|---|------|-------------------------|------------------------------|--------|
| 1 | Cold start → My Drafts | Force-stop app (ideally after >1 h idle), open, go Tests → My Drafts | `Auth initial status`, `getMyDrafts: returned N rows` and NO `getMyDrafts PostgrestException` | P0-2 closure on cold start |
| 2 | Create Practice | Create Test → Type: Practice Test → title → Next | schedule cleared, duration 3h prefilled | R4.11a defaults |
| 3 | settings round-trip | Save Draft → Continue Editing → Save Draft; reopen from My Drafts | `Test created` once, `Test updated` after; on reopen the Type shows Practice Test | `p_settings` accepted; `settings` returned in row; no duplicate create |
| 4 | Approve | Add 2 MCQ + 1 numeric + 1 short-answer question → Review → Approve All | `Question N approved`; readiness turns green without leaving the screen | P0-3 |
| 5 | Publish | Publish from Review; then also try Publish on a draft with pending questions from Detail | `Test published`; on the pending one, the message reads "Approve all questions…" once, button disabled while in flight | publish mapping + re-entrancy guard |
| 6 | Start Practice | Detail → Start Test | `rpc_start_attempt response shape: Map(keys=[…])` (or `List…`) | start RPC shape; `attempt_number`, `deadline_at` keys present? |
| 7 | MCQ | Answer an MCQ, wait 5 s | `rpc_save_answers response shape: …` | save RPC shape |
| 8 | Numeric | Type a number, page away and back | field still shows the number | P1-6 |
| 9 | Text answer | Type text, clear it, retype | grid state follows; no crash | P1-6 |
| 10 | Result | Submit (Practice: no reflection dialog expected) | `rpc_submit_attempt response shape: …`; result screen shows server score | submit RPC returns a results row |
| 11 | Repeat | Result → Repeat | either a second attempt starts or the server error text | unlimited repeat: proven / disproven |
| 12 | Code entry | Tests → Challenge with Friends → Join with code (a coded live test) | `rpc_start_attempt_by_code response shape: …`; taking screen opens (title may be fallback) | code flow + whether `test_title` / row readable |
| 13 | Safe-question shape | (captured in steps 4/6) | `get_test_questions_safe response shape: List(len=N) first=Map(keys=[…])` | which columns exist (`status`? `explanation`?) |
| 14 | Start-attempt shape | step 6 | as above | — |
| 15 | Save-answer shape | step 7 | as above | — |
| 16 | Submit shape | step 10 | as above | — |
| 17 | No answer key | any question load | NO line containing `SECURITY: get_test_questions_safe returned a correct_option key` | answer-key boundary |

Outcome mapping:
- Step 6 keys include `attempt_number` → R4_7_6 was applied live; step 11 succeeds → unlimited repeat is live.
- Step 13 keys include `status` → creation-screen readiness is fully reliable; if absent, readiness needs a fallback.
- Step 3 fails at `p_settings` → live `rpc_create_test` differs from R4_5_1; stop and read the live function body.

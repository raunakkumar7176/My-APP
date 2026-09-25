# Codex Independent Verification Report

Date: 2026-09-20  
Scope: Flutter client and backend-integration audit after backend commit `ec8f5a0`  
Verifier: Codex independent pass

## A. Repository status

The working tree is not clean. Existing work includes modified Flutter source,
tests, and reports, plus untracked acceptance/report files. The root also has
untracked `node_modules/`, `package.json`, `package-lock.json`, and `tool/`
content. These appear unrelated to the Flutter verification and were not
deleted or reverted.

The nested `My-Prepration` repository is also modified and is not represented
cleanly as a configured root submodule (`git submodule status` reports no
`.gitmodules` mapping). Its changes include the earlier Experiential AI
gateway work and are outside this Flutter audit.

No service-role credential was found in Flutter source. The checked-in
`dart-defines.dev.json` contains a Supabase anon JWT; this is a client anon key,
not a service-role credential, but it should still be treated as environment-
specific configuration.

Recent history confirms `ec8f5a0` is the stated backend remediation commit.

## B. F-06 invitation result: PASS

The repository calls:

- `fn_accept_group_invitation` with `p_invitation_id`
- `fn_decline_group_invitation` with `p_invitation_id`

The controller uses an acting-invitation guard, removes/re-reads the invitation
after success or stale failure, and maps `INVITATION_NOT_FOUND` and
`INVITATION_NOT_PENDING` to a non-sensitive “no longer available” message.
Tests cover accept, decline, stale invitations, duplicate taps, loading, and
retry. No backend changes were made.

## C. F-10 leaderboard result: PASS WITH DOCUMENTATION FINDING

The Flutter repository calls `rpc_get_leaderboard(p_test)` and no longer reads
other users’ `results` rows to construct the leaderboard. The controller keeps
server-provided ordering and rank; it does not sort, recompute rank, or invent
a participant count.

The screen distinguishes full-view users from ordinary members:

- owner / `VIEW_GROUP_ANALYTICS`: server-returned full ranking and count;
- ordinary member: only the server-returned permitted row(s), without a
  participant-count leak;
- non-member / cross-group user: access-denied state.

Loading, error/retry, empty, and denied states are implemented and covered by
tests. The client-side authorization checks are UX gates only; the RPC remains
the security boundary.

Finding: checklist item H09 still says an ordinary member should see the full
ranking and “n ranked participants”. That expectation conflicts with the
current F-10 security requirement and should be corrected before device
acceptance. The implementation was not changed because it is the secure path.

## D. F-11 deleted-chat result: PASS

The message query selects `deleted_at`; the model maps it to `deletedAt` and
`isDeleted`. The chat widget checks `isDeleted` before rendering the body and
renders exactly “Message deleted”. Tests verify both deleted and normal
messages. No client path renders the deleted body after the flag is set.

## E. G6 group-rules result: PASS by static audit

The client reads rules by exact `group_id`, orders server results, gates writes
with the server-reported settings permission, validates non-empty input, uses
single-flight mutation guards, re-reads after success and failure, and exposes
loading, empty, error, and retry states. Create, update, and delete use exact
row identifiers and treat zero-row mutations as errors. Cross-group scope is
carried by the group query and server RLS remains authoritative.

## F. G11 coach-report result: BLOCKED for live verification

The client correctly requests `rpc_request_coach_reports(p_test_id)` only from
the manager path, after a result batch exists in `completed` or
`partially_completed` state. Requests are single-flight, the RPC response is
parsed as a job, and the UI displays queued/status/error states without trying
to run an AI worker or render fabricated report content.

However, the local migration file
`migrations/G11_rpc_request_coach_reports.sql` explicitly says
“PROPOSED — NOT APPLIED LIVE”. The backend commit message claims G11 was
applied live, but no live database verification was performed in this audit,
and the requested rule forbids changing Supabase or running migrations. The
client therefore cannot be independently proven end-to-end here. If the RPC
is absent, the client safely surfaces a request error; it does not create a
worker.

## G. Route result: PASS by static audit

The router contains group list/create/join/hub/member/notification/settings/
tests/results/leaderboard routes and the R4 test routes. Group routes pass
`groupId` and `testId` as path parameters into the relevant screens. The
leaderboard is nested below the test-results route. No routing redesign or
changes were made.

## H. Test result

Command attempted: `flutter test`

Result: not independently verified. The command produced no stdout and did not
complete after several minutes; it was stopped. Agent 2’s reported `998 pass,
0 fail` could not be reproduced in this environment.

## I. Analyze result

Command attempted: `flutter analyze`

Result: not independently verified. The command produced no stdout and did not
complete after several minutes; it was stopped. Agent 2’s reported `0 errors,
0 warnings, 436 infos` could not be reproduced in this environment.

## J. APK result

Command attempted:
`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`

Result: not independently verified. The command remained active with a Java
process but produced no output after several minutes and was stopped. No APK
success is claimed.

## K. Device-acceptance readiness

`docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` contains exactly 66 ID rows. It
clearly labels the checklist as pending and says physical-device testing has
not been performed. Security expectations are generally separated in the
`Sec` column from UI expectations.

Readiness findings:

1. `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md`, referenced by the checklist, is
   missing from the repository.
2. H09 contains the stale/insecure full-ranking expectation described above.
3. No physical-device testing was performed or claimed.

## L. Discrepancies with Agent 2

- Agent 2 reported 998 passing tests; this run could not complete `flutter
  test`.
- Agent 2 reported clean analyze output; this run could not complete
  `flutter analyze`.
- Agent 2 reported a successful debug APK; this run could not complete the
  requested build.
- The checklist has 66 items as reported, but its H09 expectation conflicts
  with the secure ordinary-member leaderboard behavior.
- The referenced final device runbook is absent.
- G11 remains locally documented as proposed/not applied, conflicting with
  the backend remediation commit message; live status was not independently
  checked.

## M. Recommended next gate

Before any production-readiness decision:

1. Resolve the Flutter tool/test/build hang in a clean environment and capture
   exit codes and artifacts.
2. Reconcile the G11 migration status with a read-only live postcheck; do not
   run a migration as part of this report.
3. Add or restore the referenced final device runbook.
4. Correct H09 to match the secure ordinary-member visibility rule.
5. Execute the 66-item checklist on a physical Android device with explicit
   PASS/FAIL/BLOCKED observations.

## Final verdict

**BLOCKED** — the core client paths audit correctly, but the requested
independent test/analyze/build verification did not complete, G11 live
availability is unresolved, and the device-acceptance runbook is missing.

This report does not declare the project production-ready.

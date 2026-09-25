# R6 Test Assignment Implementation Report

Date: 2026-09-20  
Project: My Preparation — Flutter + Supabase  
Scope: R6 group test assignment discovery and implementation gate

## 1. Scope

R6 was audited as an additive group feature: an owner, leader, or otherwise
authorized manager assigns an existing test to selected group members. G19,
G20, unrelated security migrations, Supabase changes, device acceptance, and
credential work were out of scope.

## 2. Existing architecture reused

The existing architecture contains:

- `TestRepository` and `Test` for test listing and test lifecycle;
- `GroupTestsController` / `GroupTestsScreen` for group test management;
- the existing `fn_has_permission` / `GroupPermission` permission engine;
- `rpc_start_attempt` and the server-side test-access path;
- server-generated `notifications` rows and the group notification screen.

There is no existing Flutter assignment primitive to reuse.

## 3. Discovery findings

The local migration history defines `public.test_invitations` with:

- `test_id`;
- `user_id`;
- `status` in `pending`, `accepted`, or `declined`;
- `invited_at` and `responded_at`;
- a unique `(test_id, user_id)` constraint.

Its migration comment says it is “Access control for restricted tests” and is
used only when `tests.is_public = false`. No current Dart repository, model,
controller, screen, route, or test uses this table. The existing group
invitation model is for group membership and cannot be repurposed safely.

## 4. Files changed

Only this report was added:

- `docs/R6_TEST_ASSIGNMENT_IMPLEMENTATION_REPORT.md`

No Flutter source, SQL migration, dependency, route, or unrelated agent file
was changed.

## 5. Database changes

None. No migration was created or run.

## 6. RPCs

No R6 RPC exists in the repository. Adding one without first deciding whether
R6 assignments are the existing restricted-test access mechanism or a separate
group-membership assignment would define a new backend contract.

## 7. RLS policies

No R6 table policy or RPC policy exists to audit. The existing
`test_invitations` table is not enough to establish safe assignment behavior,
because its live schema and policies were not independently confirmed and its
documented purpose is restricted-test access.

## 8. Permission model

The client exposes existing test-management permissions such as
`CREATE_TEST`, `EDIT_TEST`, `PUBLISH_TEST`, and `SCHEDULE_TEST`. No explicit
assignment permission was found. The product must decide whether assignment
uses an existing permission or introduces a new permission and role seed.

## 9. Notification integration

The notification security function recognizes `TEST_INVITATION` and
`GROUP_TEST_ASSIGNED` categories. The client notification payload supports
`test_id`, but the group notification screen routes only `group_test` to the
group tests screen. No trigger or end-to-end assignment notification flow was
found. The server-side notification producer and the intended client route
must be specified before implementation.

## 10. Assignment lifecycle

No lifecycle is implemented. Pending/accepted/declined values exist in the
historical `test_invitations` table, but it is undefined whether R6 should:

1. create restricted-test invitations;
2. create a separate assignment record while preserving ordinary group access;
3. make assignment the only access path; or
4. treat assignment as notification-only.

These choices affect access, re-assignment, duplicate assignment, and test
visibility semantics.

## 11. Test-access behavior

The existing attempt entry path calls `fn_can_access_test` and applies group
membership/lifecycle checks. The local schema documentation describes
`test_invitations` as restricted-test access control, but the current Flutter
client does not integrate it. Making assignment-only access work would require
changing or extending the authoritative access contract and could affect
existing test entry, attempts, and results behavior. This lane did not make
that change.

## 12. Flutter UI flow

No assignment list, member selector, assignment action, assignment status,
empty/loading/error/retry state, route, or notification destination exists.
Existing group test management and manual test access were left unchanged.

## 13. Tests

No R6 tests were added because the required data and authorization contract is
not defined. Consequently, there are no verified tests for target validation,
duplicate taps, lifecycle transitions, cross-group protection, or test/access
isolation.

## 14. Analyze result

`flutter analyze` was attempted. It produced no output and remained active for
over 30 seconds before being stopped. Result: **BLOCKED-ENVIRONMENT**; no
clean analyze result is claimed.

## 15. APK result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` was
attempted. It produced no output and remained active for over 30 seconds
before being stopped. Result: **BLOCKED-ENVIRONMENT**; no APK success is
claimed.

## 16. Security tests

No live security test was run and no Supabase object was modified. In
particular, own-member, unauthorized-manager, cross-group, duplicate, and
removed-member assignment cases remain unverified.

## 17. Known limitations

- The assignment meaning is not defined against the existing test-access
  contract.
- The authorization permission is not defined.
- The live `test_invitations` schema/policies were not independently confirmed.
- Notification creation and routing are not an end-to-end R6 implementation.
- Flutter toolchain commands remain blocked by the existing process hang.

## 18. Migration instructions

None. Do not run a migration until the product decision and live-schema
postcheck define whether the existing table is the intended primitive or a new
additive assignment surface is required.

## 19. Rollback instructions

No implementation or database change exists to roll back. Remove this report
only if the project’s documentation policy requires it; no source rollback is
needed.

## 20. Manual verification steps

After the contract is decided, the implementation lane should verify at least:

1. authorized owner/leader/manager can select valid members in the same group;
2. non-authorized members, non-members, and cross-group users are rejected by
   the server;
3. duplicate taps are idempotent;
4. assignment status and notification delivery are server-backed;
5. assigned users can enter only when the decided lifecycle/access rules allow
   it;
6. test edits do not unexpectedly mutate assignment records, and assignment
   changes do not mutate test content;
7. ended, archived, removed-member, and retry/error states are covered;
8. the existing manual test creation and results/leaderboard flows regress
   cleanly.

## Stop reason

R6 requires stopping when assignment semantics, permission authority, or live
schema are ambiguous. Implementing now would require inventing a parallel
assignment model or silently changing `fn_can_access_test` behavior. Both are
outside the authorized implementation scope.

## Final verdict

**BLOCKED — PRODUCT DECISION**

The next decision must explicitly define whether assignment grants access,
which permission authorizes it, whether `test_invitations` is the intended
primitive, and how assignment notifications route. No R6 implementation or
commit was created.

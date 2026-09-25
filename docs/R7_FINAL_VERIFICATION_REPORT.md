# R7 Final Question Bank Verification Report

Date: 2026-09-20  
Reference: `ec8f5a0`  
Builder commits: `fb717bb` backend, `dde8248` Flutter

## R7 STATUS

**BLOCKED**

## Repository truth

The previously missing R7 commits are present in the current history:

- `fb717bb feat(r7): implement question bank v1`
- `dde8248 feat(r7): implement question bank v1`

The backend commit adds `migrations/R7_QUESTION_BANK_V1.sql`, a separate
`R7_FIX_rpc_create_question_status_cast.sql`, precheck/postcheck/rollback
documentation, and a backend contract. The Flutter commit adds the question
bank model/repository/controller/screens/widgets, test-creation integration,
and `test/r7/question_bank_controller_test.dart`.

No R7 migration is present on the current working tree outside the committed
builder history. Existing unrelated modifications and untracked files were
preserved.

## Live backend

No new live read-only database query was available in this verification. The
builder commit contains claimed live evidence, but that is repository text and
is not independently treated as live proof.

Therefore current live columns, constraints, indexes, RLS policies, grants,
views, function signatures/bodies, `search_path`, SECURITY DEFINER flags, and
EXECUTE privileges are **UNVERIFIED** in this lane.

## Architecture

The builder selected the live `public.question_bank` architecture (Option B)
and kept `public.questions` as test-linked snapshots. This avoids creating a
second bank table and is consistent with the builder’s claimed live discovery.
The architecture is not independently live-verified here.

## Migration

The migration is owner-apply-only and was not applied by this lane. It adds
server functions for listing, detail, cloning, and availability, plus helper
functions. It also includes a separate cast fix for `rpc_create_question`.

## RPC security review

The migration’s new functions declare `SECURITY DEFINER` and
`SET search_path TO ''`; it revokes `PUBLIC`/`anon` execution and grants the
new RPCs to `authenticated` and `service_role`.

However, the migration does not remove the existing authenticated direct
`SELECT`/`INSERT`/`UPDATE` grants on `public.question_bank`. Therefore the new
key-free RPCs do not by themselves establish answer-key protection against
direct PostgREST table access. This is a critical unresolved security issue.

## Answer-key security

The new list RPC omits `correct_option` as a named column, and the detail RPC
only appends it after an explicit permission check. But both paths return raw
`options` JSON. The migration does not sanitize option objects to remove
`is_correct` or equivalent embedded answer metadata.

The committed Flutter repository also contains unsafe paths:

- `list()` uses `select('*')` on `question_bank`;
- `getById()` uses `select('*')`;
- `checkDuplicates()` uses an unrestricted `select()`;
- `create()` directly inserts `correct_option` through PostgREST;
- `update()` directly updates `correct_option` and other bank fields;
- archive/restore use direct table updates.

Client-side model stripping is not a security boundary. These defects prevent
an answer-key security PASS.

## Snapshot

The committed clone function copies bank content by value into a new
test-linked `public.questions` row and retains only `bank_id` as provenance.
On repository inspection this is a plausible snapshot design, and later bank
edits should not mutate the copied row.

The required live fixture test was not independently executed in this lane.
Snapshot independence therefore remains **UNPROVEN**, not PASS.

## Authorization matrix

The migration checks authenticated identity, bank readability, target-test
creator/`EDIT_TEST`, approved/non-archived bank status, duplicate bank IDs,
and bounded batch size. This is repository evidence only.

Live behavior for owner, leader, moderator, member, non-member, anon,
cross-group IDs, forged test IDs, direct table access, archived rows, and
duplicate selection was not independently executed.

Result: **BLOCKED**.

## Pagination/performance

The list RPC bounds `p_limit` to 50 and uses server-side filters, offset, and
`updated_at DESC, id DESC` ordering. That is a reasonable bounded RPC design.

The Flutter repository still has a fallback count path that fetches every
matching `id` and counts rows in Dart. This violates the no-full-table-fetch
requirement whenever the RPC count fails. The client also retains direct table
query paths instead of using the secure RPC contract.

## Flutter integration

Question-source integration and R7 screens are present in `dde8248`. The
integration is not safe to accept until the repository stops direct bank table
reads/writes and uses only server-authorized APIs with sanitized responses.

No overlapping Flutter files were modified by this audit.

## Tests

`flutter test test/r7/question_bank_controller_test.dart` was attempted. It
produced no output and did not complete within the verification window; no
pass count is claimed.

The required live snapshot and authorization attack matrix were not run.

## Analyze

Not independently verified in this lane. The known Flutter toolchain/process
hang remains an environment blocker; no clean analyze result is claimed.

## APK

Not independently verified in this lane. No APK success is claimed.

## Exact changes made by Codex

Only this report was created:

- `docs/R7_FINAL_VERIFICATION_REPORT.md`

No R7 source, migration, Supabase object, R6 file, G20 file, or device
acceptance file was modified.

## Remaining blockers

1. Independently verify the live database read-only, including direct table
   grants and policies.
2. Revoke or otherwise close direct bank table access if it can expose answer
   keys; preserve legacy authoring through safe server APIs.
3. Sanitize `options` in all normal bank list/detail responses.
4. Replace Flutter direct `select('*')`, direct INSERT, and direct UPDATE paths
   with secure RPCs.
5. Remove the unbounded client-side count fallback.
6. Execute the temporary-fixture snapshot and full authorization attack matrix.
7. Re-run Flutter tests, analyze, and APK build in a functioning toolchain.

## Final remediation gate

The supplied remediation brief requires safe read-only live Supabase access
before changing grants, RLS, answer-key exposure, or RPC behavior. No such
verified live channel is available in this environment, so no security
remediation was applied or claimed.

Toolchain diagnosis also reproduced the environment blocker: `flutter
--version` produced no stdout/stderr for 10 seconds and was terminated with
exit code 1. No migration, Flutter source, or backend security behavior was
changed during this remediation attempt.

## Final verdict

**BLOCKED** — critical answer-key/direct-table exposure remains possible in the
committed client/backend contract, live security was not independently proven,
and snapshot/authorization gates were not executed.

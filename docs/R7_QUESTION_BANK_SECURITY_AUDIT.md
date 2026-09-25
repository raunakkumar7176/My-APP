# R7 Question Bank Security Audit

Date: 2026-09-20  
Role: Independent backend/security verifier  
Reference backend: `ec8f5a0`

## 1. Discovery

The R7 discovery premise does not match this repository checkout.

- No `question_bank` table, migration, RPC, view, model, or Flutter repository
  was found.
- No migration numbered `0045` was found.
- The local architecture uses `public.questions` for both reusable rows
  (`test_id IS NULL`) and test-linked rows (`test_id IS NOT NULL`).
- `questions.bank_id` and `questions.source_batch` are passed through existing
  test-question RPCs, but no local bank table or bank-management RPC exists.
- Existing repository audits mark the live `question_bank` shape as unknown and
  several live RLS/function details as unverified.

This is an architecture mismatch, not a safe basis for implementing R7.

## 2. Live schema findings

No live database query was performed in this lane. The repository contains
historical live-verification reports, but they explicitly distinguish
repository evidence from live evidence and do not establish a current
`question_bank` schema. No migration was applied.

The local foundation migration defines `public.questions` with content,
answer-key fields, `created_by`, optional `test_id`, lifecycle metadata, and
`options` JSON. The later question-write migration references additional live
columns such as `ordinal`, `question`, `correct_option`, `status`, `bank_id`,
and `source_batch`; those definitions are not consistently present in the
foundation migration. This is a material schema-drift warning.

## 3. Existing architecture

The current test path uses:

- `rpc_create_question` to create a question attached to a test;
- `rpc_update_question` for question edits/status changes;
- `rpc_delete_question` for delete/archive behavior;
- `rpc_publish_test` for publication validation;
- `get_test_questions_safe` for participant-safe retrieval;
- the `questions_safe` view in the original foundation design.

The Flutter client does not perform a direct `public.questions` read on the
active test-taking path and uses safe RPCs for participant question retrieval.

## 4. RLS audit

R7 bank-specific RLS cannot be audited because no bank table exists in the
checkout and no current live policy text was supplied. The original local
foundation migration defines policies/views for `questions`, but later RPC
migrations supersede parts of that design and the actual live policy set is
not established here.

Therefore these cases remain unproven: unauthorized enumeration, personal
question isolation, group isolation, cross-group ID guessing, and direct-table
bypass of answer protection.

## 5. RPC/function audit

The existing question-write RPCs are `SECURITY DEFINER` and declare
`SET search_path TO ''` in the local migration bodies. They perform an auth
lookup and call the existing question-management permission helper. Their
grants are intended for `authenticated`, with `PUBLIC` and `anon` revoked.

This is repository evidence only. It does not prove the current live function
bodies, overload set, grants, or search paths. No new RPC was created.

## 6. Permission matrix

The repository exposes `GENERATE_QUESTIONS`, `REVIEW_QUESTIONS`, `CREATE_TEST`,
and `EDIT_TEST` in the group permission model. It does not expose a distinct
question-bank permission or a bank-specific authorization contract.

| Actor | List/search/detail | Create/edit/review/archive | Select into test | View answer key |
|---|---|---|---|---|
| Owner | Not established for a bank | Not established for a bank | Not established for a bank | Must remain server-only |
| Leader | Not established for a bank | Existing test permissions only | Not established for a bank | Must remain server-only |
| Moderator | Not established for a bank | Not established for a bank | Not established for a bank | Must remain server-only |
| Member | No bank contract found | No bank contract found | No bank contract found | Deny |
| Non-member | Must deny, unverified for a bank | Must deny, unverified for a bank | Must deny, unverified for a bank | Deny |
| Anon | Must deny | Must deny | Must deny | Deny |

No new permission is proposed because the underlying bank model is absent.

## 7. Answer-key protection

The local `questions_safe` view strips `is_correct` from option objects, and
the test-taking contract uses `get_test_questions_safe`, which is documented
to omit `correct_option`. The participant path therefore has a strong
repository-level answer-key design.

However, a complete R7 verdict is blocked because the current live view/RPC
definitions and direct-table grants were not independently confirmed. No
correct answer is returned by any new code in this audit.

## 8. Question-to-test snapshot proof

Historical independence cannot be proven from this checkout.

The local foundation design treats `questions` as reusable or test-specific
rows, and existing `rpc_create_question` inserts a question directly with a
`test_id`. The repository does not contain a bank-selection RPC that copies a
bank row into an immutable test snapshot. `bank_id` is only a metadata field in
the available write signatures; it does not prove copy semantics.

Because there is no `question_bank` implementation or verified live function
body showing a copy operation, R7 cannot safely claim that changing a bank
question cannot mutate historical test content.

## 9. Attack matrix

| Attack | Result |
|---|---|
| Unauthorized bank list/detail | BLOCKED — no bank surface to test |
| Unauthorized create/edit/archive | BLOCKED — no bank surface to test |
| Cross-group access | BLOCKED — bank scope undefined |
| Forged owner/group | BLOCKED — bank RPC absent |
| Correct-answer leak | REPO-DESIGN PASS, live grants/RPCs unverified |
| Direct RPC bypass | BLOCKED — no bank RPC |
| Cross-group test selection | BLOCKED — selection RPC absent |
| Archived question selection | BLOCKED — bank lifecycle absent |
| Historical independence | BLOCKED — snapshot copy path absent |
| Anon access | REPO-DESIGN INTENT, live grants unverified |
| Duplicate/idempotency behavior | BLOCKED — bank operation absent |

No live attack calls were made and no test data was modified.

## 10. Migration required/not required

No migration was created or applied. A migration decision cannot be made until
the intended R7 architecture is restored or explicitly defined. Adding a new
bank table or changing `public.questions` now would risk creating a duplicate
question system and conflict with the Free Agent Flutter lane.

## 11. Exact files changed

Only this report was added:

- `docs/R7_QUESTION_BANK_SECURITY_AUDIT.md`

No Flutter files, SQL migrations, permissions, grants, or unrelated files were
changed.

## 12. Remaining risks

1. The claimed `question_bank` architecture is absent from this checkout.
2. The live schema may differ materially from repository migrations.
3. `bank_id`/`source_batch` metadata does not establish snapshot semantics.
4. Live RLS, grants, SECURITY DEFINER bodies, and search paths require a safe
   read-only postcheck.
5. A bank-specific authorization and lifecycle contract is undefined.
6. The client lane may be implementing against a contract not present here.

## 13. Verification commands/results

Repository searches were run for `question_bank`, `bank_id`, `source_batch`,
question RPCs, permission names, RLS-related SQL, and audit-log references.
They found the existing `public.questions`/test-question system but no
question-bank implementation.

No Supabase migration was run. No live database verification was claimed.
Flutter analyze/test/build were not run because this is a backend/security
architecture gate and the existing environment has the previously documented
Flutter process hang.

## Final verdict

**BLOCKED — ARCHITECTURE**

The R7 question-bank security audit cannot establish a safe verdict because the
question-bank implementation described by the brief is absent and the existing
`public.questions`/`bank_id` design does not prove immutable bank-to-test
snapshots. Restore or define the authoritative backend contract, then perform
a read-only live schema/RLS/grant/function postcheck before implementing or
hardening R7.

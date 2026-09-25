# R7 Final Question Bank Security Audit

Date: 2026-09-20  
Reference: `ec8f5a0` and claimed Claude R7 implementation  
Role: Independent backend/security verifier

## Verdict

**BLOCKED**

The claimed R7 backend commit is not present in Git history, no R7 migration
exists in `migrations/`, and the visible R7 implementation is an untracked
Flutter/client layer that calls a nonexistent local backend surface. Live
schema and security verification was therefore not claimed.

## 1. Actual implementation and diff

Git history contains no R7 implementation commit or commit message matching
the claimed builder work. `HEAD` is `8483a01` (G19). The R7-related files are
untracked, including:

- `lib/core/models/question_bank_item.dart`;
- `lib/features/test/data/question_bank_repository.dart`;
- `lib/features/test/screens/question_bank_screen.dart`;
- `lib/features/test/screens/question_bank_detail_screen.dart`;
- `lib/features/test/state/question_bank_controller.dart`;
- question-bank widgets and `test/r7/question_bank_controller_test.dart`.

No R7 SQL migration or backend function was found.

The client directly references `question_bank` and `rpc_clone_bank_questions`.
Those objects are absent from the local migrations. This is not a verified
backend implementation.

The R7 client files are not modified by this audit. Existing unrelated and
Free Agent changes were preserved.

## 2. Architecture conclusion

The existing repository architecture uses `public.questions`, including
reusable rows represented by `test_id IS NULL`, and test-linked rows. The R7
client instead assumes a separate `question_bank` table. That contradicts the
authoritative recovery findings and reintroduces the duplicate-system risk.

The existing `public.questions` architecture was not reused by the visible R7
client implementation.

## 3. Live read-only verification

Not completed. No safe read-only live database result was available in this
lane, so the following are **UNVERIFIED** and are not inferred from local SQL:

- `questions` columns, constraints, indexes, and foreign keys;
- RLS enablement and policy definitions;
- table/view/function grants;
- live views and definitions;
- function signatures and bodies;
- `search_path`, `SECURITY DEFINER`, and EXECUTE privileges.

No credentials were exposed and no migration or production database change was
performed.

## 4. Snapshot security — primary gate

The required server-side create → select → edit-bank → compare-test snapshot
test could not run because no verified bank table or selection RPC exists in
the checkout. The client calls `rpc_clone_bank_questions`, but no local
definition proves that it copies content into independent `public.questions`
rows.

Result: **BLOCKED**. Snapshot independence is not proven.

## 5. Authorization attack matrix

| Operation / attack | Result |
|---|---|
| Owner list/detail/create/edit/archive/select | BLOCKED — backend absent |
| Leader authorization | BLOCKED — live permission path absent |
| Moderator authorization | BLOCKED — live permission path absent |
| Member denial | BLOCKED — live RLS absent |
| Non-member denial | BLOCKED — live RLS absent |
| Anonymous denial | BLOCKED — live grants absent |
| Cross-group ID guessing | BLOCKED — no verified bank surface |
| Forged target test/owner/group | BLOCKED — selection RPC absent |
| Duplicate selection/repeated request | BLOCKED — RPC absent |
| Archived/deleted/invalid question | BLOCKED — lifecycle backend absent |
| Unauthorized direct RPC | BLOCKED — RPC absent |
| Direct table read | BLOCKED — grants/RLS unverified |
| Answer-key extraction | **CRITICAL FINDING** in client contract; see below |

No live attack calls were made and no permanent test rows were created.

## 6. Answer-key audit

The visible repository violates the required safe boundary in multiple ways:

1. `list()` selects `*` from `question_bank`.
2. `getById()` selects `*` from `question_bank`.
3. `checkDuplicates()` selects all columns from `question_bank`.
4. `create()` and `update()` write `correct_option` directly through PostgREST
   rather than a verified security RPC.
5. The model includes an optional `correctOption`, and the client contract
   states that permitted users may receive it; no live server proof limits
   that exposure to an appropriate reviewer path.

The safe model copy is not sufficient: answer-key protection must be enforced
by server-side views/RPCs and grants, not by Flutter parsing or field hiding.

Existing participant code is documented to use `get_test_questions_safe`, but
live verification of that path was not performed.

## 7. Performance audit

The visible client applies filters and a range for the primary list, but its
count path fetches all matching IDs and counts them in Dart. This violates the
bounded/server-side count requirement for large banks. Stable ordering is
present as `created_at DESC`, but no unique tie-breaker was shown.

Result: **FAIL for the visible client contract; backend pagination remains
unverified.**

## 8. Legacy regression

No regression run can prove the R7 backend because no backend commit or live
surface was identified. Existing R4 paths were not changed by this audit, but
compatibility is not independently verified here for:

- `rpc_create_question`;
- `rpc_update_question`;
- `rpc_delete_question`;
- `rpc_publish_test`;
- `get_test_questions_safe`;
- scoring and test access.

## 9. Critical findings

- Claimed Claude R7 backend commit is absent from Git history.
- No R7 migration/backend RPC exists locally.
- Visible client assumes a separate `question_bank` system, conflicting with
  the recovered `public.questions` architecture.
- Direct `select *` can expose answer-key columns if the assumed table exists.
- Direct client INSERT/UPDATE of answer keys bypasses the required verified RPC
  security boundary.
- Count fallback loads all matching IDs into client memory.
- Snapshot independence cannot be established.

## 10. Files changed

Only this audit report was created:

- `docs/R7_QUESTION_BANK_FINAL_SECURITY_AUDIT.md`

No R7 client files, SQL migrations, Supabase objects, R6 files, G20 files, or
device-acceptance files were changed.

## 11. Migration status

No migration was created or applied. The necessary remediation must be decided
by the R7 backend builder after restoring the authoritative architecture and
performing live read-only inspection. This audit does not implement overlapping
features.

## 12. Required blockers before PASS

1. Identify and provide the actual Claude R7 backend commit.
2. Reconcile the client’s `question_bank` assumption with the recovered
   `public.questions` architecture.
3. Add or verify a server-side snapshot-selection operation.
4. Replace direct `select *`/writes with safe, authorized server APIs.
5. Prove live RLS, grants, function security, and answer-key exclusion.
6. Use bounded server-side count/pagination with stable ordering.
7. Run the full snapshot and authorization attack matrix in a rolled-back or
   fixture-isolated environment.

## Final result

**BLOCKED** — architecture, backend availability, answer-key boundary, live
verification, snapshot independence, and performance requirements are not
proven.

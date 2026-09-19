# G10.2 — B2 Fix: Group Test Direct-UPDATE Lifecycle Guard

**Branch:** `r4-restart` · **Base:** `d304ef4` (G10 audit) · **Commit:** `__COMMIT__` · **Date:** 2026-09-19
**Scope:** B2 only. G10.1 (B1, `rpc_create_test`) is already applied live (`has_fix = true`, verified by the owner).

## FINAL STATUS

**BLOCKED — PRODUCT DECISION REQUIRED** (and, once decided, **OWNER APPLY REQUIRED**)

The fix is designed, drafted (`migrations/G10_2_fix_group_edit_test_policy.sql`), and **proven in a rolled-back transaction**: every B2 attack fails and every secure RPC / the sweep / archive keeps working; the live database is unchanged. It is **not applied**, for two reasons:

1. **Product semantics:** the live UPDATE policies are exactly what the **legacy Next.js web app** relies on — `My-Prepration/src/app/(app)/tests/[id]/lifecycle-actions.ts` sets `status = 'ready' | 'scheduled' | 'live' | 'cancelled' | 'archived'` by **direct UPDATE as the signed-in user** (`publishTestAction`, `scheduleTestActionV2`, `startNowAction`, `cancelTestActionV2`, `archiveTestAction`). With the guard those actions raise `LIFECYCLE_LOCKED` (proven, row `LEGACY`). The Flutter app is unaffected (every transition goes through the RPCs). Whether the legacy web app is still in use is a product decision the task forbids me to make silently.
2. **Production safety:** this session is not authorized to mutate production (the G8.1 apply was classifier-blocked); the owner applies migrations in the SQL Editor.

---

## 1. Live pre-check (read-only, actual grids)

- **UPDATE policies on `public.tests`** (both `{authenticated}`): `group edit test` — USING/CHECK `group_id IS NOT NULL AND fn_has_permission(group_id, auth.uid(), 'EDIT_TEST')`; `standalone owner update test` — USING/CHECK `group_id IS NULL AND created_by = auth.uid()`. **No column restriction on either.**
- **UPDATE grants:** `anon`, `authenticated`, `postgres`, `service_role` (anon inert: no policy targets it — proven test 8).
- **Triggers on `tests`:** `trg_group_test_notify`, `trg_set_access_code`, `trg_set_join_code`, `trg_test_chat_pin` — no lifecycle guard exists (`trigger_exists=false`, `fn_exists=false`).
- **Lifecycle functions:** `rpc_update_test`, `rpc_publish_test`, `rpc_create_test` (now with the G10.1 CREATE_TEST check), `rpc_delete_test`, `fn_soft_delete_test`, `fn_sweep_deadlines`, `_fn_validate_test_timing` — **all SECURITY DEFINER, owner `postgres`** (so inside them `current_user = postgres`).
- **What EDIT_TEST permits live:** any column of any group test, in any status, by direct UPDATE — including `status`, `created_by`, `group_id`, `is_soft_deleted`. The RPCs themselves never consult EDIT_TEST (creator-only). So "EDIT_TEST = direct content editing by managers, RPC lifecycle by the creator" is the de-facto architecture; the legacy web app additionally used direct UPDATE for lifecycle (with app-layer validation only).
- `test_status` enum: draft, published, scheduled, live, completed, cancelled, ready, ended, evaluated, archived, expired. `questions` NOT NULL columns without default: `test_id, ordinal, question, options, correct_option`.

## 2. B2 exploit reproduction (before fix, rolled back)

Fixtures inside the transaction: B added as **leader** of group "Nn" (EDIT_TEST seeded), C as member, a draft created by the owner A.

| | Attack (B, EDIT_TEST, not creator) | Result before fix |
|---|---|---|
| B2-repro | `UPDATE tests SET status='published' WHERE id=<A's draft>` | **1 row updated** — published with 0 approved questions, no `rpc_publish_test` validation |
| B2-repro-owner | `UPDATE tests SET created_by=<B>` | **1 row updated** — ownership taken |

## 3. Chosen design and why

**Option B — `BEFORE UPDATE` guard trigger `trg_guard_test_lifecycle` → `fn_guard_test_lifecycle()`** (plpgsql, `SET search_path TO ''`, **not** SECURITY DEFINER, EXECUTE granted to client roles).

- Fires only when `current_user IN ('authenticated','anon')` — i.e. direct client UPDATEs. The definer RPCs, the cron sweep and `service_role` run as `postgres`/`service_role` and are exempt, so **no existing secure path changes**.
- Raises on any change to `status` (`LIFECYCLE_LOCKED`), `created_by` (`OWNERSHIP_LOCKED`), `group_id` / `test_mode` (`GROUP_LOCKED`), `is_soft_deleted` / `deleted_at` / `deleted_by` / `deletion_reason` / `archived_at` (`DELETE_LOCKED`).
- Re-applies the live timing rule inline (`ends_at > starts_at`) to direct window edits, so schedule validation cannot be bypassed.
- Keeps every other column editable exactly as today (least privilege, additive — **no policy or grant is modified**).

Option A (narrowing the policies) was rejected: RLS `WITH CHECK` cannot express "same row, only these columns", so it would have to remove direct editing entirely — a larger semantic change than necessary and still not column-precise. A `BEFORE UPDATE` guard is the smallest change that closes exactly the reported gap.

## 4. Migration

`migrations/G10_2_fix_group_edit_test_policy.sql` — `CREATE OR REPLACE FUNCTION public.fn_guard_test_lifecycle()`, `GRANT EXECUTE … TO authenticated, anon, service_role`, `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER trg_guard_test_lifecycle BEFORE UPDATE ON public.tests FOR EACH ROW`, read-only postflight. Plain `$$`, no DO/dynamic SQL, idempotent. Rollback: drop trigger + function. Pre/post-check: `docs/G10_2_PRECHECK.sql`, `docs/G10_2_POSTCHECK.sql` (pre-check executed live: all as expected).

## 5. Post-fix security results (guard applied inside a transaction, then ROLLED BACK — live unchanged: `guard live=false`, residue 0)

| # | Requirement | Result |
|---|---|---|
| 1 | EDIT_TEST holder cannot set `status='published'` | **blocked** `LIFECYCLE_LOCKED` ✓ (also scheduled / live / completed / ended / evaluated / cancelled) |
| 2 | cannot bypass scheduling validation (`ends_at < starts_at`) | **blocked** `VALIDATION_ERROR: ends_at must be after starts_at` ✓ |
| 3 | cannot change `created_by` | **blocked** `OWNERSHIP_LOCKED` ✓ |
| 4 | cannot change `group_id` | **blocked** `GROUP_LOCKED` ✓ |
| 5 | cannot bypass archive/delete rules (`is_soft_deleted`) | **blocked** `DELETE_LOCKED` ✓ — content edit (title) of another creator's draft still allowed (existing EDIT_TEST capability kept) |
| 6 | cross-group update | 0 rows ✓ |
| 7 | non-member update | 0 rows ✓ |
| 8 | anon update | 0 rows ✓ |

## 6. RPC regression (same transaction)

| # | Path | Result |
|---|---|---|
| 9 | `rpc_update_test` by creator | ok ✓ |
| 10 | `rpc_publish_test` by creator (draft with 1 approved question) | `status: published` ✓ |
| 11 | scheduling via `rpc_update_test` (valid window) | ok ✓ |
| 12 | `fn_soft_delete_test` by owner → archived + soft-deleted | ok ✓; `rpc_delete_test` on a published test still `TEST_NOT_DRAFT` ✓ |
| 12c | `fn_sweep_deadlines()` (owner role) | ok ✓ |
| 13 | attempts row inserted/read unaffected (trigger is on `tests` only) | ✓ |
| 14 | `questions` still `permission denied` to members | ✓ |

## 7. R4 / G8 regression

No Flutter change. Full suite (G1–G8, G10, R4) green; the G8 chat, announcement and rules paths do not touch `tests`. The guard exempts the definer functions R4 uses, so `rpc_start_attempt` / results / batches are unaffected.

## 8. Flutter analyze / test / APK (HEAD, unchanged code)

`flutter analyze` → 0 errors / 0 warnings (70 info lints) · `flutter test` → **795 passed** · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built**.

## 9. Commit

`__COMMIT__` — migration + PRECHECK + POSTCHECK + this report only. G9's uncommitted work (one doc-comment line in `group_hub_screen.dart`) and the other agent's on-disk rewrite of `docs/G10_GROUP_TEST_MANAGEMENT_VERIFICATION_REPORT.md` were left untouched and uncommitted (HEAD keeps `d304ef4`'s version).

## 10. Decision needed, then apply

- **If the legacy Next.js web app is retired or its lifecycle actions may break:** apply `migrations/G10_2_fix_group_edit_test_policy.sql` in the SQL Editor (postflight: `trigger_present=true`), run `docs/G10_2_POSTCHECK.sql`, tell me "G10.2 applied" — I re-run the 26-check script live (it is rolled back) and close B2 → G10 becomes PASS-eligible (B3, the G9 precondition, remains).
- **If the legacy web app must keep working:** the alternative is to port its five lifecycle actions to the RPCs (or new definer RPCs for schedule/cancel/archive) first, then apply the guard. Not started — out of G10.2 scope.

**FINAL STATUS: BLOCKED — PRODUCT DECISION REQUIRED**

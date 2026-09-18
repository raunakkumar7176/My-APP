# G6 — Group Rules: Verification Report (auditor)

**Audited commit:** `5852481` (branch `r4-restart`, working tree clean except the untracked, pre-existing `docs/G5_8_FINAL_LIFECYCLE_HARDENING_REPORT.md`).
**Audit date:** 2026-09-18.

## Final status

**G6 BLOCKED — REQUIRED FIXES**

## Blocker (exact)

**There is no G6 implementation to audit.** Searched the repository, all local and remote branches (`r4-restart`, `master`, `origin/*`), stashes and commit history:

| Looked for | Result |
|---|---|
| Migration `migrations/G6*` / anything named `*rule*` | none |
| Flutter files matching `*rule*` under `lib/`, `test/` | none |
| Code referencing `group_rules` / `GroupRule` | none (the single textual hit is the phrase "Access rule" in a doc comment of `group_hub_controller.dart`, written in G1) |
| Report `docs/G6*` | none |
| Commit mentioning G6 / rules on any branch | none |
| Any `rules` table or column in the migration set that built the live DB (`My-Prepration/supabase`) | none — the G0 audit already recorded "no rules column" on `groups` |

Consequently none of sections 1–5 of the requested audit can produce evidence: there is no scope to confirm, no schema/RLS/function to inspect, no permission usage to check, no Flutter code to read, and no attack case to simulate. Marking anything as verified would be fabricating evidence.

## What is verified (unchanged baseline)

- **CODE VERIFIED / regression:** the tree at `5852481` is the G5.7-verified state — `flutter analyze` 0 errors / 0 warnings, `flutter test` 690 passed (G1–G5.6, G3, R4 suites green), debug APK built. Nothing in this audit changed code.
- **DATABASE VERIFIED (prior phases):** through G5.6 as recorded in their reports.
- **NOT VERIFIED:** `fn_withdraw_join_request` (G5.7) — its live postflight was never pasted back; the G5.7 report is still "BLOCKED — live RPC verification pending" and the G5.8 report is still "BLOCKED". G6's regression item "G5.7 existing live RPC must remain intact" therefore has no baseline to compare against.

## Smallest corrective action

The builder must deliver G6 before it can be audited. The minimum set, consistent with the Group Hub architecture and the standing rules (no speculative schema, live DB authoritative, SQL only via owner-applied migration):

1. `migrations/G6_group_rules.sql` — one additive migration: `public.group_rules(id uuid PK, group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE, title text, body text, position int, created_by uuid REFERENCES public.profiles(id), created_at, updated_at)`; RLS enabled; policies SELECT `public.fn_is_member(group_id, auth.uid())`, INSERT/UPDATE/DELETE `public.fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS') OR public.fn_get_group_role(group_id, auth.uid()) = 'owner'` on **both** USING and WITH CHECK (no new `app_permission` value unless justified — `GROUP_SETTINGS` is the existing "group configuration" permission); grants to `authenticated` only; postflight last statement. Plain `$$`, no DO/dynamic SQL.
2. Live inspection query (read-only, one grid) for the table, policies, grants and RLS flags, to be run by the owner after applying.
3. Flutter on the existing layers only: `lib/core/models/group_rule.dart`; repository methods on the single `GroupRepository` (`rules(groupId)`, `createRule`, `updateRule`, `deleteRule` — exact `group_id` / `id` filters, no RPC needed); a rules section on the Group Hub gated by `permissions.canEditSettings || isOwner` for mutations (UX only), member-readable; loading/empty/error/mutation states; single-flight; server re-read after each mutation; delete confirmation; input validation.
4. `test/group/group_rules_test.dart` with fakes mirroring the policies above (member read, non-member denied, member mutations denied, manager mutations allowed, cross-group forged id has no effect, empty/loading/error/refresh).
5. `docs/G6_GROUP_RULES_REPORT.md`.

Then request this audit again. Until the artefacts exist, **STOP** — no G7.

## Known limitations of this audit

- No live database access from this environment; live checks in any future G6 audit will rely on owner-run read-only grids, as in every prior phase.
- G5.7/G5.8 closure evidence is still outstanding and is independent of G6.

# G6 — Group Rules: Verification Report (auditor)

**Audited state:** commit `2fe790a` plus the Free AI Agent's **uncommitted** G6 working-tree changes (audit date 2026-09-19):
`migrations/G6_group_rules.sql`, `lib/core/models/group_rule.dart`, `lib/features/group/state/group_rules_controller.dart`, `lib/features/group/widgets/group_rules_section.dart`, `test/group/group_rules_test.dart` (new); `group_repository.dart`, `group_hub_controller.dart`, `group_hub_screen.dart`, `test/group/fakes.dart` (modified). No `docs/G6_GROUP_RULES_REPORT.md` was delivered.

## Final status

**G6 BLOCKED — REQUIRED FIXES**

## Blockers (exact)

### B1 — The delivered code does not compile (`flutter analyze`: 18 errors; `flutter test`: suite fails to load)
- `lib/features/group/screens/group_hub_screen.dart:217-219` passes `hubController:` / `rulesController:` to `GroupRulesSection`, whose constructor declares only `required this.controller` (`group_rules_section.dart:12-16`).
- `group_rules_section.dart:160,165,202,209,236,243` reference an undefined identifier `rulesController`.
- `test/group/group_rules_test.dart:6-16` imports a non-existent `../auth/fakes.dart` and uses undefined `FakeAuthService` / `FakeGroupRepository`; lines 55-56 use `const` with non-const constructors.
- `test/group/group_core_test.dart:656` — `_FailingRepository` lacks the four new `GroupRepository` members (`groupRules`, `createRule`, `updateRule`, `deleteRule`).
- Consequence: **every** test in the project is currently unrunnable (the group test files fail to compile), so the regression audit for G1–G5.7 and R4 cannot be executed either. The last green baseline is `2fe790a` (690 tests).

**Smallest corrective action:** in `group_hub_screen.dart` pass `controller: _c` (the section already reads `controller` of type `GroupHubController`); in `group_rules_section.dart` replace every `rulesController` with `controller` (all rule state now lives on `GroupHubController`); in `group_rules_test.dart` import `fakes.dart` and use `InMemoryGroupRepository` / `GroupHubController` (drop `FakeAuthService`, drop the two `const`s); add the four stubs to `_FailingRepository`; run `flutter analyze` to zero errors.

### B2 — Tests do not exercise any security boundary
`test/group/fakes.dart`'s rules methods mirror **no** policy: `groupRules` returns rows for anyone (no `fn_is_member` check), `createRule` / `updateRule` / `deleteRule` check no permission at all (and invent a duplicate-content rule the server does not have). `group_rules_test.dart` contains no widget test and no denied case. Of the required attack simulations (TEST 1–11) **none** is covered; the audit criterion "important security/functionality paths are actually tested" fails.

**Smallest corrective action:** in the fake, gate `groupRules` on `groups[groupId].roles.containsKey(currentUser)` and the three mutations on `hasPermission(groupId, GroupPermission.manageMembers)` (throw `_notAuthorized(GroupErrorContext.update)`; for update/delete of a non-visible id throw the repository's "could not be updated/deleted" message); remove the invented duplicate check. Add tests: member reads (T1); non-member gets nothing (T2); member create/update/delete refused and nothing changes (T3–T5); manager create/update/delete succeed and re-read (T6–T8); forged rule id from another group leaves that group untouched (T9); one widget test proving `add_rule_button` / `edit_rule_*` / `delete_rule_*` appear only when `canManageMembers` and that delete requires `confirm_delete_rule` (T11 UI half).

### B3 — Duplicate architecture: `GroupRulesController` is dead code
`lib/features/group/state/group_rules_controller.dart` (164 lines) duplicates, line for line, the rules state and mutations that were also added to `GroupHubController`; the hub and the section use the hub controller, so the class is referenced only by its own (non-compiling) tests.

**Smallest corrective action:** delete `group_rules_controller.dart` and its test group; keep the `GroupHubController` implementation (one roster/permission source, one refresh).

## BACKEND PENDING
No live evidence for `public.group_rules` was supplied (no postflight, no inspection grid). Nothing in the migration is fabricated as applied. **DATABASE: NOT VERIFIED. END-TO-END: NOT VERIFIED.**

## Migration review (CODE VERIFIED — the SQL itself is sound)
`create table if not exists public.group_rules(id uuid PK default gen_random_uuid(), group_id uuid NOT NULL → groups ON DELETE CASCADE, content text NOT NULL CHECK 1..2000, position int NOT NULL DEFAULT 0, created_at, updated_at)`; index `(group_id, position)`; RLS enabled; SELECT `fn_is_member(group_id, auth.uid())`; INSERT (WITH CHECK) / UPDATE (USING + WITH CHECK) / DELETE (USING) all `fn_has_permission(group_id, auth.uid(), 'MANAGE_MEMBERS')`; grants to `authenticated, service_role` only (no anon); `updated_at` trigger; `begin/commit`; postflight prints `rls_enabled` and `policy_count`.
- A–I evaluated on the policy text: member read ✓; non-member denied ✓ (no `privacy='public'` branch on rules — private rules stay private); member insert/update/delete denied ✓ (MANAGE_MEMBERS not seeded for `member`/`moderator`); manager mutations ✓ (leader seeded, owner via `fn_has_permission` bypass); cross-group forged id: UPDATE/DELETE `USING` is evaluated on the *existing* row's `group_id`, and UPDATE `WITH CHECK` on the new one, so re-pointing a rule to another group needs MANAGE_MEMBERS on both ✓; no recursion (`fn_is_member` / `fn_has_permission` are DEFINER) ✓; no anon ✓; J — no service-role key in `lib/` ✓ (`dart-defines.dev.json`, anon key only).
- Permission engine: reuses `app_permission` value `MANAGE_MEMBERS`; no new enum value, no `role_permissions` change; owner behaviour comes from `fn_has_permission`.

## Non-blocking warnings
- W1 Permission semantics: rules are group *configuration*; the existing `GROUP_SETTINGS` permission (owner-only unless granted) arguably fits better than `MANAGE_MEMBERS` (grants every leader rule edit). A product decision, not a security defect — record it either way.
- W2 `fn_touch_group_rule_updated_at()` has no `SET search_path` (Supabase lint "function_search_path_mutable"). Add `SET search_path = ''` (uses only `now()`).
- W3 `createRule` computes `position` client-side (read max, then insert) — a benign race that can duplicate positions; ordering falls back to `created_at`.
- W4 Postflight is thin (RLS flag + policy count); the inspection grid should print policy expressions and grants when the owner applies it.
- W5 `unnecessary_cast` at `group_repository.dart:723`.
- W6 No builder report (`docs/G6_GROUP_RULES_REPORT.md`) was delivered.

## Flutter review (of what was delivered)
Model maps the six live columns, `position` null-safe, timestamps to local. Repository: exact `group_id` / `id` filters, no direct access outside `group_rules`, update/delete treat 0 affected rows as an error (RLS-denied rows read as "removed" — non-leaking). Hub controller: rules loaded for all members after the permission probe; create/update/delete single-flight (`_rulesSaving`, `_actingRuleId`, global `_busy`), empty-content validation, server re-read after success and failure, mapped errors, `DisposableNotifier`. Section: manager controls gated by `canManageMembers` (server-reported, no role names), loading/error+retry/empty states, `maxLength: 2000`, confirmation dialogs for add/edit/delete, `context.mounted` checks. These are correct **in intent** but unverifiable until B1 is fixed.

## Scope
Group Rules read/create/edit/delete, group scoping, states and refresh are all present in the code. No G7 (announcements) code exists — the only "announcement" hits are the pre-existing `SEND_ANNOUNCEMENT` enum value and a G1 doc comment.

## Regression / automated testing
- `flutter analyze`: **18 errors**, 1 warning (listed under B1/W5).
- `flutter test`: **suite fails to compile** — 0 results. Baseline before these uncommitted changes: 690 passed at `2fe790a`.
- APK: not attempted (would fail to compile).
- G5.7 live RPC: still no postflight evidence on record (G5.7/G5.8 reports remain BLOCKED); unrelated to G6's blockers.

## Known limitations
No live database access from this environment; DATABASE/END-TO-END verification will rely on owner-run read-only grids after the fixes and the migration are applied.

**STOP.** Return to the builder with B1–B3; re-request this audit afterwards.

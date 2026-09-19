# G6 — Group Rules: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `3125a27` (G6 audit: BLOCKED) · **Commit:** `4e9b355 (report hash added in the follow-up commit)` · **Date:** 2026-09-19

## FINAL STATUS

**G6 IMPLEMENTATION COMPLETE — BACKEND PENDING**

Flutter, tests, fakes, migration and pre/post-check SQL are delivered and verified locally (analyze 0 errors, 714/714 tests, debug APK built). The `public.group_rules` table does not exist live until the owner runs `migrations/G6_GROUP_RULES.sql` in the Supabase SQL Editor. **BACKEND MIGRATION: NOT APPLIED LIVE.** Nothing below claims live or device end-to-end evidence.

---

## 1. Live-schema evidence used (no new assumptions)

| Fact | Class | Source |
|---|---|---|
| No rules table/column/function/policy exists live | [LEGACY-SQL] + G0/G6 audits | `My-Prepration/supabase/migrations/0001..0051`, `docs/G6_GROUP_RULES_VERIFICATION_REPORT.md` |
| `groups(id uuid PK, …)`; `groups` UPDATE policy = `fn_has_permission(id, auth.uid(), 'GROUP_SETTINGS') OR owner` | [LIVE] | G3 live audit (closed, no migration) |
| `fn_is_member(uuid, uuid)`, `fn_has_permission(uuid, uuid, app_permission)`, `fn_get_group_role(uuid, uuid)` — all SECURITY DEFINER, `search_path=''`, STABLE | [LIVE] | G3 live audit |
| `app_permission` contains `GROUP_SETTINGS`; `role_permissions` seeds it for **no** role (owner only via the function's owner bypass) | [LIVE] | G3 live audit |
| `fn_has_permission` returns true for the owner without a `role_permissions` row | [LIVE] | G3 live audit |

No column, RPC or policy beyond these is assumed. The migration touches **no** existing object (no ALTER on `groups`, `group_members`, `role_permissions`, no enum change, no new permission value).

## 2. Migration — `migrations/G6_GROUP_RULES.sql` (PROPOSED, not executed)

- `CREATE TABLE IF NOT EXISTS public.group_rules (id uuid PK default gen_random_uuid(), group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE, rule_text text NOT NULL CHECK (char_length(btrim(rule_text)) BETWEEN 1 AND 2000), position integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now())`
- Index `idx_group_rules_group_position (group_id, position, created_at)`.
- RLS enabled; 4 policies, all `TO authenticated`:
  - `members read rules` SELECT — `USING public.fn_is_member(group_id, auth.uid())`
  - `settings holders insert rules` INSERT — `WITH CHECK fn_has_permission(group_id, auth.uid(), 'GROUP_SETTINGS') OR fn_get_group_role(group_id, auth.uid()) = 'owner'`
  - `settings holders update rules` UPDATE — same expression on **USING and WITH CHECK** (a rule cannot be re-pointed to a group the caller does not manage)
  - `settings holders delete rules` DELETE — same expression on USING
- `REVOKE ALL … FROM PUBLIC, anon`; `GRANT SELECT, INSERT, UPDATE, DELETE TO authenticated, service_role`.
- `fn_touch_group_rule_updated_at()` — plpgsql trigger function, **`SET search_path TO ''`**, not SECURITY DEFINER (not needed: it only sets `NEW.updated_at`). Trigger `trg_touch_group_rule BEFORE UPDATE`.
- `NOTIFY pgrst, 'reload schema'`; last statement is a read-only postflight grid.
- Plain single-level `$$`; no DO block, no dynamic SQL; idempotent (`IF NOT EXISTS`, `DROP POLICY IF EXISTS`, `CREATE OR REPLACE`); prose only in `--` comments. No `BEGIN/COMMIT` wrapper (the SQL Editor runs the batch atomically; the statements are idempotent either way).
- No recursion: every policy calls only the three SECURITY DEFINER functions; none reads `group_rules`.
- Why not SECURITY DEFINER RPCs: plain table access under RLS is sufficient — no cross-table write, no privilege escalation, no server-side sequencing beyond what a CHECK and a trigger provide. Adding definer functions would widen the surface for no gain.

**Pre-check:** `docs/G6_GROUP_RULES_PRECHECK.sql` — statement 1 proves the dependencies (groups table, the three functions with the right arity and SECURITY DEFINER, `GROUP_SETTINGS` enum label); statement 2 proves no G6 object exists yet.
**Post-check:** `docs/G6_GROUP_RULES_POSTCHECK.sql` — structure/grants grid (incl. `rule_text` NOT NULL, CHECK present, trigger fn `proconfig`), the 4 policy texts (`qual`/`with_check`), and the 6-column shape the model parses.

## 3. Permission model (existing engine only)

| Actor | Read | Create / Edit / Delete |
|---|---|---|
| Non-member | no rows | refused (RLS) |
| member / moderator | ✓ | refused (no GROUP_SETTINGS) |
| leader (10 seeded perms, **not** GROUP_SETTINGS) | ✓ | refused |
| any role with an explicit `role_permissions(GROUP_SETTINGS)` row | ✓ | ✓ |
| owner | ✓ | ✓ (function's owner bypass; also `fn_get_group_role = 'owner'`) |

Rules follow exactly the live `groups` UPDATE gate, so "who may change group settings may change group rules." No role name appears in Flutter or SQL policy logic beyond the owner check that the live `groups` policy already uses.

## 4. Flutter — files

| File | Change |
|---|---|
| `lib/core/models/group_rule.dart` (new, 67 l.) | `GroupRule{id, groupId, ruleText, position, createdAt, updatedAt}`; `fromJson` (`rule_text`; `position` null-safe; timestamps `toLocal()`), `toJson`, `copyWith`, `==`/`hashCode` on (id, ruleText, position). |
| `lib/features/group/data/group_repository.dart` | **Existing** repository extended (no second repository): `groupRules(groupId)` (select 6 columns, `eq group_id`, order position, created_at), `createRule({groupId, ruleText})` (max position + 1, insert trimmed), `updateRule({ruleId, ruleText})` (`update … eq id … select('id')`; 0 rows ⇒ `DataError` "could not be updated. It may have been removed."), `deleteRule(ruleId)` (same 0-row rule). All under `_guard(GroupErrorContext.load/update)`. Unnecessary cast (audit W5) removed. |
| `lib/features/group/state/group_hub_controller.dart` | Rules state on the **existing** hub controller: `rules`, `rulesLoading`, `rulesError`, `actingRuleId`, `rulesSaving`, `hasRules`; `_loadRules()` in `load()` for every member (a rules failure never blocks the hub); `retryRules()`; `createRule/updateRule/deleteRule` — UX pre-check `_ruleMutationAllowed()` (= `canEditBasics`, the existing `GROUP_SETTINGS ∨ owner` mirror), trim + reject empty ("Rule text cannot be empty."), single-flight (`_rulesSaving`, per-rule `_actingRuleId`, global `_busy`), server re-read after success **and** failure, errors mapped via `GroupErrors.map(…, GroupErrorContext.update)`. |
| `lib/features/group/widgets/group_rules_section.dart` (new, 251 l.) | `GroupRulesSection(controller: GroupHubController)`; keys `group_rules_section`, `rules_count`, `add_rule_button`, `rules_loading`, `rules_error`, `rules_retry`, `rules_empty`, `rules_action_error`, `rule_<id>`, `edit_rule_<id>`, `delete_rule_<id>`, dialogs `new_rule_field`/`edit_rule_field` (maxLength 2000), `confirm_add_rule`, `confirm_edit_rule`, `confirm_delete_rule`. Manager controls shown only when `canEditBasics`; buttons disabled while saving / per-rule acting; delete needs confirmation. |
| `lib/features/group/screens/group_hub_screen.dart` | `GroupRulesSection(controller: _c)` after the description block, before the manager-only queues. |
| `test/group/fakes.dart` | `FakeGroup.rules`; `groupRules` gated on membership; `createRule/updateRule/deleteRule` gated on `canEditSettings` (GROUP_SETTINGS grant ∨ owner) — non-writable rows are simply not matched (0 rows ⇒ "could not be updated/deleted"), CHECK 1..2000 mirrored; invented duplicate-content rule removed. |
| `test/group/group_core_test.dart` | `_FailingRepository` gains the four stubs (compile); the G1 hub widget test gets a tall viewport (lazy ListView must build the leave note below the new section) — minimal additive dependency. |
| `test/group/group_rules_test.dart` (new, 461 l.) | 24 tests, below. |

Removed relative to the audited draft: dead `lib/features/group/state/group_rules_controller.dart` (B3); wrong constructor args in the hub (B1); `MANAGE_MEMBERS` gating → `GROUP_SETTINGS ∨ owner`; column `content` → `rule_text`; migration renamed `G6_group_rules.sql` → `G6_GROUP_RULES.sql`.

Untouched: G1–G5.7 code paths, G3 permission engine, R4, all existing RLS/RPCs. No service-role key, no anon key printed, no `correct_option`, no `public.questions` read (grep-verified).

## 5. Tests (`flutter test test/group/group_rules_test.dart` → 24 passed)

| # | Spec item | Test(s) |
|---|---|---|
| 1 | Model parsing | `fromJson maps the six live columns; position null-safe` (+ toJson, copyWith) |
| 2 | Read as member | `member reads only this group, ordered by position` |
| 3 | Empty | `empty state: loaded, no error, no rules`; widget `empty state for member` |
| 4 | Error / retry | `load error surfaces rulesError; retry recovers`; widget `error + retry` |
| 5 | Manager create | `owner create → trimmed, appended, re-read`; `explicit GROUP_SETTINGS grant (non-owner) may mutate` |
| 6 | Manager update | `owner update → text changed, re-read` |
| 7 | Manager delete | `owner delete → row gone, re-read` |
| 8 | Member read-only UI | widget `member: read-only — rules shown, no controls`; `leader (MANAGE_MEMBERS, no GROUP_SETTINGS): read-only` |
| 9 | Unauthorized mutation | `u-me / u-lead / u-mod: controller refuses and server refuses; nothing changes` (also bypasses the UI guard and hits the fake policy directly); `owner of g-1 cannot touch a forged rule id from g-2`; `server rejection is mapped and the list is re-read` |
| 10 | Single-flight | `second create while first in flight is dropped`; `delete twice on the same rule runs once` |
| 11 | Refresh after mutation | asserted inside 5/6/7 and the widget flow `owner: add → edit → delete with confirmation, list refreshes` |
| 12 | Hub regression | `member: read-only…` asserts roster heading + leave button still render; `section uses the hub controller, not a second source`; plus the full existing suite (below) |

Also: `non-member gets no rows (fn_is_member gate)`, `create/update reject empty or whitespace text`, widget `owner: empty add is rejected without a server call`.

## 6. Regression

- `flutter analyze`: **0 errors, 0 warnings** (68 pre-existing `info` lints, unchanged set).
- `flutter test`: **714 passed, 0 failed** (baseline 690 at `2fe790a` + 24 G6).
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`: **built — `build/app/outputs/flutter-apk/app-debug.apk` (assembleDebug 273.5s, exit 0)**

## 7. Security review

- Server-authoritative: the RLS policies are the boundary; the controller's `canEditBasics` pre-check is UX only and tested as such (bypass test 9).
- No new permission enum value; no `role_permissions` change; no modification of any existing policy/grant/function.
- Non-leaking failures: RLS-denied UPDATE/DELETE surface as 0 rows → "could not be updated/deleted. It may have been removed." (no existence oracle).
- `anon` has no privileges on the table; `service_role` keeps its normal grant.
- Trigger function has `search_path = ''`; no SECURITY DEFINER added.
- Input: trimmed client-side; CHECK enforces 1..2000 server-side regardless.

## 8. Known limitations / warnings carried

- W3 (audit): `position` is computed client-side (max + 1) — a benign race can duplicate positions; ordering falls back to `created_at`. A server default via trigger would be the fix if ever needed; not added (speculative).
- Reordering rules is not in scope (no UI, no RPC).
- No live evidence: the table, policies and grants are unverified until the owner runs the post-check.

## 9. Concurrency note (working tree)

During this build another process (the Free AI Agent session) wrote to `test/group/group_rules_test.dart` and created `docs/G6_GROUP_RULES_PRECHECK.sql` / `POSTCHECK.sql` concurrently. The committed versions are the ones described here (the test file was re-written three times before it held; its final content is the 24-test file above). `docs/G5_8_FINAL_LIFECYCLE_HARDENING_REPORT.md` (that agent's, untracked) is **not** included in this commit.

## 10. Owner steps to reach "G6 IMPLEMENTATION COMPLETE"

1. Supabase SQL Editor → paste `docs/G6_GROUP_RULES_PRECHECK.sql` → expect statement 1 all true / `definer_fns=3`, statement 2 all false / 0.
2. Paste `migrations/G6_GROUP_RULES.sql` → run → the last grid should read `rls_enabled=true, policies=4, fk_to_groups=true, index_present=true, trigger_present=true, anon_privileges=0, authenticated_privileges=DELETE,INSERT,SELECT,UPDATE`.
3. Paste `docs/G6_GROUP_RULES_POSTCHECK.sql` → paste all three grids back.
4. Device (Moto G31, `adb logcat`) or Chrome: as owner open a group hub → add / edit / delete a rule; as a plain member open the same hub → rules visible, no controls; the logcat `rpcShape` lines for `group_rules` are the evidence.
5. Then request the G6 verification pass; only after that does the status change.

## 11. Rollback

`DROP TRIGGER IF EXISTS trg_touch_group_rule ON public.group_rules; DROP FUNCTION IF EXISTS public.fn_touch_group_rule_updated_at(); DROP TABLE IF EXISTS public.group_rules;` — no other object was changed. Flutter reads then fail with a mapped load error inside the section only; the hub stays usable.

## 12. Scope guard

No G7 work (announcements) was started. No file under G1–G5.7 was changed except the two additive test adjustments listed in §4 and the repository/controller/hub extensions that G6 requires by design (single repository, single hub controller).

## 13. Files in this commit

`migrations/G6_GROUP_RULES.sql`, `docs/G6_GROUP_RULES_PRECHECK.sql`, `docs/G6_GROUP_RULES_POSTCHECK.sql`, `docs/G6_GROUP_RULES_IMPLEMENTATION_REPORT.md`, `lib/core/models/group_rule.dart`, `lib/features/group/widgets/group_rules_section.dart`, `lib/features/group/data/group_repository.dart`, `lib/features/group/state/group_hub_controller.dart`, `lib/features/group/screens/group_hub_screen.dart`, `test/group/fakes.dart`, `test/group/group_core_test.dart`, `test/group/group_rules_test.dart`.

## 14. Final status

**G6 IMPLEMENTATION COMPLETE — BACKEND PENDING**

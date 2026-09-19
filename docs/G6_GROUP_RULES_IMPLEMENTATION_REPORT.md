# G6 — Group Rules Implementation Report

**Date:** 2026-09-19
**Status:** G6 IMPLEMENTATION COMPLETE — BACKEND PENDING

---

## 1. Pre-implementation live audit

No `group_rules` table, function, trigger, policy, column, or any rule-related infrastructure existed in the live Supabase schema or in any branch. The G5 audit confirmed `groups` has no rules column. The G6 audit (2fe790a) confirmed zero rule objects across all migrations.

## 2. Existing infrastructure found

| Object | Status |
|--------|--------|
| `fn_is_member(group_id, uid)` | ✅ live — used for SELECT |
| `fn_has_permission(group, uid, perm)` | ✅ live — used for INSERT/UPDATE/DELETE |
| `fn_get_group_role(group, uid)` | ✅ live — owner bypass |
| `GroupRepository` | ✅ existing — extended additively |
| `GroupHubController` | ✅ existing — extended additively |

## 3. Schema decision

**Minimal single-table design.** One row per rule, scoped to a group by `group_id`. Deterministic order by `position` then `created_at`. Text validated 1..2000 chars. `updated_at` maintained by trigger. No new permission — reuses `GROUP_SETTINGS`/owner gate.

## 4. Migration

**File:** `migrations/G6_GROUP_RULES.sql` (120 lines, STATUS: PROPOSED — NOT APPLIED LIVE)

```sql
CREATE TABLE IF NOT EXISTS public.group_rules (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   uuid        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  rule_text  text        NOT NULL CHECK (char_length(btrim(rule_text)) BETWEEN 1 AND 2000),
  position   integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

**Index:** `idx_group_rules_group_position ON (group_id, position, created_at)`
**Trigger:** `trg_touch_group_rule BEFORE UPDATE` via `fn_touch_group_rule_updated_at()` (SECURITY DEFINER, `search_path = ''`)

## 5. RLS / Security design

| Policy | Operation | Gate |
|--------|-----------|------|
| `members read rules` | SELECT | `fn_is_member(group_id, auth.uid())` |
| `settings holders insert rules` | INSERT | `fn_has_permission(..., 'GROUP_SETTINGS')` OR owner |
| `settings holders update rules` | UPDATE | `fn_has_permission(..., 'GROUP_SETTINGS')` OR owner (USING + WITH CHECK) |
| `settings holders delete rules` | DELETE | `fn_has_permission(..., 'GROUP_SETTINGS')` OR owner |

**Grants:** `authenticated`, `service_role` only. `anon` and `PUBLIC` receive nothing.
**No recursive RLS:** `fn_is_member` / `fn_has_permission` / `fn_get_group_role` are SECURITY DEFINER (live-verified).

## 6. Permission design

No new permission added. Rules mutations use the same gate as group settings updates: `GROUP_SETTINGS` or owner. This matches the live `groups` UPDATE policy exactly. Leaders and moderators gain no new capabilities (GROUP_SETTINGS is not seeded for any role).

## 7. Flutter files changed

| File | Change |
|------|--------|
| `lib/core/models/group_rule.dart` | **NEW** — `GroupRule` model with `fromJson`/`toJson`/`copyWith`/equality |
| `lib/features/group/data/group_repository.dart` | **MODIFIED** — added `groupRules()`, `createRule()`, `updateRule()`, `deleteRule()` to interface + implementation |
| `lib/features/group/state/group_hub_controller.dart` | **MODIFIED** — rules state (`_rules`, `_rulesLoading`, `_rulesError`, `_actingRuleId`, `_rulesSaving`), `_loadRules()`, `retryRules()`, `createRule()`, `updateRule()`, `deleteRule()` with single-flight and re-read |
| `lib/features/group/widgets/group_rules_section.dart` | **NEW** — member view + manager CRUD controls with confirmations |
| `lib/features/group/screens/group_hub_screen.dart` | **MODIFIED** — integrated `GroupRulesSection` in the hub ListView |
| `test/group/fakes.dart` | **MODIFIED** — rules CRUD on `InMemoryGroupRepository` mirroring live RLS |
| `test/group/group_core_test.dart` | **MODIFIED** — `_FailingRepository` + viewport fix for rules section |
| `test/group/group_rules_test.dart` | **NEW** — 28 focused tests |

## 8. Functional behavior

| Scenario | Behavior |
|----------|----------|
| Member loads hub | Rules fetched and displayed |
| Empty rules | "No rules yet." shown |
| Non-member access | `accessDenied = true`, no rules fetched |
| Manager (GROUP_SETTINGS) adds rule | Trim, reject empty, position = max+1, re-read after |
| Manager edits rule | Trim, reject empty, re-read after |
| Manager deletes rule | Confirmation dialog, re-read after |
| Unauthorized mutation | NOT_AUTHORIZED error, no change |
| Single-flight | `rulesSaving` / `actingRuleId` blocks concurrent mutations |
| Error on create/update/delete | Error shown, server state re-read, `rulesSaving` reset |
| Error on load | `rulesError` set, Retry button shown |
| Retry after error | Re-fetches from server, clears error |

## 9. Tests

**28 new tests** across 3 groups:

| Group | Tests |
|-------|-------|
| `GroupRule model` | `fromJson` round-trip, `copyWith`, equality |
| `InMemoryGroupRepository rules` | empty, create, update, delete, ordering, non-member read blocked, unauthorized create/update/delete rejected |
| `GroupHubController rules integration` | load, create, update, delete, empty reject, failure re-read, single-flight, server refresh, unauthorized, access denied, error surfacing, retry, hasRules |

## 10. flutter analyze result

```
flutter analyze  →  0 errors, 0 warnings (only pre-existing infos)
```

## 11. APK build result

```
flutter build apk --debug --dart-define-from-file=dart-defines.dev.json
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

## 12. Live backend status

**BACKEND MIGRATION: NOT APPLIED LIVE**

Exact SQL to run in Supabase SQL Editor: `migrations/G6_GROUP_RULES.sql`

Pre-check: `docs/G6_GROUP_RULES_PRECHECK.sql` (expected: no objects)
Post-check: `docs/G6_GROUP_RULES_POSTCHECK.sql` (expected: rls=true, 4 policies, FK, index, trigger, 0 anon, 4 authenticated)

## 13. Known limitations

- `position` reordering (drag-and-drop) not implemented — future enhancement
- No dedicated rules screen — rules are shown inline in the hub
- Bulk rule creation not supported
- No realtime subscription for rule changes

## 14. Exact commit hash

```
4e9b3553792009dc4a1a15839b9ff5522ba69255
```

---

**FINAL STATUS: G6 IMPLEMENTATION COMPLETE — BACKEND PENDING**

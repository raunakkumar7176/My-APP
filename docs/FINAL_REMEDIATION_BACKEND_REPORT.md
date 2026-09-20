# FINAL REMEDIATION — Backend Security + Drift Closure

**Branch:** `r4-restart` · **Base:** `92caf55` (FINAL GAP AUDIT) · **Date:** 2026-09-20 · **Role:** backend security remediation engineer
**Authority:** `docs/FINAL_GAP_AUDIT_REPORT.md` + live Supabase (re-verified before every step). Applications were done one migration at a time (BEGIN → file → COMMIT), each preceded by its precheck and followed by its postcheck; every behavioural proof ran in a transaction that was rolled back and residue was re-checked (0).
**Not production-ready.** This phase closes the backend security and drift gaps only; device acceptance, product decisions and the P3 list are untouched (see §11).

---

## 1. Migrations applied (live, committed, in this order)

| # | Migration | Closes | Statements | Postflight (from the file) |
|---|---|---|---|---|
| 1 | `G14_drop_legacy_group_members_policy.sql` | F-01 P0 | 2 | `legacy_policy_count=0, remaining_policy_count=6` |
| 2 | `G16_revoke_fn_notify_group_execute.sql` | F-02 P0 | 2 | `authenticated=false, anon=false, service_role=true, notify_triggers=4` |
| 3 | `G17_01_fix_rpc_get_leaderboard_access.sql` | F-03 P1 | 4 | `security_definer=true, search_path='', anon=false, authenticated=true, code_branch_removed=true` |
| 4 | `G17_02_fix_fn_increment_batch_progress.sql` | F-04 P1 | 4 | `anon=false, authenticated=true, service_role=true, search_path=''` |
| 5 | `G17_03_revoke_fn_insert_system_message_execute.sql` | F-05 P1 | 2 | `anon=false, authenticated=false, service_role=true` |
| 6 | `FINAL_AUDIT_fix_group_invitation_accept_decline.sql` | F-06 P1 (backend) | 7 | both fns: `expires_branch_removed=true, search_path='', auth_exec=true, anon_exec=false`, parameter `p_invitation_id` unchanged |
| 7 | `FINAL_AUDIT_test_lifecycle_guard_legacy_compatible.sql` | F-07 P1 (legacy-compatible design, **not** G10.2) | 4 | `trg_guard_test_lifecycle` enabled ('O'); function is SECURITY INVOKER, `search_path=''` |
| 8 | `G17_04_fix_test_syllabus_and_announcement_author_policies.sql` | F-08 / F-09 P2 | 6 | `test_syllabus`: SELECT "syllabus read for members and creator", ALL "syllabus write for creator or editor"; `group_announcements` INSERT now `author_id = auth.uid() AND (…)` |
| 9 | `G6_GROUP_RULES.sql` | G6 drift | 19 | `rls_enabled=true, 4 policies, fk_to_groups, index, trigger, anon_privileges=0, authenticated=DELETE,INSERT,SELECT,UPDATE` |
| 10 | `G11_rpc_request_coach_reports.sql` | G11 drift | 6 | `fn_present, security_definer, search_path='', anon=false, authenticated=true` |

## 2. Migrations NOT applied (by design)
- `G10_2_fix_group_edit_test_policy.sql` — superseded by #7 (would break the legacy `→ready/cancelled/archived` writes).
- `G7_GROUP_ANNOUNCEMENTS.sql`, `G8_GROUP_CHAT.sql` — conditional/no-op (tables pre-existed); never meant to run.
- Nothing else is pending from the audit's §5 matrix.

## 3. Precheck results (live, before each apply)
- G14: `legacy_present=true`, 7 policies incl. the FOR ALL one, both guard triggers present, 3 `role_permissions` policies, engine functions definer/`search_path=''`, leader=30 seeded rows.
- G16: `authenticated_can_execute=true, anon=false, security_definer=true`; only callers = 4 definer trigger functions (postgres); notifications policies = `mark own read`, `own notifications`; 39 rows / 9 unread / 39 with `group_id`.
- G17: `g14 legacy=0` (already applied at that point), `g16 auth=false`, `g17_01 uses_access_code=true`, `g17_02 anon=true` with the one-line body, `g17_03 auth=true`, `g17_04a` old policy present, `g17_04b` 1 insert policy, `g5_7 exists=true`.
- Invitations: both functions `refs_missing_col=true`, args `p_invitation_id uuid`. Guard: trigger 0, function 0.
- G6: prerequisites true (groups, fn_is_member, fn_has_permission, fn_get_group_role, GROUP_SETTINGS enum), table/trigger/policies absent.
- G11: results/result_batches/ai_reports/ai_jobs/rpc_generate_results/fn_score_attempt present, `request_rpc=false`, `ai_jobs` policy `false`, idempotency UNIQUE present.

## 4. Postcheck results (live, after each apply)
- G14 POSTCHECK: `legacy_policy_count=0`, `remaining=6` (`group creator adds self as owner, join via invite code, manage members, members see roster, role changes, self leave group`), `all_cmd_policies=0`, RLS on, `guard_triggers=2`, `role_permissions_policies=3`, `owners=3`.
- G16 POSTCHECK: `false,false,true`; 4 notify triggers enabled; 2 notification policies; 1 mute policy; fn still definer.
- G17 POSTCHECK: g14 0/6, g16 false/false, g17_03 false/false, g17_01 `code_branch_removed=true, creator_check=true`, anon no EXECUTE, g17_02 anon no EXECUTE / auth+service EXECUTE, syllabus + announcement policies as listed in §1.
- G6 POSTCHECK: RLS on, 4 policies, FK/index/trigger present, anon 0 privileges, `rule_text NOT NULL`, CHECK present, trigger fn `search_path=''`.
- G11 POSTCHECK: fn present, definer, `search_path=''`, anon denied, authenticated allowed, `gated_by_generate_results=true`, `requires_finished_batch=true`, `idempotent_insert=true`.
- `final_drift.js` after: `G6=true, G10_2 guard fn+trigger=true (the legacy-compatible one), G11=true, G14 legacy=false, G16 auth_exec=false, G17_01 code_branch=false / anon=false, G17_02 guarded=true / anon=false, G17_03 auth_exec=false, G17_04A legacy=false / new=true, G17_04B author bound`.

## 5. Attack results (live state, rolled back — `g17_matrix.js live`, 118 assertions)
113 assertions matched the post-fix expectations; the 5 deviations are all improvements the expectations had not encoded:
- **A6** moderator→owner: `0 rows` (RLS) instead of the trigger error — stricter; owner protections still hold (A7, A9, C8, L1/L1b).
- **G3** `ended → draft` by an EDIT_TEST holder: **denied `LIFECYCLE_LOCKED`** (was `UPDATED`). **G4** `created_by` forge: **denied `OWNERSHIP_LOCKED`** (was `UPDATED`).
- **D0 / K5**: `group_rules` and `rpc_request_coach_reports` now *present*.
Every previously successful attack is now denied: A1 member self-promotion `no rows`; A3/A4/A5 self/other insertion `denied`; A6b `no rows`; E2 forged author `denied`; F6/F6b system-message injection `denied`, 0 rows; F8 `fn_notify_group` `denied`; G11/G11b syllabus writes `denied`/`no rows`; I1/I2 leaderboard by non-participant/non-member `0 rows`; K3/K3b batch progress by anon / negative count `denied`; J5 anon notify `denied`; B6a accept works (`ok`), B6 reuse `denied`, B6c status `accepted`.
Residue after rollback: `tests=0, GA_members=1, msgs=0, notifs=0`.

**Guard proof (`final_guard_proof.js live`): 18/18** — direct `draft→live`, `draft→published`, `created_by`, `test_mode`, soft-delete flip, `ended→draft`, `ended→evaluated` all denied; legacy `draft→ready`, `ready→cancelled`, `cancelled→archived`, `ended→archived`, schedule + title edit allowed; `ends_at ≤ starts_at` rejected (check constraint); `rpc_publish_test`, `rpc_start_attempt` (scheduled→live), `fn_soft_delete_test`, `fn_sweep_deadlines`, postgres/service session all unaffected.

**G6/G11 proof (`rem_g6_g11_proof.js`): 26/27** — G6: owner insert/delete, member read, non-member 0 rows, member/leader insert denied, member update/delete 0 rows, cross-group insert denied, GROUP_SETTINGS holder update allowed, anon denied (R10's `updated_at > created_at` is false only because `now()` is constant inside one transaction — the trigger fired). G11: request before results `RESULTS_NOT_GENERATED`; opening results / leaderboard creates no job; deterministic generation creates 0 jobs; member/non-member `GENERATE_RESULTS_FORBIDDEN`; anon `permission denied`; creator → `created=true, pending`; second call `created=false`, same job; owner bypass reuses; exactly 1 `ai_jobs` row; member cannot read `ai_jobs` or others' `ai_reports`; `correct_option` denied.

## 6. Legitimate-path results (same live run)
L1/L1b owner promote/demote · L2 leader invites · L3 member leaves · L4 rejoin by code (`fn_join_group`) · L5 member sends chat · L5b owner receives the chat notification via trigger · L6/L6b owner and leader announcements as self · L7 leader creates a test via `rpc_create_test` · L8 creator regenerates results · L9 analytics holder reads all results · L10 owner edits settings · L11/L11b owner grants a moderator permission and the moderator holds it · L12 mark own notifications read · L13 mute · L14 safe questions · L15 leader clears chat (system notice inserted by `fn_clear_group_chat` itself) — **all pass**. Legacy-specific: G11c creator inserts `test_syllabus` directly, K3c creator increments batch progress, I3/I3b members/creators/participants read leaderboards, legacy status transitions (guard 8–12) — **all pass**.

## 7. Live DB drift before / after
| Item | Before | After |
|---|---|---|
| G6 `group_rules` | absent | **LIVE** |
| G10.2 lifecycle guard | absent | **LIVE (legacy-compatible variant)** |
| G11 `rpc_request_coach_reports` | absent | **LIVE** |
| G14 legacy policy | present | **FIXED** |
| G16 `fn_notify_group` authenticated EXECUTE | true | **FIXED** |
| G17-01 leaderboard code branch | present | **FIXED** |
| G17-02 batch progress guard / anon | none / true | **FIXED** |
| G17-03 system message authenticated EXECUTE | true | **FIXED** |
| G17-04 syllabus + author policies | legacy | **FIXED** |
| FINAL invitation fix | broken (`expires_at`) | **LIVE** |

## 8. Rollback verification (`rem_rollback_proof.js`, rolled back)
Inside one transaction the verbatim rollback statements of all ten migrations were executed (recreate legacy policy, re-grant `fn_notify_group`/`fn_insert_system_message`/anon batch progress, restore the one-line batch body, restore the old syllabus and announcement policies, drop the guard trigger+function, drop `rpc_request_coach_reports`, drop the rules trigger/function/table, restore the previous `rpc_get_leaderboard` body): every drift key flipped back (`legacy_policy=1, notify_auth=true, sysmsg_auth=true, batch_anon=true, batch_guarded=false, syllabus_legacy=1, author_bound=false, guard=0, coach_rpc=0, rules_table=0, leaderboard old body=true`). After `ROLLBACK` the live keys were identical to the pre-test state (`fixes intact = true`). The invitation functions' rollback is the previous body captured by `docs/FINAL_AUDIT_fix_group_invitation_accept_decline_PRECHECK.md §2` (it re-creates the broken `expires_at` branch; only useful for strict reversal).

## 9. Remaining P0 / P1 / P2 (from the audit)
- **P0: 0.**
- **P1 security: 0.** Remaining P1: **F-12** credential rotation (operational — the plaintext pooler password in untracked `tool/` is still valid; rotate and gitignore `tool/`, `node_modules/`, `package*.json`).
- **P2: 2 product decisions** — F-10 (G12 F1 rank wording; a true rank is now safely available through `rpc_get_leaderboard` for members/participants) and F-11 (soft-deleted chat rows visible; 4 live rows).
- P3 (F-13…F-18) untouched by design.

## 10. Legacy compatibility
| Legacy path | Effect |
|---|---|
| role change / remove / leave via direct `group_members` writes | unaffected (specific policies remain; G14 removed only the FOR ALL policy) |
| createGroup direct owner insert | unaffected (`group creator adds self as owner`) |
| owner transfer via `owner_id` update | still blocked by the pre-existing triggers (unchanged) |
| lifecycle `tests.update({status: ready|cancelled|archived})`, schedule edits | **kept** by the legacy-compatible guard (proof 8–12); any other direct status change now raises `LIFECYCLE_LOCKED` |
| `test_syllabus` insert by the creator | kept (creator branch) |
| `rpc_get_leaderboard` pages | kept for creators/members/participants; anonymous enumeration closed |
| `fn_increment_batch_progress` inline reports (user session) | kept for creator / GENERATE_RESULTS; service role unaffected |
| `fn_accept/decline_group_invitation` (`p_invitation_id`) | now works |
| `notifications.insert`, `results.update`, `ai_jobs.insert` from the user session | were already failing under live RLS before this phase (unchanged) |

## 11. Exact remaining blockers (not addressed here, by scope)
1. **Flutter compatibility update applied in this phase:** `lib/features/group/data/group_repository.dart` — `p_invite_id` → `p_invitation_id` for accept/decline (the only client change; required by the live signature; `test/group/incoming_invitations_test.dart` 16/16). Committed with this report.
2. **Credential rotation** (F-12) — owner action.
3. **Product decisions:** G12 F1 wording (F-10), soft-deleted chat (F-11), owner transfer / group deletion, group logo upload (no bucket), AI worker for the now-live queue.
4. **Device acceptance:** `docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` 0/66 — invitations and rules can now be exercised on device.
5. **P3 hygiene:** F-13 permission-probe enumeration, F-14 attempts privacy, F-15 anon grants / `handle_new_user` search_path, F-16 cron function grants, F-17 report corrections, F-18 uncommitted G15/G18 artifacts.

## 12. Flutter validation (relevant suites)
`flutter analyze lib/features/group/data/group_repository.dart` → no issues; `test/group/incoming_invitations_test.dart` 16/16; `flutter test test/group` → **478 passed**. No test was modified.

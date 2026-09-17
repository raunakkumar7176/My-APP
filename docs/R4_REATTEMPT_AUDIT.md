# R4 — Attempt / Re-attempt System: Forensic Audit (2026-09-17)

Audit only. No code or SQL changed for this item. Labels: **VERIFIED-LIVE** (device/Chrome logs or owner-run SQL this week), **REPO** (migration/Dart source), **UNKNOWN** (needs one read-only query).

## 1. Live schema evidence

| Object | Evidence | Status |
|---|---|---|
| `attempts(id, test_id, user_id, status, started_at, deadline_at, submitted_at, integrity_event_count, auto_submit_threshold, attempt_number)` | owner audit, frozen contract | VERIFIED-LIVE |
| `attempt_status` ∈ in_progress, submitted, auto_submitted, scored | hotfix bodies (`rpc_submit_attempt`, `rpc_generate_results`) | VERIFIED-LIVE |
| `tests` has **no** `max_attempts` column | R4_7_6 header + contract §tests | REPO / owner statement |
| `tests.settings jsonb` exists and round-trips through `rpc_create_test(p_settings)` / `rpc_update_test(p_settings)` (`COALESCE(p_settings, settings)`); client already stores `settings.test_kind` there | R4_5_1 + Chrome `rpc_update_test` shape logs | VERIFIED-LIVE |
| `results` PK = `attempt_id` (no `id`, no `attempt_number`); one result row per scored attempt; own rows readable (`mineForTest` works) | Chrome `results.select` shape, `fn_score_attempt` ON CONFLICT (attempt_id) | VERIFIED-LIVE |
| `attempts` unique constraint form: `(test_id, user_id, attempt_number)` | R4.1 evidence "multiple attempts per user/test: yes, MAX+1" proves the 2-column form is gone | VERIFIED-LIVE by behaviour |
| `attempts` SELECT policy for the owner (`user_id = auth.uid()`) | never exercised — client reads attempts nowhere by design | **UNKNOWN** |

## 2. Current attempt RPC body (what actually runs)

`rpc_start_attempt(p_test)` / `rpc_start_attempt_by_code(p_code)` → `_fn_start_attempt_core(uuid, boolean)` (R4_7_6 body, behaviour-verified). Order inside core:

1. auth → test load (`is_soft_deleted=false`) → lifecycle status gate
2. window: `now() < starts_at` → TEST_NOT_STARTED; `now() >= ends_at` → TEST_ENDED
3. **resume**: latest `in_progress` attempt for (test, user) → return it
4. late-join (live mode only) → LATE_JOIN_NOT_ALLOWED
5. `max_participants` (distinct users) → TEST_FULL
6. `attempt_number := MAX(attempt_number)+1` for (test, user)
7. deadline = `LEAST(now()+duration_sec, ends_at)` → INSERT `in_progress` → return row

**There is no attempt-count limit anywhere.** Step 6 happily allocates 2, 3, 4… forever.

## 3. Current `attempt_number` behaviour

Per (test_id, user_id): resume if in_progress exists, else MAX+1. Deterministic, server-owned, never client-supplied. Any new limit must sit between step 3 and step 6 (after resume, before allocation).

## 4. Current test configuration storage

Columns: `test_mode, duration_sec, starts_at, ends_at, group_id, allow_late_join, max_participants, access_code, join_code, config jsonb, settings jsonb`. Kind lives in `settings.test_kind` (R4.11a), preserved on update by `BackendMapping.settingsFor` (merges, never drops unknown keys).

**Decision (schema-driven): store attempt settings in `tests.settings` jsonb** — `settings.allow_reattempt` (bool) and `settings.max_attempts` (int). Reasons: no `max_attempts` column exists; adding one means ALTER TABLE + changing `rpc_create_test`/`rpc_update_test` signatures (16/14 params) + every caller; `settings` already round-trips through both RPCs unchanged and is readable inside `_fn_start_attempt_core` as `v_test.settings->>'max_attempts'`. No duplicate configuration is created.

## 5. Current Flutter start / resume / re-attempt flow

| Screen | CTA | Call | Server outcome |
|---|---|---|---|
| Test Detail | **Start Test** (shown whenever status startable and window active — the client has no attempt state) | `TestDetailController.start()` → `rpc_start_attempt` | resumes in_progress **or creates MAX+1** |
| Result | **Repeat Test** | `ResultsController.repeat()` → `rpc_start_attempt` | creates MAX+1 |
| Result | **Back to Tests** → `/tests` → card → Detail | — | lands on the "Start Test" CTA above |
| Taking | back-guard "Submit & leave" / countdown | `rpc_submit_attempt` | attempt becomes submitted/auto_submitted → scored |

The client never reads `public.attempts` (RPC-only by design), so Detail cannot tell "never attempted" from "completed" and always offers Start Test.

## 6. Exact bug path (completed test starts again)

1. Student submits → attempt status `scored`, result row exists.
2. Result → "Back to Tests" → listing → Detail. Detail knows only the **test** (status published, window active) → shows **Start Test**.
3. Tap → `rpc_start_attempt` → core step 3 finds no `in_progress` → step 6 allocates `attempt_number+1` → **new attempt, no limit, no explicit consent**.
4. Same via "Repeat Test" on the result screen (explicit, but also unlimited).

Root causes: (a) server has no completed-attempt guard and no max-attempts rule; (b) client has no attempt state, so the CTA is wrong after completion. Both must be fixed; (a) is authoritative.

## 7. Minimal implementation plan

### Backend (one migration; only after the verbatim live bodies are pasted)
1. `_fn_start_attempt_core`: add parameter `p_reattempt boolean DEFAULT false` (or a new wrapper — decided from the live signature). Insert **between resume (3) and late-join (4)**:
   - `v_used := count(*) FROM attempts WHERE test_id=p_test AND user_id=v_uid` (all statuses; in_progress already returned above)
   - `v_allow := COALESCE((v_test.settings->>'allow_reattempt')::boolean, false)`
   - `v_max := CASE WHEN v_allow THEN GREATEST(1, COALESCE((v_test.settings->>'max_attempts')::int, 1)) ELSE 1 END`
   - `IF v_used >= v_max THEN RAISE 'REATTEMPT_LIMIT_REACHED'`
   - `IF v_used > 0 AND NOT p_reattempt THEN RAISE 'ATTEMPT_ALREADY_COMPLETED'` (plain Start can never silently create attempt 2+)
2. `rpc_start_attempt(p_test uuid, p_reattempt boolean DEFAULT false)` and `rpc_start_attempt_by_code(p_code text, p_reattempt boolean DEFAULT false)` pass it through. Defaulted params keep PostgREST resolution for existing callers.
3. Attempt state for the UI — pick after one read-only query on `attempts` policies:
   - if an own-rows SELECT policy exists live → plain RLS read (`select id,status,attempt_number,started_at,submitted_at,deadline_at from attempts where test_id=… and user_id=auth.uid()`), no SQL change;
   - else → minimal `rpc_my_attempt_state(p_test uuid)` returning `{in_progress_attempt_id, attempts_used, max_attempts, allow_reattempt, can_reattempt}` (DEFINER, `search_path ''`, own rows only, no answer keys).
4. No schema, RLS, scoring, question or results change. Never exposes `correct_option`.

### Flutter
- **Creation/Config step**: "Attempt Settings" — Allow Re-attempt (off/on) + Maximum Attempts (1/2/3/5/10, enabled only when on) → `settings.allow_reattempt`, `settings.max_attempts` via `BackendMapping.settingsFor` (other keys preserved). Review step shows it. No Unlimited in V1.
- **Domain**: `AttemptPolicy` (pure): `{used, max, allowReattempt, hasInProgress}` → CTA state `continueTest | startTest | reattempt | limitReached | viewResultOnly`; `TestErrors` maps `REATTEMPT_LIMIT_REACHED`, `ATTEMPT_ALREADY_COMPLETED`.
- **Detail**: attempt section — "Attempt N · Completed · [View Result]", "Attempts N/M", **Continue Test** (in_progress), **Re-attempt** (only when allowed, sends `p_reattempt=true`), "Re-attempt limit reached". Never "Continue Test" on a completed attempt. `Start Test` only when `used == 0`.
- **Result**: "Repeat Test" → **Re-attempt**, gated by the same policy; **Latest / Best / History** sections; per-attempt: attempt number, score/max, %, accuracy, correct/wrong/unanswered, completed_at (`computed_at`), duration (`submitted_at − started_at`, only when the attempts read is available); comparison vs immediately previous attempt: Δscore, Δpercentage, Δaccuracy, Δcorrect/wrong/unanswered, Δtime (if available), subject/topic breakdown Δ per key present in both rows. Nothing fabricated: fields absent in the stored rows are omitted.
- **Listing**: card badge "Completed · View Result" instead of implying start (small, reuses existing category logic).

### Test kinds
Self, Practice, Quick, Sectional: same rule (settings-driven; default allow_reattempt=false → 1 attempt). Challenge with Friends (`test_mode=live`): same rule; late-join rule unchanged; default 1. Group: same rule (group permission checks untouched). Adaptive: not supported, unchanged.

## 8. DB migration plan (only if the audit in §7.3 confirms)
- Required: `_fn_start_attempt_core` (+ the two wrappers) — verbatim live bodies needed first.
- Conditional: `rpc_my_attempt_state` only if no own-rows `attempts` SELECT policy exists.
- Not required: any table/column/constraint/RLS change.

Read-only queries to run before any SQL is written:
```sql
select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code') order by p.proname;
select policyname, cmd, roles, qual from pg_policies where schemaname='public' and tablename='attempts';
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid='public.attempts'::regclass;
select column_name, data_type from information_schema.columns where table_schema='public' and table_name='tests' and column_name in ('settings','config');
```

## 9. Test matrix (to be added with the implementation)

| # | Scenario | Layer |
|---|---|---|
| A | allow_reattempt=off: attempt 1 ok, attempt 2 → REATTEMPT_LIMIT_REACHED; UI shows limit | policy + fake repo mirroring the server rule + widget |
| B | max_attempts=2: 1 ok, 2 ok (explicit), 3 blocked | same |
| C | in_progress exists: Start/Continue resumes same id, no new attempt | controller + fake |
| D | completed attempt: Detail shows View Result, plain start → ATTEMPT_ALREADY_COMPLETED, no new attempt | controller + widget |
| E | explicit Re-attempt creates attempt N+1 only when policy allows; sends `p_reattempt=true` | controller + repository contract |
| F | limit reached: deterministic error mapped; Re-attempt hidden/disabled, "Attempts 3/3" | domain + widget |
| G | different users: counts keyed per (test, user) — fake mirrors the server WHERE clause | fake + controller |
| H | security: policy is server-side (fake raises even when the client passes `p_reattempt=true` past the limit); client never reads questions/correct_option; only RPC used | repository/fake contract |
| + | timezone/window and existing lifecycle tests keep passing | existing suites |

Physical device / Chrome E2E after the SQL is applied: A, C, D, E, F on a real test.

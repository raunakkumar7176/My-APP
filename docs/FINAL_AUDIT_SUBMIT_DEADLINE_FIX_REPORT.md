# FINAL AUDIT — `rpc_submit_attempt` Deadline Enforcement Fix

## 1. Old behavior

`public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)` (live, per this task's own read-only audit: `SECURITY DEFINER`, `search_path=public`):

```sql
declare a attempts;
begin
  select * into a from attempts where id = p_attempt and user_id = auth.uid() for update;
  if a.id is null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
  if a.status <> 'in_progress' then return; end if;
  update attempts
  set status = case
                 when p_auto then 'auto_submitted'::public.attempt_status
                 else 'submitted'::public.attempt_status
               end,
      submitted_at = now()
  where id = p_attempt;
  perform fn_score_attempt(p_attempt);
end
```

It locks the caller's own row (`FOR UPDATE`), checks ownership via `auth.uid()`, and is correctly idempotent (`status <> 'in_progress'` guards a second call). But the final `status` is decided **purely by the client-supplied `p_auto` boolean** — the function never reads `attempts.deadline_at` at all.

## 2. Vulnerability / gap

`attempts.deadline_at` is computed and stored **server-side** by `_fn_start_attempt_core` (`LEAST(now() + duration_sec, tests.ends_at)`) and is correctly enforced on the **autosave** path — `rpc_save_answers` already contains `IF now() > a.deadline_at THEN PERFORM fn_auto_submit(a.id); ...`. But the **finalization** path did not mirror that check. A client that:

1. Stops calling autosave before the deadline (e.g. goes offline, or simply doesn't trigger another save), and
2. Calls `rpc_submit_attempt(attempt_id, false)` after `deadline_at` has already passed,

gets that submission accepted, scored, and recorded as an on-time `'submitted'` attempt — with no server-side record that it was actually late. The server-computed deadline existed and was trustworthy; it just wasn't consulted at the one call that actually finalizes an attempt.

## 3. New behavior

```sql
v_expired := now() >= a.deadline_at;

UPDATE public.attempts
   SET status = CASE
                   WHEN p_auto OR v_expired
                     THEN 'auto_submitted'::public.attempt_status
                   ELSE 'submitted'::public.attempt_status
                 END,
       submitted_at = now()
 WHERE id = p_attempt;
```

- **Boundary**: `now() >= deadline_at` (inclusive) is treated as expired, per this task's explicit requirement 11 wording ("If now() >= deadline_at ... MUST become auto_submitted"). This was the one place the task said to stop and report ambiguity if unclear — it was not ambiguous here, the requirement stated the boundary explicitly, so it was followed as given rather than re-derived.
- **Client cannot bypass expiry**: `p_auto=false` no longer has any effect once the deadline has passed — the server's own clock (`now()`) decides, not the client's claim.
- **Before the deadline, behavior is unchanged**: `p_auto=false` → `submitted`, `p_auto=true` → `auto_submitted`, exactly as before.
- **`submitted_at` is always `now()`** — it always was; there is no parameter on this function through which a client could supply a timestamp, so this property required no change, only confirmation (see Test Matrix #10).
- **Everything else is byte-for-byte the same**: the `FOR UPDATE` lock, the `user_id = auth.uid()` ownership filter, the `ATTEMPT_NOT_FOUND` exception, the `status <> 'in_progress'` idempotency guard, and the single `fn_score_attempt(p_attempt)` call at the end.

## 4. Exact function changes

See `migrations/FINAL_AUDIT_fix_rpc_submit_attempt_deadline.sql`, Step 1, for the full `CREATE OR REPLACE`. Summary of the diff against the old body:

| Aspect | Old | New |
|---|---|---|
| `search_path` | `'public'` | `''` (tightened; every reference fully schema-qualified: `public.attempts`, `public.attempt_status`, `public.fn_score_attempt`) |
| Deadline check | none | `v_expired := now() >= a.deadline_at` |
| Status decision | `CASE WHEN p_auto THEN ... ELSE ...` | `CASE WHEN p_auto OR v_expired THEN ... ELSE ...` |
| Ownership check | `user_id = auth.uid()` | unchanged |
| Locking | `FOR UPDATE` | unchanged |
| Idempotency guard | `status <> 'in_progress'` → return | unchanged |
| Scoring call | `perform fn_score_attempt(p_attempt)` | unchanged (still exactly one call, same guard) |
| Schema | — | untouched, no columns added or changed |

## 5. Security reasoning

- **Server time is authoritative**: the new check uses Postgres's own `now()` against a value (`deadline_at`) that was itself computed and stored server-side at attempt-start time — no client input is trusted for either side of the comparison.
- **Fail-safe direction**: on any ambiguity the function now resolves toward the *stricter* outcome (`auto_submitted`), never toward silently accepting a late submission as on-time. A submission is still always **accepted** (never rejected/errored for being late) — only its recorded lateness changes — which avoids a worse failure mode where a legitimate submission delayed by normal network latency would be lost entirely.
- **No new trust surface introduced**: no new parameter was added to the function, so there is no new way for a client to influence the outcome; the fix strictly removes a way the client could previously influence it (by claiming `p_auto=false` past the deadline).
- **search_path tightening is defense-in-depth**: the old `'public'` value was schema-qualified and not currently exploitable, but `''` with explicit qualification is strictly safer and consistent with the ~30 other `SECURITY DEFINER` functions in this codebase that already use it — this reduces the chance a future edit to this function accidentally introduces an unqualified reference that could resolve against an unexpected schema.
- **RLS is untouched**: this function's authorization boundary is `SECURITY DEFINER` + the `auth.uid()` ownership filter inside the function body, not table-level RLS — nothing here weakens or bypasses any RLS policy.

## 6. Rollback

The exact prior function body is included, commented out, directly in the migration file under `-- OLD BEHAVIOR (for rollback)`. To roll back: uncomment and run that `CREATE OR REPLACE FUNCTION` block (it restores `search_path='public'` and the `p_auto`-only status logic verbatim). No schema changes were made, so no `DROP`/data-migration is needed either direction — this is a pure function-body swap, fully reversible with a single statement.

## 7. Verification SQL

Preflight and postflight read-only queries are embedded in the migration file (function signature/`proconfig`/grants before and after, plus `pg_get_functiondef` to visually confirm the new body). These were **not executed** — this environment has no live Supabase access (no CLI, `psql`, `.env`, or credentials anywhere in this repo or dev machine). They must be run by whoever applies the migration via the Supabase SQL Editor.

## 8. Test matrix

Ten numbered scenarios are embedded in the migration file's `TEST MATRIX` section (before/at/after-deadline submissions crossed with both `p_auto` values, duplicate submit, forged attempt ID, another user's attempt, exactly-once scoring, and confirmation that no timestamp parameter exists for a client to forge). These are **SQL scenarios for a human with live/staging database access to run**, not automated tests — see §9 for why.

### Automated (Dart) test coverage — what could and couldn't be added

This fix lives entirely in a Postgres function. The existing Flutter test double for this path, `FakeAttemptRepository` (`test/r4_restart/fakes.dart`), is a plain in-memory stub — `submit()` simply trusts whatever `timedOut` the caller passes and returns a canned `Result`; it does not model real Postgres semantics (`FOR UPDATE` locking, `auth.uid()`, or a `deadline_at` comparison), unlike some of this codebase's other fakes (e.g. `FakeRoutineRepository`, `InMemoryGroupRepository`) which do deliberately mirror server-side RLS/permission logic for controller-level testing. Extending it to fake deadline enforcement would test a *re-implementation* of this SQL fix in Dart, not the fix itself — which would be a false sense of verification, not a real one. Per this task's own instruction not to invent behavior where there's ambiguity, and not to touch unrelated UI/controller code, no such fake was added.

What **is** already covered and was reconfirmed still passing in this pass: `test/r4_restart/attempt_results_test.dart`'s `'submit flushes, calls the RPC once, parks the result, blocks re-entry'` test already verifies the client-side contract this fix depends on — `AttemptController.submit()` calls the repository exactly once per attempt, a second concurrent call throws `ValidationError` before ever reaching the network, and the `timedOut` flag is threaded through to the RPC call unchanged (`attempts.calls == ['submit:a-1:false']`). This is real, existing, passing coverage of the *client's* half of the contract (requirement 24's "duplicate submit" item) — it was not modified or re-run differently in this pass, just confirmed to still exist and still pass.

**Out-of-scope observation, not fixed**: while tracing `AttemptController.submit()` for this task, one related but explicitly out-of-scope detail was noticed — after a successful `submit()` call, the controller sets its **local** `_attempt.status` from the client's own `timedOut` argument (`status: timedOut ? AttemptStatus.autoSubmitted : AttemptStatus.submitted`), not from anything the server actually returned. Once this SQL fix is live, a client that called `submit(timedOut: false)` after the deadline would have the server correctly record `auto_submitted`, but the app's in-memory state would still briefly *display* `submitted` until the user navigates to a screen that re-fetches the attempt via RLS. This is a minor, self-correcting UI staleness issue, not a security issue (the server's stored truth is already correct) — flagged here rather than silently fixed, since this task's objective and scope discipline (requirements 3-8, 26) is explicitly the database function only.

## 9. Migration applied live?

**No.** Per requirement 20 ("DO NOT apply the migration to production automatically") and because this environment has no Supabase CLI, `psql`, `.env`, or credentials of any kind — a fact already established in prior sessions and re-confirmed in this one.

## 10. Live verification status

**BLOCKED — UNVERIFIED.** The preflight/postflight queries and the ten-scenario test matrix in §8 are written and ready but have not been run against any real database. Whoever applies this migration via the Supabase SQL Editor should run the preflight query first (to confirm the function is still in the expected "old" state before replacing it), then the migration, then the postflight query and as many of the ten test-matrix scenarios as practical against a staging attempt.

## 11. Remaining blockers

1. **Deployment**: this migration must be run by someone with Supabase SQL Editor access; it does not apply itself.
2. **Live verification**: none of the preflight/postflight/test-matrix queries have been executed against the real database.
3. **Client display staleness** (§8, out-of-scope observation): once deployed, a late submission with `p_auto=false` will be correctly recorded server-side as `auto_submitted`, but the Flutter client's immediate local state after `submit()` returns will still show `submitted` until a subsequent RLS-backed re-fetch (e.g. opening the result screen) corrects it. Not fixed in this pass — flagged for a future, explicitly-scoped UI task if it matters to the product.
4. This fix addresses `rpc_submit_attempt` only. It does not change, and was not asked to change, `rpc_save_answers`'s existing autosave-path deadline enforcement, `fn_auto_submit`, `rpc_start_attempt`, or scoring/result-calculation logic — all confirmed untouched.

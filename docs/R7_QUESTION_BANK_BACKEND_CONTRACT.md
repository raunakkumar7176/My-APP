# R7 — Question Bank V1: Backend Contract for the Flutter client

**Status:** functions defined in `migrations/R7_QUESTION_BANK_V1.sql` (+ `migrations/R7_FIX_rpc_create_question_status_cast.sql`), proven in a rolled-back transaction 41/41, **NOT YET APPLIED LIVE** (owner apply required). Until applied, every call below returns PostgREST 404 "function not found". The client must not fall back to reading `question_bank.correct_option` from the table.

## Architecture facts the client must respect
- Reusable questions are rows of **`public.question_bank`** (existing live table). There is no `test_id IS NULL` question; `public.questions.test_id` is NOT NULL.
- A test question is a **separate `public.questions` row** created by the server copy in `rpc_clone_bank_questions`; `questions.bank_id` is provenance metadata only (FK ON DELETE SET NULL). Later bank edits/deletes never change test questions.
- Browsing scope (server-enforced, same as the live `auth read bank` policy): the caller's **own** bank rows, plus **all** bank rows when the caller holds `REVIEW_QUESTIONS` or `GENERATE_QUESTIONS` in **any** group (live seeding: leaders hold both; owners via bypass; moderators/members none).
- The client never needs `correct_option`. Do not select it from the table; use `rpc_get_question_bank_question(..., true)` only for authors/reviewers.
- `profiles` has `full_name` (there is **no** `display_name`); the RPCs return `created_by_name` already.

## RPCs (all: `authenticated` only; anon/PUBLIC denied; SECURITY DEFINER, `search_path=''`)

### `rpc_list_question_bank`
```
rpc_list_question_bank(
  p_search text = null,        -- ILIKE on question, subject_name, chapter
  p_status text = null,        -- pending_review | approved | rejected | needs_revision | archived
  p_subject_id uuid = null,
  p_topic_node_id uuid = null,
  p_difficulty text = null,    -- easy | medium | hard
  p_language text = null,      -- en | hi | hinglish
  p_question_type text = null, -- live CHECK allows only 'mcq'
  p_source text = null,        -- manual | upload | ai | mixed
  p_limit int = 20,            -- clamped to 1..50
  p_offset int = 0
) RETURNS TABLE(
  id uuid, question text, options jsonb, explanation text, subject_id uuid, subject_name text,
  chapter text, topic_node_id uuid, difficulty text, language text, question_type text,
  source text, status question_status, created_by uuid, created_by_name text, times_used int,
  created_at timestamptz, updated_at timestamptz, archived_at timestamptz, total_count bigint)
```
- Ordering: `updated_at DESC, id DESC` (stable). `total_count` = filtered total (same on every row); `has_more = offset + rows.length < total_count`.
- Never returns `correct_option`. Unauthorized callers get **0 rows** (not an error). Invalid filter values raise `VALIDATION_ERROR: invalid … filter`.
- Errors: `AUTH_REQUIRED`.

### `rpc_get_question_bank_question`
```
rpc_get_question_bank_question(p_id uuid, p_include_answer boolean = false) RETURNS jsonb
```
- Returns the row fields above plus `reviewed_by`, `reviewed_at`, `answer_included`.
- `p_include_answer = true` adds `correct_option` **only** when the caller is the author or holds `REVIEW_QUESTIONS` in any group; otherwise `ANSWER_KEY_FORBIDDEN`. `GENERATE_QUESTIONS` alone does not unlock the key.
- Errors: `AUTH_REQUIRED`, `QUESTION_NOT_FOUND` (missing or not readable — the server does not say which), `ANSWER_KEY_FORBIDDEN`.

### `rpc_clone_bank_questions` — selection with server-side snapshot
```
rpc_clone_bank_questions(p_test_id uuid, p_bank_ids uuid[], p_marks_per_question numeric = 1) RETURNS jsonb
→ { "test_id": uuid, "cloned": int, "question_ids": uuid[], "skipped_duplicate": uuid[], "skipped_unavailable": uuid[] }
```
- Authorization: caller is the test **creator**, or holds **`EDIT_TEST`** in the test's group. Target must exist, not be soft-deleted, status ∈ {draft, ready, scheduled, published} (else `TEST_NOT_FOUND` / `TEST_LOCKED`), otherwise `PERMISSION_DENIED`.
- Each bank id must be readable by the caller (scope above), `status = 'approved'`, `archived_at IS NULL` → otherwise it is listed in `skipped_unavailable` (no error, nothing created; forged ids land here too).
- Duplicate: a bank id already present in the test (`questions.bank_id`) is listed in `skipped_duplicate`; repeated ids in the same call are collapsed. Idempotent.
- Copy: `question, options, correct_option, explanation, subject_id, topic_node_id, difficulty, language, question_type` by value; `marks = p_marks_per_question`; `status = 'approved'`; `ordinal` = next free ordinal; `bank_id` set; `source_batch` null. `question_bank.times_used` += 1.
- Limits: 1..100 ids per call; `p_marks_per_question > 0`.
- Errors: `AUTH_REQUIRED`, `VALIDATION_ERROR: …`, `TEST_NOT_FOUND`, `TEST_LOCKED: …`, `PERMISSION_DENIED: creator or EDIT_TEST required for this test`.
- After the call, re-read the test's questions with `get_test_questions_safe` (existing, key-free) — do not trust local state.

### `fn_bank_available` (compat with the existing client call)
```
fn_bank_available(p_subject_name text = '', p_chapter text = '', p_difficulty text = '', p_language text = '') RETURNS integer
```
Count of **approved, non-archived** bank rows readable by the caller, filtered by ILIKE subject/chapter and exact difficulty/language. `AUTH_REQUIRED` for anon.

## Existing RPCs the client keeps using
- `rpc_create_question(...)` — manual test question; **live body is broken today** (text→enum), fixed by `R7_FIX_rpc_create_question_status_cast.sql`. Creator-only, test in draft/published.
- `rpc_update_question`, `rpc_delete_question` — unchanged.
- `get_test_questions_safe(p_test_id, p_access_code)` — the only participant-facing read; no `correct_option`.
- Bank CRUD stays on the table under the live policies: INSERT (own, or REVIEW/GENERATE holder), UPDATE (author, `created_by IS NULL`, or REVIEW holder). The table SELECT grant still exposes `correct_option` to bank readers (legacy design; see report §security). Prefer the RPCs for reads.

## Error mapping guidance
Map `PERMISSION_DENIED`, `ANSWER_KEY_FORBIDDEN` → "You don't have permission…"; `TEST_LOCKED` → "This test can no longer be edited"; `QUESTION_NOT_FOUND`/`TEST_NOT_FOUND` → stale/refresh; `VALIDATION_ERROR: …` → show the text after the colon.

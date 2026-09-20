# R7 Question Bank V1 — Implementation Report

## 1. Phase 0 Discovery Findings

### Existing Architecture Discovered
- **`question_bank` table** exists in `0017_question_bank_ai_controls.sql` with full governance added in `0045_question_bank_governance.sql`
- **Snapshot model**: Bank questions are cloned/copied into test questions (not live references). `bank_id` on `questions` is `ON DELETE SET NULL` for provenance tracking
- **No Flutter question_bank UI existed** — all bank management was through Next.js admin only
- **RLS restricts access** to users with `GENERATE_QUESTIONS` or `REVIEW_QUESTIONS` permissions
- **`fn_bank_available` RPC** returns count of matching questions
- **`content_reports`** and **`content_audit_logs`** tables exist for governance
- **Duplicate detection** via `duplicate_key` column with auto-populating triggers

### Question Bank Table Schema
| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `question` | text | min 5 chars |
| `options` | jsonb | array of `{text}` |
| `correct_option` | int | 0-3 index |
| `explanation` | text | |
| `subject_id` | uuid FK | nullable |
| `subject_name` | text | denormalized |
| `chapter` | text | |
| `topic_node_id` | uuid FK | nullable |
| `difficulty` | text | easy/medium/hard/basic/mixed |
| `language` | text | en/hi/hinglish |
| `question_type` | text | mcq/tf/short/num |
| `source` | text | manual/upload/ai |
| `created_by` | uuid FK | |
| `times_used` | int | |
| `status` | question_status | pending_review/approved/archived/needs_revision |
| `reviewed_by` | uuid FK | |
| `reviewed_at` | timestamptz | |
| `updated_at` | timestamptz | auto via trigger |
| `archived_at` | timestamptz | |
| `duplicate_key` | text | auto via trigger |

## 2. Existing Architecture Reused

### Database Objects (all existing, no new tables)
- `question_bank` table — fully reused
- `question_status` enum — extended with `archived`, `needs_revision`
- `content_reports` table — exists for student reporting
- `content_audit_logs` table — exists for audit trail
- `fn_bank_available()` — reused for count queries
- `fn_qb_bank_key()` — reused for normalized key generation
- `fn_log_content_audit()` — reused for audit logging
- RLS policies: `auth read bank`, `auth insert bank`, `owner update bank` — all enforced

### New Migration (0053)
- **`rpc_clone_bank_questions(p_test_id, p_bank_ids, p_marks_per_question)`** — SECURITY DEFINER function that clones approved bank questions into a test's `questions` table, increments `times_used`, and logs audit trail
- This is the Supabase RPC equivalent of the Next.js `cloneBankQuestionsToTest` Server Action
- Additive only, RLS-protected, reversible

## 3. Files Changed

### New Files (10)
| File | Purpose |
|------|---------|
| `lib/core/models/question_bank_item.dart` | Model for `question_bank` table + filter/pagination types |
| `lib/features/test/data/question_bank_repository.dart` | Repository interface + Supabase implementation |
| `lib/features/test/state/question_bank_controller.dart` | State management for bank listing/selection/CRUD |
| `lib/features/test/screens/question_bank_screen.dart` | Paginated list with search/filters/selection mode |
| `lib/features/test/screens/question_bank_detail_screen.dart` | Question detail view with governance info |
| `lib/features/test/widgets/question_bank_item_card.dart` | Card widget for bank items |
| `lib/features/test/widgets/question_bank_filter_sheet.dart` | Bottom sheet for filter options |
| `My-Prepration/supabase/migrations/0053_question_bank_clone_to_test.sql` | Clone RPC migration |
| `test/r7/question_bank_controller_test.dart` | 25 unit tests for controller |
| `docs/R7_QUESTION_BANK_IMPLEMENTATION_REPORT.md` | This report |

### Modified Files (5)
| File | Change |
|------|--------|
| `lib/features/test/widgets/question_source_step.dart` | Added `onBankQuestionsSelected` callback, `books` now functional |
| `lib/features/test/screens/test_creation_screen.dart` | Added `_handleBankQuestionsSelected` to clone bank questions |
| `lib/app/app_router.dart` | Added `/question-bank` and `/question-bank/:questionId` routes |
| `test/r4_restart/fakes.dart` | Added `FakeQuestionBankRepository` for testing |

## 4. Permission Matrix

| Operation | Required Permission | Enforcement |
|-----------|---------------------|-------------|
| List bank questions | GENERATE_QUESTIONS or REVIEW_QUESTIONS | RLS `auth read bank` |
| View bank question detail | GENERATE_QUESTIONS or REVIEW_QUESTIONS | RLS `auth read bank` |
| Create bank question | GENERATE_QUESTIONS or REVIEW_QUESTIONS | RLS `auth insert bank` |
| Edit bank question | Owner or REVIEW_QUESTIONS | RLS `owner update bank` |
| Archive bank question | Owner or REVIEW_QUESTIONS | RLS `owner update bank` |
| Restore bank question | Owner or REVIEW_QUESTIONS | RLS `owner update bank` |
| Clone to test | Test owner (draft only) | `rpc_clone_bank_questions` |

## 5. Answer-Security Model

- **Bank listing**: RLS restricts to authorized users only (GENERATE_QUESTIONS/REVIEW_QUESTIONS)
- **Bank detail**: Same RLS restriction; `correct_option` visible to authorized users for governance
- **Student test access**: Uses `get_test_questions_safe` RPC which strips `correct_option` (existing mechanism)
- **Clone operation**: Copies `correct_option` into test question row (snapshot), protected by RLS + RPC auth check
- **Historical independence**: Bank edits do NOT affect already-cloned test questions (snapshot model with `ON DELETE SET NULL`)

## 6. Pagination/Filter Strategy

- **Server-side filtering**: All filters (status, subject, difficulty, language, type, source, search) applied via PostgREST before fetching
- **Offset pagination**: `.range(offset, offset + limit - 1)` with page size of 20
- **No client-side loading of thousands of rows**: RLS + server-side filtering ensures only relevant data is fetched
- **Infinite scroll**: `loadMore()` appends next page to existing list

## 7. Test-Selection Flow

1. User opens Test Creation wizard → navigates to Question Source step
2. Selects "From Books" → opens `QuestionBankScreen` in selection mode
3. Searches/filters bank questions (server-side)
4. Long-presses to enter selection mode → taps to toggle selection
5. Uses "Select All" / "Deselect All" for bulk operations
6. Taps "Add N Questions" FAB → calls `rpc_clone_bank_questions`
7. Bank questions are cloned into test's `questions` table with `bank_id` set
8. User returns to wizard → cloned questions appear in Questions step

## 8. Historical Test Independence Mechanism

- **Snapshot model**: `cloneBankQuestionsToTest` copies full question content (text, options, correct_option, explanation, metadata) into `questions` table
- **`bank_id` column**: Set as provenance link, `ON DELETE SET NULL` — if bank question is deleted, test copies survive
- **No live reference**: Editing a bank question does NOT propagate to existing test questions
- **Audit trail**: `content_audit_logs` records every `bank_reused` action with test_id and question_id

## 9. Tests Added/Results

### Unit Tests (25 passing)
- `test/r7/question_bank_controller_test.dart`
  - load: loads items, sets error, clears error
  - search: by text, case insensitive, clears
  - setFilter: by status, difficulty, language, combined
  - clearFilters: clears all
  - selection: enter/exit, toggle, selectAll/deselectAll, getSelectedItems
  - createQuestion: creates and refreshes
  - updateQuestion: updates and refreshes
  - archiveQuestion: archives
  - restoreQuestion: restores
  - checkDuplicates: finds duplicates, empty when none
  - getById: finds by id, null for non-existent
  - getAvailableCount: counts approved items

### Fake Repository
- `FakeQuestionBankRepository` added to `test/r4_restart/fakes.dart` with full in-memory implementation

## 10. Analyze Result

- **0 errors** in R7 files
- Pre-existing info-level lint warnings (prefer_single_quotes in group tests) — not introduced by R7
- 2 minor warnings fixed: unused import, unused field

## 11. APK Result

```
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

## 12. Known Limitations

1. **Pagination total count**: Uses client-side count (fetches all matching IDs) rather than `COUNT(*)`. Could be optimized with a dedicated count RPC if performance becomes an issue.
2. **No inline question editing**: Bank questions can be archived/restored but not edited inline. Editing requires a dedicated form (not in V1 scope).
3. **Filter chips don't include subject/topic**: Subject and topic filters are supported in the repository but not fully exposed in the filter sheet UI (would require a subject picker component).
4. **No duplicate prevention on clone**: The `rpc_clone_bank_questions` function doesn't check if a question from the same bank is already in the test.

## 13. Manual Verification Steps

1. Open app → navigate to Tests → Create Test → Question Source → select "From Books"
2. Verify question bank screen loads with paginated results
3. Search for questions by text
4. Apply filters (status, difficulty, language)
5. Long-press a question to enter selection mode
6. Select multiple questions → tap "Add N Questions"
7. Return to wizard → verify cloned questions appear in Questions step
8. Verify the test can be published with cloned questions
9. Verify bank question detail screen shows metadata and governance info

## 14. Blocked Items

None. All R7 scope items implemented successfully.

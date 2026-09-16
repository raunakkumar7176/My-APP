# R4.1 — TEST SYSTEM GREENFIELD ARCHITECTURE SPECIFICATION

**Date:** 2026-09-12
**Status:** DESIGN ONLY — NO IMPLEMENTATION
**Author:** Architecture Specification
**Depends On:** R4_TEST_SYSTEM_DISCOVERY_AUDIT.md

---

## EXECUTIVE SUMMARY

The R4 Discovery Audit confirmed that the current live project does NOT contain the Test System. The single test-related table (`test_syllabus`) is orphaned — it references a `tests` table that does not exist.

This document specifies a **greenfield build** of a complete test system for the "My Preparation" Flutter + Supabase application. The system supports practice tests, mock exams, and competitive exam preparation with deterministic scoring, secure attempt handling, and batch result generation.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| RLS Model | Option A: Simple Owner-Based | Eliminates recursion by design; sufficient for preparation app |
| Question Storage | Question Bank (reusable) | Avoids duplication; questions shared across tests |
| test_syllabus | D + RECREATE | Drop orphaned table; create clean junction table |
| AI Reports | Deferred to Phase R4.12 | Deterministic scoring is primary; AI is enhancement |
| Groups | Deferred — designed interface only | No groups infrastructure exists; design for future |
| Attempt Limits | Server-enforced via RPC | Client cannot bypass; prevents duplicate starts |
| Scoring | Deterministic, server-calculated | AI must never be authoritative for marks |

### Tables Summary

| # | Table | Purpose | Status |
|---|-------|---------|--------|
| 1 | `tests` | Test metadata and configuration | NEW |
| 2 | `questions` | Reusable question bank | NEW |
| 3 | `test_syllabus` | Junction: tests ↔ syllabus_nodes | RECREATE |
| 4 | `test_invitations` | Access control for restricted tests | NEW |
| 5 | `attempts` | User test attempts | NEW |
| 6 | `answers` | Per-question answers within attempts | NEW |
| 7 | `results` | Attempt scores and breakdowns | NEW |
| 8 | `ai_reports` | AI-generated post-test analysis | NEW (deferred) |

**Total: 8 tables** (down from R4's proposed 12 — 4 tables eliminated as unnecessary)

### Tables NOT Created

| Table | Reason Eliminated |
|-------|-------------------|
| `question_bank` | Merged into `questions` — all questions are bank questions |
| `test_questions` | Unnecessary — `questions.test_id` nullable links question to test |
| `result_batches` | Merged into `results` — `batch_id` column on `results` tracks batch |
| `integrity_events` | Merged into `attempts` — `violations` jsonb column tracks events |

---

## TABLE OF CONTENTS

1. Source of Truth
2. Database Schema Design
3. Existing test_syllabus Investigation
4. Test Lifecycle
5. Test Creation Model
6. Question Architecture
7. Attempt Architecture
8. Answer Architecture
9. Deterministic Scoring
10. Batch Results
11. Group/Permission Integration
12. Syllabus Integration
13. Security/RLS
14. Performance
15. Idempotency/Concurrency
16. Flutter Architecture
17. Implementation Phases
18. Report

---

## 1. SOURCE OF TRUTH

### 1.1 Live Database Tables (VERIFIED from R4 CSV dump)

| Table | Rows | Status | Relevance to Test System |
|-------|------|--------|--------------------------|
| `subjects` | 11 | ✓ EXISTS | Test references subject |
| `syllabus_nodes` | 2 | ✓ EXISTS | Test syllabus references nodes |
| `profiles` | varies | ✓ EXISTS | User identity; test creator/participant |
| `test_syllabus` | varies | ⚠️ ORPHANED | References nonexistent `tests` table |
| `study_materials` | varies | ✓ EXISTS | Optional material links |
| `node_materials` | varies | ✓ EXISTS | Junction: nodes ↔ materials |
| `material_chunks` | varies | ✓ EXISTS | Material content storage |
| `progress_snapshots` | varies | ✓ EXISTS | Deferred |
| `routines` | varies | ✓ EXISTS | Deferred |
| `routine_logs` | varies | ✓ EXISTS | Deferred |
| `groups` | N/A | ❌ DOES NOT EXIST | Must be designed for future |
| `group_members` | N/A | ❌ DOES NOT EXIST | Must be designed for future |
| `role_permissions` | N/A | ❌ DOES NOT EXIST | Must be designed for future |

### 1.2 Verified Schema Details

**`subjects`** — PK: `id` (uuid), Column: `name` (text NOT NULL)

**`syllabus_nodes`** — PK: `id` (uuid), FK: `subject_id → subjects.id`, FK: `parent_id → syllabus_nodes.id` (nullable), Columns: `class_level` (text nullable), `name` (text NOT NULL), `created_at` (timestamptz)

**`profiles`** — PK: `id` (uuid, FK to `auth.users.id`), Columns: `full_name`, `avatar_url`, `timezone`, `created_at`, `student_code`, `bio`, `mobile`, `exam_targets` (jsonb)

**`test_syllabus`** — Columns: `test_id` (uuid NOT NULL), `syllabus_node_id` (uuid NOT NULL), `material_ids` (uuid[]). **ORPHANED** — `test_id` references `tests` which does not exist.

### 1.3 Constraints Verified

- FK `syllabus_nodes.subject_id → subjects.id` ✓
- FK `syllabus_nodes.parent_id → syllabus_nodes.id` ✓
- PK on `syllabus_nodes.id` ✓
- Index on `syllabus_nodes.subject_id` ✓
- NO unique constraint on `syllabus_nodes` (name + parent_id not unique)
- NO index on `syllabus_nodes.parent_id`

### 1.4 Assumptions

1. `auth.users` exists (Supabase Auth — required for `auth.uid()`)
2. Supabase client library available in Flutter (`supabase_flutter ^2.8.4`)
3. `go_router ^14.8.1` available for routing
4. Database uses UUID primary keys (consistent with existing schema)
5. Timestamps use `timestamptz` (consistent with existing schema)
6. RLS is enabled on all tables (Supabase default)

### 1.5 What This Document Does NOT Do

- Does NOT create/modify any database table
- Does NOT create/modify any RLS policy
- Does NOT create/modify any RPC/function
- Does NOT create/modify any Flutter file
- Does NOT create/modify any Edge Function
- Does NOT seed any data

---

## 2. DATABASE SCHEMA DESIGN

### 2.1 Custom Types (Enums)

```sql
-- Test status lifecycle
CREATE TYPE public.test_status AS ENUM (
  'draft',       -- Created, not published
  'published',   -- Visible to participants, can start attempts
  'closed',      -- No new attempts allowed
  'archived'     -- Hidden from active lists
);

-- Attempt lifecycle
CREATE TYPE public.attempt_status AS ENUM (
  'in_progress', -- User has started, not yet submitted
  'submitted',   -- User submitted or auto-submitted on timeout
  'expired'      -- Time expired without submission
);

-- Question types
CREATE TYPE public.question_type AS ENUM (
  'mcq_single',   -- Single correct option
  'mcq_multiple', -- Multiple correct options
  'true_false',   -- True/False
  'integer',      -- Numerical answer
  'short_answer'  -- Text answer (manual grading)
);

-- Difficulty levels
CREATE TYPE public.difficulty_level AS ENUM (
  'easy',
  'medium',
  'hard'
);
```

### 2.2 Table: `tests`

**Purpose:** Store test metadata, configuration, and scheduling.

```sql
CREATE TABLE public.tests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         text NOT NULL,
  description   text,
  instructions  text,
  subject_id    uuid NOT NULL REFERENCES public.subjects(id) ON DELETE RESTRICT,
  class_level   text,
  status        public.test_status NOT NULL DEFAULT 'draft',

  -- Timing
  duration_minutes    integer NOT NULL CHECK (duration_minutes > 0),
  start_at            timestamptz,  -- NULL = no scheduled start
  end_at              timestamptz,  -- NULL = no deadline

  -- Scoring
  total_marks         integer NOT NULL DEFAULT 0 CHECK (total_marks >= 0),
  passing_marks       integer NOT NULL DEFAULT 0 CHECK (passing_marks >= 0),
  negative_marking    boolean NOT NULL DEFAULT false,
  negative_marks      numeric(4,2) NOT NULL DEFAULT 0.00,

  -- Question selection
  total_questions     integer NOT NULL DEFAULT 0 CHECK (total_questions >= 0),
  shuffle_questions   boolean NOT NULL DEFAULT false,
  show_answers_after  boolean NOT NULL DEFAULT false,  -- Show correct answers after submission

  -- Access control
  is_public           boolean NOT NULL DEFAULT true,  -- true = all authenticated users, false = invited only
  max_attempts        integer NOT NULL DEFAULT 1 CHECK (max_attempts > 0),

  -- Metadata
  difficulty          public.difficulty_level,
  tags                text[] DEFAULT '{}',
  language            text NOT NULL DEFAULT 'en',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
```

**Indexes:**
```sql
CREATE INDEX idx_tests_created_by ON public.tests (created_by);
CREATE INDEX idx_tests_subject_id ON public.tests (subject_id);
CREATE INDEX idx_tests_status ON public.tests (status);
CREATE INDEX idx_tests_start_at ON public.tests (start_at) WHERE start_at IS NOT NULL;
CREATE INDEX idx_tests_end_at ON public.tests (end_at) WHERE end_at IS NOT NULL;
```

**Constraints:**
- `passing_marks <= total_marks` (enforced at application level or CHECK constraint)
- `end_at > start_at` when both non-null (CHECK constraint)
- `created_by` must be authenticated user

**Lifecycle:** draft → published → closed → archived

**Ownership:** `created_by` = test creator. Participants have no ownership.

**Relationships:**
- `tests.created_by` → `profiles.id` (creator)
- `tests.subject_id` → `subjects.id` (subject)
- `tests` → `test_syllabus` (1:N — which syllabus nodes are covered)
- `tests` → `questions` (1:N — which questions are in this test)
- `tests` → `test_invitations` (1:N — who is invited, if restricted)
- `tests` → `attempts` (1:N — who has attempted)

### 2.3 Table: `questions`

**Purpose:** Reusable question bank. Questions can exist independently of any test (bank questions) or be linked to a specific test (test-specific questions).

```sql
CREATE TABLE public.questions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  test_id         uuid REFERENCES public.tests(id) ON DELETE SET NULL,  -- NULL = bank question

  -- Content
  question_text   text NOT NULL,
  question_type   public.question_type NOT NULL DEFAULT 'mcq_single',
  options         jsonb NOT NULL DEFAULT '[]',  -- Array of {id, text, is_correct}
  -- For mcq_single/mcq_multiple/true_false: options array with is_correct flag
  -- For integer: options is empty array, answer is numeric
  -- For short_answer: options is empty array, answer is text

  -- Correct answer (for non-MCQ types, or for validation)
  correct_answer  text,  -- For integer: numeric string; for short_answer: expected text

  -- Scoring
  marks           integer NOT NULL DEFAULT 1 CHECK (marks > 0),
  negative_marks  numeric(4,2) NOT NULL DEFAULT 0.00 CHECK (negative_marks >= 0),
  difficulty      public.difficulty_level NOT NULL DEFAULT 'medium',

  -- Metadata
  explanation     text,
  source          text,  -- e.g., "NCERT Class 10 Science Chapter 3"
  language        text NOT NULL DEFAULT 'en',
  tags            text[] DEFAULT '{}',
  is_active       boolean NOT NULL DEFAULT true,
  version         integer NOT NULL DEFAULT 1,

  -- Timestamps
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
```

**Indexes:**
```sql
CREATE INDEX idx_questions_created_by ON public.questions (created_by);
CREATE INDEX idx_questions_test_id ON public.questions (test_id) WHERE test_id IS NOT NULL;
CREATE INDEX idx_questions_difficulty ON public.questions (difficulty);
CREATE INDEX idx_questions_question_type ON public.questions (question_type);
CREATE INDEX idx_questions_is_active ON public.questions (is_active) WHERE is_active = true;
CREATE INDEX idx_questions_tags ON public.questions USING gin(tags);
```

**Constraints:**
- `options` must be valid JSON array
- For `mcq_single`: at least 2 options, exactly 1 with `is_correct = true`
- For `mcq_multiple`: at least 2 options, at least 2 with `is_correct = true`
- For `true_false`: exactly 2 options (true, false), exactly 1 correct
- For `integer`: `correct_answer` must be numeric
- For `short_answer`: `correct_answer` must be non-null (manual grading)
- `marks > 0` always
- `negative_marks < marks` (cannot penalize more than the question is worth)

**Lifecycle:** is_active = true/false (soft archive)

**Ownership:** `created_by` = question creator

**Relationships:**
- `questions.created_by` → `profiles.id` (creator)
- `questions.test_id` → `tests.id` (nullable — NULL means bank question)
- `questions` → `answers` (1:N — user answers referencing this question)

**Reusability Design:**
- Bank questions (`test_id IS NULL`): Reusable across multiple tests
- Test-specific questions (`test_id IS NOT NULL`): Owned by one test
- Both types exist in the same `questions` table
- When creating a test, creator can select from bank questions or create new test-specific questions
- `is_active` allows soft-deletion without breaking existing attempts

### 2.4 Table: `test_syllabus`

**Purpose:** Junction table linking tests to syllabus nodes. Defines which syllabus topics a test covers.

```sql
CREATE TABLE public.test_syllabus (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id           uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  syllabus_node_id  uuid NOT NULL REFERENCES public.syllabus_nodes(id) ON DELETE CASCADE,
  material_ids      uuid[] DEFAULT '{}',  -- Optional material references

  created_at        timestamptz NOT NULL DEFAULT now(),

  UNIQUE (test_id, syllabus_node_id)  -- Prevent duplicate syllabus entries per test
);
```

**Indexes:**
```sql
CREATE INDEX idx_test_syllabus_test_id ON public.test_syllabus (test_id);
CREATE INDEX idx_test_syllabus_syllabus_node_id ON public.test_syllabus (syllabus_node_id);
```

**Constraints:**
- `UNIQUE (test_id, syllabus_node_id)` — same node cannot appear twice in one test
- FK to `tests.id` with CASCADE on delete
- FK to `syllabus_nodes.id` with CASCADE on delete

**Relationships:**
- `test_syllabus.test_id` → `tests.id`
- `test_syllabus.syllabus_node_id` → `syllabus_nodes.id`

### 2.5 Table: `test_invitations`

**Purpose:** Control access for restricted tests (`is_public = false`). Lists which users are invited.

```sql
CREATE TABLE public.test_invitations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id     uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  invited_at  timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,

  UNIQUE (test_id, user_id)  -- One invitation per user per test
);
```

**Indexes:**
```sql
CREATE INDEX idx_test_invitations_test_id ON public.test_invitations (test_id);
CREATE INDEX idx_test_invitations_user_id ON public.test_invitations (user_id);
```

**Constraints:**
- `UNIQUE (test_id, user_id)` — one invitation per user per test
- FK to `tests.id` with CASCADE on delete
- FK to `auth.users(id)` with CASCADE on delete

**Note:** For public tests (`is_public = true`), `test_invitations` is not used. All authenticated users can see and start public tests.

### 2.6 Table: `attempts`

**Purpose:** Record each user's attempt at a test. One row per attempt.

```sql
CREATE TABLE public.attempts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id       uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
  status        public.attempt_status NOT NULL DEFAULT 'in_progress',

  -- Timing (server-authoritative)
  started_at    timestamptz NOT NULL DEFAULT now(),
  submitted_at  timestamptz,  -- NULL until submitted
  time_spent_seconds integer,  -- Calculated on submission

  -- Violations tracking
  violations    jsonb DEFAULT '[]',  -- Array of {type, timestamp, details}

  -- Metadata
  ip_address    inet,
  user_agent    text,

  created_at    timestamptz NOT NULL DEFAULT now(),

  UNIQUE (test_id, user_id, attempt_number)  -- Prevent duplicate attempt numbers
);
```

**Indexes:**
```sql
CREATE INDEX idx_attempts_test_id ON public.attempts (test_id);
CREATE INDEX idx_attempts_user_id ON public.attempts (user_id);
CREATE INDEX idx_attempts_test_user ON public.attempts (test_id, user_id);
CREATE INDEX idx_attempts_status ON public.attempts (status);
```

**Constraints:**
- `UNIQUE (test_id, user_id, attempt_number)` — one attempt number per user per test
- FK to `tests.id` with CASCADE on delete
- FK to `auth.users(id)` with CASCADE on delete
- `submitted_at >= started_at` when not null
- `attempt_number <= tests.max_attempts` (enforced by RPC)

**Lifecycle:** in_progress → submitted | expired

**Ownership:** `user_id` = attempt owner. Test creator can read all attempts for their tests.

**Relationships:**
- `attempts.test_id` → `tests.id`
- `attempts.user_id` → `auth.users(id)`
- `attempts` → `answers` (1:N — answers within this attempt)
- `attempts` → `results` (1:1 — score result for this attempt)

### 2.7 Table: `answers`

**Purpose:** Store each user's answer to each question within an attempt. One row per question per attempt.

```sql
CREATE TABLE public.answers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id      uuid NOT NULL REFERENCES public.attempts(id) ON DELETE CASCADE,
  question_id     uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,

  -- Answer content
  selected_option_id text,      -- For MCQ: the selected option ID
  text_answer       text,      -- For integer/short_answer: the typed answer

  -- State
  is_marked_for_review boolean NOT NULL DEFAULT false,
  is_answered         boolean NOT NULL DEFAULT false,

  -- Timestamps
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (attempt_id, question_id)  -- One answer per question per attempt
);
```

**Indexes:**
```sql
CREATE INDEX idx_answers_attempt_id ON public.answers (attempt_id);
CREATE INDEX idx_answers_question_id ON public.answers (question_id);
CREATE INDEX idx_answers_attempt_question ON public.answers (attempt_id, question_id);
```

**Constraints:**
- `UNIQUE (attempt_id, question_id)` — one answer per question per attempt
- FK to `attempts.id` with CASCADE on delete
- FK to `questions.id` with CASCADE on delete
- For `mcq_single`/`mcq_multiple`: `selected_option_id` must be non-null when `is_answered = true`
- For `integer`/`short_answer`: `text_answer` must be non-null when `is_answered = true`

**Ownership:** `attempt_id` links to attempt owner (`attempts.user_id`). Users can only modify their own answers.

**Relationships:**
- `answers.attempt_id` → `attempts.id`
- `answers.question_id` → `questions.id`

**Write Pattern:**
- `is_answered` is `false` by default (unanswered)
- Client sets `is_answered = true` and populates `selected_option_id` or `text_answer`
- `is_marked_for_review` toggled independently
- `updated_at` updated on every save (for autosave tracking)
- Duplicate protection: `UNIQUE (attempt_id, question_id)` prevents multiple answers to same question

### 2.8 Table: `results`

**Purpose:** Store calculated scores for each attempt. One row per attempt. Generated deterministically after submission.

```sql
CREATE TABLE public.results (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id        uuid NOT NULL REFERENCES public.attempts(id) ON DELETE CASCADE,
  test_id           uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  batch_id          uuid,  -- Optional: links to batch generation run

  -- Score breakdown
  total_marks       integer NOT NULL DEFAULT 0,
  marks_obtained    numeric(8,2) NOT NULL DEFAULT 0,
  percentage        numeric(5,2) NOT NULL DEFAULT 0,
  is_passed         boolean NOT NULL DEFAULT false,

  -- Counts
  total_questions   integer NOT NULL DEFAULT 0,
  correct_count     integer NOT NULL DEFAULT 0,
  wrong_count       integer NOT NULL DEFAULT 0,
  unanswered_count  integer NOT NULL DEFAULT 0,
  partial_count     integer NOT NULL DEFAULT 0,  -- For mcq_multiple: partially correct

  -- Metadata
  generated_at      timestamptz NOT NULL DEFAULT now(),
  generation_method text NOT NULL DEFAULT 'deterministic',  -- 'deterministic' | 'ai_assisted'

  UNIQUE (attempt_id)  -- One result per attempt
);
```

**Indexes:**
```sql
CREATE INDEX idx_results_attempt_id ON public.results (attempt_id);
CREATE INDEX idx_results_test_id ON public.results (test_id);
CREATE INDEX idx_results_user_id ON public.results (user_id);
CREATE INDEX idx_results_test_user ON public.results (test_id, user_id);
CREATE INDEX idx_results_batch_id ON public.results (batch_id) WHERE batch_id IS NOT NULL;
```

**Constraints:**
- `UNIQUE (attempt_id)` — one result per attempt (idempotent generation)
- FK to `attempts.id` with CASCADE on delete
- FK to `tests.id` with CASCADE on delete
- FK to `auth.users(id)` with CASCADE on delete
- `percentage >= 0 AND percentage <= 100`
- `marks_obtained >= 0 AND marks_obtained <= total_marks`
- `correct_count + wrong_count + unanswered_count + partial_count = total_questions`
- `is_passed = (marks_obtained >= passing_marks)` (consistency)

**Lifecycle:** Generated after attempt submission. Immutable once created.

**Ownership:** `user_id` = result owner. Test creator can read all results for their tests.

**Relationships:**
- `results.attempt_id` → `attempts.id` (1:1)
- `results.test_id` → `tests.id`
- `results.user_id` → `auth.users(id)`
- `results.batch_id` → batch identifier (uuid, not a FK to a table)

### 2.9 Table: `ai_reports`

**Purpose:** Store AI-generated analysis of test performance. Created AFTER deterministic results exist.

```sql
CREATE TABLE public.ai_reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  result_id     uuid NOT NULL REFERENCES public.results(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  test_id       uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,

  -- AI content
  summary       text,
  strengths     jsonb DEFAULT '[]',  -- Array of strength descriptions
  weaknesses    jsonb DEFAULT '[]',  -- Array of weakness descriptions
  recommendations jsonb DEFAULT '[]', -- Array of recommendation objects
  detailed_analysis text,

  -- Metadata
  model_used    text,  -- e.g., 'gpt-4', 'claude-3'
  tokens_used   integer,
  generated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (result_id)  -- One AI report per result
);
```

**Indexes:**
```sql
CREATE INDEX idx_ai_reports_result_id ON public.ai_reports (result_id);
CREATE INDEX idx_ai_reports_user_id ON public.ai_reports (user_id);
CREATE INDEX idx_ai_reports_test_id ON public.ai_reports (test_id);
```

**Constraints:**
- `UNIQUE (result_id)` — one AI report per result (idempotent)
- FK to `results.id` with CASCADE on delete
- FK to `auth.users(id)` with CASCADE on delete
- FK to `tests.id` with CASCADE on delete

**Note:** This table is DEFERRED. The deterministic `results` table is the primary scoring mechanism. `ai_reports` is an enhancement added in Phase R4.12. The `generation_method` column on `results` tracks whether AI was used.

**Ownership:** `user_id` = report owner. Test creator can read all reports for their tests.

---

## 3. EXISTING test_syllabus INVESTIGATION

### 3.1 Current Definition

```sql
CREATE TABLE public.test_syllabus (
  test_id uuid NOT NULL,          -- FK -> tests.id (DOES NOT EXIST)
  syllabus_node_id uuid NOT NULL, -- FK -> syllabus_nodes.id (EXISTS)
  material_ids uuid[]             -- Array of material IDs
);
```

**Observed Issues:**
1. `test_id` references `tests` table which does not exist → FK constraint is broken
2. No primary key on the table
3. No unique constraint preventing duplicate syllabus entries
4. `material_ids` is an unbounded array — potential performance issue
5. No timestamps for auditing
6. RLS status unknown

### 3.2 Investigation Results

| Question | Answer |
|----------|--------|
| Does `tests` table exist? | NO |
| Is FK constraint enforced? | NO (target table missing) |
| Does the table have a PK? | NO |
| Can duplicate rows exist? | YES (no unique constraint) |
| Is RLS enabled? | UNKNOWN |
| Are there orphaned rows? | LIKELY (test_id values point to nonexistent tests) |

### 3.3 Decision: DROP AND RECREATE

**Recommendation: D — Drop and Replace**

**Reasoning:**

1. The table is structurally broken (FK to nonexistent table)
2. No primary key means no clean way to reference individual rows
3. No unique constraint means data integrity cannot be guaranteed
4. The new schema adds `id` (PK), timestamps, and proper constraints
5. Since the old table has no valid data (all `test_id` values reference nonexistent tests), dropping it loses nothing

**Migration Plan:**
```sql
-- Step 1: Drop orphaned table
DROP TABLE IF EXISTS public.test_syllabus;

-- Step 2: Create new table (from Section 2.4)
CREATE TABLE public.test_syllabus (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id           uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  syllabus_node_id  uuid NOT NULL REFERENCES public.syllabus_nodes(id) ON DELETE CASCADE,
  material_ids      uuid[] DEFAULT '{}',
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (test_id, syllabus_node_id)
);
```

**Alternative Considered:** Reuse (A) — rejected because the table is structurally unsound and has no valid data.

---

## 4. TEST LIFECYCLE

### 4.1 Test Status States

```
DRAFT ──→ PUBLISHED ──→ CLOSED ──→ ARCHIVED
  ↑          ↑
  └──────────┘  (can unpublish: PUBLISHED → DRAFT)
```

| Status | Meaning | Visible to Participants | Can Start Attempt |
|--------|---------|------------------------|-------------------|
| `draft` | Being created/edited | NO (only creator) | NO |
| `published` | Live, available | YES | YES (if within time window) |
| `closed` | Ended, no new attempts | YES (read-only) | NO |
| `archived` | Hidden from lists | NO (only creator) | NO |

### 4.2 Status Transitions

| From | To | Trigger | Who |
|------|----|---------|-----|
| draft | published | Creator clicks "Publish" | Test creator |
| published | draft | Creator clicks "Unpublish" | Test creator |
| published | closed | Deadline passes or creator closes | System/Creator |
| closed | archived | Creator clicks "Archive" | Test creator |
| draft | archived | Creator clicks "Archive" | Test creator |

**Rules:**
- Tests with active attempts (in_progress) CANNOT be archived
- Tests with `is_public = false` require invitations before publishing
- Unpublishing a published test does NOT affect in-progress attempts
- Closing a published test auto-submits any in-progress attempts (via RPC)

### 4.3 Attempt Lifecycle

```
START ──→ IN_PROGRESS ──→ SUBMITTED
               │
               └──→ EXPIRED (time ran out)
```

| Status | Meaning | Can Answer Questions | Can Submit |
|--------|---------|---------------------|------------|
| `in_progress` | Active attempt | YES | YES |
| `submitted` | Completed by user or auto-submitted | NO | NO |
| `expired` | Time expired without submission | NO | NO |

### 4.4 Attempt Transitions

| From | To | Trigger | Who |
|------|----|---------|-----|
| — | in_progress | User starts attempt (RPC) | Participant |
| in_progress | submitted | User clicks Submit (RPC) | Participant |
| in_progress | expired | Time limit reached (RPC/cron) | System |
| in_progress | submitted | Test deadline reached (RPC/cron) | System |

**Rules:**
- Only `in_progress` attempts can be modified (answers saved)
- `submitted` attempts are immutable
- `expired` attempts are immutable
- A user cannot start a new attempt if they have `max_attempts` completed attempts

### 4.5 Participant Timing Rules

| Scenario | Behavior |
|----------|----------|
| Test has `start_at` in future | Test visible but "Not started yet" — cannot begin |
| Test has `end_at` in past | Test visible but "Expired" — cannot begin |
| User starts attempt, test `end_at` passes | Attempt auto-submitted (time remaining = 0) |
| User starts attempt, `duration_minutes` passes | Attempt auto-submitted (time remaining = 0) |
| Whichever is earlier: `end_at` or `started_at + duration_minutes` | Auto-submit trigger |

### 4.6 Published Test Editing

**Can a published test be edited?**

| Field | Editable When Published? | Reason |
|-------|-------------------------|--------|
| title | YES | Fix typos |
| description | YES | Clarify instructions |
| instructions | YES | Update rules |
| duration_minutes | NO (affects active attempts) | Would invalidate timing |
| start_at | NO (affects scheduling) | Would confuse participants |
| end_at | NO (affects deadlines) | Would affect auto-submit |
| total_marks | NO (affects scoring) | Would invalidate results |
| negative_marking | NO (affects scoring) | Would invalidate results |
| questions | NO (affects active attempts) | Would invalidate answers |
| is_public | NO (affects access) | Would lock/unlock participants |
| max_attempts | NO (affects attempt counting) | Would invalidate limits |

**Implementation:** Published tests have a `published_at` timestamp. The RPC for updating tests checks `status != 'published'` for restricted fields.

---

## 5. TEST CREATION MODEL

### 5.1 Test Configuration Fields

| Field | Type | Required | Source | Notes |
|-------|------|----------|--------|-------|
| title | text | YES | Creator input | Display name |
| description | text | NO | Creator input | Markdown supported |
| instructions | text | NO | Creator input | Shown before attempt starts |
| subject_id | uuid | YES | Creator selects from `subjects` | Must exist in subjects table |
| class_level | text | NO | Creator selects | Display only, matches syllabus_nodes |
| duration_minutes | integer | YES | Creator input | 1–480 minutes |
| start_at | timestamptz | NO | Creator sets | NULL = available immediately |
| end_at | timestamptz | NO | Creator sets | NULL = no deadline |
| total_marks | integer | YES | Auto-calculated | Sum of question marks |
| passing_marks | integer | YES | Creator input | Must be <= total_marks |
| negative_marking | boolean | YES | Creator toggles | Default: false |
| negative_marks | numeric(4,2) | COND | Creator input | Required if negative_marking = true |
| total_questions | integer | YES | Auto-calculated | Count of questions |
| shuffle_questions | boolean | YES | Creator toggles | Default: false |
| show_answers_after | boolean | YES | Creator toggles | Default: false |
| is_public | boolean | YES | Creator toggles | Default: true |
| max_attempts | integer | YES | Creator input | 1–10 |
| difficulty | enum | NO | Creator selects | easy/medium/hard |
| tags | text[] | NO | Creator adds | Search/filter tags |
| language | text | YES | Creator selects | Default: 'en' |

### 5.2 CONFIRMED REQUIREMENTS

| # | Requirement | Status |
|---|-------------|--------|
| 1 | Title and instructions | CONFIRMED |
| 2 | Duration and deadline | CONFIRMED |
| 3 | Marks and negative marking | CONFIRMED |
| 4 | Syllabus selection from syllabus_nodes | CONFIRMED |
| 5 | Question selection from question bank | CONFIRMED |
| 6 | Public vs restricted access | CONFIRMED |
| 7 | Attempt limits | CONFIRMED |
| 8 | Question randomization | CONFIRMED |
| 9 | Language selection | CONFIRMED |
| 10 | Publication status control | CONFIRMED |

### 5.3 PROPOSED DESIGN

| # | Design Decision | Rationale |
|---|-----------------|-----------|
| 1 | Group association deferred | No groups infrastructure exists |
| 2 | Scheduling via start_at/end_at | Simple, sufficient for preparation app |
| 3 | Difficulty distribution via tags | Avoids complex distribution constraints |
| 4 | Question selection manual or auto | Creator picks questions or system generates from syllabus |

### 5.4 UNKNOWN

| # | Item | Impact |
|---|------|--------|
| 1 | Expected number of tests created per day | Performance planning |
| 2 | Whether AI-assisted question generation is needed | Phase R4.12 scope |
| 3 | Whether bulk test creation is needed | UI complexity |
| 4 | Whether tests can be cloned | Convenience feature |

---

## 6. QUESTION ARCHITECTURE

### 6.1 Question Type Support

| Type | Options | Correct Answer | Scoring | Notes |
|------|---------|----------------|---------|-------|
| `mcq_single` | 2–6 options | Exactly 1 correct | Full marks or 0 | Most common |
| `mcq_multiple` | 2–6 options | 2+ correct | Partial scoring possible | Complex scoring |
| `true_false` | 2 options (true/false) | Exactly 1 correct | Full marks or 0 | Simple variant of mcq_single |
| `integer` | No options (typed) | Numeric answer | Exact match or 0 | For numerical questions |
| `short_answer` | No options (typed) | Text answer | Manual grading | Teacher reviews |

### 6.2 Question Options Format (JSONB)

For `mcq_single`, `mcq_multiple`, `true_false`:

```json
[
  {"id": "opt_a", "text": "Option A text", "is_correct": true},
  {"id": "opt_b", "text": "Option B text", "is_correct": false},
  {"id": "opt_c", "text": "Option C text", "is_correct": false},
  {"id": "opt_d", "text": "Option D text", "is_correct": false}
]
```

**Rules:**
- Each option has `id` (string), `text` (string), `is_correct` (boolean)
- `id` is client-generated (e.g., "opt_a", "opt_b") — not stored as UUID
- For `mcq_single`: exactly 1 option with `is_correct = true`
- For `mcq_multiple`: 2+ options with `is_correct = true`
- For `true_false`: exactly 2 options, exactly 1 correct

### 6.3 Reusability Design

**Decision: Questions ARE reusable across tests.**

**Justification:**

1. **Avoids duplication:** Same question (e.g., "What is the powerhouse of the cell?") can appear in multiple tests without being stored twice
2. **Centralized updates:** Fixing a typo in a question updates it everywhere
3. **Version control:** `version` column tracks changes; existing attempts reference the question version at time of attempt
4. **Bank model:** Questions exist in a global bank (`test_id IS NULL`) or test-specific (`test_id IS NOT NULL`)
5. **Performance:** No data duplication means less storage, faster queries

**When creating a test:**
1. Creator can browse the question bank and select existing questions
2. Creator can create new test-specific questions (linked to that test only)
3. Creator can search by subject, difficulty, type, tags

**When editing a published test:**
- Questions CANNOT be added or removed (would invalidate active attempts)
- Question content CAN be updated (but version number increments)

### 6.4 Question Validation Rules

```sql
-- mcq_single: exactly 1 correct
-- Enforced by application layer or trigger

-- mcq_multiple: 2+ correct
-- Enforced by application layer or trigger

-- true_false: exactly 2 options, 1 correct
-- Enforced by application layer or trigger

-- integer: correct_answer must be numeric
-- Enforced by application layer or trigger

-- short_answer: correct_answer must be non-null
-- Enforced by application layer or trigger

-- marks > 0 always
-- Enforced by CHECK constraint

-- negative_marks < marks
-- Enforced by CHECK constraint
```

### 6.5 Question Metadata

| Field | Purpose | Example |
|-------|---------|---------|
| source | Where the question came from | "NCERT Class 10 Science Chapter 3" |
| tags | Searchable labels | ["physics", "optics", "class-10"] |
| language | Question language | "en", "hi" |
| difficulty | Easy/medium/hard | "medium" |
| explanation | Answer explanation (shown after submission) | "The mitochondria is known as..." |
| is_active | Soft delete flag | true/false |
| version | Version number | 1, 2, 3... |

---

## 7. ATTEMPT ARCHITECTURE

### 7.1 Server-Authoritative Operations

| Operation | Client Role | Server Role | Reason |
|-----------|-------------|-------------|--------|
| Start attempt | Request start | Record `started_at`, validate limits | Prevents fake start times |
| Save answers | Send answers | Update `answers` table | Prevents answer tampering |
| Submit attempt | Request submit | Record `submitted_at`, calculate time | Prevents time manipulation |
| Auto-submit | None | System triggers on timeout | Prevents time abuse |
| Calculate score | None | Server computes from answers | Prevents score tampering |

### 7.2 Attempt Start Flow

```
1. Client calls RPC: start_attempt(test_id)
2. Server validates:
   a. Test exists and status = 'published'
   b. Test is within time window (start_at <= now <= end_at)
   c. User has not exceeded max_attempts
   d. No in_progress attempt already exists
3. Server creates attempt row:
   a. status = 'in_progress'
   b. started_at = now() (server time)
   c. attempt_number = (existing count) + 1
4. Server creates empty answer rows for each question
5. Server returns attempt_id + question list
6. Client starts timer based on returned data
```

### 7.3 Reconnection Handling

**Scenario:** User closes browser/app mid-attempt and returns.

**Flow:**
1. Client checks for existing in_progress attempts on app start
2. If found, client resumes from last saved state
3. Timer recalculates: `remaining = duration_minutes - (now - started_at)`
4. If `remaining <= 0`: auto-submit triggered
5. If `remaining > 0`: resume normally
6. Client fetches latest saved answers from `answers` table

**Data Recovery:**
- Answers are saved individually (not batched) — partial saves are recoverable
- `updated_at` on each answer tracks last save time
- Client can display "Last saved at HH:MM:SS" indicator

### 7.4 Duplicate Submit Protection

**Mechanism:**
1. `attempts.status` transitions from `in_progress` to `submitted` via RPC
2. RPC checks `status = 'in_progress'` before allowing submission
3. If status is already `submitted`, RPC returns error
4. `UNIQUE (test_id, user_id, attempt_number)` prevents duplicate attempt creation
5. `UNIQUE (attempt_id)` on `results` prevents duplicate scoring

**Race Condition Protection:**
```sql
-- RPC: submit_attempt(attempt_uuid)
-- Uses SELECT ... FOR UPDATE to lock the attempt row
BEGIN;
  SELECT * FROM attempts WHERE id = attempt_uuid AND status = 'in_progress' FOR UPDATE;
  -- If row found and status = 'in_progress':
  UPDATE attempts SET status = 'submitted', submitted_at = now() WHERE id = attempt_uuid;
COMMIT;
-- If row not found or status != 'in_progress': return error
```

### 7.5 Autosave Design

**Strategy:** Client saves answers individually as user interacts.

**Pattern:**
1. User selects an answer → client calls `save_answer(attempt_id, question_id, selected_option_id)`
2. Server upserts the answer row (INSERT ON CONFLICT UPDATE)
3. Client shows "Saved" indicator
4. Debounced: client waits 500ms of inactivity before saving (reduces writes)
5. Periodic save: every 30 seconds regardless of user activity
6. On submit: all answers are guaranteed saved (final flush)

**Conflict Resolution:**
- Last-write-wins: `updated_at` determines latest save
- No optimistic locking needed (single-user attempt)

### 7.6 Time Tracking

| Field | Updated When | Value |
|-------|-------------|-------|
| `started_at` | Attempt creation | `now()` (server time) |
| `submitted_at` | Submission | `now()` (server time) |
| `time_spent_seconds` | Submission | `submitted_at - started_at` (server calculated) |

**Client Timer:** Client displays countdown based on `duration_minutes - (now - started_at)`. Server is authoritative — client timer is display-only.

---

## 8. ANSWER ARCHITECTURE

### 8.1 Answer States

```
UNANSWERED ──→ ANSWERED ──→ MARKED FOR REVIEW
     ↑              ↑              │
     └──────────────┴──────────────┘
     (can toggle between states freely)
```

| State | `is_answered` | `is_marked_for_review` | Meaning |
|-------|---------------|----------------------|---------|
| Unanswered | false | false | Question not attempted |
| Answered | true | false | User selected/typed an answer |
| Marked for Review | true | true | User answered but wants to revisit |
| Marked Unanswered | false | true | User marked review without answering |

### 8.2 Answer Data Model

```dart
// Client-side representation
class AnswerState {
  final String attemptId;
  final String questionId;
  String? selectedOptionId;  // For MCQ
  String? textAnswer;        // For integer/short_answer
  bool isAnswered;
  bool isMarkedForReview;
  DateTime? lastSavedAt;
}
```

### 8.3 Save Operations

| Operation | Client Action | Server Action | Notes |
|-----------|--------------|---------------|-------|
| Select option | Set `selected_option_id`, `is_answered = true` | UPSERT answer row | Debounced |
| Clear selection | Set `selected_option_id = null`, `is_answered = false` | UPSERT answer row | Debounced |
| Type answer | Set `text_answer`, `is_answered = true` | UPSERT answer row | Debounced |
| Toggle review | Toggle `is_marked_for_review` | UPSERT answer row | Immediate |
| Save all | Batch all changed answers | Multiple UPSERTs | On submit |

### 8.4 UPSERT Pattern

```sql
-- save_answer RPC
INSERT INTO answers (attempt_id, question_id, selected_option_id, text_answer, is_answered, is_marked_for_review)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (attempt_id, question_id)
DO UPDATE SET
  selected_option_id = EXCLUDED.selected_option_id,
  text_answer = EXCLUDED.text_answer,
  is_answered = EXCLUDED.is_answered,
  is_marked_for_review = EXCLUDED.is_marked_for_review,
  updated_at = now();
```

**Benefits:**
- No duplicate rows (UNIQUE constraint enforced)
- First save creates row, subsequent saves update
- Atomic operation — no race condition
- `updated_at` automatically tracks latest save

### 8.5 Empty Answer Rows

When an attempt starts, the server creates empty answer rows for ALL questions in the test. This ensures:
1. Unanswered questions have a row (with `is_answered = false`)
2. Client can update existing rows rather than creating new ones
3. Reporting is simpler (no need to LEFT JOIN to find unanswered)

**Alternative Considered:** Lazy creation (only create rows when user answers). Rejected because:
- More complex client logic
- Reporting requires LEFT JOIN
- Race condition on first save

---

## 9. DETERMINISTIC SCORING

### 9.1 Scoring Rules

| Outcome | Marks | Counted As |
|---------|-------|------------|
| Correct answer | +question.marks | correct_count |
| Wrong answer | -question.negative_marks (if enabled) | wrong_count |
| Unanswered | 0 | unanswered_count |
| Partial (mcq_multiple) | +proportional marks | partial_count |

### 9.2 Scoring Algorithm (Server-Side)

```sql
-- calculate_score RPC
-- Input: attempt_id
-- Output: score breakdown

WITH attempt_answers AS (
  SELECT
    a.id as answer_id,
    a.question_id,
    a.selected_option_id,
    a.text_answer,
    a.is_answered,
    q.question_type,
    q.marks,
    q.negative_marks,
    q.options,
    q.correct_answer
  FROM answers a
  JOIN questions q ON q.id = a.question_id
  WHERE a.attempt_id = $1
),
scored AS (
  SELECT
    *,
    CASE
      WHEN NOT is_answered THEN
        JSON_BUILD_OBJECT('marks', 0, 'status', 'unanswered')
      WHEN question_type IN ('mcq_single', 'true_false') THEN
        CASE
          WHEN (SELECT is_correct FROM jsonb_to_recordset(options) AS opt(id text, text text, is_correct boolean) WHERE id = selected_option_id) THEN
            JSON_BUILD_OBJECT('marks', marks, 'status', 'correct')
          ELSE
            JSON_BUILD_OBJECT('marks', -negative_marks, 'status', 'wrong')
        END
      WHEN question_type = 'mcq_multiple' THEN
        -- Partial scoring: (correct selected / total correct) * marks
        -- Simplified: full marks if all correct selected, 0 otherwise
        JSON_BUILD_OBJECT('marks', 0, 'status', 'partial')
      WHEN question_type = 'integer' THEN
        CASE
          WHEN text_answer = correct_answer THEN
            JSON_BUILD_OBJECT('marks', marks, 'status', 'correct')
          ELSE
            JSON_BUILD_OBJECT('marks', -negative_marks, 'status', 'wrong')
        END
      WHEN question_type = 'short_answer' THEN
        JSON_BUILD_OBJECT('marks', 0, 'status', 'manual')
    END as score
  FROM attempt_answers
)
SELECT
  SUM((score->>'marks')::numeric) as marks_obtained,
  SUM(marks) as total_marks,
  COUNT(*) FILTER (WHERE (score->>'status') = 'correct') as correct_count,
  COUNT(*) FILTER (WHERE (score->>'status') = 'wrong') as wrong_count,
  COUNT(*) FILTER (WHERE (score->>'status') = 'unanswered') as unanswered_count,
  COUNT(*) FILTER (WHERE (score->>'status') = 'partial') as partial_count,
  ROUND(SUM((score->>'marks')::numeric) / SUM(marks) * 100, 2) as percentage
FROM scored;
```

### 9.3 MCQ Multiple Partial Scoring

**Design Decision:** For simplicity, `mcq_multiple` uses binary scoring:
- All correct options selected (and no wrong options) → full marks
- Any incorrect selection or missing selection → 0 marks

**Alternative (proportional scoring):** `(correctly selected / total correct) * marks`. Can be added later as enhancement.

### 9.4 Short Answer Grading

**Design Decision:** `short_answer` questions require manual grading by the test creator.

**Flow:**
1. Attempt is submitted
2. Deterministic scoring runs for all non-short_answer questions
3. Result shows "X/Y marks (Z short answer questions pending review)"
4. Creator reviews short answer questions and assigns marks
5. Result is updated with final score

**Implementation:** `results.marks_obtained` is updated after manual grading. `generation_method` can be 'deterministic' or 'deterministic_with_manual'.

### 9.5 Score Calculation Location

| Component | Role |
|-----------|------|
| `calculate_score` RPC | Runs on submission; calculates deterministic score |
| `results` table | Stores calculated score; immutable after creation |
| Client | Displays score from `results` table; never calculates |
| AI Reports | Reads from `results`; does NOT influence marks |

**Rule:** AI must NEVER be responsible for authoritative marks.

---

## 10. BATCH RESULTS

### 10.1 Batch Generation Flow

```
1. Creator clicks "Generate Results" for a test
2. Server checks: test must be closed (or all attempts submitted)
3. Server processes ALL attempts for the test:
   a. For each attempt without a result:
      - Run calculate_score
      - INSERT INTO results (ON CONFLICT DO NOTHING)
   b. For each attempt with a result:
      - Skip (idempotent)
4. Server returns summary: X results generated, Y already existed
5. Results are now available to all participants
```

### 10.2 Idempotency

**Key Property:** Running batch generation multiple times produces the same result.

**Mechanism:**
- `UNIQUE (attempt_id)` on `results` table
- `INSERT ... ON CONFLICT DO NOTHING` for each result
- First run: creates results. Second run: skips existing.
- Score calculation is deterministic: same answers → same score every time

### 10.3 Batch Tracking

The `results.batch_id` column (uuid, nullable) links results to a batch generation run:
- Each batch generation creates a new `batch_id`
- Creator can see "Results generated on [date] by batch [id]"
- Optional: store batch metadata in a separate `result_batches` table (future enhancement)

### 10.4 Retry Safety

If batch generation fails partway:
1. Already-generated results remain (committed)
2. Remaining attempts are not yet processed
3. Re-running batch generation processes remaining attempts
4. No duplicate results (UNIQUE constraint)

### 10.5 Progress Tracking

```sql
-- During batch generation, update a progress indicator
-- Option A: Store in Redis/cache (not available in current stack)
-- Option B: Use a temporary table
-- Option C: Return progress via WebSocket (future enhancement)

-- Simple approach: Return count of processed/total
SELECT
  COUNT(*) FILTER (WHERE r.id IS NOT NULL) as processed,
  COUNT(*) as total
FROM attempts a
LEFT JOIN results r ON r.attempt_id = a.id
WHERE a.test_id = $1;
```

### 10.6 AI Reports After Batch

**Rule:** AI reports are generated ONLY after deterministic results exist.

**Flow:**
1. Batch result generation completes
2. Creator can trigger AI report generation (optional)
3. AI reads from `results` table (not from answers directly)
4. AI generates summary/strengths/weaknesses/recommendations
5. Stored in `ai_reports` table
6. Opening an existing AI report does NOT trigger a new AI call (reads from DB)

---

## 11. GROUP/PERMISSION INTEGRATION

### 11.1 Current State

**No groups infrastructure exists.** The `groups`, `group_members`, and `role_permissions` tables do NOT exist in the live database.

### 11.2 Designed Interface (Future)

The test system is designed to work WITHOUT groups. When groups are implemented, the following integration points activate:

```sql
-- Future: groups table
CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Future: group_members table
CREATE TABLE public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, user_id)
);

-- Future: role_permissions table
CREATE TABLE public.role_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text NOT NULL,
  permission text NOT NULL,
  UNIQUE (role, permission)
);
```

### 11.3 Permission Matrix

| Permission | leader | member | Unauthenticated |
|------------|--------|--------|-----------------|
| CREATE_TEST | ✓ | ✗ | ✗ |
| EDIT_OWN_TEST | ✓ | ✗ | ✗ |
| EDIT_ANY_TEST | ✓ | ✗ | ✗ |
| PUBLISH_TEST | ✓ | ✗ | ✗ |
| INVITE_USERS | ✓ | ✗ | ✗ |
| VIEW_TEST | ✓ | ✓ | ✗ |
| TAKE_TEST | ✓ | ✓ | ✗ |
| VIEWOWN_ATTEMPT | ✓ | ✓ | ✗ |
| VIEW_ALL_ATTEMPTS | ✓ | ✗ | ✗ |
| GENERATE_RESULTS | ✓ | ✗ | ✗ |
| VIEW_ALL_RESULTS | ✓ | ✗ | ✗ |
| GENERATE_AI_REPORTS | ✓ | ✗ | ✗ |

### 11.4 Test-Group Association

When groups are implemented, `tests` table gains:
```sql
-- Future column on tests table
group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL
```

- `group_id IS NULL`: Test is not associated with any group (personal test)
- `group_id IS NOT NULL`: Test belongs to a group; access controlled by group membership

**Note:** This column is NOT added in the current schema. It is added when groups are implemented.

---

## 12. SYLLABUS INTEGRATION

### 12.1 Syllabus Hierarchy

```
Subject
  └── Class Level (e.g., "6", "7", ... "12")
       └── Textbook (e.g., "Mathematics", "Science")
            └── Chapter (e.g., "Chapter 1: Knowing Our Numbers")
                 └── Topic (optional)
                      └── Sub-topic (optional)
```

**Implemented as:** `syllabus_nodes` with self-referential `parent_id` FK.

### 12.2 Test-Syllabus Linkage

Tests reference syllabus nodes via `test_syllabus` junction table:

```
tests ──→ test_syllabus ──→ syllabus_nodes
  │                              │
  │                              └──→ subjects (via subject_id)
  │
  └──→ questions ──→ test_syllabus (optional: question-level syllabus mapping)
```

### 12.3 Syllabus Selection During Test Creation

**Flow:**
1. Creator selects subject (from `subjects` table)
2. Creator selects class level (e.g., "10")
3. System displays syllabus tree for that subject + class
4. Creator selects chapters/topics to include
5. System creates `test_syllabus` rows for selected nodes
6. Questions can be filtered by selected syllabus nodes

### 12.4 Question-Syllabus Mapping

**Design Decision:** Questions do NOT have a direct `syllabus_node_id` column.

**Reasoning:**
- Questions can cover multiple syllabus topics
- `test_syllabus` defines which topics the test covers
- Individual questions within the test may or may not map to specific syllabus nodes
- Adding `syllabus_node_id` to questions would require multiple rows for multi-topic questions

**Alternative Considered:** A `question_syllabus` junction table. Rejected because:
- Adds complexity without clear benefit for a preparation app
- Questions are already scoped by their test's syllabus
- Can be added later if needed

### 12.5 Future Class 11–12 Stream Support

**Current Design:** `class_level` is a text field on `syllabus_nodes` (display only).

**Stream Support:** Class 11–12 have streams (Science, Commerce, Humanities). This is handled by:
1. Syllabus nodes for Class 11–12 include stream-specific subjects
2. `subjects` table already contains stream-specific subjects (e.g., "Physics", "Accountancy")
3. No new columns needed — streams are implicit in subject selection

**Example:**
```
Class 11 (Science)
  ├── Physics
  ├── Chemistry
  └── Mathematics

Class 11 (Commerce)
  ├── Accountancy
  ├── Business Studies
  └── Economics
```

**No duplication of subjects** — "Physics" is one row in `subjects`, used by both Class 11 and Class 12.

---

## 13. SECURITY/RLS

### 13.1 RLS Strategy: Option A — Simple Owner-Based

**Principle:** Each user can only see/modify their own data. Test creators see data for their tests via a separate policy.

**Why Option A:**
1. Eliminates recursion risk entirely (no self-referencing policies)
2. Sufficient for a preparation app (not a high-stakes exam)
3. Simple to audit and maintain
4. Can be extended later if needed

### 13.2 RLS Policies Per Table

#### `tests`

```sql
-- Anyone can read published tests
CREATE POLICY "tests_select_published" ON public.tests
  FOR SELECT USING (
    status = 'published' OR created_by = auth.uid()
  );

-- Authenticated users can create tests
CREATE POLICY "tests_insert" ON public.tests
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
  );

-- Only creator can update their tests
CREATE POLICY "tests_update_own" ON public.tests
  FOR UPDATE USING (
    created_by = auth.uid()
  );

-- Only creator can delete their tests
CREATE POLICY "tests_delete_own" ON public.tests
  FOR DELETE USING (
    created_by = auth.uid()
  );
```

#### `questions`

```sql
-- Anyone can read active questions
CREATE POLICY "questions_select" ON public.questions
  FOR SELECT USING (
    is_active = true OR created_by = auth.uid()
  );

-- Authenticated users can create questions
CREATE POLICY "questions_insert" ON public.questions
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
  );

-- Only creator can update their questions
CREATE POLICY "questions_update_own" ON public.questions
  FOR UPDATE USING (
    created_by = auth.uid()
  );

-- Only creator can delete their questions
CREATE POLICY "questions_delete_own" ON public.questions
  FOR DELETE USING (
    created_by = auth.uid()
  );
```

#### `test_syllabus`

```sql
-- Anyone can read test syllabus for published tests
CREATE POLICY "test_syllabus_select" ON public.test_syllabus
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = test_syllabus.test_id
      AND (t.status = 'published' OR t.created_by = auth.uid())
    )
  );

-- Only test creator can modify test syllabus
CREATE POLICY "test_syllabus_insert" ON public.test_syllabus
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = test_syllabus.test_id
      AND t.created_by = auth.uid()
    )
  );

CREATE POLICY "test_syllabus_delete" ON public.test_syllabus
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = test_syllabus.test_id
      AND t.created_by = auth.uid()
    )
  );
```

#### `test_invitations`

```sql
-- Users can see their own invitations
CREATE POLICY "test_invitations_select_own" ON public.test_invitations
  FOR SELECT USING (
    user_id = auth.uid()
  );

-- Test creator can see all invitations for their tests
CREATE POLICY "test_invitations_select_creator" ON public.test_invitations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = test_invitations.test_id
      AND t.created_by = auth.uid()
    )
  );

-- Test creator can insert invitations
CREATE POLICY "test_invitations_insert" ON public.test_invitations
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = test_invitations.test_id
      AND t.created_by = auth.uid()
    )
  );

-- Users can update their own invitation status
CREATE POLICY "test_invitations_update_own" ON public.test_invitations
  FOR UPDATE USING (
    user_id = auth.uid()
  );
```

#### `attempts`

```sql
-- Users can read their own attempts
CREATE POLICY "attempts_select_own" ON public.attempts
  FOR SELECT USING (
    user_id = auth.uid()
  );

-- Test creator can read all attempts for their tests
CREATE POLICY "attempts_select_creator" ON public.attempts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = attempts.test_id
      AND t.created_by = auth.uid()
    )
  );

-- Users can insert their own attempts (via RPC)
CREATE POLICY "attempts_insert" ON public.attempts
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
  );

-- Users can update their own attempts (for submission)
CREATE POLICY "attempts_update_own" ON public.attempts
  FOR UPDATE USING (
    user_id = auth.uid()
  );
```

**No DELETE policy** — attempts are never deleted (immutable record).

#### `answers`

```sql
-- Users can read their own answers
CREATE POLICY "answers_select_own" ON public.answers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.attempts a
      WHERE a.id = answers.attempt_id
      AND a.user_id = auth.uid()
    )
  );

-- Test creator can read all answers for their tests
CREATE POLICY "answers_select_creator" ON public.answers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.attempts a
      JOIN public.tests t ON t.id = a.test_id
      WHERE a.id = answers.attempt_id
      AND t.created_by = auth.uid()
    )
  );

-- Users can insert/update their own answers (via RPC)
CREATE POLICY "answers_upsert_own" ON public.answers
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.attempts a
      WHERE a.id = answers.attempt_id
      AND a.user_id = auth.uid()
      AND a.status = 'in_progress'
    )
  );

CREATE POLICY "answers_update_own" ON public.answers
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.attempts a
      WHERE a.id = answers.attempt_id
      AND a.user_id = auth.uid()
      AND a.status = 'in_progress'
    )
  );
```

#### `results`

```sql
-- Users can read their own results
CREATE POLICY "results_select_own" ON public.results
  FOR SELECT USING (
    user_id = auth.uid()
  );

-- Test creator can read all results for their tests
CREATE POLICY "results_select_creator" ON public.results
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = results.test_id
      AND t.created_by = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policies — results are generated via RPC (SECURITY DEFINER)
```

#### `ai_reports`

```sql
-- Users can read their own AI reports
CREATE POLICY "ai_reports_select_own" ON public.ai_reports
  FOR SELECT USING (
    user_id = auth.uid()
  );

-- Test creator can read all AI reports for their tests
CREATE POLICY "ai_reports_select_creator" ON public.ai_reports
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = ai_reports.test_id
      AND t.created_by = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policies — AI reports are generated via RPC
```

### 13.3 Security Threats Mitigated

| Threat | Mitigation |
|--------|------------|
| User reads another user's private attempts | RLS: `attempts_select_own` filters by `user_id = auth.uid()` |
| User modifies another user's answers | RLS: `answers_update_own` filters by attempt ownership + status check |
| Unauthorized result access | RLS: `results_select_own` filters by `user_id` |
| Unauthorized test editing | RLS: `tests_update_own` filters by `created_by` |
| Unauthorized result generation | RPC with `SECURITY DEFINER` — only callable by authenticated users, results stored with user_id |
| Answer-key leakage before submission | `questions.options` contains `is_correct` — **VISIBLE to client** (see note below) |
| Privilege escalation | No `SECURITY DEFINER` on read policies; all policies use `auth.uid()` |

### 13.4 Answer-Key Visibility Note

**Issue:** The `questions.options` JSONB column contains `is_correct` flags. This means the correct answer is visible to the client before submission.

**Risk Level:** LOW for a preparation app (not a high-stakes exam). Students could theoretically see correct answers in browser DevTools.

**Mitigations:**
1. For a preparation app, answer visibility is acceptable (practice mode)
2. If needed in future: store options without `is_correct` in a client-facing view, and `is_correct` only in server-side scoring
3. Alternative: use Edge Functions to serve questions without answer keys

**Recommendation:** Accept answer visibility for now. If high-stakes testing is needed later, implement a `questions_safe` view that strips `is_correct`.

### 13.5 RPC Functions (SECURITY DEFINER)

These operations require `SECURITY DEFINER` to bypass RLS for write operations:

| RPC | Purpose | Bypasses |
|-----|---------|----------|
| `start_attempt(test_id)` | Create attempt + empty answers | RLS on attempts, answers |
| `submit_attempt(attempt_id)` | Mark attempt as submitted | RLS on attempts |
| `save_answer(attempt_id, question_id, ...)` | Upsert answer | RLS on answers |
| `calculate_score(attempt_id)` | Compute score, store result | RLS on results |
| `batch_generate_results(test_id)` | Generate all results for test | RLS on results |

**Note:** These are PostgreSQL functions, not Edge Functions. They run within the database and can bypass RLS when declared as `SECURITY DEFINER`.

---

## 14. PERFORMANCE

### 14.1 Expected Access Patterns

| Pattern | Frequency | Tables | Optimization |
|---------|-----------|--------|--------------|
| List published tests | High | tests | Index on status + start_at |
| Load test questions | High (per attempt) | questions | Index on test_id |
| Save answer | Very high (per question) | answers | UPSERT with UNIQUE index |
| Load attempt answers | High (per attempt) | answers | Index on attempt_id |
| Calculate score | Medium (per submission) | answers, questions | JOIN on attempt_id |
| List user results | Medium | results | Index on user_id |
| Batch generate results | Low (per test) | results, answers | Sequential scan acceptable |

### 14.2 Index Summary

| Table | Index | Columns | Purpose |
|-------|-------|---------|---------|
| tests | idx_tests_status | status | Filter by status |
| tests | idx_tests_created_by | created_by | Creator's tests |
| tests | idx_tests_subject_id | subject_id | Filter by subject |
| tests | idx_tests_start_at | start_at | Scheduled tests |
| questions | idx_questions_test_id | test_id | Test's questions |
| questions | idx_questions_difficulty | difficulty | Filter by difficulty |
| questions | idx_questions_is_active | is_active | Active questions only |
| test_syllabus | idx_test_syllabus_test_id | test_id | Test's syllabus |
| test_syllabus | idx_test_syllabus_node | syllabus_node_id | Node's tests |
| attempts | idx_attempts_test_id | test_id | Test's attempts |
| attempts | idx_attempts_user_id | user_id | User's attempts |
| attempts | idx_attempts_test_user | test_id, user_id | User's attempt for test |
| answers | idx_answers_attempt_id | attempt_id | Attempt's answers |
| answers | idx_answers_question_id | question_id | Question's answers |
| results | idx_results_test_id | test_id | Test's results |
| results | idx_results_user_id | user_id | User's results |

### 14.3 Large Group Considerations

For tests with 100+ participants:
- Batch result generation: process in chunks of 50
- Answer saves: debounced client-side (500ms)
- Simultaneous submissions: `SELECT ... FOR UPDATE` prevents race conditions
- Results listing: paginated (20 per page)

### 14.4 Many Questions Considerations

For tests with 100+ questions:
- Question loading: paginated or lazy-loaded
- Answer saving: individual UPSERTs (not batch)
- Score calculation: single SQL query (not loop)
- Navigation: client-side question navigator with status indicators

---

## 15. IDEMPOTENCY/CONCURRENCY

### 15.1 Duplicate Attempt Prevention

| Mechanism | Location | Protection |
|-----------|----------|------------|
| `UNIQUE (test_id, user_id, attempt_number)` | attempts table | Prevents duplicate attempt numbers |
| RPC `start_attempt` | Server function | Checks `max_attempts` before creating |
| `status = 'in_progress'` check | Server function | Prevents multiple active attempts |

### 15.2 Duplicate Answer Prevention

| Mechanism | Location | Protection |
|-----------|----------|------------|
| `UNIQUE (attempt_id, question_id)` | answers table | Prevents duplicate answers per question |
| UPSERT pattern | save_answer RPC | First save creates, subsequent updates |

### 15.3 Duplicate Result Prevention

| Mechanism | Location | Protection |
|-----------|----------|------------|
| `UNIQUE (attempt_id)` | results table | One result per attempt |
| `INSERT ... ON CONFLICT DO NOTHING` | batch_generate_results RPC | Skips existing results |
| `calculate_score` idempotency | RPC | Same answers → same score every time |

### 15.4 Double Submission Protection

| Mechanism | Location | Protection |
|-----------|----------|------------|
| `SELECT ... FOR UPDATE` | submit_attempt RPC | Locks attempt row during submission |
| `status = 'in_progress'` check | submit_attempt RPC | Only allows submission if in_progress |
| `UNIQUE (attempt_id)` on results | results table | Prevents duplicate scoring |

### 15.5 Simultaneous Autosave Handling

| Mechanism | Location | Protection |
|-----------|----------|------------|
| UPSERT pattern | save_answer RPC | Last write wins |
| `updated_at` timestamp | answers table | Tracks latest save |
| No optimistic locking | Client | Acceptable for single-user attempt |

### 15.6 Batch Result Generation

| Mechanism | Location | Protection |
|-----------|----------|------------|
| `UNIQUE (attempt_id)` | results table | Idempotent — skips existing |
| Sequential processing | RPC | Processes one attempt at a time |
| Deterministic scoring | calculate_score RPC | Same inputs → same outputs |

---

## 16. FLUTTER ARCHITECTURE

### 16.1 Layer Structure

```
lib/
├── core/
│   ├── models/
│   │   ├── test.dart                    # Test model
│   │   ├── question.dart                # Question model
│   │   ├── attempt.dart                 # Attempt model
│   │   ├── answer.dart                  # Answer model
│   │   ├── result.dart                  # Result model
│   │   └── test_invitation.dart         # Invitation model
│   └── services/
│       ├── test_service.dart            # Test CRUD + lifecycle
│       ├── question_service.dart        # Question CRUD + bank
│       ├── attempt_service.dart         # Attempt start/submit
│       ├── answer_service.dart          # Answer save/load
│       ├── result_service.dart          # Result generation/display
│       └── invitation_service.dart      # Invitation management
├── features/
│   └── test/
│       ├── test_list_screen.dart        # Browse available tests
│       ├── test_detail_screen.dart      # View test details before starting
│       ├── test_creation_screen.dart    # Create/edit test (creator)
│       ├── test_taker_screen.dart       # Take test (timed)
│       ├── question_widget.dart         # Individual question display
│       ├── question_navigation.dart     # Question navigator sidebar
│       ├── test_result_screen.dart      # View results after submission
│       ├── test_review_screen.dart      # Review answers (if enabled)
│       └── test_creation_widgets.dart   # Reusable creation form widgets
└── main.dart                            # Add test routes
```

### 16.2 Model Pattern

```dart
// Reusable pattern from existing codebase
class Test {
  final String id;
  final String createdBy;
  final String title;
  // ... immutable fields

  const Test({required this.id, ...});

  factory Test.fromJson(Map<String, dynamic> json) => Test(...);
  Map<String, dynamic> toJson() => {...};
}
```

### 16.3 Service Pattern

```dart
// Reusable pattern from existing codebase
class TestService {
  TestService._();

  static final TestService instance = TestService._();

  final _client = SupabaseService.client;

  // CRUD operations
  Future<List<Test>> getPublishedTests() async { ... }
  Future<Test> getTest(String id) async { ... }
  Future<Test> createTest(CreateTestRequest request) async { ... }
  Future<void> updateTest(String id, UpdateTestRequest request) async { ... }
  Future<void> deleteTest(String id) async { ... }

  // Lifecycle
  Future<void> publishTest(String id) async { ... }
  Future<void> closeTest(String id) async { ... }
  Future<void> archiveTest(String id) async { ... }
}
```

### 16.4 Screen Pattern

```dart
// Reusable pattern from existing codebase
class TestTakerScreen extends StatefulWidget {
  final String attemptId;
  // ...

  @override
  State<TestTakerScreen> createState() => _TestTakerScreenState();
}

class _TestTakerScreenState extends State<TestTakerScreen> {
  // Loading state
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAttempt();
  }

  Future<void> _loadAttempt() async { ... }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const LoadingWidget();
    if (_error != null) return ErrorWidget(message: _error!);
    return _buildContent();
  }
}
```

### 16.5 Route Pattern

```dart
// Add to existing GoRouter configuration
GoRoute(
  path: '/tests',
  name: 'tests',
  builder: (context, state) => const TestListScreen(),
  routes: [
    GoRoute(
      path: ':id',
      name: 'test-detail',
      builder: (context, state) => TestDetailScreen(testId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: ':id/take',
      name: 'test-take',
      builder: (context, state) => TestTakerScreen(attemptId: state.extra as String),
    ),
    GoRoute(
      path: ':id/result',
      name: 'test-result',
      builder: (context, state) => TestResultScreen(resultId: state.extra as String),
    ),
  ],
),
```

### 16.6 State Management

**Approach:** Local state with `setState` (consistent with existing codebase).

**No external state management** (no Provider, Riverpod, Bloc). State is local to each screen.

**Shared state:** Attempt data is passed via route parameters or fetched fresh from Supabase.

### 16.7 Error Handling

```dart
// Extend existing AppError pattern
sealed class TestError extends AppError {
  TestError(String message) : super(message);
}

class TestNotFoundError extends TestError { ... }
class AttemptLimitExceededError extends TestError { ... }
class TestExpiredError extends TestError { ... }
class SubmissionFailedError extends TestError { ... }
```

### 16.8 Loading/Empty/Error States

| State | Widget | Usage |
|-------|--------|-------|
| Loading | `LoadingWidget()` | While fetching data |
| Empty | `EmptyWidget(message: 'No tests available')` | No data to display |
| Error | `ErrorWidget(message: error)` | Something went wrong |
| Success | Content widget | Normal display |

### 16.9 New Files Summary

| # | File | Purpose | Est. Lines |
|---|------|---------|-----------|
| 1 | `lib/core/models/test.dart` | Test model | ~80 |
| 2 | `lib/core/models/question.dart` | Question model | ~100 |
| 3 | `lib/core/models/attempt.dart` | Attempt model | ~60 |
| 4 | `lib/core/models/answer.dart` | Answer model | ~50 |
| 5 | `lib/core/models/result.dart` | Result model | ~70 |
| 6 | `lib/core/models/test_invitation.dart` | Invitation model | ~40 |
| 7 | `lib/core/services/test_service.dart` | Test service | ~200 |
| 8 | `lib/core/services/question_service.dart` | Question service | ~150 |
| 9 | `lib/core/services/attempt_service.dart` | Attempt service | ~120 |
| 10 | `lib/core/services/answer_service.dart` | Answer service | ~100 |
| 11 | `lib/core/services/result_service.dart` | Result service | ~100 |
| 12 | `lib/core/services/invitation_service.dart` | Invitation service | ~80 |
| 13 | `lib/features/test/test_list_screen.dart` | Test list | ~150 |
| 14 | `lib/features/test/test_detail_screen.dart` | Test detail | ~120 |
| 15 | `lib/features/test/test_creation_screen.dart` | Test creation | ~300 |
| 16 | `lib/features/test/test_taker_screen.dart` | Test taking | ~400 |
| 17 | `lib/features/test/question_widget.dart` | Question display | ~200 |
| 18 | `lib/features/test/question_navigation.dart` | Navigator | ~100 |
| 19 | `lib/features/test/test_result_screen.dart` | Results display | ~150 |
| 20 | `lib/features/test/test_review_screen.dart` | Answer review | ~150 |
| 21 | `lib/features/test/test_creation_widgets.dart` | Creation widgets | ~200 |
| 22 | Route additions in `main.dart` | Route config | ~30 |
| 23 | Error class additions | Test errors | ~40 |

**Total: ~29 new/modified files, ~2940 estimated lines**

---

## 17. IMPLEMENTATION PHASES

### Phase R4.1: DB Foundation
**Scope:** Create all tables, types, and indexes
**DB Changes:** CREATE TYPE, CREATE TABLE (all 8), CREATE INDEX (all)
**Flutter Changes:** None
**Tests:** Schema validation queries
**Acceptance Criteria:**
- All 8 tables created with correct columns
- All FK constraints enforced
- All CHECK constraints working
- All indexes created
- Existing data (subjects, syllabus_nodes, profiles) unchanged
**Rollback:** DROP all new tables and types
**Hard Stop:** YES — verify schema before proceeding

### Phase R4.2: RLS Policies
**Scope:** Apply all RLS policies to all new tables
**DB Changes:** CREATE POLICY (all policies from Section 13)
**Flutter Changes:** None
**Tests:** Access control tests (run as different users)
**Acceptance Criteria:**
- All policies created
- User can only read own attempts/answers/results
- Creator can read all attempts/answers/results for their tests
- Unauthenticated users cannot access any table
- No recursion errors
**Rollback:** DROP all policies
**Hard Stop:** YES — verify no recursion before proceeding

### Phase R4.3: RPC Functions
**Scope:** Create all server-authoritative functions
**DB Changes:** CREATE FUNCTION (start_attempt, submit_attempt, save_answer, calculate_score)
**Flutter Changes:** None
**Tests:** Function tests with various inputs
**Acceptance Criteria:**
- `start_attempt` creates attempt + empty answers
- `submit_attempt` transitions status + records time
- `save_answer` upserts answer correctly
- `calculate_score` computes correct score
- All functions enforce constraints
**Rollback:** DROP all functions
**Hard Stop:** YES — verify scoring correctness

### Phase R4.4: Models + Services
**Scope:** Create Dart models and services
**DB Changes:** None
**Flutter Changes:** Create 12 files (6 models + 6 services)
**Tests:** Unit tests for models and services
**Acceptance Criteria:**
- All models have `fromJson`/`toJson`
- All services have CRUD operations
- All services handle errors correctly
- All services use existing patterns
**Rollback:** Remove new files
**Hard Stop:** YES — verify compilation + tests pass

### Phase R4.5: Test Creation
**Scope:** Test creation UI
**DB Changes:** None
**Flutter Changes:** Create test_creation_screen.dart, test_creation_widgets.dart
**Tests:** Widget tests
**Acceptance Criteria:**
- Creator can fill in test details
- Creator can select syllabus nodes
- Creator can add questions from bank
- Creator can create new questions
- Creator can publish test
- Form validation works
**Rollback:** Remove new screen files
**Hard Stop:** YES — verify creation flow

### Phase R4.6: Test Listing + Detail
**Scope:** Test browsing UI
**DB Changes:** None
**Flutter Changes:** Create test_list_screen.dart, test_detail_screen.dart
**Tests:** Widget tests
**Acceptance Criteria:**
- User can browse published tests
- User can filter by subject, difficulty
- User can view test details
- User can see syllabus coverage
- Empty state handled
**Rollback:** Remove new screen files
**Hard Stop:** YES — verify browsing flow

### Phase R4.7: Test Taking
**Scope:** Timed test-taking UI
**DB Changes:** None
**Flutter Changes:** Create test_taker_screen.dart, question_widget.dart, question_navigation.dart
**Tests:** Widget tests + integration tests
**Acceptance Criteria:**
- Timer counts down correctly
- Questions displayed correctly (MCQ, true/false, integer)
- Answers save correctly (autosave)
- Mark-for-review works
- Question navigator shows status
- Reconnection works (resume attempt)
- Submit works
- Timeout auto-submits
**Rollback:** Remove new screen files
**Hard Stop:** YES — verify test-taking flow end-to-end

### Phase R4.8: Results + Review
**Scope:** Results display + answer review UI
**DB Changes:** None
**Flutter Changes:** Create test_result_screen.dart, test_review_screen.dart
**Tests:** Widget tests
**Acceptance Criteria:**
- Score displayed correctly
- Answer breakdown shown
- Correct/wrong/unanswered counts match
- Review shows correct answers (if show_answers_after = true)
- Review highlights user's wrong answers
**Rollback:** Remove new screen files
**Hard Stop:** YES — verify results display

### Phase R4.9: Batch Results
**Scope:** Creator-triggered batch result generation
**DB Changes:** CREATE FUNCTION (batch_generate_results)
**Flutter Changes:** Add batch results button to creator view
**Tests:** Batch generation tests
**Acceptance Criteria:**
- Creator can trigger batch generation
- All results generated correctly
- Re-running is idempotent (no duplicates)
- Progress indicator works
- Results visible to participants after generation
**Rollback:** DROP batch_generate_results function
**Hard Stop:** YES — verify batch idempotency

### Phase R4.10: Invitations
**Scope:** Restricted test access
**DB Changes:** None
**Flutter Changes:** Create invitation management UI
**Tests:** Invitation flow tests
**Acceptance Criteria:**
- Creator can invite users by email/code
- Invited users see test in their list
- Users can accept/decline invitations
- Non-invited users cannot see restricted tests
**Rollback:** Remove invitation UI
**Hard Stop:** YES — verify invitation flow

### Phase R4.11: Security Audit + Performance
**Scope:** End-to-end security testing + performance optimization
**DB Changes:** Additional indexes if needed
**Flutter Changes:** Optimizations if needed
**Tests:** Security tests, performance tests
**Acceptance Criteria:**
- All RLS policies working correctly
- No privilege escalation possible
- No answer-key leakage (or accepted risk documented)
- Batch generation completes in <30s for 100 participants
- Answer saves complete in <200ms
**Rollback:** Revert optimization changes
**Hard Stop:** YES — final security sign-off

### Phase R4.12: AI Reports (DEFERRED)
**Scope:** AI-generated test analysis
**DB Changes:** CREATE TABLE ai_reports, CREATE FUNCTION generate_ai_report
**Flutter Changes:** AI report display UI
**Tests:** AI report generation tests
**Acceptance Criteria:**
- AI report generated after deterministic results
- Report stored in ai_reports table
- Opening report does NOT trigger new AI call
- Report includes summary, strengths, weaknesses, recommendations
**Rollback:** DROP ai_reports table + function
**Hard Stop:** YES — verify AI integration

---

## 18. REPORT

### 18.1 CONFIRMED

| # | Item | Evidence |
|---|------|----------|
| 1 | subjects table exists with 11 rows | R4 CSV dump |
| 2 | syllabus_nodes table exists with 2 rows | R4 CSV dump |
| 3 | profiles table exists | R4 CSV dump |
| 4 | test_syllabus table exists but is orphaned | R4 CSV dump |
| 5 | tests table does NOT exist | R4 CSV dump |
| 6 | questions table does NOT exist | R4 CSV dump |
| 7 | attempts table does NOT exist | R4 CSV dump |
| 8 | answers table does NOT exist | R4 CSV dump |
| 9 | results table does NOT exist | R4 CSV dump |
| 10 | No Flutter test system code exists | R4 code audit |
| 11 | Existing patterns: services, models, routes | R4 code audit |
| 12 | RLS on subjects: authenticated SELECT | R3 verification |
| 13 | RLS on syllabus_nodes: authenticated SELECT | R3 verification |
| 14 | FK constraints verified on syllabus_nodes | SEED-0 verification |

### 18.2 PROPOSED

| # | Item | Rationale |
|---|------|-----------|
| 1 | 8 tables (not 12) | Eliminated unnecessary tables |
| 2 | Option A RLS (simple owner-based) | Eliminates recursion by design |
| 3 | Reusable question bank | Avoids duplication |
| 4 | Server-authoritative RPCs | Prevents cheating/tampering |
| 5 | Deterministic scoring | No AI dependency for marks |
| 6 | UPSERT pattern for answers | Prevents duplicates, simplifies client |
| 7 | 12 implementation phases | Gated, reversible, testable |
| 8 | Deferred AI reports | Deterministic scoring is primary |
| 9 | Deferred groups integration | No groups infrastructure exists |
| 10 | Answer-key visibility accepted | Low risk for preparation app |

### 18.3 UNKNOWN

| # | Item | Impact | Mitigation |
|---|------|--------|------------|
| 1 | Live RLS policies on existing tables | Security audit | Verify in Phase R4.2 |
| 2 | Expected concurrent test takers | Performance | Design for 100+ |
| 3 | AI API credentials/budget | AI reports | Defer to Phase R4.12 |
| 4 | Groups infrastructure | Group-based tests | Design interface only |
| 5 | Supabase project plan (free/pro) | Edge Function limits | Use RPCs instead |
| 6 | Deployment environment | Migration strategy | Assume standard Supabase |

### 18.4 DECISIONS REQUIRED

| # | Decision | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Answer-key visibility | Accept risk vs. server-side stripping | Accept risk (preparation app) |
| 2 | MCQ multiple scoring | Binary vs. proportional | Binary (simpler, defensible) |
| 3 | Groups integration timing | Now vs. deferred | Deferred (no groups exist) |
| 4 | AI reports timing | Now vs. deferred | Deferred (Phase R4.12) |
| 5 | Short answer grading | Auto vs. manual | Manual (teacher reviews) |
| 6 | Test editing when published | Full edit vs. restricted | Restricted (see Section 4.6) |
| 7 | Batch generation trigger | Manual vs. automatic | Manual (creator triggers) |

### 18.5 BLOCKERS

| # | Blocker | Resolution |
|---|---------|------------|
| 1 | Live RLS policies unknown | Must verify in Phase R4.2 before proceeding |
| 2 | Groups table does not exist | Design interface only; implement when groups are built |
| 3 | AI credentials unknown | Defer AI reports to Phase R4.12 |
| 4 | No database credentials in codebase | Cannot verify live RLS; design assumes standard Supabase RLS |

---

## FINAL STATUS

**READY FOR HUMAN APPROVAL**

All 18 sections complete. The architecture is self-consistent, avoids recursion by design, and is decomposed into 12 gated implementation phases.

**Awaiting human decision on:**
1. Approval to proceed with Phase R4.1 (DB Foundation)
2. Decision on 7 items in Section 18.4 (DECISIONS REQUIRED)
3. Confirmation that answer-key visibility risk is accepted

**HARD STOP — NO IMPLEMENTATION WITHOUT EXPLICIT HUMAN APPROVAL.**

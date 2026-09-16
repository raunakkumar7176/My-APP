# R4: Test System Discovery & Architecture Audit

**Project:** My Preparation  
**Date:** 2026-09-12  
**Status:** DISCOVERY COMPLETE — BLOCKED (schema does not exist)  
**Mode:** READ-ONLY AUDIT — NO DATABASE MODIFICATION

---

## 1. Executive Summary

### Critical Finding

**The test system does not exist.** Of the 12 tables listed in the audit request, only 1 (`test_syllabus`) exists in the live database, and it is an orphaned junction table referencing a `tests` table that does not exist. The remaining 11 tables (`tests`, `questions`, `question_bank`, `attempts`, `answers`, `test_invitations`, `results`, `result_batches`, `ai_jobs`, `ai_reports`, `integrity_events`) have never been created.

### What Exists

| Table | Status | Notes |
|-------|--------|-------|
| `subjects` | ✓ EXISTS | 11 rows, fully functional |
| `syllabus_nodes` | ✓ EXISTS | 2 rows (Hindi), verified |
| `profiles` | ✓ EXISTS | Verified in R2 |
| `study_materials` | ✓ EXISTS | Functional |
| `node_materials` | ✓ EXISTS | Junction table |
| `material_chunks` | ✓ EXISTS | Content storage |
| `progress_snapshots` | ✓ EXISTS | User progress |
| `routines` | ✓ EXISTS | Deferred (not implemented) |
| `routine_logs` | ✓ EXISTS | Deferred |
| `test_syllabus` | ✓ EXISTS | **ORPHANED** — references nonexistent `tests` table |

### What Does NOT Exist

| Table | Status | Required For |
|-------|--------|-------------|
| `tests` | **NOT FOUND** | Test metadata, configuration |
| `questions` | **NOT FOUND** | Question content, options |
| `question_bank` | **NOT FOUND** | Reusable question pool |
| `attempts` | **NOT FOUND** | Student test attempts |
| `answers` | **NOT FOUND** | Individual answer records |
| `test_invitations` | **NOT FOUND** | Access control, group invites |
| `results` | **NOT FOUND** | Final scores, outcomes |
| `result_batches` | **NOT FOUND** | Batch result generation |
| `ai_jobs` | **NOT FOUND** | AI processing queue |
| `ai_reports` | **NOT FOUND** | AI coach reports |
| `integrity_events` | **NOT FOUND** | Cheating detection |
| `groups` | **NOT FOUND** | Group/class management |
| `group_members` | **NOT FOUND** | Group membership |

### Flutter Code Status

**Zero test system implementation exists in Flutter code:**
- No test models, services, screens, or repositories
- No question, attempt, answer, or result code
- No quiz/test feature code whatsoever
- No RPC calls related to testing
- No Edge Function calls

### Implications

R4 cannot be an "audit and fix" — it must be a **greenfield build** of the entire test system. The `test_syllabus` table is an orphaned artifact that must either be incorporated into the new schema or dropped.

### Recommendation

**BLOCKED — DISCOVERY INCOMPLETE**

The test system requires creating ~12 new database tables, ~15+ new Flutter files, and ~5+ new RPCs/Edge Functions from scratch. This is a full R4 implementation, not an audit of existing code.

---

## 2. Live Schema Inventory

### 2.1 Tables That Exist (VERIFIED from R3 CSV dump)

#### `subjects`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `name` | text | NOT NULL | — | Subject name |

**RLS:** Unknown (not provided in schema dump)  
**Indexes:** Primary key on `id`  
**Row count:** 11

#### `syllabus_nodes`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `subject_id` | uuid | NOT NULL | — | FK → `subjects.id` |
| `parent_id` | uuid | NULLABLE | NULL | Self-referential FK → `syllabus_nodes.id` |
| `class_level` | text | NULLABLE | NULL | Display-only |
| `name` | text | NOT NULL | — | Node name |
| `created_at` | timestamptz | NOT NULL | `now()` | Timestamp |

**RLS:** Authenticated SELECT confirmed (from R3.5 queries)  
**Indexes:** PK on `id`, index on `subject_id`  
**FK constraints:** `subject_id → subjects.id`, `parent_id → syllabus_nodes.id`  
**Unique constraints:** None  
**Row count:** 2 (both Hindi)

#### `profiles`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | — | PK, FK → `auth.users.id` |
| `full_name` | text | NULLABLE | — | Display name |
| `avatar_url` | text | NULLABLE | — | Profile image |
| `timezone` | text | NULLABLE | — | User timezone |
| `created_at` | timestamptz | NOT NULL | `now()` | Timestamp |
| `student_code` | text | NULLABLE | — | Unique student ID |
| `bio` | text | NULLABLE | — | Bio text |
| `mobile` | text | NULLABLE | — | Phone number |
| `exam_targets` | jsonb | NULLABLE | — | Target exams |

**RLS:** Verified in R2 — authenticated SELECT, own profile UPDATE  
**RPC:** `fn_ensure_profile()` creates profile if missing  
**Row count:** Unknown

#### `study_materials`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `group_id` | uuid | NOT NULL | — | FK → unknown (groups not found) |
| `uploaded_by` | uuid | NOT NULL | — | FK → `auth.users.id` |
| `title` | text | NOT NULL | — | Material title |
| `storage_path` | text | NOT NULL | — | Supabase Storage path |
| `mime_type` | text | NULLABLE | — | File type |
| `status` | material_status | NOT NULL | — | Enum |
| `created_at` | timestamptz | NOT NULL | `now()` | Timestamp |

**RLS:** Unknown  
**Enum:** `material_status` (values: uploaded, processing, ready, etc.)  
**Warning:** `group_id` is NOT NULL but no `groups` table exists

#### `node_materials`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `node_id` | uuid | NOT NULL | — | FK → `syllabus_nodes.id` |
| `material_id` | uuid | NOT NULL | — | FK → `study_materials.id` |
| `linked_by` | uuid | NOT NULL | — | FK → `auth.users.id` |
| `created_at` | timestamptz | NOT NULL | `now()` | Timestamp |

**RLS:** Unknown  
**Purpose:** Junction table linking syllabus nodes to materials (M:N)

#### `material_chunks`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `material_id` | uuid | NOT NULL | — | FK → `study_materials.id` |
| `idx` | integer | NOT NULL | — | Chunk order |
| `content` | text | NOT NULL | — | Chunk content |

**RLS:** Unknown  
**Purpose:** Stores material content in ordered chunks

#### `progress_snapshots`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `user_id` | uuid | NOT NULL | — | FK → `auth.users.id` |
| `period_type` | text | NOT NULL | — | e.g., "weekly", "monthly" |
| `period_start` | date | NOT NULL | — | Period start date |
| `stats` | jsonb | NULLABLE | — | Computed statistics |
| `computed_at` | timestamptz | NOT NULL | `now()` | When computed |

**RLS:** Unknown  
**Purpose:** Periodic progress tracking

#### `routines`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `user_id` | uuid | NOT NULL | — | FK → `auth.users.id` |
| `subject_id` | uuid | NULLABLE | — | FK → `subjects.id` |
| `title` | text | NOT NULL | — | Routine name |
| `start_time` | time | NOT NULL | — | Start time |
| `end_time` | time | NOT NULL | — | End time |
| `weekdays` | int4[] | NOT NULL | — | Array of weekday numbers |
| `reminder_enabled` | bool | NOT NULL | `false` | Reminder flag |
| `is_active` | bool | NOT NULL | `true` | Active flag |

**RLS:** Unknown  
**Status:** DEFERRED — not implemented in Flutter

#### `routine_logs`

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | PK |
| `routine_id` | uuid | NOT NULL | — | FK → `routines.id` |
| `log_date` | date | NOT NULL | — | Log date |
| `completed` | bool | NOT NULL | — | Completion status |
| `status` | text | NOT NULL | — | Status text |

**RLS:** Unknown  
**Status:** DEFERRED

#### `test_syllabus` (ORPHANED)

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `test_id` | uuid | NOT NULL | — | FK → `tests.id` (**TABLE DOES NOT EXIST**) |
| `syllabus_node_id` | uuid | NOT NULL | — | FK → `syllabus_nodes.id` |
| `material_ids` | uuid[] | NULLABLE | — | Array of material IDs |

**RLS:** Unknown  
**Status:** ORPHANED — `test_id` references a `tests` table that does not exist  
**Action:** Must be either incorporated into new schema or dropped

### 2.2 Tables That Do NOT Exist

| Table | Requested Status | Actual Status |
|-------|-----------------|---------------|
| `tests` | Inspect | **NOT FOUND** |
| `questions` | Inspect | **NOT FOUND** |
| `question_bank` | Inspect | **NOT FOUND** |
| `attempts` | Inspect | **NOT FOUND** |
| `answers` | Inspect | **NOT FOUND** |
| `test_invitations` | Inspect | **NOT FOUND** |
| `results` | Inspect | **NOT FOUND** |
| `result_batches` | Inspect | **NOT FOUND** |
| `ai_jobs` | Inspect | **NOT FOUND** |
| `ai_reports` | Inspect | **NOT FOUND** |
| `integrity_events` | Inspect | **NOT FOUND** |
| `groups` | Historical reference | **NOT FOUND** |
| `group_members` | Historical reference | **NOT FOUND** |
| `role_permissions` | Historical reference | **NOT FOUND** |

### 2.3 Known Enums/Types

| Enum | Values | Used By |
|------|--------|---------|
| `material_status` | uploaded, processing, ready, (others unknown) | `study_materials.status` |

No test-related enums exist (no `attempt_status`, `question_type`, `test_status`, etc.).

### 2.4 Known Functions/RPCs

| Function | Purpose | Status |
|----------|---------|--------|
| `fn_ensure_profile()` | Auto-create profile for new user | EXISTS, used in R2 |

No test-related functions exist.

### 2.5 Known Triggers

**None documented.** Schema dump did not include trigger information.

### 2.6 RLS Status

**UNKNOWN for all tables.** The R3 CSV dump did not include RLS policies. The R3.5 seed plan queries include RLS inspection SQL but results have not been reported.

**What is assumed (from R3 report):**
- Authenticated users can SELECT from `subjects`, `syllabus_nodes`, `study_materials`, `node_materials`, `material_chunks`
- Authenticated users can SELECT from `progress_snapshots` filtered by `user_id`
- All queries use normal Supabase client (anon key), relying on RLS

**What is NOT verified:**
- Whether RLS is actually enabled on any table
- What specific policies exist
- Whether INSERT/UPDATE/DELETE policies exist
- Whether the `attempts` RLS recursion issue exists (attempts table doesn't exist)

---

## 3. Relationship Map

### 3.1 Existing Relationships (VERIFIED from schema)

```
auth.users (Supabase Auth)
    │
    ├──< profiles.id                    (1:1, profile per user)
    ├──< study_materials.uploaded_by    (1:N, user uploads materials)
    ├──< progress_snapshots.user_id     (1:N, user progress records)
    ├──< routines.user_id               (1:N, user routines)
    ├──< node_materials.linked_by       (1:N, user links materials)
    │
subjects (id)
    │
    ├──< syllabus_nodes.subject_id      (1:N, subject has many nodes)
    ├──< routines.subject_id            (1:N, optional routine subject)
    │
syllabus_nodes (id)
    │
    ├──< syllabus_nodes.parent_id       (self-referential, tree)
    ├──< node_materials.node_id         (M:N with study_materials)
    ├──< test_syllabus.syllabus_node_id (ORPHANED, tests don't exist)
    │
study_materials (id)
    │
    ├──< node_materials.material_id     (M:N with syllabus_nodes)
    ├──< material_chunks.material_id    (1:N, content chunks)
    │
routines (id)
    │
    └──< routine_logs.routine_id        (1:N, daily logs)
```

### 3.2 Missing Relationships (for test system)

The following relationships are NEEDED but DO NOT EXIST:

```
tests (DOES NOT EXIST)
    │
    ├──< questions.test_id              (1:N, test has many questions)
    ├──< attempts.test_id               (1:N, test has many attempts)
    ├──< test_syllabus.test_id          (1:N, ORPHANED - table exists but tests doesn't)
    ├──< test_invitations.test_id       (1:N, test has many invitations)
    └──> results.test_id                (N:1, results belong to test)
        │
questions (DOES NOT EXIST)
    │
    └──< answers.question_id            (1:N, question has many answers)
        │
attempts (DOES NOT EXIST)
    │
    ├──< answers.attempt_id             (1:N, attempt has many answers)
    └──> results.attempt_id             (1:1, attempt has one result)
        │
results (DOES NOT EXIST)
    │
    └──< result_batch_id                (N:1, results belong to batch)
        │
result_batches (DOES NOT EXIST)
    │
    └──> ai_jobs.batch_id               (1:N, batch triggers AI jobs)
        │
ai_jobs (DOES NOT EXIST)
    │
    └──< ai_reports.job_id              (1:N, job produces reports)
        │
ai_reports (DOES NOT EXIST)
    │
    └──> attempts.ai_report_id          (1:1, attempt gets one AI report)
        │
integrity_events (DOES NOT EXIST)
    │
    └──> attempts.integrity_events      (1:N, attempt has many events)
```

### 3.3 Visual Relationship Map

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ auth.users  │────<│    profiles      │     │    subjects     │
│             │     └──────────────────┘     └────────┬────────┘
│             │────<┌──────────────────┐              │
│             │     │progress_snapshots│              │
│             │     └──────────────────┘              │
│             │────<┌──────────────────┐              │
│             │     │    routines      │              │
│             │     └────────┬─────────┘              │
│             │              │                        │
│             │────<┌───────┴────────┐     ┌─────────┴────────┐
│             │     │  routine_logs  │     │  syllabus_nodes  │
│             │     └────────────────┘     └────────┬─────────┘
│             │                                     │
│             │────<┌──────────────────┐            │
│             │     │ node_materials   │>───────────┘
│             │     └────────┬─────────┘
│             │              │
│             │────<┌────────┴─────────┐
│             │     │ study_materials  │
│             │     └────────┬─────────┘
│             │              │
│             │              └────────<┌─────────────────┐
│             │                        │ material_chunks  │
│             │                        └─────────────────┘
│             │
│             │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
│             │  │   NOT YET CREATED                      │
│             │  │                                        │
│             │────<┌──────────────────┐                 │
│             │     │     tests        │                 │
│             │     └────────┬─────────┘                 │
│             │              │                            │
│             │────<┌────────┴─────────┐  ┌─────────────┴───────┐
│             │     │   questions      │  │  test_syllabus       │
│             │     └────────┬─────────┘  │  (ORPHANED)          │
│             │              │            └──────────────────────┘
│             │────<┌────────┴─────────┐
│             │     │    attempts      │
│             │     └────────┬─────────┘
│             │              │
│             │     ┌────────┴─────────┐     ┌─────────────────┐
│             │     │    answers       │     │    results      │
│             │     └──────────────────┘     └────────┬────────┘
│             │                                      │
│             │     ┌──────────────────┐     ┌───────┴────────┐
│             │     │test_invitations  │     │ result_batches  │
│             │     └──────────────────┘     └───────┬────────┘
│             │                                      │
│             │     ┌──────────────────┐     ┌───────┴────────┐
│             │     │ integrity_events │     │    ai_jobs      │
│             │     └──────────────────┘     └───────┬────────┘
│             │                                      │
│             │     ┌──────────────────┐     ┌───────┴────────┐
│             │     │  question_bank   │     │   ai_reports    │
│             │     └──────────────────┘     └────────────────┘
│             │
└─────────────┘
  └ ─ ─ ─ ─ ─ ─┘
```

---

## 4. RLS Policy Audit

### 4.1 Current RLS Status

**RLS status is UNKNOWN for all tables.** The R3 CSV dump did not include RLS policy information. The R3.5 seed plan includes SQL queries to inspect RLS, but results have not been provided.

### 4.2 RLS Inspection Queries (from R3.5)

The following queries exist in `docs/R3_5_SYLLABUS_DATA_SPECIFICATION.md` and `docs/R3_5_SEED_1_MATH_CLASS6_PLAN.md`:

```sql
-- A. Check RLS status for a table
SELECT
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'TABLE_NAME'
AND n.nsppublic = 'public';

-- B. List RLS policies for a table
SELECT
  polname AS policy_name,
  polcmd AS command,
  polqual AS using_expr,
  polwithcheck AS with_check_expr
FROM pg_policy
WHERE polrelid = 'public.TABLE_NAME'::regclass;
```

**These queries have NOT been run against the live database.** Results are UNKNOWN.

### 4.3 What RLS Must Exist (for test system to work)

For the test system to function, the following RLS policies will be NEEDED:

| Table | Required Policies | Purpose |
|-------|-------------------|---------|
| `tests` | Creator can CRUD, participants can read published | Test management |
| `questions` | Creator can CRUD, attempt context for students | Question access |
| `attempts` | Own attempts, creator can read all | Attempt management |
| `answers` | Own answers, creator can read for grading | Answer management |
| `results` | Own results, creator can read all | Result visibility |
| `test_invitations` | Creator can manage, invitee can read | Invitation flow |
| `integrity_events` | Creator can read, system can insert | Integrity monitoring |

### 4.4 RLS Policy Design Constraints

**Key constraint:** The `attempts` table RLS recursion issue (documented in historical records) must be designed around from the start. See Part 5 for analysis.

---

## 5. Attempts RLS Recursion — CRITICAL

### 5.1 Historical Record

The R3 report references an "infinite recursion detected in policy for relation 'attempts'" error. This error was documented as a **known runtime error** before R4.

### 5.2 Current Status

**The `attempts` table DOES NOT EXIST in the live database.** Therefore, the recursion error CANNOT currently occur. However, the error was documented as a known issue, suggesting:

1. The `attempts` table existed at some point and was dropped, OR
2. The error was anticipated/planned for but the table was never created, OR
3. The error was encountered in a development/staging environment

### 5.3 Recursion Analysis (Theoretical)

When the `attempts` table IS created, the documented recursion pattern is:

**Policy 3: "participants can see fellow attempts"**

```sql
-- PROBLEMATIC PATTERN (theoretical):
CREATE POLICY "participants can see fellow attempts" ON public.attempts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.attempts a
      WHERE a.test_id = attempts.test_id
      AND a.user_id = auth.uid()
    )
  );
```

**Why this recurses:**
1. User queries `attempts` → RLS checks Policy 3
2. Policy 3 queries `attempts` (same table) → RLS checks Policy 3 again
3. Policy 3 queries `attempts` again → infinite loop

### 5.4 Dependent Tables That Could Trigger Recursion

When `attempts` RLS fires, any query that touches `attempts` from within another table's RLS policy will also trigger the recursion:

| Table | Potential Recursion Path |
|-------|-------------------------|
| `answers` | If `answers` RLS checks `attempts` to verify ownership |
| `results` | If `results` RLS checks `attempts` to verify test membership |
| `integrity_events` | If `integrity_events` RLS checks `attempts` for context |
| `ai_reports` | If `ai_reports` RLS checks `attempts` for ownership |

### 5.5 Root Cause

The recursion happens because the RLS policy on `attempts` references `attempts` itself. This violates the PostgreSQL rule that RLS policies on a table cannot query the same table in their `USING` expression without `SECURITY DEFINER`.

### 5.6 Impact

- **Runtime error:** "infinite recursion detected in policy for relation 'attempts'"
- **Complete data access failure:** Cannot read, write, or query attempts
- **Cascading failure:** Any table that references `attempts` in its RLS also breaks
- **User-visible:** Test taking becomes completely non-functional

---

## 6. Security Design Options

### Option A: Simple Owner-Based RLS (RECOMMENDED)

**Design:** Each user can only see their own attempts. Test creators see all attempts for their tests via a separate policy.

```sql
-- Policy 1: Users can read their own attempts
CREATE POLICY "own_attempts" ON public.attempts
  FOR SELECT
  USING (user_id = auth.uid());

-- Policy 2: Users can insert their own attempts
CREATE POLICY "create_own_attempt" ON public.attempts
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Policy 3: Users can update their own attempts (for submission)
CREATE POLICY "update_own_attempt" ON public.attempts
  FOR UPDATE
  USING (user_id = auth.uid());

-- Policy 4: Test creators can read all attempts for their tests
CREATE POLICY "creator_reads_all" ON public.attempts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = attempts.test_id
      AND t.created_by = auth.uid()
    )
  );
```

**Who can SELECT:** Own attempts + test creators for their tests  
**Who can INSERT:** Own attempts only  
**Who can UPDATE:** Own attempts only (for submission)  
**Who can DELETE:** Nobody (soft-delete via status)  
**Fellow participant visibility:** NOT supported (by design — privacy)  
**SECURITY DEFINER:** Not required  
**auth.uid() checks:** Yes, in every policy  
**search_path:** Default  
**Risk of privilege escalation:** Low — owner-only access  
**Impact on answers/results/profiles:** Minimal — separate tables, separate RLS  
**Performance impact:** Low — simple equality checks  
**Migration complexity:** Low — straightforward policies

**Pros:**
- Simple, auditable, no recursion risk
- Follows Supabase best practices
- Easy to understand and maintain

**Cons:**
- No "fellow participant" visibility (cannot see who else took the test)
- Test creators need a separate policy to view all attempts

### Option B: View-Based with SECURITY DEFINER

**Design:** Create a database view that joins attempts with tests, then apply RLS on the view.

```sql
-- Create a view that includes test metadata
CREATE VIEW public.attempts_with_test AS
SELECT a.*, t.created_by as test_creator_id
FROM public.attempts a
JOIN public.tests t ON a.test_id = t.id;

-- RLS on the view
CREATE POLICY "view_attempts" ON public.attempts_with_test
  FOR SELECT
  USING (
    user_id = auth.uid()  -- own attempts
    OR test_creator_id = auth.uid()  -- creator viewing
  );

-- Use SECURITY DEFINER function for writes
CREATE FUNCTION public.create_attempt(p_test_id uuid)
RETURNS public.attempts
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_attempt public.attempts%ROWTYPE;
BEGIN
  INSERT INTO public.attempts (test_id, user_id, status, started_at)
  VALUES (p_test_id, auth.uid(), 'in_progress', now())
  RETURNING * INTO v_attempt;
  RETURN v_attempt;
END;
$$;
```

**Who can SELECT:** Via view — own attempts + creator's tests  
**Who can INSERT:** Via SECURITY DEFINER function only  
**Who can UPDATE:** Via SECURITY DEFINER function only  
**Who can DELETE:** Nobody  
**Fellow participant visibility:** Supported via view (if creator)  
**SECURITY DEFINER:** Required for write operations  
**auth.uid() checks:** In view RLS + function  
**search_path:** Must be set in function  
**Risk of privilege escalation:** Medium — SECURITY DEFINER functions bypass RLS  
**Impact on answers/results/profiles:** Moderate — requires similar function-based approach  
**Performance impact:** Medium — view join overhead  
**Migration complexity:** High — requires functions + views + RLS on views

**Pros:**
- Fellow participant visibility works
- Write operations are server-controlled
- Clean separation of read (view) and write (function)

**Cons:**
- More complex to implement and maintain
- SECURITY DEFINER functions are harder to audit
- View + function + RLS triple layer

### Option C: Hybrid with Temporal Lock

**Design:** Use RLS for read access, Edge Functions for time-sensitive operations (start, submit).

```sql
-- Simple RLS for reads
CREATE POLICY "own_attempts" ON public.attempts
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "creator_reads" ON public.attempts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tests t
      WHERE t.id = attempts.test_id AND t.created_by = auth.uid()
    )
  );

-- All writes go through Edge Functions (server-side)
-- No INSERT/UPDATE policies on attempts table
-- Edge Functions use service_role key
```

**Who can SELECT:** Own attempts + test creators  
**Who can INSERT:** Edge Functions only (service_role)  
**Who can UPDATE:** Edge Functions only (service_role)  
**Who can DELETE:** Edge Functions only (service_role)  
**Fellow participant visibility:** Via Edge Function response  
**SECURITY DEFINER:** Not required (Edge Functions bypass RLS)  
**auth.uid() checks:** In Edge Function logic  
**search_path:** N/A (Edge Functions)  
**Risk of privilege escalation:** Low — all writes server-controlled  
**Impact on answers/results/profiles:** Significant — all writes must go through Edge Functions  
**Performance impact:** High — network round-trips for every write  
**Migration complexity:** High — requires multiple Edge Functions

**Pros:**
- Maximum security — all mutations server-controlled
- No RLS recursion risk
- Time-sensitive operations (start, submit) are server-authoritative

**Cons:**
- High latency for every write operation
- Edge Functions add infrastructure complexity
- Harder to debug and test
- Requires service_role key management

### Recommendation: Option A (Simple Owner-Based RLS)

**Rationale:**
1. The documented recursion issue was for "fellow participant visibility" — Option A deliberately does not support this, eliminating the recursion risk entirely
2. The test system is for a student preparation app, not a high-stakes exam — simple owner-based access is sufficient
3. Test creators (teachers/admins) can view attempts via a separate policy without recursion
4. Low complexity, easy to audit, follows Supabase best practices
5. Can be extended later if fellow participant visibility is needed

**If fellow participant visibility is REQUIRED later:** Upgrade to Option B with SECURITY DEFINER functions.

---

## 7. Recommended Security Design

### 7.1 Security Model

```
┌─────────────────────────────────────────────────┐
│                   AUTH LAYER                     │
│  Supabase Auth → auth.uid() → JWT token         │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│                   RLS LAYER                      │
│  Each table has owner-based policies            │
│  Tests: creator + participant access             │
│  Attempts: own attempts only                     │
│  Answers: own answers only                       │
│  Results: own results + creator view             │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│                SERVICE LAYER                     │
│  Flutter services → Supabase client → PostgREST  │
│  No service_role key on client                   │
│  No Edge Functions for basic operations          │
└─────────────────────────────────────────────────┘
```

### 7.2 Access Matrix

| Operation | Tests | Questions | Attempts | Answers | Results |
|-----------|-------|-----------|----------|---------|---------|
| SELECT (own) | ✓ (published) | ✓ (during attempt) | ✓ | ✓ | ✓ |
| SELECT (all) | ✓ (creator) | ✓ (creator) | ✓ (creator) | ✓ (creator) | ✓ (creator) |
| INSERT | ✓ (creator) | ✓ (creator) | ✓ (own) | ✓ (own) | ✓ (system) |
| UPDATE | ✓ (creator) | ✓ (creator) | ✓ (own, limited) | ✓ (own, limited) | ✓ (system) |
| DELETE | ✗ | ✗ | ✗ | ✗ | ✗ |

### 7.3 Server-Authoritative Operations

These operations MUST be enforced server-side (RPC/Edge Function):

1. **Attempt start time** — Server records `started_at` to prevent client manipulation
2. **Attempt submission** — Server sets `submitted_at` and calculates duration
3. **Score calculation** — Server computes scores to prevent tampering
4. **Result generation** — Server generates results after submission
5. **Attempt limits** — Server enforces max attempts per test

### 7.4 Client-Safe Operations

These operations can safely run from Flutter via PostgREST:

1. **Load test list** — SELECT published tests
2. **Load questions** — SELECT questions for an active attempt
3. **Save answers** — INSERT/UPDATE answers (own attempt only)
4. **Load results** — SELECT own results
5. **Load profile** — SELECT own profile

---

## 8. Test Lifecycle

### 8.1 Confirmed Lifecycle (PROPOSED — no enums exist yet)

Since no test-related enums exist in the database, the following is a PROPOSED lifecycle:

```
DRAFT
  │ (creator edits test)
  ▼
PUBLISHED
  │ (creator publishes, invitations sent)
  ▼
INVITED / ACCESSIBLE
  │ (student sees test, can start)
  ▼
IN_PROGRESS
  │ (student starts attempt, timer running)
  │ (answers being saved)
  ▼
SUBMITTED
  │ (student submits or time expires)
  │ (server records submitted_at)
  ▼
SCORING
  │ (server calculates score)
  ▼
RESULT_READY
  │ (result available to student)
  │ (optional: AI report generated)
  ▼
COMPLETED
```

### 8.2 Status Values (PROPOSED)

| Status | Meaning | Transitions |
|--------|---------|-------------|
| `draft` | Test created, not published | → `published` |
| `published` | Test visible to invited participants | → `archived`, → `draft` (unpublish) |
| `archived` | Test no longer active | Terminal |
| `in_progress` | Student has started attempt | → `submitted`, → `expired` |
| `submitted` | Student submitted or time expired | → `scoring` |
| `scoring` | Server calculating results | → `result_ready` |
| `result_ready` | Result available | Terminal |
| `expired` | Time ran out without submission | → `scoring` |

### 8.3 Attempt Status (PROPOSED)

| Status | Meaning |
|--------|---------|
| `in_progress` | Attempt active, timer running |
| `submitted` | Manually submitted by student |
| `expired` | Time expired without submission |
| `cancelled` | Cancelled by creator |

---

## 9. Test Creation Architecture

### 9.1 Schema Design (PROPOSED)

**No test-related columns exist.** The following is a PROPOSED schema:

```sql
CREATE TABLE public.tests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  title text NOT NULL,
  description text,
  instructions text,
  duration_minutes integer NOT NULL DEFAULT 60,
  total_marks numeric NOT NULL DEFAULT 0,
  question_count integer NOT NULL DEFAULT 0,
  difficulty text CHECK (difficulty IN ('easy', 'medium', 'hard', 'mixed')),
  negative_marking boolean DEFAULT false,
  negative_marks numeric DEFAULT 0,
  max_attempts integer DEFAULT 1,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  starts_at timestamptz,
  ends_at timestamptz,
  randomize_questions boolean DEFAULT false,
  randomize_options boolean DEFAULT false,
  show_results_immediately boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 9.2 Feature Support Matrix

| Feature | Column/Field | Status |
|---------|-------------|--------|
| Test title | `title` (text) | PROPOSED |
| Description/instructions | `description`, `instructions` (text) | PROPOSED |
| Duration | `duration_minutes` (integer) | PROPOSED |
| Total marks | `total_marks` (numeric) | PROPOSED |
| Question count | `question_count` (integer) | PROPOSED |
| Difficulty | `difficulty` (text enum) | PROPOSED |
| Negative marking | `negative_marking` (bool), `negative_marks` (numeric) | PROPOSED |
| Syllabus selection | `test_syllabus` table (EXISTS, orphaned) | CONFIRMED (table exists) |
| Group assignment | NOT SUPPORTED | UNKNOWN (groups table doesn't exist) |
| Creator | `created_by` (uuid FK → auth.users) | PROPOSED |
| Publication status | `status` (text enum) | PROPOSED |
| Start/end scheduling | `starts_at`, `ends_at` (timestamptz) | PROPOSED |
| Invitation/access code | `test_invitations` table | NOT EXISTS |
| Attempt limits | `max_attempts` (integer) | PROPOSED |
| Randomization | `randomize_questions`, `randomize_options` (bool) | PROPOSED |
| Question ordering | Via `question_order` in question record | PROPOSED |

---

## 10. Question Architecture

### 10.1 Current State

**No question-related tables exist.** No question models, services, or screens exist in Flutter.

### 10.2 Proposed Schema

```sql
CREATE TYPE public.question_type AS ENUM (
  'mcq',           -- Multiple choice (single answer)
  'multi_correct', -- Multiple choice (multiple answers)
  'true_false',    -- True/False
  'short_answer',  -- Short text answer
  'long_answer',   -- Long text answer (essay)
  'numerical',     -- Numerical answer
  'fill_blank'     -- Fill in the blank
);

CREATE TABLE public.questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  question_type public.question_type NOT NULL DEFAULT 'mcq',
  question_text text NOT NULL,
  options jsonb,  -- [{id: "a", text: "...", is_correct: false}, ...]
  correct_answer jsonb,  -- {value: "a"} or {values: ["a", "c"]} or {text: "..."}
  marks numeric NOT NULL DEFAULT 1,
  negative_marks numeric DEFAULT 0,
  difficulty text CHECK (difficulty IN ('easy', 'medium', 'hard')),
  explanation text,
  syllabus_node_id uuid REFERENCES public.syllabus_nodes(id),
  question_order integer NOT NULL DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.question_bank (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  question_type public.question_type NOT NULL,
  question_text text NOT NULL,
  options jsonb,
  correct_answer jsonb,
  marks numeric NOT NULL DEFAULT 1,
  negative_marks numeric DEFAULT 0,
  difficulty text,
  explanation text,
  syllabus_node_id uuid REFERENCES public.syllabus_nodes(id),
  tags text[],
  is_active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 10.3 Question Features

| Feature | Field | Status |
|---------|-------|--------|
| Question storage | `questions` table | PROPOSED |
| Options | `options` (jsonb array) | PROPOSED |
| Correct answer | `correct_answer` (jsonb) | PROPOSED |
| Marks | `marks` (numeric) | PROPOSED |
| Negative marks | `negative_marks` (numeric) | PROPOSED |
| Difficulty | `difficulty` (text) | PROPOSED |
| Explanation | `explanation` (text) | PROPOSED |
| Syllabus mapping | `syllabus_node_id` (uuid FK) | PROPOSED |
| Source | `question_bank` table | PROPOSED |
| Language | NOT SUPPORTED | UNKNOWN |
| Question type | `question_type` (enum) | PROPOSED |
| Ordering | `question_order` (integer) | PROPOSED |
| Active/deleted | `is_active` (boolean) | PROPOSED |
| Version status | NOT SUPPORTED | PROPOSED (add `version` column) |
| AI-generated | NOT SUPPORTED | PROPOSED (add `is_ai_generated` boolean) |

### 10.4 AI-Generated Questions

**Not currently supported.** The `ai_jobs` and `ai_reports` tables do not exist. AI question generation would require:
1. `ai_jobs` table for tracking generation requests
2. Edge Function or RPC for calling AI API
3. `is_ai_generated` flag on questions
4. `ai_model` and `ai_prompt` fields for audit trail

---

## 11. Live Test Runner Architecture

### 11.1 What the Current DB Can Support

| Feature | Can Support? | Notes |
|---------|-------------|-------|
| Starting an attempt | NO (attempts table doesn't exist) | Must create table first |
| Server-authoritative start time | NO (no server-side enforcement) | Requires RPC/Edge Function |
| Duration tracking | NO (no timer infrastructure) | Client-side timer + server validation |
| Autosave | NO (no answers table) | Must create table first |
| Answer save | NO (no answers table) | Must create table first |
| Mark for review | NO (no UI or storage) | Requires answer metadata |
| Question navigation | NO (no question loading) | Requires questions table |
| Reconnect/retry | NO (no session management) | Requires attempt status tracking |
| Submission | NO (no submission mechanism) | Requires RPC for server-side submission |
| Duplicate submission prevention | NO (no idempotency) | Requires server-side check |
| Attempt limits | NO (no limit enforcement) | Requires RPC |

### 11.2 Required Infrastructure

**Every feature requires creating the underlying tables first.** The test runner cannot function with the current schema.

### 11.3 Server-Authoritative Operations (RPC Required)

| Operation | Why Server-Authoritative | Implementation |
|-----------|-------------------------|----------------|
| Attempt creation | Prevent duplicate attempts, enforce limits | `fn_start_attempt(test_id)` |
| Start time recording | Prevent client clock manipulation | RPC records `started_at` |
| Answer save | Validate attempt is in_progress | `fn_save_answer(attempt_id, question_id, answer)` |
| Submission | Set `submitted_at`, prevent double-submit | `fn_submit_attempt(attempt_id)` |
| Score calculation | Prevent answer tampering | `fn_score_attempt(attempt_id)` |
| Result generation | Ensure deterministic scoring | `fn_generate_result(attempt_id)` |

### 11.4 Client-Safe Operations

| Operation | Why Client-Safe | Implementation |
|-----------|----------------|----------------|
| Load test list | Read-only, RLS-filtered | `.from('tests').select()` |
| Load questions | Read-only, during active attempt | `.from('questions').select()` |
| Load own answers | Read-only, owner-filtered | `.from('answers').select()` |
| Load own results | Read-only, owner-filtered | `.from('results').select()` |
| Timer display | Client-side countdown | Flutter Timer widget |
| Question navigation | Client-side UI state | Flutter state management |

---

## 12. Result Architecture

### 12.1 Existing Tables

| Table | Status | Purpose |
|-------|--------|---------|
| `results` | NOT EXISTS | Final scores |
| `result_batches` | NOT EXISTS | Batch generation |
| `ai_jobs` | NOT EXISTS | AI processing queue |
| `ai_reports` | NOT EXISTS | AI coach reports |

### 12.2 Proposed Schema

```sql
CREATE TABLE public.results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id uuid NOT NULL REFERENCES public.attempts(id),
  test_id uuid NOT NULL REFERENCES public.tests(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  total_score numeric NOT NULL DEFAULT 0,
  max_score numeric NOT NULL DEFAULT 0,
  percentage numeric NOT NULL DEFAULT 0,
  correct_answers integer NOT NULL DEFAULT 0,
  incorrect_answers integer NOT NULL DEFAULT 0,
  unattempted integer NOT NULL DEFAULT 0,
  time_taken_seconds integer,
  score_breakdown jsonb,  -- {question_id: {marks: 5, earned: 5, status: "correct"}}
  generated_at timestamptz NOT NULL DEFAULT now(),
  batch_id uuid REFERENCES public.result_batches(id)
);

CREATE TABLE public.result_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id uuid NOT NULL REFERENCES public.tests(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  total_attempts integer NOT NULL DEFAULT 0,
  processed_count integer NOT NULL DEFAULT 0,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.ai_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid REFERENCES public.result_batches(id),
  attempt_id uuid REFERENCES public.attempts(id),
  job_type text NOT NULL CHECK (job_type IN ('scoring', 'ai_report', 'question_generation')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  input_data jsonb,
  output_data jsonb,
  error_message text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.ai_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id uuid NOT NULL REFERENCES public.attempts(id),
  job_id uuid NOT NULL REFERENCES public.ai_jobs(id),
  report_type text NOT NULL CHECK (report_type IN ('performance', 'weak_areas', 'suggestions')),
  report_data jsonb NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now()
);
```

### 12.3 Batch Result Generation

| Feature | Supported? | Notes |
|---------|-----------|-------|
| All participants together | PROPOSED | `result_batches` groups attempts |
| Deterministic scoring | PROPOSED | Score calculated server-side in RPC |
| Stored results | PROPOSED | `results` table stores final scores |
| Retry | PROPOSED | `result_batches.status` tracks progress |
| Idempotency | PROPOSED | `result_batches` prevents duplicate processing |
| Batch status | PROPOSED | `status` column tracks pending/processing/completed |
| AI coach report | PROPOSED | `ai_reports` table, generated after results |

### 12.4 Token-Saving Architecture

**RESULTS SHOULD NOT REQUIRE AN AI CALL FOR BASIC SCORING.**

```
Basic Scoring (NO AI):
  fn_score_attempt(attempt_id)
    → Compare answers vs correct_answer
    → Calculate marks, negative marks
    → Store in results table
    → Return score breakdown
    → NO AI CALL

AI Reports (OPTIONAL, AFTER results):
  fn_generate_ai_report(attempt_id)
    → Read results + answers
    → Call AI API for analysis
    → Store in ai_reports table
    → Returns suggestions, weak areas
    → AI CALL (token cost)
```

---

## 13. Syllabus Integration

### 13.1 Existing `test_syllabus` Table

```sql
-- CONFIRMED: This table exists (ORPHANED)
CREATE TABLE public.test_syllabus (
  test_id uuid NOT NULL,          -- FK → tests.id (DOES NOT EXIST)
  syllabus_node_id uuid NOT NULL, -- FK → syllabus_nodes.id (EXISTS)
  material_ids uuid[]             -- Array of material IDs
);
```

**Status:** ORPHANED — `test_id` references `tests` which does not exist.

### 13.2 Integration Design

```
tests
  │
  ├──< test_syllabus.test_id          (which syllabus topics are covered)
  │     │
  │     └──> syllabus_nodes.id        (specific topics)
  │           │
  │           └──< node_materials     (materials for those topics)
  │                 │
  │                 └──> study_materials (actual content)
  │
  ├──< questions.test_id              (questions for this test)
  │     │
  │     └──> questions.syllabus_node_id (which topic each question covers)
  │
  └──< attempts.test_id               (student attempts)
        │
        └──< answers.attempt_id       (individual answers)
```

### 13.3 Future Class 11–12 Stream Integration

The syllabus hierarchy supports this naturally:

```
subjects (Mathematics)
  └── syllabus_nodes (Class 11, Class 12)
        └── Textbook nodes
              └── Chapter nodes
                    └── Topic nodes (optional)
```

`test_syllabus.syllabus_node_id` can reference ANY node in the tree — class-level, textbook-level, or chapter-level. No duplication needed.

---

## 14. Group/Permission Integration

### 14.1 Current State

| Table | Status |
|-------|--------|
| `groups` | NOT FOUND |
| `group_members` | NOT FOUND |
| `role_permissions` | NOT FOUND |

**No group or permission infrastructure exists.**

### 14.2 Implications for Test System

Without groups, the test system cannot support:
- Class/group-based test assignment
- Role-based access (teacher vs student)
- Group-wide result viewing

### 14.3 Minimal Viable Approach

For initial R4, skip groups entirely:
- **Creator** = the user who created the test (`created_by` in `tests`)
- **Participant** = any authenticated user (or use invitation system)
- **No role system** — simple owner/participant split

If groups are needed later:
1. Create `groups` and `group_members` tables
2. Add `group_id` to `tests` table
3. Update RLS to check group membership

---

## 15. Performance Audit

### 15.1 Index Requirements (PROPOSED)

| Table | Index | Purpose |
|-------|-------|---------|
| `tests` | `created_by` | Find tests by creator |
| `tests` | `status` | Filter published tests |
| `questions` | `test_id` | Load questions for test |
| `questions` | `test_id, question_order` | Ordered question loading |
| `attempts` | `test_id, user_id` | Find user's attempt for test |
| `attempts` | `user_id` | Find all user attempts |
| `answers` | `attempt_id` | Load answers for attempt |
| `answers` | `attempt_id, question_id` | Find answer for specific question |
| `results` | `attempt_id` | Load result for attempt |
| `results` | `user_id` | Find all user results |
| `results` | `test_id` | Find all results for test |
| `result_batches` | `test_id` | Find batches for test |

### 15.2 Performance Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Loading all questions for a test | Medium | Index on `test_id`, paginate if >50 questions |
| Autosave frequency | High | Debounce saves (every 5-10 seconds), batch updates |
| Concurrent submissions | Medium | Server-side locking in RPC |
| Large group result generation | High | Batch processing with `result_batches` |
| AI report generation | High | Async via `ai_jobs`, not blocking submission |

---

## 16. Flutter Audit

### 16.1 Existing Code

| Category | Files Found | Status |
|----------|------------|--------|
| Test models | 0 | NOT EXISTS |
| Test services | 0 | NOT EXISTS |
| Test screens | 0 | NOT EXISTS |
| Question models | 0 | NOT EXISTS |
| Attempt services | 0 | NOT EXISTS |
| Answer services | 0 | NOT EXISTS |
| Result services | 0 | NOT EXISTS |
| Test routes | 0 | NOT EXISTS |
| RPC calls | 1 (fn_ensure_profile) | No test RPCs |
| Edge Function calls | 0 | None |

### 16.2 Existing Architecture (to reuse)

| Component | Pattern | Reuse for R4 |
|-----------|---------|-------------|
| Service pattern | Static final class with `._()` | ✓ Use same pattern |
| Model pattern | Immutable with `fromJson`/`toJson` | ✓ Use same pattern |
| Error handling | `AppError` sealed classes | ✓ Extend for test errors |
| Route pattern | GoRouter with named routes | ✓ Add test routes |
| Screen pattern | StatefulWidget with loading/error/empty | ✓ Use same pattern |
| Supabase access | `SupabaseService.client.from()` | ✓ Use same pattern |

### 16.3 New Files Required

**Models (6 files):**
- `lib/core/models/test.dart`
- `lib/core/models/question.dart`
- `lib/core/models/attempt.dart`
- `lib/core/models/answer.dart`
- `lib/core/models/result.dart`
- `lib/core/models/test_invitation.dart`

**Services (6 files):**
- `lib/core/services/test_service.dart`
- `lib/core/services/question_service.dart`
- `lib/core/services/attempt_service.dart`
- `lib/core/services/answer_service.dart`
- `lib/core/services/result_service.dart`
- `lib/core/services/invitation_service.dart`

**Screens (8 files):**
- `lib/features/test/test_list_screen.dart`
- `lib/features/test/test_detail_screen.dart`
- `lib/features/test/test_creation_screen.dart`
- `lib/features/test/test_taker_screen.dart`
- `lib/features/test/question_navigation_screen.dart`
- `lib/features/test/test_result_screen.dart`
- `lib/features/test/test_review_screen.dart`
- `lib/features/test/invitation_screen.dart`

**Total: ~20 new files**

---

## 17. Client vs Server Authority

### 17.1 Client-Safe Operations

| Operation | Why Safe | Implementation |
|-----------|----------|----------------|
| Load test list | Read-only, RLS-filtered | `.from('tests').select()` |
| Load questions | Read-only, during active attempt | `.from('questions').select()` |
| Load own answers | Read-only, owner-filtered | `.from('answers').select()` |
| Load own results | Read-only, owner-filtered | `.from('results').select()` |
| Save answer (own attempt) | Owner-only via RLS | `.from('answers').upsert()` |
| Timer display | Client-side only | Flutter Timer |

### 17.2 Server-Authoritative Operations

| Operation | Why Server-Authoritative | Implementation |
|-----------|-------------------------|----------------|
| Create attempt | Enforce limits, record start time | `fn_start_attempt(test_id)` |
| Record submission | Prevent double-submit, record time | `fn_submit_attempt(attempt_id)` |
| Score calculation | Prevent answer tampering | `fn_score_attempt(attempt_id)` |
| Generate results | Deterministic scoring | `fn_generate_result(attempt_id)` |
| Enforce attempt limits | Prevent cheating | Inside `fn_start_attempt` |

### 17.3 Architecture Diagram

```
Flutter Client
  │
  ├─[Client-Safe]──→ Supabase PostgREST → RLS → Database
  │                     (SELECT, limited INSERT/UPDATE)
  │
  └─[Server-Authoritative]──→ Supabase RPC → Database
                                (fn_start_attempt, fn_submit_attempt, etc.)
```

---

## 18. R4 Implementation Phases

### Phase R4.0: RLS Recursion Security Foundation

**Objective:** Verify and fix RLS on existing tables before adding test tables

**Files/Tables affected:**
- All existing tables (subjects, syllabus_nodes, profiles, etc.)
- RLS policies on existing tables

**Tests:**
- Run RLS inspection queries on live database
- Verify authenticated SELECT works for all tables
- Verify no recursion on existing tables

**Security checks:**
- RLS enabled on all tables
- No overly permissive policies
- No service-role key in client

**Acceptance criteria:**
- All existing RLS policies documented
- No recursion detected
- Flutter app loads all data correctly

**Hard-stop gate:** RLS audit must complete before creating test tables

---

### Phase R4.1: Test Tables & Schema

**Objective:** Create all test-related database tables

**Files/Tables affected:**
- NEW: `tests`, `questions`, `question_bank`, `attempts`, `answers`, `results`, `result_batches`, `test_invitations`, `integrity_events`, `ai_jobs`, `ai_reports`
- MODIFY: `test_syllabus` (link to new `tests` table)
- NEW: Enums (`question_type`, `attempt_status`, `test_status`)
- NEW: Indexes on all foreign keys

**Tests:**
- All tables created with correct schema
- All FK constraints work
- All enums created
- All indexes created

**Security checks:**
- RLS enabled on all new tables
- Owner-based policies applied
- No recursion possible

**Acceptance criteria:**
- All 12 tables created
- All constraints verified
- RLS policies active

**Hard-stop gate:** Schema must be complete before Flutter code

---

### Phase R4.2: Test Models (Flutter)

**Objective:** Create Dart models for all test entities

**Files affected:**
- NEW: `lib/core/models/test.dart`
- NEW: `lib/core/models/question.dart`
- NEW: `lib/core/models/attempt.dart`
- NEW: `lib/core/models/answer.dart`
- NEW: `lib/core/models/result.dart`
- NEW: `lib/core/models/test_invitation.dart`
- MODIFY: `test/widget_test.dart` (add model tests)

**Tests:**
- All models parse from JSON correctly
- All models serialize to JSON correctly
- All enums mapped correctly
- Equality operators work

**Acceptance criteria:**
- All 6 models created
- All model tests pass
- `flutter analyze` clean

**Hard-stop gate:** Models must compile before services

---

### Phase R4.3: Test Services (Flutter)

**Objective:** Create service layer for test operations

**Files affected:**
- NEW: `lib/core/services/test_service.dart`
- NEW: `lib/core/services/question_service.dart`
- NEW: `lib/core/services/attempt_service.dart`
- NEW: `lib/core/services/answer_service.dart`
- NEW: `lib/core/services/result_service.dart`

**Tests:**
- Service methods call correct Supabase tables
- Error handling follows existing pattern
- RLS integration works

**Acceptance criteria:**
- All 5 services created
- Services follow existing pattern
- `flutter analyze` clean

**Hard-stop gate:** Services must compile before screens

---

### Phase R4.4: Test Creation Flow

**Objective:** Build test creation UI for teachers/creators

**Files affected:**
- NEW: `lib/features/test/test_creation_screen.dart`
- MODIFY: `lib/app/app_router.dart` (add routes)
- MODIFY: `lib/features/home/home_screen.dart` (add test section)

**Tests:**
- Test creation form validates all fields
- Syllabus selection works
- Question adding works
- Test saves to database

**Acceptance criteria:**
- Creator can create a test with title, description, duration, marks
- Creator can select syllabus topics
- Creator can add questions
- Test saves as draft

**Hard-stop gate:** Test creation must work before test taking

---

### Phase R4.5: Question Integration

**Objective:** Build question management for test creators

**Files affected:**
- NEW: `lib/features/test/question_creation_screen.dart`
- NEW: `lib/features/test/question_bank_screen.dart`

**Tests:**
- MCQ questions with options save correctly
- Correct answer stored securely
- Question ordering works
- Question bank management works

**Acceptance criteria:**
- Creator can add MCQ, true/false, short answer questions
- Options and correct answers save
- Questions display in correct order

**Hard-stop gate:** Questions must exist before test taking

---

### Phase R4.6: Live Test Runner

**Objective:** Build the student test-taking experience

**Files affected:**
- NEW: `lib/features/test/test_taker_screen.dart`
- NEW: `lib/features/test/question_navigation_screen.dart`

**Tests:**
- Timer counts down correctly
- Questions load in order
- Answer selection works
- Mark for review works
- Navigation between questions works

**Acceptance criteria:**
- Student can start an attempt
- Timer displays and counts down
- Questions load from database
- Answers save to database (autosave)
- Student can navigate between questions

**Hard-stop gate:** Test runner must work before submission

---

### Phase R4.7: Submission & Scoring

**Objective:** Implement attempt submission and scoring

**Files affected:**
- NEW: `lib/core/services/scoring_service.dart`
- MODIFY: `lib/core/services/attempt_service.dart`
- NEW: RPC: `fn_submit_attempt`
- NEW: RPC: `fn_score_attempt`

**Tests:**
- Submission sets submitted_at
- Duplicate submission prevented
- Score calculated correctly
- Negative marking applied
- Results stored

**Acceptance criteria:**
- Student can submit attempt
- Double-submit prevented
- Score calculated server-side
- Result available immediately (if configured)

**Hard-stop gate:** Scoring must work before result display

---

### Phase R4.8: Result Display

**Objective:** Build result viewing experience

**Files affected:**
- NEW: `lib/features/test/test_result_screen.dart`
- NEW: `lib/features/test/test_review_screen.dart`
- NEW: `lib/core/services/result_service.dart`

**Tests:**
- Result loads correctly
- Score breakdown displays
- Question review shows correct/incorrect
- Time taken displayed

**Acceptance criteria:**
- Student can view result after submission
- Score breakdown visible
- Question review shows correct answers
- Performance summary displayed

**Hard-stop gate:** Results must display before AI features

---

### Phase R4.9: Batch Results & AI Reports (Optional)

**Objective:** Implement batch result generation and AI reports

**Files affected:**
- NEW: `lib/core/services/batch_result_service.dart`
- NEW: `lib/core/services/ai_report_service.dart`
- NEW: Edge Function: `generate-ai-report`

**Tests:**
- Batch processing works
- AI report generated after results
- Report displays correctly

**Acceptance criteria:**
- Creator can generate batch results for all participants
- AI coach report generated (optional, token-cost)
- Reports viewable by students

**Hard-stop gate:** Basic scoring must work first

---

### Phase R4.10: Security & Performance Hardening

**Objective:** Final security audit and performance optimization

**Files affected:**
- All test-related files
- Database indexes
- RLS policies

**Tests:**
- No recursion in any RLS policy
- All queries use auth.uid()
- No service-role key in client
- Indexes optimize common queries
- Autosave debounced
- Concurrent submissions handled

**Acceptance criteria:**
- Security audit passes
- Performance acceptable for 50+ concurrent users
- No data leaks

**Hard-stop gate:** Security must pass before production

---

### Phase R4.11: Integration Testing

**Objective:** End-to-end testing of complete flow

**Files affected:**
- `test/widget_test.dart` (expand)
- NEW: `test/integration/test_flow_test.dart`

**Tests:**
- Complete flow: create test → add questions → publish → student takes test → submit → view result
- Edge cases: time expiry, double-submit, reconnect
- Permission tests: creator vs student access

**Acceptance criteria:**
- Complete flow works end-to-end
- All edge cases handled
- All tests pass

**Hard-stop gate:** Integration tests must pass before production

---

## 19. Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| RLS recursion on new tables | High | Medium | Option A design (no self-reference) |
| Schema changes break existing app | High | Low | Test existing flows after each change |
| Timer manipulation by clients | Medium | High | Server-side validation in RPC |
| Answer tampering | High | Medium | Score calculation server-side only |
| Large test performance | Medium | Medium | Pagination, indexing, async processing |
| AI report cost | Medium | Low | Make optional, token budgeting |
| Group system missing | Medium | High | Skip for R4.0, add later if needed |
| Migration complexity | High | Medium | Phase-gated approach |

---

## 20. Unknowns

| Item | Status | Required For |
|------|--------|-------------|
| Live RLS policies on existing tables | UNKNOWN | Security audit |
| `tests` table schema (if it ever existed) | UNKNOWN | Migration planning |
| `attempts` RLS recursion (exact policy) | UNKNOWN | Cannot verify — table doesn't exist |
| `groups` table (if needed) | UNKNOWN | Group-based test assignment |
| Supabase project plan (free/pro) | UNKNOWN | Edge Function limits |
| Expected user count | UNKNOWN | Performance planning |
| Expected concurrent test takers | UNKNOWN | Infrastructure planning |
| AI API credentials/budget | UNKNOWN | AI reports feature |
| Deployment environment | UNKNOWN | Migration strategy |

---

## 21. Acceptance Criteria

### R4.0 (Security Foundation)
- [ ] All existing RLS policies documented
- [ ] No recursion detected on any table
- [ ] Flutter app loads data correctly

### R4.1 (Schema)
- [ ] All 12 test tables created
- [ ] All FK constraints verified
- [ ] All enums created
- [ ] RLS enabled on all tables

### R4.2 (Models)
- [ ] All 6 models created
- [ ] All model tests pass
- [ ] `flutter analyze` clean

### R4.3 (Services)
- [ ] All 5 services created
- [ ] Services follow existing pattern
- [ ] `flutter analyze` clean

### R4.4 (Test Creation)
- [ ] Creator can create test
- [ ] Creator can select syllabus
- [ ] Creator can add questions
- [ ] Test saves as draft

### R4.5 (Questions)
- [ ] MCQ questions work
- [ ] Options and answers save
- [ ] Question ordering works

### R4.6 (Test Runner)
- [ ] Student can start attempt
- [ ] Timer works
- [ ] Questions load
- [ ] Answers autosave
- [ ] Navigation works

### R4.7 (Submission)
- [ ] Submission works
- [ ] Double-submit prevented
- [ ] Score calculated
- [ ] Result stored

### R4.8 (Results)
- [ ] Result displays
- [ ] Score breakdown visible
- [ ] Question review works

### R4.9 (AI Reports — Optional)
- [ ] Batch results work
- [ ] AI report generated
- [ ] Reports display

### R4.10 (Security)
- [ ] No recursion
- [ ] All queries use auth.uid()
- [ ] Indexes optimized
- [ ] No data leaks

### R4.11 (Integration)
- [ ] Complete flow works
- [ ] Edge cases handled
- [ ] All tests pass

---

## FINAL STATUS

**R4 TEST SYSTEM DISCOVERY AUDIT STATUS:** BLOCKED — DISCOVERY INCOMPLETE

### CONFIRMED
- `subjects` table exists (11 rows)
- `syllabus_nodes` table exists (2 rows)
- `profiles` table exists
- `study_materials`, `node_materials`, `material_chunks` exist
- `progress_snapshots` exists
- `routines`, `routine_logs` exist
- `test_syllabus` exists (ORPHANED)
- `fn_ensure_profile()` RPC exists
- Flutter project has zero test system code
- No supabase/ directory exists
- No SQL migrations exist

### INFERENCE
- RLS likely enabled on some tables (app works)
- `test_syllabus` was created for a planned test feature that was never built
- The `attempts` RLS recursion was likely encountered during earlier development
- The `groups` table was likely planned but never created

### UNKNOWN
- Exact RLS policies on any table
- Whether `tests` table ever existed
- Exact `attempts` recursion policy
- Live database credentials and project plan
- Expected user/concurrent test taker counts
- AI API budget/credentials

### PROPOSED
- All test-related schemas (tests, questions, attempts, answers, results, etc.)
- All RLS policies for test tables
- All Flutter models, services, screens
- All RPCs for server-authoritative operations
- All implementation phases

### BLOCKERS
1. **Cannot verify live RLS** — no database credentials in codebase
2. **Cannot verify `test_syllabus` orphan status** — need to check if `tests` table was dropped
3. **No group infrastructure** — test assignment by group not possible without creating `groups` table
4. **No AI credentials** — AI reports feature blocked without API access

---

**HARD STOP.**

**NO DATABASE CHANGES.**  
**NO FLUTTER CHANGES.**  
**NO SEED EXECUTION.**  
**NO FIXES YET.**

**Wait for human approval before implementing R4.**

---

**END OF R4 TEST SYSTEM DISCOVERY AUDIT**

# R3.5 SEED-1 PLAN — Mathematics Class 6 Pilot

**Phase:** SEED-1 (One Subject, One Class Pilot)  
**Subject:** Mathematics  
**Class:** Class 6  
**Date:** 2026-09-12  
**Status:** READY FOR HUMAN APPROVAL  

---

## A. LIVE DATABASE FINDINGS

**Action required:** Run the discovery queries below in Supabase SQL Editor and paste results.

### Discovery Queries

```sql
-- A1. Mathematics subject row
SELECT id, name FROM public.subjects WHERE name = 'Mathematics';

-- A2. Confirm exactly one Mathematics row
SELECT count(*) AS math_count FROM public.subjects WHERE name = 'Mathematics';

-- A3. syllabus_nodes column metadata
SELECT
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default,
  c.character_maximum_length,
  c.numeric_precision
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name = 'syllabus_nodes'
ORDER BY c.ordinal_position;

-- A4. All constraints on syllabus_nodes
SELECT
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name AS foreign_table,
  ccu.column_name AS foreign_column,
  pg_get_constraintdef(pgc.oid) AS constraint_definition
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
LEFT JOIN pg_constraint pgc
  ON pgc.conname = tc.constraint_name
  AND pgc.connamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
WHERE tc.table_schema = 'public'
  AND tc.table_name = 'syllabus_nodes'
ORDER BY tc.constraint_type, tc.constraint_name;

-- A5. Indexes on syllabus_nodes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'syllabus_nodes';

-- A6. RLS status
SELECT
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'syllabus_nodes';

-- A7. Policies
SELECT
  polname AS policy_name,
  polcmd AS command,
  polroles::regrole[] AS roles,
  pg_get_expr(polqual, polrelid) AS using_expr,
  pg_get_expr(polwithcheck, polrelid) AS with_check_expr
FROM pg_policy
WHERE polrelid = 'syllabus_nodes'::regclass;

-- A8. Existing Mathematics syllabus nodes
SELECT sn.id, sn.subject_id, sn.parent_id, sn.class_level, sn.name, sn.created_at
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Mathematics'
ORDER BY sn.parent_id NULLS FIRST, sn.name;

-- A9. Existing Hindi data unchanged
SELECT sn.id, sn.subject_id, sn.parent_id, sn.class_level, sn.name, sn.created_at
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Hindi'
ORDER BY sn.parent_id NULLS FIRST, sn.name;

-- A10. Duplicate sibling check
SELECT subject_id, parent_id, name, count(*)
FROM public.syllabus_nodes
GROUP BY subject_id, parent_id, name
HAVING count(*) > 1;

-- A11. Cross-subject parent check
SELECT child.id, child.subject_id AS child_subject, parent.subject_id AS parent_subject
FROM public.syllabus_nodes child
JOIN public.syllabus_nodes parent ON parent.id = child.parent_id
WHERE child.subject_id != parent.subject_id;

-- A12. Triggers on syllabus_nodes
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'syllabus_nodes';

-- A13. Functions referencing syllabus_nodes
SELECT p.proname AS function_name, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE pg_get_functiondef(p.oid) ILIKE '%syllabus_nodes%';
```

### Results Template

| Item | Finding |
|------|---------|
| Mathematics subject exists | PENDING |
| Mathematics UUID | PENDING |
| Mathematics row count | PENDING |
| syllabus_nodes `id` type | PENDING |
| syllabus_nodes `id` default | PENDING |
| syllabus_nodes `subject_id` nullable | PENDING |
| syllabus_nodes `parent_id` nullable | PENDING |
| syllabus_nodes `class_level` type | PENDING |
| syllabus_nodes `class_level` nullable | PENDING |
| `subject_id → subjects.id` FK | PENDING |
| `parent_id → syllabus_nodes.id` FK | PENDING |
| UNIQUE constraint on (subject_id, parent_id, name) | PENDING |
| UNIQUE constraint on (subject_id, name) | PENDING |
| Index on `subject_id` | PENDING |
| Index on `parent_id` | PENDING |
| Check constraint on `class_level` | PENDING |
| Check constraint on `parent_id` | PENDING |
| RLS enabled | PENDING |
| INSERT policy | PENDING |
| Existing Mathematics nodes | PENDING |
| Existing Hindi data unchanged | PENDING |
| Triggers on syllabus_nodes | PENDING |
| Functions referencing syllabus_nodes | PENDING |
| Duplicate siblings | PENDING |
| Cross-subject parents | PENDING |

---

## B. SOURCE VERIFICATION

### Source

| Field | Value |
|-------|-------|
| Source name | NCERT |
| Book title | GANITA PRAKASH (Mathematics) |
| Class | 6 |
| Publisher | NCERT, Council of Educational Research and Training, New Delhi |
| Language | English |
| Edition | Current (NEP 2025-26 aligned) |
| PDF URL | https://ncert.nic.in/textbook/pdf/fegp1ps.pdf |
| Verified by | Web search cross-referenced across 3 sources |
| Verification date | 2026-09-12 |

### IMPORTANT: NCERT Revised the Textbook

The Class 6 Mathematics textbook was **revised under NEP for 2025-26**. The new textbook is named **"GANITA PRAKASH"** and contains **10 chapters** (not 14 from the previous edition). Chapter names have changed entirely.

**Old edition (pre-NEP):** 14 chapters — Knowing Our Numbers, Whole Numbers, etc.  
**Current edition (NEP 2025-26):** 10 chapters — Patterns in Mathematics, Lines and Angles, etc.

### Verified Chapter List (GANITA PRAKASH, Class 6)

| # | Chapter Name | Source Reference |
|---|-------------|-----------------|
| 1 | Patterns in Mathematics | GANITA PRAKASH Class 6, Chapter 1 |
| 2 | Lines and Angles | GANITA PRAKASH Class 6, Chapter 2 |
| 3 | Number Play | GANITA PRAKASH Class 6, Chapter 3 |
| 4 | Data Handling and Presentation | GANITA PRAKASH Class 6, Chapter 4 |
| 5 | Prime Time | GANITA PRAKASH Class 6, Chapter 5 |
| 6 | Perimeter and Area | GANITA PRAKASH Class 6, Chapter 6 |
| 7 | Fractions | GANITA PRAKASH Class 6, Chapter 7 |
| 8 | Playing with Constructions | GANITA PRAKASH Class 6, Chapter 8 |
| 9 | Symmetry | GANITA PRAKASH Class 6, Chapter 9 |
| 10 | The Other Side of Zero | GANITA PRAKASH Class 6, Chapter 10 |

### Cross-Reference Verification

| Source | Chapter Count | Match |
|--------|--------------|-------|
| NCERT PDF table of contents (fegp1ps.pdf) | 10 | YES |
| Careers360 NCERT syllabus page | 10 | YES |
| Official annual syllabus (edustud.nic.in) | 10 | YES |

### Topic Level

**NOT INCLUDED in this pilot.** Topics per chapter require a separate verified source (NCERT chapter sub-headings). This pilot seeds only Class 6 root + 10 chapters.

### Human Verification Required

- [ ] Confirm the GANITA PRAKASH chapter list matches your NCERT edition
- [ ] Confirm the class_level value ("6" vs "Class 6")
- [ ] Confirm no topics should be included in this pilot
- [ ] Confirm the source PDF is accessible

---

## C. PROPOSED TREE

```
Mathematics (subject_id = <math_uuid>)
└── Class 6 (parent_id = NULL, class_level = 'Class 6', name = 'Class 6')
    ├── Patterns in Mathematics (parent_id = <class6_id>, class_level = NULL)
    ├── Lines and Angles (parent_id = <class6_id>, class_level = NULL)
    ├── Number Play (parent_id = <class6_id>, class_level = NULL)
    ├── Data Handling and Presentation (parent_id = <class6_id>, class_level = NULL)
    ├── Prime Time (parent_id = <class6_id>, class_level = NULL)
    ├── Perimeter and Area (parent_id = <class6_id>, class_level = NULL)
    ├── Fractions (parent_id = <class6_id>, class_level = NULL)
    ├── Playing with Constructions (parent_id = <class6_id>, class_level = NULL)
    ├── Symmetry (parent_id = <class6_id>, class_level = NULL)
    └── The Other Side of Zero (parent_id = <class6_id>, class_level = NULL)
```

**Total rows to insert: 11** (1 root + 10 chapters)

---

## D. EXACT DATA TO BE INSERTED

### D.1 Class 6 Root Node

| Column | Value |
|--------|-------|
| `id` | Auto-generated (gen_random_uuid()) |
| `subject_id` | `<MATH_UUID>` — from Step 1 query A1 |
| `parent_id` | NULL |
| `class_level` | `'Class 6'` |
| `name` | `'Class 6'` |
| `created_at` | now() |

### D.2 Chapter Nodes

| # | `name` | `parent_id` | `class_level` | `subject_id` |
|---|--------|-------------|---------------|-------------|
| 1 | Patterns in Mathematics | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 2 | Lines and Angles | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 3 | Number Play | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 4 | Data Handling and Presentation | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 5 | Prime Time | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 6 | Perimeter and Area | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 7 | Fractions | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 8 | Playing with Constructions | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 9 | Symmetry | `<class6_root_id>` | NULL | `<MATH_UUID>` |
| 10 | The Other Side of Zero | `<class6_root_id>` | NULL | `<MATH_UUID>` |

### D.3 Field Rules

| Field | Rule |
|-------|------|
| `id` | Database-generated via `gen_random_uuid()` default |
| `subject_id` | Must match exact Mathematics subject UUID |
| `parent_id` | Root = NULL; chapters = Class 6 root UUID |
| `class_level` | Root = `'Class 6'`; chapters = NULL |
| `name` | Exact chapter names from GANITA PRAKASH source |
| `created_at` | Database default `now()` |

---

## E. EXISTING DATA SAFETY CHECK

### Before INSERT, verify:

| # | Check | Expected | Query |
|---|-------|----------|-------|
| 1 | Mathematics exists exactly once | 1 row | `SELECT count(*) FROM public.subjects WHERE name = 'Mathematics'` |
| 2 | Mathematics has 0 syllabus nodes | 0 rows | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Mathematics'` |
| 3 | No Class 6 root for Mathematics | 0 rows | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Mathematics' AND sn.class_level = 'Class 6' AND sn.parent_id IS NULL` |
| 4 | Hindi data unchanged | 2 rows | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Hindi'` |
| 5 | No duplicate siblings | 0 rows | `SELECT subject_id, parent_id, name, count(*) FROM public.syllabus_nodes GROUP BY subject_id, parent_id, name HAVING count(*) > 1` |
| 6 | No cross-subject parents | 0 rows | `SELECT count(*) FROM public.syllabus_nodes child JOIN public.syllabus_nodes parent ON parent.id = child.parent_id WHERE child.subject_id != parent.subject_id` |

### After INSERT, verify:

| # | Check | Expected | Query |
|---|-------|----------|-------|
| 1 | Mathematics has 11 nodes | 11 | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Mathematics'` |
| 2 | 1 root node | 1 | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Mathematics' AND sn.parent_id IS NULL` |
| 3 | 10 chapter nodes | 10 | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Mathematics' AND sn.parent_id IS NOT NULL AND sn.class_level IS NULL` |
| 4 | Hindi data still 2 rows | 2 | `SELECT count(*) FROM public.syllabus_nodes sn JOIN public.subjects s ON s.id = sn.subject_id WHERE s.name = 'Hindi'` |
| 5 | No orphans | 0 | `SELECT count(*) FROM public.syllabus_nodes sn LEFT JOIN public.subjects s ON s.id = sn.subject_id WHERE s.id IS NULL` |
| 6 | No cross-subject parents | 0 | `SELECT count(*) FROM public.syllabus_nodes child JOIN public.syllabus_nodes parent ON parent.id = child.parent_id WHERE child.subject_id != parent.subject_id` |
| 7 | No duplicate siblings | 0 | `SELECT subject_id, parent_id, name, count(*) FROM public.syllabus_nodes GROUP BY subject_id, parent_id, name HAVING count(*) > 1` |
| 8 | Max depth = 2 | 2 | See recursive CTE in validation section |

---

## F. DUPLICATE / IDEMPOTENCY STRATEGY

### Problem

`syllabus_nodes` has **NO UNIQUE constraint**. Running the same INSERT twice would create duplicate rows.

### Strategy

**Check-before-insert within a single transaction.**

Each chapter insert is guarded by a `NOT EXISTS` check matching on `(subject_id, parent_id, name)`. If a matching row already exists, the insert is skipped.

### Limitations

- Without a UNIQUE constraint, the check-before-insert is **race-condition vulnerable** if two sessions seed simultaneously
- Mitigation: Seed only from a single SQL Editor session
- Future: Add `unique(subject_id, parent_id, name)` constraint after SEED-1 validation

---

## G. SQL INSERT PLAN

### G.1 Full Seed Script

**STATUS: NOT FOR EXECUTION — requires human approval**

```sql
-- ============================================================
-- SEED-1: Mathematics Class 6 Pilot (GANITA PRAKASH)
-- STATUS: NOT FOR EXECUTION — requires human approval
-- DATE: 2026-09-12
-- ROWS: 11 (1 root + 10 chapters)
-- SOURCE: NCERT GANITA PRAKASH Class 6 Mathematics (NEP 2025-26)
-- ============================================================

BEGIN;

DO $$
DECLARE
  math_id uuid;
  class6_id uuid;
BEGIN
  -- Get Mathematics subject UUID
  SELECT id INTO math_id FROM public.subjects WHERE name = 'Mathematics';

  IF math_id IS NULL THEN
    RAISE EXCEPTION 'Mathematics subject not found in public.subjects';
  END IF;

  -- Check if Class 6 root already exists
  SELECT id INTO class6_id
  FROM public.syllabus_nodes
  WHERE subject_id = math_id
    AND parent_id IS NULL
    AND class_level = 'Class 6'
    AND name = 'Class 6';

  -- Insert Class 6 root if not exists
  IF class6_id IS NULL THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, NULL, 'Class 6', 'Class 6')
    RETURNING id INTO class6_id;
  END IF;

  -- Chapter 1: Patterns in Mathematics
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Patterns in Mathematics'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Patterns in Mathematics');
  END IF;

  -- Chapter 2: Lines and Angles
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Lines and Angles'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Lines and Angles');
  END IF;

  -- Chapter 3: Number Play
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Number Play'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Number Play');
  END IF;

  -- Chapter 4: Data Handling and Presentation
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Data Handling and Presentation'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Data Handling and Presentation');
  END IF;

  -- Chapter 5: Prime Time
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Prime Time'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Prime Time');
  END IF;

  -- Chapter 6: Perimeter and Area
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Perimeter and Area'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Perimeter and Area');
  END IF;

  -- Chapter 7: Fractions
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Fractions'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Fractions');
  END IF;

  -- Chapter 8: Playing with Constructions
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Playing with Constructions'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Playing with Constructions');
  END IF;

  -- Chapter 9: Symmetry
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'Symmetry'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'Symmetry');
  END IF;

  -- Chapter 10: The Other Side of Zero
  IF NOT EXISTS (
    SELECT 1 FROM public.syllabus_nodes
    WHERE subject_id = math_id AND parent_id = class6_id AND name = 'The Other Side of Zero'
  ) THEN
    INSERT INTO public.syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES (math_id, class6_id, NULL, 'The Other Side of Zero');
  END IF;

END $$;

COMMIT;
```

### G.2 Rollback Script

```sql
-- ============================================================
-- ROLLBACK: Remove SEED-1 Mathematics Class 6 rows only
-- PRESERVES: All other subjects and Hindi data
-- ============================================================

BEGIN;

DELETE FROM public.syllabus_nodes
WHERE subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
  AND (
    (parent_id IS NULL AND class_level = 'Class 6' AND name = 'Class 6')
    OR parent_id IN (
      SELECT id FROM public.syllabus_nodes
      WHERE subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
        AND parent_id IS NULL AND class_level = 'Class 6' AND name = 'Class 6'
    )
  );

COMMIT;
```

---

## H. VALIDATION SQL

```sql
-- 1. Total Mathematics nodes
SELECT count(*) AS total_math_nodes
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Mathematics';
-- Expected: 11

-- 2. Root count
SELECT count(*) AS root_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Mathematics' AND sn.parent_id IS NULL;
-- Expected: 1

-- 3. Chapter count
SELECT count(*) AS chapter_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Mathematics' AND sn.parent_id IS NOT NULL AND sn.class_level IS NULL;
-- Expected: 10

-- 4. Hindi data unchanged
SELECT count(*) AS hindi_nodes
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Hindi';
-- Expected: 2

-- 5. No orphans
SELECT count(*) AS orphan_count
FROM public.syllabus_nodes sn
LEFT JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.id IS NULL;
-- Expected: 0

-- 6. No cross-subject parents
SELECT count(*) AS cross_subject_count
FROM public.syllabus_nodes child
JOIN public.syllabus_nodes parent ON parent.id = child.parent_id
WHERE child.subject_id != parent.subject_id;
-- Expected: 0

-- 7. No duplicate siblings
SELECT subject_id, parent_id, name, count(*)
FROM public.syllabus_nodes
GROUP BY subject_id, parent_id, name
HAVING count(*) > 1;
-- Expected: 0 rows

-- 8. Maximum depth
WITH RECURSIVE tree AS (
  SELECT id, subject_id, parent_id, 1 AS depth
  FROM public.syllabus_nodes WHERE parent_id IS NULL
  UNION ALL
  SELECT sn.id, sn.subject_id, sn.parent_id, t.depth + 1
  FROM public.syllabus_nodes sn
  JOIN tree t ON sn.parent_id = t.id
)
SELECT max(depth) AS max_depth FROM tree;
-- Expected: 2 (root + chapters)

-- 9. Complete Mathematics tree
SELECT
  sn.id,
  sn.parent_id,
  sn.class_level,
  sn.name,
  CASE WHEN sn.parent_id IS NULL THEN 'root' ELSE 'chapter' END AS level
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Mathematics'
ORDER BY sn.parent_id NULLS FIRST, sn.name;
-- Expected: 1 root + 10 chapters = 11 rows

-- 10. Flutter load simulation
SELECT sn.*
FROM public.syllabus_nodes sn
WHERE sn.subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
ORDER BY sn.name;
-- Expected: 11 rows loadable by Flutter

-- 11. Flutter navigation simulation (root -> child)
SELECT
  root.name AS root_name,
  child.name AS chapter_name
FROM public.syllabus_nodes root
JOIN public.syllabus_nodes child ON child.parent_id = root.id
JOIN public.subjects s ON s.id = root.subject_id
WHERE s.name = 'Mathematics'
ORDER BY child.name;
-- Expected: 10 pairs
```

---

## I. RISKS

| Risk | Impact | Mitigation |
|------|--------|------------|
| No UNIQUE constraint → duplicate on double-run | Medium | Check-before-insert in script; seed from single session |
| Race condition if two sessions seed simultaneously | Low | Seed only from one SQL Editor session |
| User has old NCERT edition (pre-NEP) | High | User must confirm GANITA PRAKASH vs old textbook |
| class_level value mismatch ("6" vs "Class 6") | Medium | User must confirm before execution |
| Existing Hindi data accidentally modified | High | WHERE clause scopes to Mathematics only |
| Missing parent_id index (confirmed absent) | Low | Query performance acceptable for <1000 nodes |
| No rollback automation | Medium | Manual rollback script provided |

---

## J. UNKNOWNS

| # | Unknown | Required Action |
|---|---------|-----------------|
| 1 | Exact Mathematics subject UUID | Run query A1 |
| 2 | Whether `class_level` accepts "Class 6" text | Confirmed: column is text, nullable, no check constraint |
| 3 | Whether topics should be included | Human decision — pilot excludes topics |
| 4 | Whether user has GANITA PRAKASH (NEP) or old edition | Human must confirm |
| 5 | Whether chapter names match user's exact source | Human must verify |

---

## K. HUMAN APPROVAL REQUIRED

| # | Approval Item | Status |
|---|--------------|--------|
| 1 | Mathematics UUID is correct (from query A1) | PENDING |
| 2 | Chapter list matches GANITA PRAKASH (NEP 2025-26) | PENDING |
| 3 | class_level value = 'Class 6' | PENDING |
| 4 | No topics in this pilot | PENDING |
| 5 | Seed script is approved for execution | PENDING |
| 6 | Rollback script is understood | PENDING |
| 7 | Validation queries are approved | PENDING |

---

## SEED-1 STATUS: READY FOR HUMAN APPROVAL

**DATABASE CHANGES:** NONE (until human approves and executes)  
**FLUTTER CHANGES:** NONE  
**REPORT:** `docs/R3_5_SEED_1_MATH_CLASS6_PLAN.md`  
**APPROVAL REQUIRED:** YES  
**HARD STOP:** YES  

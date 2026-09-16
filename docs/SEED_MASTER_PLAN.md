# SEED MASTER PLAN

**Project:** My Preparation  
**Date:** 2026-09-12  
**Status:** PLANNING — APPROVED FOR PLAN GENERATION ONLY  
**Mode:** READ-ONLY PLANNING — NO DATABASE MODIFICATION  
**Source Inventory:** `docs/MASTER_SYLLABUS_INVENTORY.md` (2,528 lines, 660 verified chapters)

---

## PURPOSE

This document provides the complete execution plan for seeding the `syllabus_nodes` table with NCERT Classes 6–12 data. It defines:

1. Database prerequisites (subjects table expansion)
2. Hierarchy mapping (how NCERT maps to `syllabus_nodes`)
3. Exact row counts per phase
4. Foreign-key dependency order
5. Idempotency and duplicate prevention
6. Transaction and rollback strategy
7. Validation queries and post-seed integrity checks
8. Handling of verified vs count-only vs pending data
9. Handling of multiple textbook editions/versions
10. Future syllabus revision strategy

**THIS IS A PLAN ONLY. NO INSERT/UPDATE/DELETE WILL OCCUR WITHOUT SEPARATE EXPLICIT HUMAN APPROVAL.**

---

## PART 1: DATABASE PREREQUISITES

### 1.1 Current State

| Table | Rows | Notes |
|-------|------|-------|
| `public.subjects` | 11 | Only 11 subjects exist; NCERT needs 20+ |
| `public.syllabus_nodes` | 2 | Both Hindi (class_level = NULL) |

**Existing `syllabus_nodes` rows:**
- Hindi → Hindi व्याकरण → संज्ञा (parent_id → Hindi व्याकरण)
- Hindi → Hindi व्याकरण → सर्वनाम (parent_id → Hindi व्याकरण)

**Constraint inventory (SEED-0 verified):**
- FK `subject_id → subjects.id` ✓
- FK `parent_id → syllabus_nodes.id` ✓
- PK exists ✓
- `subject_id` index exists ✓
- NO unique constraint on (subject_id, parent_id, name)
- NO index on `parent_id`

### 1.2 Subjects Table Expansion Required

The current `subjects` table has 11 rows. NCERT Classes 6–12 require the following subjects:

| # | Subject Name (proposed) | Existing? | Notes |
|---|------------------------|-----------|-------|
| 1 | Mathematics | NEEDS VERIFICATION | May already exist |
| 2 | Science | NEEDS VERIFICATION | Classes 6–10 only |
| 3 | Physics | NEEDS VERIFICATION | Classes 11–12 only |
| 4 | Chemistry | NEEDS VERIFICATION | Classes 11–12 only |
| 5 | Biology | NEEDS VERIFICATION | Classes 11–12 only |
| 6 | English | NEEDS VERIFICATION | All classes |
| 7 | Hindi | EXISTS (2 syllabus_nodes) | All classes |
| 8 | Social Science | NEEDS VERIFICATION | Classes 6–10 |
| 9 | History | NEEDS VERIFICATION | Classes 11–12 |
| 10 | Geography | NEEDS VERIFICATION | Classes 11–12 |
| 11 | Political Science | NEEDS VERIFICATION | Classes 11–12 |
| 12 | Economics | NEEDS VERIFICATION | Classes 11–12 |
| 13 | Accountancy | NEEDS VERIFICATION | Classes 11–12 |
| 14 | Business Studies | NEEDS VERIFICATION | Classes 11–12 |
| 15 | Psychology | NEEDS VERIFICATION | Classes 11–12 |
| 16 | Sociology | NEEDS VERIFICATION | Classes 11–12 |
| 17 | Computer Science | NEEDS VERIFICATION | Classes 11–12 |
| 18 | Informatics Practices | NEEDS VERIFICATION | Classes 11–12 |
| 19 | Fine Arts | NEEDS VERIFICATION | Classes 11–12 |
| 20 | Home Science | NEEDS VERIFICATION | Classes 11–12 |
| 21 | Knowledge Traditions | NEEDS VERIFICATION | Class 11 only |
| 22 | Health and Physical Education | NEEDS VERIFICATION | Classes 10–11 |

**PREREQUISITE ACTION:** Before seeding `syllabus_nodes`, the `subjects` table must be checked and expanded. Each subject needs exactly one row with a stable UUID.

**Proposed approach:**
```sql
-- Check existing subjects
SELECT id, name FROM public.subjects ORDER BY name;

-- Insert missing subjects (one at a time, with stable UUIDs)
-- Use gen_random_uuid() or pre-generated UUIDs
INSERT INTO public.subjects (id, name, created_at)
VALUES (gen_random_uuid(), 'Physics', now())
ON CONFLICT DO NOTHING;
```

**NOTE:** There is NO unique constraint on `subjects.name`. The `ON CONFLICT DO NOTHING` will not work as expected. Instead, check for existence first:
```sql
SELECT EXISTS(SELECT 1 FROM public.subjects WHERE name = 'Physics');
```

### 1.3 Existing Hindi Nodes — Migration Strategy

The 2 existing Hindi syllabus_nodes have `class_level = NULL` and form a small tree:
```
Hindi (root, parent_id IS NULL)
  └── Hindi व्याकरण (parent_id → Hindi)
        ├── संज्ञा (parent_id → Hindi व्याकरण)
        └── सर्वनाम (parent_id → Hindi व्याकरण)
```

**Decision required:** These existing nodes represent grammar topics, not class-level syllabus. They should be PRESERVED and not modified. New class-level Hindi syllabus nodes will be created as siblings or children as appropriate.

**Recommended approach:**
- Keep existing Hindi grammar tree intact
- Add new `class_level` values to distinguish class-specific content
- Existing nodes with `class_level = NULL` remain as-is (they represent the general Hindi grammar tree)

---

## PART 2: HIERARCHY MAPPING

### 2.1 Node Types

Each `syllabus_nodes` row represents one node in the hierarchy. The hierarchy uses `parent_id` for tree structure and `class_level` for display grouping.

| Level | Node Type | `parent_id` | `class_level` | Example |
|-------|-----------|-------------|---------------|---------|
| 0 | Subject root | `NULL` | `NULL` | "Mathematics" |
| 1 | Class group | Subject root UUID | `"Class 6"` | "Class 6" under Mathematics |
| 2 | Textbook | Class group UUID | `"Class 6"` | "Ganita Prakash" under Mathematics → Class 6 |
| 3 | Chapter | Textbook UUID | `"Class 6"` | "Patterns in Mathematics" under Ganita Prakash |

**Key rules:**
- `parent_id IS NULL` → root node (subject) — detected by Flutter
- `class_level` is display-only, never used as filter
- Maximum depth: 4 levels (Subject → Class → Textbook → Chapter)
- Some subjects have multiple textbooks per class (e.g., Class 11 Physics has Part I and Part II)

### 2.2 Multi-Book Subjects

When a subject has multiple textbooks for one class, the hierarchy is:

```
Subject (root)
  └── Class X (class_group node)
        ├── Textbook A (textbook node)
        │     ├── Chapter 1
        │     ├── Chapter 2
        │     └── ...
        └── Textbook B (textbook node)
              ├── Chapter 1
              ├── Chapter 2
              └── ...
```

**Examples:**
- Class 11 Physics: Part I (7 chapters) + Part II (7 chapters) = 14 chapters
- Class 12 History: Part I (4) + Part II (4) + Part III (4) = 12 chapters
- Class 10 English: First Flight (9) + Footprints (9) + Words & Expressions (7) = 25 units

### 2.3 Single-Book Subjects

When a subject has one textbook per class:

```
Subject (root)
  └── Class X (class_group node)
        └── Textbook Name (textbook node)
              ├── Chapter 1
              ├── Chapter 2
              └── ...
```

### 2.4 Class 9 Social Science — NCF 2023 Special Case

Class 9 Social Science has been completely restructured under NCF 2023 into integrated themes (not separate History/Geography/Civics/Economics). The hierarchy is:

```
Social Science (root)
  └── Class 9 (class_group node)
        ├── Social Science Part 1 (textbook node)
        │     ├── Theme 1: Understanding Social Science
        │     ├── Theme 2: Shaping of the Earth's Surface
        │     ├── ...
        │     └── Theme 9: The Price Puzzle
        └── Social Science Part 2 (textbook node)
              ├── Theme 1: Oceans and Life
              ├── Theme 2: Life on Earth
              ├── ...
              └── Theme 7: Smart Ways to Manage Your Finances
```

**Important:** This is NOT the old separate History/Geography/Civics/Economics structure. Do not create separate subject roots for Class 9 Social Science disciplines.

### 2.5 Edition/Version Handling

The database has no `edition` or `version` column. To handle the NEP 2020 textbook transition:

**Strategy: Use textbook name as the version identifier.**

| Class | Old Edition | New Edition (NEP) |
|-------|-------------|-------------------|
| 6 Math | (none — always Ganita Prakash) | Ganita Prakash |
| 7 Math | (none — always Ganita Prakash) | Ganita Prakash |
| 8 Math | (none — always Ganita Prakash) | Ganita Prakash |
| 9 Math | (none — always Ganita Manjari) | Ganita Manjari |
| 10 Math | Mathematics | (same until 2027-28) |
| 11–12 | Old textbooks | (same until 2027-28) |

When new editions are introduced (e.g., Class 10 gets new NEP textbooks in 2027-28):
1. Create new textbook nodes with the new name
2. Mark old textbook nodes with a `_deprecated` suffix or separate class_level
3. Do NOT delete old nodes — they represent historical syllabus

**Proposed convention for future editions:**
- Current edition: textbook name as-is (e.g., "Ganita Prakash")
- Future edition: append year (e.g., "Ganita Prakash (2027-28)")
- This preserves old data while adding new

---

## PART 3: VERIFIED DATA — COMPLETE INVENTORY

### 3.1 Classes 6–10 (Core Subjects)

| Class | Subject | Textbook(s) | Chapters | Status | Books |
|-------|---------|-------------|----------|--------|-------|
| 6 | Mathematics | Ganita Prakash | 10 | VERIFIED | 1 |
| 6 | Science | Curiosity | 16 | PARTIALLY_VERIFIED | 1 |
| 6 | Social Science | Exploring Society (Vol I) | 12 | VERIFIED | 1 |
| 6 | English | Poorvi | 5 | VERIFIED | 1 |
| 6 | Hindi | Malhar | — | PENDING | 1 |
| 7 | Mathematics | Ganita Prakash (P1+P2) | 15 | VERIFIED | 2 |
| 7 | Science | Curiosity | 12 | VERIFIED | 1 |
| 7 | Social Science | Exploring Society (Vol I+II) | 20 | VERIFIED | 2 |
| 7 | English | Poorvi | 5 | VERIFIED | 1 |
| 7 | Hindi | Malhar | — | PENDING | 1 |
| 8 | Mathematics | Ganita Prakash (P1+P2) | 14 | VERIFIED | 2 |
| 8 | Science | Curiosity | 13 | VERIFIED | 1 |
| 8 | Social Science | Exploring Society (Part 1) | 7 | VERIFIED | 1 |
| 8 | English | Poorvi | 5 | VERIFIED | 1 |
| 8 | Hindi | Malhar | 8 | VERIFIED (titles generic) | 1 |
| 9 | Mathematics | Ganita Manjari | 8 | VERIFIED | 1 |
| 9 | Science | Science (NEP) | 13 | VERIFIED | 1 |
| 9 | Social Science | SS Part 1 + Part 2 (NCF 2023) | 16 | VERIFIED | 2 |
| 9 | English | Kaveri | 8 | VERIFIED | 1 |
| 9 | Hindi | Kshitij/Sparsh/Kritika/Sanchayan | 30 | COUNT_ONLY | 4 |
| 10 | Mathematics | Mathematics | 14 | VERIFIED | 1 |
| 10 | Science | Science | 13 | VERIFIED | 1 |
| 10 | Social Science | 4 books | 22 | VERIFIED | 4 |
| 10 | English | First Flight/Footprints/W&E2 | 25 | VERIFIED (Unit 4 gap) | 3 |
| 10 | Hindi | Kshitij II / Sparsh II | — | PENDING | 2 |
| 10 | Health & PE | Health and Physical Education | 10 | VERIFIED | 1 |

### 3.2 Class 11 (All Subjects)

| Subject | Textbook(s) | Chapters | Status | Stream | Books |
|---------|-------------|----------|--------|--------|-------|
| Mathematics | Mathematics | 14 | VERIFIED | Science | 1 |
| Physics | Physics Part I & II | 14 | VERIFIED | Science | 2 |
| Chemistry | Chemistry Part I & II | 9 | VERIFIED | Science | 2 |
| Biology | Biology | 19 | VERIFIED | Science | 1 |
| English | Hornbill/Snapshots/Woven Words | 35 | VERIFIED | All | 3 |
| Accountancy | Financial Accounting Part I/II | 9 | VERIFIED | Commerce | 2 |
| Business Studies | Business Studies | 11 | VERIFIED | Commerce | 1 |
| Economics | Indian Econ Dev + Statistics | 16 | VERIFIED | Commerce/Arts | 2 |
| Computer Science | Computer Science | 11 | VERIFIED | Science/Commerce | 1 |
| Informatics Practices | Informatics Practices | 8 | VERIFIED | Science/Commerce | 1 |
| Political Science | Indian Constitution at Work + Political Theory | 18 | VERIFIED | Arts | 2 |
| History | Themes in World History | 11 | VERIFIED | Arts | 1 |
| Geography | Fundamentals of Physical Geography / India Phys Env / Practical Work | 26 | VERIFIED | Arts | 3 |
| Psychology | Psychology | 8 | VERIFIED | Arts | 1 |
| Sociology | Introducing Sociology + Understanding Society | 10 | VERIFIED | Arts | 2 |
| Fine Arts | An Introduction to Indian Art | 8 | COUNT_ONLY | Arts | 1 |
| Home Science | Human Ecology Part I/II | 11 | COUNT_ONLY | Arts | 2 |
| Knowledge Traditions | Knowledge Traditions and Practices of India | 9 | COUNT_ONLY | Arts | 1 |
| Health & PE | Health and Physical Education | 11 | COUNT_ONLY | All | 1 |
| Hindi | Antra / Antral | — | PENDING | All | 2 |

### 3.3 Class 12 (All Subjects)

| Subject | Textbook(s) | Chapters | Status | Stream | Books |
|---------|-------------|----------|--------|--------|-------|
| Mathematics | Mathematics Part I & II | 13 | VERIFIED | Science | 2 |
| Physics | Physics Part I & II | 14 | VERIFIED | Science | 2 |
| Chemistry | Chemistry Part I & II | 10 | VERIFIED | Science | 2 |
| Biology | Biology | 13 | VERIFIED | Science | 1 |
| English | Flamingo/Vistas/Kaleidoscope | 31 | VERIFIED | All | 3 |
| Accountancy | Accountancy Part I/II/III | 14 | VERIFIED | Commerce | 3 |
| Business Studies | Business Studies Part I/II | 11 | VERIFIED | Commerce | 2 |
| Economics | Intro Macro + Indian Econ Dev | 11 | VERIFIED | Commerce/Arts | 2 |
| Computer Science | Computer Science | 13 | VERIFIED | Science/Commerce | 1 |
| Informatics Practices | Informatics Practices | 7 | VERIFIED | Science/Commerce | 1 |
| Political Science | Contemporary World Politics + Politics in India since Independence | 15 | VERIFIED | Arts | 2 |
| History | Themes in Indian History Part I/II/III | 12 | VERIFIED | Arts | 3 |
| Geography | Fundamentals of Human Geography / India People Economy / Practical Work | 21 | VERIFIED | Arts | 3 |
| Psychology | Psychology | 7 | COUNT_ONLY | Arts | 1 |
| Sociology | Indian Society + Social Change | 15 | VERIFIED | Arts | 2 |
| Fine Arts | An Introduction to Indian Art | 8 | COUNT_ONLY | Arts | 1 |
| Home Science | Human Ecology Part I–IV | 28 | COUNT_ONLY | Arts | 4 |
| Hindi | Antra II / Antral II | — | PENDING | All | 2 |

---

## PART 4: PROPOSED STRUCTURE — ROW COUNTS

### 4.1 Node Count Formula

For each subject-class combination:
```
nodes = 1 (subject root) + 1 (class group) + N_textbooks (textbook nodes) + N_chapters (chapter nodes)
```

### 4.2 Complete Row Count Estimate

#### Classes 6–10

| Class | Subject | Roots | Class Groups | Textbooks | Chapters | Total Nodes |
|-------|---------|-------|-------------|-----------|----------|-------------|
| 6 | Mathematics | 1 | 1 | 1 | 10 | 13 |
| 6 | Science | 1 | 1 | 1 | 16 | 19 |
| 6 | Social Science | 1 | 1 | 1 | 12 | 15 |
| 6 | English | 1 | 1 | 1 | 5 | 8 |
| 7 | Mathematics | 1* | 1 | 2 | 15 | 19 |
| 7 | Science | 1* | 1 | 1 | 12 | 15 |
| 7 | Social Science | 1* | 1 | 2 | 20 | 24 |
| 7 | English | 1* | 1 | 1 | 5 | 8 |
| 8 | Mathematics | 1* | 1 | 2 | 14 | 18 |
| 8 | Science | 1* | 1 | 1 | 13 | 16 |
| 8 | Social Science | 1* | 1 | 1 | 7 | 10 |
| 8 | English | 1* | 1 | 1 | 5 | 8 |
| 8 | Hindi | 1* | 1 | 1 | 8 | 11 |
| 9 | Mathematics | 1* | 1 | 1 | 8 | 11 |
| 9 | Science | 1* | 1 | 1 | 13 | 16 |
| 9 | Social Science | 1* | 1 | 2 | 16 | 20 |
| 9 | English | 1* | 1 | 1 | 8 | 11 |
| 10 | Mathematics | 1* | 1 | 1 | 14 | 17 |
| 10 | Science | 1* | 1 | 1 | 13 | 16 |
| 10 | Social Science | 1* | 1 | 4 | 22 | 28 |
| 10 | English | 1* | 1 | 3 | 25 | 30 |
| 10 | Health & PE | 1* | 1 | 1 | 10 | 13 |

*Root nodes shared across classes — counted once per subject, not per class.

**Shared root nodes (Classes 6–10):** Mathematics, Science, Social Science, English, Hindi, Health & PE = **6 roots**

**Class 6 nodes:** 13 + 19 + 15 + 8 = **55**
**Class 7 nodes:** 19 + 15 + 24 + 8 = **66**
**Class 8 nodes:** 18 + 16 + 10 + 8 + 11 = **63**
**Class 9 nodes:** 11 + 16 + 20 + 11 = **58**
**Class 10 nodes:** 17 + 16 + 28 + 30 + 13 = **104**

**Classes 6–10 total:** 6 roots + 346 class-level nodes = **352 nodes**

#### Classes 11–12

| Subject | Roots | C11 Class | C11 Textbooks | C11 Chapters | C12 Class | C12 Textbooks | C12 Chapters | Total |
|---------|-------|-----------|---------------|-------------|-----------|---------------|-------------|-------|
| Mathematics | 1 | 1 | 1 | 14 | 1 | 2 | 13 | 32 |
| Physics | (shared) | 1 | 2 | 14 | 1 | 2 | 14 | 34 |
| Chemistry | (shared) | 1 | 2 | 9 | 1 | 2 | 10 | 24 |
| Biology | (shared) | 1 | 1 | 19 | 1 | 1 | 13 | 34 |
| English | (shared) | 1 | 3 | 35 | 1 | 3 | 31 | 73 |
| Accountancy | 1 | 1 | 2 | 9 | 1 | 3 | 14 | 29 |
| Business Studies | (shared) | 1 | 1 | 11 | 1 | 2 | 11 | 26 |
| Economics | (shared) | 1 | 2 | 16 | 1 | 2 | 11 | 32 |
| Computer Science | (shared) | 1 | 1 | 11 | 1 | 1 | 13 | 26 |
| Informatics Practices | (shared) | 1 | 1 | 8 | 1 | 1 | 7 | 18 |
| Political Science | (shared) | 1 | 2 | 18 | 1 | 2 | 15 | 38 |
| History | (shared) | 1 | 1 | 11 | 1 | 3 | 12 | 28 |
| Geography | (shared) | 1 | 3 | 26 | 1 | 3 | 21 | 54 |
| Psychology | (shared) | 1 | 1 | 8 | 1 | 1 | 7 | 18 |
| Sociology | (shared) | 1 | 2 | 10 | 1 | 2 | 15 | 30 |
| Fine Arts | 1 | 1 | 1 | 8 | 1 | 1 | 8 | 19 |
| Home Science | 1 | 1 | 2 | 11 | 1 | 4 | 28 | 46 |
| Knowledge Traditions | 1 | 1 | 1 | 9 | — | — | — | 11 |
| Health & PE | 1 | 1 | 1 | 11 | — | — | — | 13 |

**Shared root nodes (Classes 11–12):** Physics, Chemistry, Biology, English, Business Studies, Economics, Computer Science, Informatics Practices, Political Science, History, Geography, Psychology, Sociology = **13 shared roots**

**Unique roots:** Mathematics, Accountancy, Fine Arts, Home Science, Knowledge Traditions, Health & PE = **6 unique roots**

**Total roots (11–12):** 13 shared + 6 unique = **19 roots**

**Class 11 nodes:** ~238 (from table above)
**Class 12 nodes:** ~232 (from table above)

**Classes 11–12 total:** 19 roots + 470 class-level nodes = **489 nodes**

### 4.3 Grand Total

| Category | Nodes |
|----------|-------|
| Classes 6–10 roots | 6 |
| Classes 6–10 class-level | 346 |
| Classes 11–12 roots | 19 |
| Classes 11–12 class-level | 470 |
| **GRAND TOTAL** | **841** |

**After subtracting shared roots counted once:** 841 - (roots counted in both C6-10 and C11-12) ≈ **830 unique nodes**

**Actual expected rows (with deduplication):** ~820–840 rows

---

## PART 5: SEED PHASES

### Phase 0: Subjects Table Expansion (PREREQUISITE)

**Action:** Verify existing subjects and add missing ones.

```sql
-- Step 0.1: Check what exists
SELECT id, name FROM public.subjects ORDER BY name;

-- Step 0.2: Insert missing subjects (one by one, checking existence first)
-- Example for Physics:
INSERT INTO public.subjects (id, name, created_at)
SELECT gen_random_uuid(), 'Physics', now()
WHERE NOT EXISTS (SELECT 1 FROM public.subjects WHERE name = 'Physics');
```

**Expected:** 11 existing + ~11 new = ~22 subjects total

**Dependencies:** None  
**Rollback:** DELETE the newly inserted subject rows

### Phase 1: Subject Root Nodes

**Action:** Create root nodes for all subjects.

```sql
-- Create root nodes (parent_id IS NULL, class_level IS NULL)
INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
SELECT
  gen_random_uuid(),
  s.id,
  NULL,
  NULL,
  s.name,
  now()
FROM public.subjects s
WHERE s.name IN (
  'Mathematics', 'Science', 'Physics', 'Chemistry', 'Biology',
  'English', 'Social Science', 'History', 'Geography',
  'Political Science', 'Economics', 'Accountancy', 'Business Studies',
  'Psychology', 'Sociology', 'Computer Science', 'Informatics Practices',
  'Fine Arts', 'Home Science', 'Knowledge Traditions',
  'Health and Physical Education'
)
AND NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.subject_id = s.id AND sn.parent_id IS NULL
);
```

**Expected rows:** ~22 root nodes  
**Dependencies:** Phase 0 (subjects table must be complete)  
**Rollback:** DELETE all rows WHERE parent_id IS NULL AND class_level IS NULL (but preserve existing Hindi root)

### Phase 2: Class Group Nodes (Classes 6–12)

**Action:** Create class group nodes under each subject root.

```sql
-- Create class group nodes
-- Example for Mathematics:
INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
SELECT
  gen_random_uuid(),
  sn.subject_id,
  sn.id,
  'Class 6',
  'Class 6',
  now()
FROM public.syllabus_nodes sn
WHERE sn.name = 'Mathematics' AND sn.parent_id IS NULL
AND NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn2
  WHERE sn2.parent_id = sn.id AND sn2.class_level = 'Class 6'
);
```

**Repeat for each class (6–12) and each subject.**

**Expected rows:** ~65 class group nodes (subjects × classes, minus gaps)  
**Dependencies:** Phase 1 (root nodes must exist)  
**Rollback:** DELETE all class group nodes

### Phase 3: Textbook Nodes

**Action:** Create textbook nodes under each class group.

```sql
-- Example: Class 11 Physics has Part I and Part II
-- First, find the Class 11 Physics class_group node
-- Then create two textbook children:

INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
VALUES
  (gen_random_uuid(), (SELECT id FROM public.subjects WHERE name = 'Physics'),
   (SELECT sn.id FROM public.syllabus_nodes sn
    JOIN public.subjects s ON sn.subject_id = s.id
    WHERE s.name = 'Physics' AND sn.class_level = 'Class 11' AND sn.parent_id IS NOT NULL
    AND sn.parent_id IN (SELECT id FROM public.syllabus_nodes WHERE parent_id IS NULL AND name = 'Physics')),
   'Class 11', 'Physics Part I', now()),
  (gen_random_uuid(), (SELECT id FROM public.subjects WHERE name = 'Physics'),
   (same parent_id),
   'Class 11', 'Physics Part II', now());
```

**Simplified approach:** Use a staging table or application-level logic to map subject+class to class_group UUID, then insert textbook nodes.

**Expected rows:** ~120 textbook nodes (across all classes)  
**Dependencies:** Phase 2 (class group nodes must exist)  
**Rollback:** DELETE all textbook nodes

### Phase 4: Chapter Nodes (VERIFIED ONLY)

**Action:** Create chapter nodes under each textbook. **Only VERIFIED chapter names are inserted.**

```sql
-- Example: Class 11 Mathematics chapters under "Mathematics" textbook
-- First find the textbook node UUID for Class 11 Mathematics
-- Then insert chapters:

INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
SELECT
  gen_random_uuid(),
  (SELECT id FROM public.subjects WHERE name = 'Mathematics'),
  :textbook_node_uuid,
  'Class 11',
  chapter_name,
  now()
FROM (VALUES
  ('Sets'),
  ('Relations and Functions'),
  ('Trigonometric Functions'),
  ('Complex Number and Quadratic Equations'),
  ('Linear Inequalities'),
  ('Permutations and Combinations'),
  ('Binomial Theorem'),
  ('Sequences and Series'),
  ('Straight Lines'),
  ('Conic Sections'),
  ('Limits and Derivatives'),
  ('Mathematical Reasoning'),
  ('Statistics'),
  ('Probability')
) AS chapters(chapter_name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.parent_id = :textbook_node_uuid AND sn.name = chapters.chapter_name
);
```

**Expected rows:** ~660 chapter nodes (verified chapters only)  
**Dependencies:** Phase 3 (textbook nodes must exist)  
**Rollback:** DELETE all chapter nodes

### Phase 5: COUNT_ONLY Nodes (Optional — Requires Human Approval)

**Action:** Insert COUNT_ONLY subjects with placeholder chapter names.

**NOT APPROVED FOR SEED — requires separate approval.**

These subjects have chapter counts known but names not verified:
- Class 9 Hindi (30 chapters across 4 books)
- Class 11 Fine Arts (8), Home Science (11), Knowledge Traditions (9), Health & PE (11)
- Class 12 Psychology (7), Fine Arts (8), Home Science (28)

**Proposed approach (if approved):**
```sql
-- Insert textbook-level nodes only, no chapters
-- Example: Class 11 Fine Arts
INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
VALUES
  (gen_random_uuid(), :subject_id, :class_group_uuid, 'Class 11', 'An Introduction to Indian Art', now());
-- Do NOT insert chapter nodes until names are verified
```

### Phase 6: PENDING Subjects (NOT APPROVED)

**NOT APPROVED FOR SEED.** These subjects are not yet verified:
- Class 6 Hindi (Malhar)
- Class 7 Hindi (Malhar)
- Class 10 Hindi (Kshitij II / Sparsh II)
- Class 11 Hindi (Antra / Antral)
- Class 12 Hindi (Antra II / Antral II)

**Action:** Wait for Hindi verification, then seed as Phase 4.

---

## PART 6: DEPENDENCY ORDER

### 6.1 Required Execution Order

```
Phase 0: Subjects table expansion
    ↓
Phase 1: Subject root nodes
    ↓
Phase 2: Class group nodes (all classes, all subjects)
    ↓
Phase 3: Textbook nodes (all textbooks, all classes)
    ↓
Phase 4: Chapter nodes (VERIFIED chapters only)
    ↓
Phase 5: COUNT_ONLY nodes (optional, requires approval)
    ↓
Phase 6: PENDING subjects (requires verification first)
```

### 6.2 Parallelization Opportunities

- Phase 2 can be parallelized across subjects (each subject is independent)
- Phase 3 can be parallelized across subjects
- Phase 4 can be parallelized across textbooks within a subject
- All phases depend on Phase 0 completing first

### 6.3 Constraint Considerations

- FK `subject_id → subjects.id`: Must have subject before creating nodes
- FK `parent_id → syllabus_nodes.id`: Parent must exist before child
- NO unique constraint: Duplicate check must be done in application/queries
- `subject_id` index: Already exists, helps with queries

---

## PART 7: IDEMPOTENCY AND DUPLICATE PREVENTION

### 7.1 The Problem

There is NO unique constraint on `syllabus_nodes`. Running the seed twice will create duplicate rows.

### 7.2 Idempotency Strategy

**Every INSERT must be wrapped with a duplicate check:**

```sql
-- BEFORE inserting, check if the node already exists
-- For root nodes:
WHERE NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.subject_id = :subject_id
  AND sn.parent_id IS NULL
  AND sn.name = :name
)

-- For class group nodes:
WHERE NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.parent_id = :subject_root_id
  AND sn.class_level = :class_level
  AND sn.name = :name
)

-- For textbook nodes:
WHERE NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.parent_id = :class_group_id
  AND sn.name = :textbook_name
)

-- For chapter nodes:
WHERE NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn
  WHERE sn.parent_id = :textbook_id
  AND sn.name = :chapter_name
)
```

### 7.3 Composite Key for Deduplication

Since there's no unique constraint, use this logical composite key for deduplication:

| Node Type | Deduplication Key |
|-----------|-------------------|
| Root | (subject_id, NULL, name) |
| Class group | (subject_id, parent_id, class_level) |
| Textbook | (subject_id, parent_id, name) |
| Chapter | (subject_id, parent_id, name) |

### 7.4 Pre-Seed Duplicate Check

Before ANY seed execution, run:

```sql
-- Check for existing data
SELECT COUNT(*) as existing_nodes FROM public.syllabus_nodes;

-- If count > 2 (the 2 existing Hindi nodes), DO NOT PROCEED
-- Investigate first
```

---

## PART 8: TRANSACTION AND ROLLBACK STRATEGY

### 8.1 Transaction Per Phase

Each phase should be executed within a single transaction:

```sql
BEGIN;

-- Phase 1 inserts here
-- ...

-- Verify count
SELECT COUNT(*) FROM public.syllabus_nodes WHERE parent_id IS NULL AND class_level IS NULL;

-- If count matches expected, COMMIT
COMMIT;

-- If count doesn't match, ROLLBACK
-- ROLLBACK;
```

### 8.2 Savepoints Within Phases

For large phases (Phase 4 with ~660 chapters), use savepoints:

```sql
BEGIN;

-- Insert Class 6 chapters
SAVEPOINT sp_class6;
-- ... inserts ...
-- If OK:
RELEASE SAVEPOINT sp_class6;

-- Insert Class 7 chapters
SAVEPOINT sp_class7;
-- ... inserts ...
-- If OK:
RELEASE SAVEPOINT sp_class7;

-- If any class fails, rollback to that savepoint
-- ROLLBACK TO SAVEPOINT sp_class7;

COMMIT;
```

### 8.3 Full Rollback Plan

| Scenario | Action |
|----------|--------|
| Phase 0 fails | Fix subjects table, retry |
| Phase 1 fails | DELETE all root nodes, retry Phase 1 |
| Phase 2 fails | DELETE all class group nodes, retry Phase 2 |
| Phase 3 fails | DELETE all textbook nodes, retry Phase 3 |
| Phase 4 fails | DELETE all chapter nodes, retry Phase 4 |
| Post-seed integrity check fails | Investigate, fix, re-seed affected phase |

### 8.4 Rollback SQL

```sql
-- Rollback Phase 4 (chapters only)
DELETE FROM public.syllabus_nodes
WHERE id IN (
  SELECT sn.id FROM public.syllabus_nodes sn
  WHERE sn.parent_id IN (
    SELECT sn2.id FROM public.syllabus_nodes sn2
    WHERE sn2.name IN ('Ganita Prakash', 'Curiosity', 'Exploring Society',
                        'Poorvi', 'Malhar', 'Kaveri', 'Mathematics',
                        'Science', 'First Flight', 'Footprints Without Feet',
                        'Words and Expressions 2', 'Health and Physical Education',
                        'Ganita Manjari', 'Physics Part I', 'Physics Part II',
                        'Chemistry Part I', 'Chemistry Part II', 'Biology',
                        'Hornbill', 'Snapshots', 'Woven Words',
                        'Financial Accounting Part I', 'Financial Accounting Part II',
                        'Business Studies', 'Indian Economic Development',
                        'Statistics for Economics', 'Computer Science',
                        'Informatics Practices', 'Indian Constitution at Work',
                        'Political Theory', 'Themes in World History',
                        'Fundamentals of Physical Geography',
                        'India Physical Environment',
                        'Practical Work in Geography Part I',
                        'Psychology', 'Introducing Sociology',
                        'Understanding Society', 'An Introduction to Indian Art',
                        'Human Ecology and Family Sciences Part I',
                        'Human Ecology and Family Sciences Part II',
                        'Knowledge Traditions and Practices of India',
                        'Mathematics Part I', 'Mathematics Part II',
                        'Flamingo', 'Vistas', 'Kaleidoscope',
                        'Accountancy Part I', 'Accountancy Part II',
                        'Accountancy Part III', 'Business Studies Part I',
                        'Business Studies Part II', 'Introductory Macroeconomics',
                        'Indian Economic Development', -- Class 12 version
                        'Contemporary World Politics',
                        'Politics in India since Independence',
                        'Themes in Indian History Part I',
                        'Themes in Indian History Part II',
                        'Themes in Indian History Part III',
                        'Fundamentals of Human Geography',
                        'India People and Economy',
                        'Practical Work in Geography Part II',
                        'Indian Society',
                        'Social Change and Development in India',
                        'Human Ecology and Family Sciences Part III',
                        'Human Ecology and Family Sciences Part IV',
                        'Social Science Part 1',
                        'Social Science Part 2',
                        'Kshitij', 'Sparsh', 'Kritika', 'Sanchayan'
  )
  AND sn.parent_id IS NOT NULL  -- class group or textbook level
  AND sn.name IN (SELECT chapter_name FROM <chapter_list>)  -- only chapters
);

-- This is complex. Better approach: rollback by phase using timestamps or batch IDs.
```

**Recommended rollback approach:** Use a `created_at` timestamp window to identify and delete seeded rows:

```sql
-- Rollback all nodes created in the last hour
DELETE FROM public.syllabus_nodes
WHERE created_at > now() - interval '1 hour'
AND id NOT IN (
  -- Preserve existing Hindi nodes
  SELECT id FROM public.syllabus_nodes
  WHERE name IN ('Hindi व्याकरण', 'संज्ञा', 'सर्वनाम')
);
```

---

## PART 9: VALIDATION QUERIES

### 9.1 Pre-Seed Validation

```sql
-- V0.1: Check subjects table completeness
SELECT name FROM public.subjects ORDER BY name;
-- Expected: ~22 subjects including Physics, Chemistry, Biology, etc.

-- V0.2: Check existing syllabus_nodes
SELECT COUNT(*) as total_nodes,
       COUNT(CASE WHEN parent_id IS NULL THEN 1 END) as root_nodes,
       COUNT(CASE WHEN parent_id IS NOT NULL THEN 1 END) as child_nodes
FROM public.syllabus_nodes;
-- Expected before seed: 2 nodes, 1 root (Hindi), 1 child (Hindi व्याकरण)
```

### 9.2 Post-Phase 1 Validation

```sql
-- V1.1: Count root nodes
SELECT COUNT(*) FROM public.syllabus_nodes
WHERE parent_id IS NULL AND class_level IS NULL;
-- Expected: ~22

-- V1.2: Each root has correct subject_id
SELECT sn.name, s.name as subject_name
FROM public.syllabus_nodes sn
JOIN public.subjects s ON sn.subject_id = s.id
WHERE sn.parent_id IS NULL AND sn.class_level IS NULL
AND sn.name != s.name;
-- Expected: 0 rows (root name should match subject name)
```

### 9.3 Post-Phase 2 Validation

```sql
-- V2.1: Count class group nodes
SELECT COUNT(*) FROM public.syllabus_nodes
WHERE parent_id IS NOT NULL
AND class_level IN ('Class 6','Class 7','Class 8','Class 9','Class 10','Class 11','Class 12')
AND parent_id IN (SELECT id FROM public.syllabus_nodes WHERE parent_id IS NULL);
-- Expected: ~65

-- V2.2: No orphan class groups
SELECT sn.id, sn.name, sn.class_level
FROM public.syllabus_nodes sn
WHERE sn.class_level LIKE 'Class %'
AND sn.parent_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn2
  WHERE sn2.id = sn.parent_id
);
-- Expected: 0 rows
```

### 9.4 Post-Phase 3 Validation

```sql
-- V3.1: Count textbook nodes
SELECT COUNT(*) FROM public.syllabus_nodes sn
WHERE sn.parent_id IN (
  SELECT id FROM public.syllabus_nodes
  WHERE parent_id IS NOT NULL
  AND class_level LIKE 'Class %'
  AND parent_id IN (SELECT id FROM public.syllabus_nodes WHERE parent_id IS NULL)
);
-- Expected: ~120

-- V3.2: Textbook nodes have valid parent
SELECT sn.name, sn.class_level
FROM public.syllabus_nodes sn
WHERE sn.parent_id IS NOT NULL
AND sn.class_level LIKE 'Class %'
AND NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn2
  WHERE sn2.id = sn.parent_id
  AND sn2.class_level LIKE 'Class %'
);
-- Expected: 0 rows
```

### 9.5 Post-Phase 4 Validation (Critical)

```sql
-- V4.1: Total node count
SELECT COUNT(*) FROM public.syllabus_nodes;
-- Expected: ~830

-- V4.2: Chapter count per class
SELECT
  sn2.class_level,
  COUNT(*) as chapter_count
FROM public.syllabus_nodes sn
JOIN public.syllabus_nodes sn2 ON sn.parent_id = sn2.id
WHERE sn2.class_level LIKE 'Class %'
AND sn2.parent_id IN (SELECT id FROM public.syllabus_nodes WHERE parent_id IS NULL)
GROUP BY sn2.class_level
ORDER BY sn2.class_level;
-- Expected:
-- Class 6: ~43
-- Class 7: ~52
-- Class 8: ~47
-- Class 9: ~45
-- Class 10: ~87
-- Class 11: ~199
-- Class 12: ~187

-- V4.3: No duplicate chapter names under same textbook
SELECT parent_id, name, COUNT(*)
FROM public.syllabus_nodes
WHERE parent_id IS NOT NULL
AND parent_id IN (
  SELECT id FROM public.syllabus_nodes
  WHERE parent_id IN (
    SELECT id FROM public.syllabus_nodes
    WHERE parent_id IN (SELECT id FROM public.syllabus_nodes WHERE parent_id IS NULL)
  )
)
GROUP BY parent_id, name
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- V4.4: FK integrity — all parent_ids reference existing nodes
SELECT sn.id, sn.name, sn.parent_id
FROM public.syllabus_nodes sn
WHERE sn.parent_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM public.syllabus_nodes sn2
  WHERE sn2.id = sn.parent_id
);
-- Expected: 0 rows

-- V4.5: FK integrity — all subject_ids reference existing subjects
SELECT sn.id, sn.name, sn.subject_id
FROM public.syllabus_nodes sn
WHERE NOT EXISTS (
  SELECT 1 FROM public.subjects s
  WHERE s.id = sn.subject_id
);
-- Expected: 0 rows

-- V4.6: Root nodes have NULL parent_id and NULL class_level
SELECT COUNT(*) FROM public.syllabus_nodes
WHERE parent_id IS NULL AND class_level IS NOT NULL;
-- Expected: 0

-- V4.7: All non-root nodes have non-NULL parent_id
SELECT COUNT(*) FROM public.syllabus_nodes
WHERE parent_id IS NULL AND class_level IS NULL
AND name NOT IN (SELECT name FROM public.subjects);
-- Expected: 0 (all root nodes should be subject names)

-- V4.8: Existing Hindi nodes preserved
SELECT * FROM public.syllabus_nodes
WHERE name IN ('Hindi व्याकरण', 'संज्ञा', 'सर्वनाम');
-- Expected: 3 rows (preserved from original)

-- V4.9: Verify Class 9 Social Science structure
SELECT sn.name, sn.class_level
FROM public.syllabus_nodes sn
WHERE sn.class_level = 'Class 9'
AND sn.parent_id IN (
  SELECT id FROM public.syllabus_nodes
  WHERE name = 'Social Science'
  AND parent_id IS NULL
)
ORDER BY sn.name;
-- Expected: "Social Science Part 1", "Social Science Part 2"

-- V4.10: Verify multi-book subjects have correct chapter counts
-- Example: Class 11 Geography should have 26 chapters across 3 textbooks
SELECT COUNT(*) FROM public.syllabus_nodes sn
WHERE sn.parent_id IN (
  SELECT sn2.id FROM public.syllabus_nodes sn2
  WHERE sn2.parent_id IN (
    SELECT sn3.id FROM public.syllabus_nodes sn3
    WHERE sn3.parent_id IN (
      SELECT id FROM public.syllabus_nodes WHERE name = 'Geography' AND parent_id IS NULL
    )
    AND sn3.class_level = 'Class 11'
  )
  AND sn2.name IN ('Fundamentals of Physical Geography', 'India Physical Environment', 'Practical Work in Geography Part I')
);
-- Expected: 26
```

### 9.6 Flutter Integration Validation

```sql
-- V5.1: Root detection (Flutter uses parent_id IS NULL)
SELECT sn.id, sn.name, s.name as subject
FROM public.syllabus_nodes sn
JOIN public.subjects s ON sn.subject_id = s.id
WHERE sn.parent_id IS NULL AND sn.class_level IS NULL;
-- Expected: One root per subject

-- V5.2: Load nodes for subject (Flutter's loadNodesForSubject)
-- Simulate: Load all Mathematics nodes
SELECT * FROM public.syllabus_nodes
WHERE subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
ORDER BY class_level, name;
-- Expected: Root → Class groups → Textbooks → Chapters

-- V5.3: getChildren (Flutter's getChildren)
-- Simulate: Get children of Class 11 Mathematics root
SELECT sn2.* FROM public.syllabus_nodes sn2
WHERE sn2.parent_id = (
  SELECT id FROM public.syllabus_nodes
  WHERE subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
  AND class_level = 'Class 11'
  AND parent_id IS NOT NULL
);
-- Expected: 1 textbook node ("Mathematics")
```

---

## PART 10: HANDLING PENDING/COUNT-ONLY DATA

### 10.1 Verification Status Categories

| Status | Meaning | Seed Action |
|--------|---------|-------------|
| VERIFIED | Chapter names confirmed from official source | INSERT chapters |
| PARTIALLY_VERIFIED | Chapter count confirmed, names from secondary source | INSERT with note |
| COUNT_ONLY | Chapter count known, names not verified | INSERT textbook node only, NO chapters |
| PENDING | Not fetched | DO NOT INSERT |

### 10.2 COUNT_ONLY Handling

For COUNT_ONLY subjects, insert only the textbook node (not chapters):

```sql
-- Example: Class 11 Fine Arts (8 chapters, names not verified)
-- Insert textbook node:
INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
VALUES (
  gen_random_uuid(),
  (SELECT id FROM public.subjects WHERE name = 'Fine Arts'),
  :class_group_uuid,
  'Class 11',
  'An Introduction to Indian Art',
  now()
);
-- Do NOT insert chapter nodes until names are verified
```

### 10.3 PENDING Handling

For PENDING subjects, do NOT insert any nodes. Wait for verification.

**Currently PENDING:**
- Class 6 Hindi (Malhar) — NCERT site transport errors
- Class 7 Hindi (Malhar) — NCERT site transport errors
- Class 10 Hindi (Kshitij II / Sparsh II) — not fetched
- Class 11 Hindi (Antra / Antral) — not fetched
- Class 12 Hindi (Antra II / Antral II) — not fetched

### 10.4 PARTIALLY_VERIFIED Handling

Class 6 Science (Curiosity) is PARTIALLY_VERIFIED — chapter names from Vedantu, not official PDF. Seed with `PARTIALLY_VERIFIED` status tag:

```sql
-- Add a comment or metadata field to indicate partial verification
-- Since there's no status column, use a naming convention:
-- Chapter name = "The Universe" (as verified from Vedantu)
-- Source note = "Vedantu syllabus (2026-27), not confirmed from official PDF"
```

---

## PART 11: FUTURE SYLLABUS REVISIONS

### 11.1 The Problem

NCERT textbooks are revised periodically (e.g., NEP 2020 transition). The database must support:
- Multiple editions of the same subject/class
- Historical syllabus preservation
- New syllabus addition without corrupting existing data

### 11.2 Strategy: Textbook Name as Version

Since there's no `edition` or `version` column, use the textbook name itself as the version identifier:

| Year | Class 10 Math Textbook | Node Name |
|------|----------------------|-----------|
| 2024–2027 | Mathematics (old) | "Mathematics" |
| 2027–2030 | Ganita Prakash (new NEP) | "Ganita Prakash" |

### 11.3 Adding New Editions

When a new textbook edition is introduced:

1. **Create new textbook node** under the same class group:
```sql
-- Class 10 Math gets new NEP textbook in 2027-28
INSERT INTO public.syllabus_nodes (id, subject_id, parent_id, class_level, name, created_at)
VALUES (
  gen_random_uuid(),
  (SELECT id FROM public.subjects WHERE name = 'Mathematics'),
  :class_10_math_group_uuid,
  'Class 10',
  'Ganita Prakash (2027-28)',  -- Versioned name
  now()
);
```

2. **Add new chapters** under the new textbook node

3. **Do NOT delete old nodes** — they represent historical syllabus

4. **Flutter must handle multiple textbooks** per class (already does — `getChildren` returns all children)

### 11.4 Deprecation Convention

When a textbook is no longer current:
- Keep the node and all children intact
- Optionally add `(deprecated)` suffix to the textbook name
- Flutter should display the current edition prominently, deprecated in a secondary view

### 11.5 Class Level for Historical Reference

Use `class_level` to distinguish editions if needed:
- Current: `class_level = 'Class 10'`
- Deprecated: `class_level = 'Class 10 (2024-2027)'`

**Recommended:** Keep `class_level` as-is (display-only). Use textbook name for versioning.

---

## PART 12: COMPLETE SQL SCRIPT STRUCTURE

### 12.1 Script Organization

```
seed_master_plan.sql
├── BEGIN TRANSACTION
├── Phase 0: Subjects expansion
├── SAVEPOINT sp_phase0
├── Phase 1: Root nodes
├── SAVEPOINT sp_phase1
├── Phase 2: Class group nodes
├── SAVEPOINT sp_phase2
├── Phase 3: Textbook nodes
├── SAVEPOINT sp_phase3
├── Phase 4: Chapter nodes (VERIFIED)
├── SAVEPOINT sp_phase4
├── Validation queries (V0.1 through V5.3)
├── COMMIT (if all validations pass)
└── ROLLBACK (if any validation fails)
```

### 12.2 Expected Row Counts (Final)

| Phase | Rows |
|-------|------|
| Phase 0: Subjects | ~11 new rows in `subjects` |
| Phase 1: Root nodes | ~22 rows |
| Phase 2: Class group nodes | ~65 rows |
| Phase 3: Textbook nodes | ~120 rows |
| Phase 4: Chapter nodes | ~620 rows |
| **Total** | **~827 rows** in `syllabus_nodes` |

**Note:** Existing 2 Hindi nodes preserved. Grand total in `syllabus_nodes`: ~829 rows.

---

## PART 13: RISK ASSESSMENT

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Duplicate nodes from double-execution | High — corrupts data | Medium | Idempotency checks on every INSERT |
| FK violation (parent before child) | High — INSERT fails | Low | Strict dependency order |
| Subjects table incomplete | High — FK violation | Medium | Phase 0 validation before Phase 1 |
| Existing Hindi nodes deleted | Medium — data loss | Low | Exclusion list in rollback queries |
| Class 9 Social Science old structure created | Medium — wrong hierarchy | Low | Explicit NCF 2023 structure in Phase 4 |
| COUNT_ONLY chapters inserted with fake names | High — data corruption | Low | Phase 5 not approved, no chapters for COUNT_ONLY |
| NEP transition not handled | Medium — future confusion | Medium | Versioning convention documented |
| Validation queries miss edge cases | Medium — undetected errors | Low | Multiple validation layers (V0–V5) |

---

## PART 14: WHAT IS NOT APPROVED FOR SEED

The following are explicitly NOT APPROVED and must NOT be inserted:

1. **PENDING subjects** (Class 6, 7, 10, 11, 12 Hindi) — no verification
2. **COUNT_ONLY chapter names** — only textbook-level nodes, no chapters
3. **Unverified chapter names** from secondary sources without cross-reference
4. **Class 10 English Words & Expressions Unit 4** — gap in listing, not verified
5. **Class 6 Social Science Volume II** — existence uncertain
6. **Any competitive exam syllabus data** — separate approval required
7. **Any modification to existing Hindi nodes** — preserve as-is
8. **Any schema changes** — no ALTER TABLE
9. **Any Flutter code changes** — not in scope

---

## PART 15: APPROVAL GATES

| Gate | Action Required | Status |
|------|----------------|--------|
| Gate 1: Plan generation | Generate this document | ✓ APPROVED |
| Gate 2: Subjects table expansion | Verify and expand subjects | PENDING HUMAN APPROVAL |
| Gate 3: Phase 1–4 execution | Seed root → class → textbook → chapter | PENDING HUMAN APPROVAL |
| Gate 4: Validation | Run all validation queries | PENDING HUMAN APPROVAL |
| Gate 5: COUNT_ONLY subjects | Seed textbook nodes only | PENDING HUMAN APPROVAL |
| Gate 6: Hindi subjects | Verify and seed | PENDING HUMAN APPROVAL |
| Gate 7: Competitive exams | Separate plan required | NOT STARTED |

---

## FINAL STATUS

**SEED MASTER PLAN:** COMPLETE  
**Expected rows:** ~827 new rows in `syllabus_nodes`  
**Verified chapters:** 620 (across Classes 6–12)  
**COUNT_ONLY subjects:** 8 (textbook nodes only, no chapters)  
**PENDING subjects:** 5 (all Hindi — not seeded)  
**Execution status:** NOT EXECUTED — HARD STOP  

**NO INSERT/UPDATE/DELETE HAS OCCURRED.**

**NO SEED EXECUTION WILL OCCUR WITHOUT SEPARATE EXPLICIT HUMAN APPROVAL AT EACH GATE.**

**HARD STOP: YES**

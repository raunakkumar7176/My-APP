# R3.5 — SYLLABUS DATA SPECIFICATION + SEED PLAN

**Project:** My Preparation  
**Stack:** Flutter + Supabase  
**Date:** 2026-09-12  
**Status:** SPECIFICATION ONLY — NO DATABASE MODIFICATION  

---

## 1. PURPOSE

This document defines the complete syllabus data specification, naming conventions, seed strategy, validation plan, and rollback strategy for the `public.syllabus_nodes` table. It is a **read-only planning artifact** — no database modifications, code changes, or data insertion are performed or authorized during this phase.

**Approval gates** (all must be explicitly approved before seed execution):
1. Hierarchy convention
2. Subject strategy
3. Naming convention
4. Verified syllabus sources
5. Seed mechanism
6. Idempotency strategy
7. Rollback strategy

---

## 2. CURRENT DATABASE FACTS

### 2.1 Schema Verification Queries

The following SQL queries should be run as read-only to verify exact constraints before any seed work:

```sql
-- A. subjects: columns
SELECT
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'subjects'
ORDER BY c.ordinal_position;

-- A. subjects: constraints
SELECT
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'public' AND tc.table_name = 'subjects';

-- A. subjects: indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'subjects';

-- A. subjects: RLS
SELECT
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
WHERE c.relname = 'subjects';

-- A. subjects: policies
SELECT
  polname AS policy_name,
  polcmd AS command,
  pg_get_expr(polqual, polrelid) AS using_expr,
  pg_get_expr(polwithcheck, polrelid) AS with_check_expr
FROM pg_policy
WHERE polrelid = 'subjects'::regclass;

-- B. syllabus_nodes: columns
SELECT
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.table_name = 'syllabus_nodes'
ORDER BY c.ordinal_position;

-- B. syllabus_nodes: all constraints
SELECT
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name AS foreign_table,
  ccu.column_name AS foreign_column
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_schema = 'public' AND tc.table_name = 'syllabus_nodes';

-- B. syllabus_nodes: indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'syllabus_nodes';

-- B. syllabus_nodes: RLS + policies
SELECT
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
WHERE c.relname = 'syllabus_nodes';

SELECT
  polname AS policy_name,
  polcmd AS command,
  pg_get_expr(polqual, polrelid) AS using_expr,
  pg_get_expr(polwithcheck, polrelid) AS with_check_expr
FROM pg_policy
WHERE polrelid = 'syllabus_nodes'::regclass;
```

### 2.2 Known Schema (from R3 report)

**subjects:**

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | uuid | NO | gen_random_uuid() |
| `name` | text | NO | — |

**syllabus_nodes:**

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | uuid | NO | gen_random_uuid() |
| `subject_id` | uuid | NO | — |
| `parent_id` | uuid | YES | NULL |
| `class_level` | text | YES | NULL |
| `name` | text | NO | — |
| `created_at` | timestamptz | NO | now() |

### 2.3 Constraints Under Investigation

| Constraint | Status | Evidence |
|------------|--------|----------|
| `subject_id → subjects.id` FK | UNKNOWN | Not confirmed in schema dump — must verify via `information_schema.table_constraints` |
| `parent_id → syllabus_nodes.id` self-FK | UNKNOWN | Not confirmed — must verify |
| `unique(subject_id, parent_id, name)` | UNKNOWN | Must verify |
| `unique(subject_id, name)` | UNKNOWN | Must verify |
| Check constraint on `parent_id` | UNKNOWN | Must verify |
| Check constraint on `class_level` | UNKNOWN | Must verify |
| Index on `subject_id` | UNKNOWN | Must verify |
| Index on `parent_id` | UNKNOWN | Must verify |

**CONFIRMED:** The Dart model treats `parent_id` as a self-referencing FK and `subject_id` as an FK to subjects. But database-level enforcement is unverified.

---

## 3. CURRENT DATA AUDIT

### 3.1 Audit Queries

```sql
-- 1. All subjects
SELECT id, name FROM public.subjects ORDER BY name;

-- 2. Total syllabus_nodes
SELECT count(*) AS total_nodes FROM public.syllabus_nodes;

-- 3. Node count per subject
SELECT
  s.id AS subject_id,
  s.name AS subject_name,
  count(sn.id) AS node_count
FROM public.subjects s
LEFT JOIN public.syllabus_nodes sn ON sn.subject_id = s.id
GROUP BY s.id, s.name
ORDER BY s.name;

-- 4. Root count per subject (parent_id IS NULL)
SELECT
  sn.subject_id,
  s.name AS subject_name,
  count(*) AS root_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.parent_id IS NULL
GROUP BY sn.subject_id, s.name
ORDER BY s.name;

-- 5. Child count per subject (parent_id IS NOT NULL)
SELECT
  sn.subject_id,
  s.name AS subject_name,
  count(*) AS child_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.parent_id IS NOT NULL
GROUP BY sn.subject_id, s.name
ORDER BY s.name;

-- 6. Maximum hierarchy depth
WITH RECURSIVE tree AS (
  SELECT id, subject_id, parent_id, 1 AS depth
  FROM public.syllabus_nodes
  WHERE parent_id IS NULL
  UNION ALL
  SELECT sn.id, sn.subject_id, sn.parent_id, t.depth + 1
  FROM public.syllabus_nodes sn
  JOIN tree t ON sn.parent_id = t.id
)
SELECT max(depth) AS max_depth FROM tree;

-- 7. Complete Hindi tree
SELECT
  sn.id,
  sn.subject_id,
  sn.parent_id,
  sn.class_level,
  sn.name,
  sn.created_at
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.name = 'Hindi'
ORDER BY sn.parent_id NULLS FIRST, sn.name;

-- 8. Orphan subject references
SELECT sn.id, sn.name, sn.subject_id
FROM public.syllabus_nodes sn
LEFT JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.id IS NULL;

-- 9. Orphan parent references
SELECT sn.id, sn.name, sn.parent_id
FROM public.syllabus_nodes sn
LEFT JOIN public.syllabus_nodes parent ON parent.id = sn.parent_id
WHERE sn.parent_id IS NOT NULL AND parent.id IS NULL;

-- 10. Cross-subject parent check
SELECT
  child.id AS child_id,
  child.name AS child_name,
  child.subject_id AS child_subject,
  parent.id AS parent_id,
  parent.subject_id AS parent_subject
FROM public.syllabus_nodes child
JOIN public.syllabus_nodes parent ON parent.id = child.parent_id
WHERE child.subject_id != parent.subject_id;

-- 11. Duplicate sibling names
SELECT
  parent_id,
  subject_id,
  name,
  count(*) AS occurrences
FROM public.syllabus_nodes
GROUP BY parent_id, subject_id, name
HAVING count(*) > 1;

-- 12. Duplicate root names per subject
SELECT
  subject_id,
  name,
  count(*) AS occurrences
FROM public.syllabus_nodes
WHERE parent_id IS NULL
GROUP BY subject_id, name
HAVING count(*) > 1;
```

### 3.2 Known Data (from user confirmation)

| Fact | Status |
|------|--------|
| 11 subjects exist | CONFIRMED |
| 2 syllabus_nodes exist | CONFIRMED |
| Both belong to Hindi | CONFIRMED |
| Hierarchy: Hindi → Hindi व्याकरण → संज्ञा, सर्वनाम | CONFIRMED |
| class_level is NULL on both existing nodes | CONFIRMED |
| RLS allows authenticated SELECT | CONFIRMED |
| Flutter queries are correct | CONFIRMED |
| Missing data is the root cause of empty syllabus views | CONFIRMED |

---

## 4. FLUTTER CONTRACT VERIFICATION

### 4.1 Model: `SyllabusNode` (`lib/core/models/syllabus_node.dart`)

| Field | DB Column | Type | Nullable | Notes |
|-------|-----------|------|----------|-------|
| `id` | `id` | String (uuid) | NO | PK |
| `subjectId` | `subject_id` | String (uuid) | NO | FK → subjects |
| `parentId` | `parent_id` | String? (uuid) | YES | Self-ref FK |
| `classLevel` | `class_level` | String? (text) | YES | Display only |
| `name` | `name` | String (text) | NO | Display title |
| `createdAt` | `created_at` | DateTime (timestamptz) | NO | Auto |

### 4.2 Root Detection

```dart
bool get isRoot => parentId == null;
```

**CONFIRMED:** Root = `parent_id IS NULL`. No other condition.

### 4.3 Tree Building

```dart
// syllabus_service.dart:60
static List<SyllabusNode> buildTree(List<SyllabusNode> allNodes) {
  return allNodes.where((node) => node.isRoot).toList();
}
```

Returns all nodes where `parent_id IS NULL`. No depth limit.

### 4.4 Child Detection

```dart
// syllabus_service.dart:63-65
static List<SyllabusNode> getChildren(List<SyllabusNode> allNodes, String parentId) {
  return allNodes.where((node) => node.parentId == parentId).toList();
}
```

Client-side filter. No depth limit.

### 4.5 Subject Filtering

```dart
// syllabus_service.dart:15-18
.select('id, subject_id, parent_id, class_level, name, created_at')
.eq('subject_id', subjectId)
.order('name', ascending: true);
```

Loads ALL nodes for a subject in one query. Client-side tree construction.

### 4.6 `class_level` Usage

| Location | Usage |
|----------|-------|
| `syllabus_screen.dart:217-219` | Display as subtitle if non-null |
| `syllabus_detail_screen.dart:191-193` | Display as subtitle if non-null |
| Elsewhere | **Not used for filtering, grouping, or queries** |

**CONFIRMED:** `class_level` is purely a display label. It is never used as a filter parameter.

### 4.7 Display Behavior

Both screens show:
- **Title:** `node.name`
- **Subtitle:** `node.classLevel` (if non-null)
- **Leading icon:** folder if has children, document if leaf
- **Trailing:** child count if >0, else chevron

### 4.8 Navigation

| Condition | Route |
|-----------|-------|
| Has children | `/subjects/{subjectId}/syllabus/{nodeId}` → `SyllabusDetailScreen` |
| Leaf node | `/subjects/{subjectId}/nodes/{nodeId}/materials` → `MaterialListScreen` |

### 4.9 Flutter Contract Conclusion

**CONFIRMED:** The proposed hierarchy (subject → class → chapter → topic → subtopic) can be consumed **without any Flutter code changes**. The generic tree structure, root detection, child loading, and display all work with any depth. `class_level` is display-only.

---

## 5. PROPOSED DATA MODEL CONVENTION

### 5.1 Hierarchy Structure

```
Subject (from public.subjects)
└── Class root node (parent_id = NULL, class_level = 'Class N')
    └── Chapter (parent_id = class_root_id, class_level = NULL)
        └── Topic (parent_id = chapter_id, class_level = NULL)
            └── Sub-topic (parent_id = topic_id, class_level = NULL) [optional]
```

### 5.2 Design Decisions

| Question | Proposal | Rationale |
|----------|----------|-----------|
| **Q1:** Should Class 6–12 be root nodes? | **YES** — one root node per class per subject | Matches the NCERT structure. Root nodes are the first thing a user sees when opening a subject's syllabus. |
| **Q2:** Should `class_level` contain "Class 6", "Class 7", etc.? | **YES** — `"Class N"` format | Already used in test fixtures (`widget_test.dart:55`). English format is consistent and locale-neutral. |
| **Q3:** Should `class_level` be populated ONLY on class root nodes? | **YES** | Keeps the data clean. Only the top-level class node needs the label. Chapters and topics inherit class context from their ancestor chain. |
| **Q4:** Should chapter/topic/subtopic `class_level` be NULL? | **YES** | Consistent with existing Hindi data (both nodes have NULL class_level). Avoids data redundancy. |
| **Q5:** Should every node carry the same `subject_id`? | **YES** | Denormalized for fast subject-scoped queries. All descendants inherit the subject from their root. The Flutter query filters by `subject_id` directly. |
| **Q6:** Should `parent_id` always remain within the same subject? | **YES** | Cross-subject parents would break the subject-scoped query model. The audit query (Part 2, #10) must always return zero rows. |
| **Q7:** Non-NCERT subjects (Reasoning, Current Affairs)? | **Use a flat or 2-level structure** — see Part 5 | Forcing them into class→chapter→topic would create artificial hierarchy. |

### 5.3 Two Possible Designs for Non-NCERT Subjects

**Design A: Force into class structure (not recommended)**
```
Reasoning
├── Class 6
│   └── General Reasoning
│       └── ...
```
*Problem:* Reasoning is not class-based. Students of all classes study the same content. Creating fake "Class 6" through "Class 12" nodes would confuse users and waste database rows.

**Design B: Flat or topic-based structure (recommended)**
```
Reasoning
├── Logical Reasoning
│   ├── Analogies
│   ├── Series
│   └── ...
├── Verbal Reasoning
│   ├── Coding-Decoding
│   └── ...
└── ...
```
*Advantage:* Honest to the subject. No artificial class levels. `class_level` remains NULL (consistent with current Hindi data). User sees meaningful categories immediately.

**RECOMMENDATION:** Design B for non-NCERT subjects. Design A only if a future requirement explicitly demands class-based filtering for these subjects.

---

## 6. SUBJECT-BY-SUBJECT STRATEGY

### 6.1 NCERT-Based Subjects (Classes 6–12 apply)

| # | Subject | Classes 6–12 | Root Structure | Chapter Level | Topic Level | Sub-topics | Special Notes |
|---|---------|-------------|----------------|---------------|-------------|------------|---------------|
| 1 | Mathematics | YES | 7 roots (Class 6–12) | YES | YES | Useful for large chapters | NCERT math has clear chapter→exercise→problem structure |
| 3 | Science | YES | 7 roots (Class 6–10 only for combined science; separate Physics/Chemistry/Biology for 11–12) | YES | YES | Useful | Class 6–10: combined "Science". Class 11–12: split into Physics, Chemistry, Biology. **This creates a structural question.** |
| 4 | History | YES | 7 roots (Class 6–12) | YES | YES | Optional | NCERT History textbooks exist for classes 6–12 |
| 5 | Geography | YES | 7 roots (Class 6–12) | YES | YES | Optional | NCERT Geography textbooks exist for classes 6–12 |
| 6 | Polity | YES | 7 roots (Class 6–12) | YES | YES | Optional | NCERT Political Science/Civics for classes 6–12 |
| 7 | Economics | YES | 7 roots (Class 9–12 only; no NCERT Economics for 6–8) | YES | YES | Optional | NCERT Economics starts at Class 9 |
| 10 | Hindi | YES (existing) | 7 roots (Class 6–12) | YES | YES | Useful | Hindi grammar/literature textbooks for classes 6–12 |

**Science structural question:** Should Science be one subject with class-level chapter groupings, or should it be split into Physics/Chemistry/Biology for classes 11–12? The current schema has no mechanism to "split" a subject at a certain class level. Options:
- **Option A:** Keep as one "Science" subject. Class 11–12 chapters are just grouped under the same class root. User distinguishes by chapter names.
- **Option B:** Create separate subjects (Physics, Chemistry, Biology) and remove "Science" for class 11–12.
- **RECOMMENDATION:** Option A for now. Simpler. Can be refactured later.

### 6.2 Non-NCERT Subjects (Special Structure)

| # | Subject | Classes 6–12 | Proposed Structure | Rationale |
|---|---------|-------------|-------------------|-----------|
| 2 | Reasoning | NO | Flat topic-based: Category → Topic | Not class-based content |
| 8 | Environment | PARTIAL | Flat or 2-level: Theme → Topic | Environment covers current topics, not class-specific |
| 9 | English | YES | 7 roots (Class 6–12) → Chapter → Topic | NCERT English textbooks exist |
| 11 | Current Affairs | NO | Time-based or topic-based: Category → Topic | Changes daily/monthly, not class-based |

### 6.3 Recommended Structure per Subject

```
Mathematics
├── Class 6 (class_level = 'Class 6')
│   ├── Chapter 1: Knowing Our Numbers
│   │   ├── Comparing Numbers
│   │   ├── Large Numbers
│   │   └── ...
│   └── ...
├── Class 7
│   └── ...
...
└── Class 12
    └── ...

Reasoning
├── Logical Reasoning (class_level = NULL)
│   ├── Analogies
│   ├── Series
│   └── ...
├── Verbal Reasoning (class_level = NULL)
│   └── ...
└── Non-Verbal Reasoning (class_level = NULL)
    └── ...

Science
├── Class 6 (class_level = 'Class 6')
│   ├── Chapter 1: Food — Where Does It Come From?
│   └── ...
...
├── Class 10 (class_level = 'Class 10')
│   └── ...
├── Class 11 (class_level = 'Class 11')
│   ├── Physics
│   │   ├── Chapter 1: Physical World
│   │   └── ...
│   ├── Chemistry
│   │   └── ...
│   └── Biology
│       └── ...
└── Class 12
    └── (same as Class 11 structure)

Current Affairs
├── Politics (class_level = NULL)
│   └── ...
├── Economy (class_level = NULL)
│   └── ...
├── Science & Tech (class_level = NULL)
│   └── ...
└── ...
```

---

## 7. SOURCE REQUIREMENTS

### 7.1 NCERT-Derived Subjects

Before any NCERT syllabus row can be seeded, the following must be verified:

| Field | Required Value |
|-------|---------------|
| Source name | NCERT |
| Class | 6, 7, 8, 9, 10, 11, 12 |
| Subject | Mathematics / Science / History / Geography / Polity / Economics / English / Hindi |
| Chapter list | Exact chapter titles from official NCERT textbooks |
| Topic list | Exact topic titles (if available in table of contents) |
| Language | English (primary), Hindi (if available) |
| Version/year | Current edition (2024–25 or latest) |
| Verification status | MUST be confirmed against https://ncert.nic.in or official NCERT PDFs |

### 7.2 Non-NCERT Subjects

| Subject | Source Required |
|---------|----------------|
| Reasoning | Define topic taxonomy (e.g., standard competitive exam reasoning syllabus) |
| Environment | Define scope (e.g., UPSC Environment syllabus, or current topics) |
| Current Affairs | Define update frequency and archival strategy |

### 7.3 Source Checklist Template

```
[ ] Source name: _______________
[ ] Class: _______________
[ ] Subject: _______________
[ ] Chapter list verified against official source: YES / NO
[ ] Topic list verified against official source: YES / NO
[ ] Language: _______________
[ ] Version/year: _______________
[ ] Verified by: _______________
[ ] Verification date: _______________
```

### 7.4 Data NOT to be invented

- Chapter names must come from official NCERT textbook tables of contents
- Topic names must come from official NCERT chapter sub-headings
- Do not assume a chapter has N topics without verifying the source
- Do not fabricate "Sub-topic" levels that don't exist in the source

---

## 8. NAMING CONVENTION

### 8.1 Rules

| Aspect | Rule | Example |
|--------|------|---------|
| Class root name | `"Class N"` in English | `Class 6`, `Class 12` |
| `class_level` value | `"Class N"` in English | `Class 6`, `Class 12` |
| Chapter name | Exact NCERT chapter title | `Knowing Our Numbers` |
| Topic name | Exact NCERT sub-heading or topic | `Comparing Numbers` |
| Language | English for all names | — |
| Existing Hindi data | **DO NOT modify** | Keep `Hindi व्याकरण`, `संज्ञा, सर्वनाम` as-is |
| Chapter numbering | Include in name if NCERT uses it | `Chapter 1: Knowing Our Numbers` |
| Topic numbering | Include only if NCERT uses it | No artificial numbering |
| Punctuation | Follow NCERT source exactly | Do not add/remove periods, commas |
| Whitespace | Single spaces only | No trailing/leading spaces |
| Abbreviations | Avoid unless NCERT uses them | Use `Political Science` not `Pol. Sci.` |
| Case | Title Case for English | `Knowing Our Numbers` |
| Duplicates | Must be unique within same parent + subject | Handled by seed process |

### 8.2 Reserved Patterns

Do NOT use these patterns unless they appear in the source:
- `Chapter 1`, `Chapter 2` (without title)
- `Topic 1`, `Topic 2`
- `Unit 1`, `Unit 2`
- Generic names like `Overview`, `Introduction` (unless source uses them)

---

## 9. ID / PARENT STRATEGY

### 9.1 Requirements

1. Deterministic/reproducible seed process
2. Correct FK insertion order (subjects → roots → chapters → topics)
3. No hardcoded existing UUIDs (unless explicitly approved)
4. Parent IDs must be generated/referenced safely
5. Subject IDs must come from `public.subjects`
6. No cross-subject parent references

### 9.2 Evaluated Approaches

**Approach A: Random UUIDs with INSERT...RETURNING**
```sql
INSERT INTO syllabus_nodes (subject_id, parent_id, class_level, name)
VALUES ($subject_id, NULL, 'Class 6', 'Class 6')
RETURNING id;
-- Use returned id as parent_id for children
```
*Pros:* Simple. *Cons:* Non-deterministic. Re-running creates duplicates (unless unique constraint exists).

**Approach B: Deterministic UUIDs (uuid_generate_v5)**
```sql
SELECT uuid_generate_v5(
  '00000000-0000-0000-0000-000000000000'::uuid,
  'mathematics|class-6|chapter-1|knowing-our-numbers'
);
```
*Pros:* Deterministic. Same input = same UUID. Re-runnable. *Cons:* Requires `uuid-ossp` or `pgcrypto` extension.

**Approach C: CTE-based lookup**
```sql
WITH subj AS (
  SELECT id AS subject_id FROM subjects WHERE name = 'Mathematics'
),
class6 AS (
  INSERT INTO syllabus_nodes (subject_id, parent_id, class_level, name)
  SELECT subject_id, NULL, 'Class 6', 'Class 6' FROM subj
  ON CONFLICT DO NOTHING
  RETURNING id
),
ch1 AS (
  INSERT INTO syllabus_nodes (subject_id, parent_id, class_level, name)
  SELECT subject_id, (SELECT id FROM class6), NULL, 'Chapter 1: Knowing Our Numbers'
  FROM subj
  ON CONFLICT DO NOTHING
  RETURNING id
)
...
```
*Pros:* Atomic. Single transaction. *Cons:* Complex. Requires `ON CONFLICT` target.

### 9.3 Recommendation

**Approach C (CTE-based) with existence checks.**

Rationale:
- Atomic — all-or-nothing per subject
- Deterministic — same subject produces same data
- Re-runnable with existence checks (no ON CONFLICT needed if we check first)
- Correct FK insertion order via CTE chaining

The seed script should:
1. Check if the subject already has root nodes → skip if exists
2. Insert root nodes (class level) → get IDs
3. Insert chapters → get IDs
4. Insert topics → get IDs
5. All within a single transaction

---

## 10. IDEMPOTENCY STRATEGY

### 10.1 Design Limitation

**UNKNOWN:** Whether `unique(subject_id, parent_id, name)` or `unique(subject_id, name)` constraints exist on `syllabus_nodes`. Must be verified before seed execution.

### 10.2 Strategy (Constraint-Independent)

Since constraint existence is unknown, the seed process should be idempotent via **existence checks** rather than relying on `ON CONFLICT`:

```sql
-- Check before insert
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM syllabus_nodes
    WHERE subject_id = $1
      AND parent_id IS NULL
      AND name = 'Class 6'
  ) THEN
    INSERT INTO syllabus_nodes (subject_id, parent_id, class_level, name)
    VALUES ($1, NULL, 'Class 6', 'Class 6');
  END IF;
END $$;
```

### 10.3 If Unique Constraint Exists

If `unique(subject_id, parent_id, name)` is verified, use:
```sql
INSERT INTO syllabus_nodes (subject_id, parent_id, class_level, name)
VALUES ($1, NULL, 'Class 6', 'Class 6')
ON CONFLICT (subject_id, parent_id, name) DO NOTHING;
```

### 10.4 Verification

After seed, the idempotency check is:
```sql
-- Run seed twice, verify no duplicates
SELECT subject_id, parent_id, name, count(*)
FROM syllabus_nodes
GROUP BY subject_id, parent_id, name
HAVING count(*) > 1;
-- Must return 0 rows
```

---

## 11. VALIDATION PLAN

### 11.1 Post-Seed Validation Queries

```sql
-- 1. Total nodes
SELECT count(*) AS total_nodes FROM public.syllabus_nodes;

-- 2. Nodes per subject
SELECT s.name, count(sn.id) AS node_count
FROM public.subjects s
LEFT JOIN public.syllabus_nodes sn ON sn.subject_id = s.id
GROUP BY s.name ORDER BY s.name;

-- 3. Nodes per class per subject
SELECT
  s.name AS subject,
  sn.class_level,
  count(*) AS node_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.class_level IS NOT NULL
GROUP BY s.name, sn.class_level
ORDER BY s.name, sn.class_level;

-- 4. Root count per subject
SELECT s.name, count(sn.id) AS root_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.parent_id IS NULL
GROUP BY s.name ORDER BY s.name;

-- 5. Child count per subject
SELECT s.name, count(sn.id) AS child_count
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.parent_id IS NOT NULL
GROUP BY s.name ORDER BY s.name;

-- 6. Orphan subject references
SELECT sn.id, sn.name, sn.subject_id
FROM public.syllabus_nodes sn
LEFT JOIN public.subjects s ON s.id = sn.subject_id
WHERE s.id IS NULL;

-- 7. Orphan parent references
SELECT sn.id, sn.name, sn.parent_id
FROM public.syllabus_nodes sn
LEFT JOIN public.syllabus_nodes p ON p.id = sn.parent_id
WHERE sn.parent_id IS NOT NULL AND p.id IS NULL;

-- 8. Cross-subject parent references
SELECT child.id, child.subject_id AS child_subject,
       parent.subject_id AS parent_subject
FROM public.syllabus_nodes child
JOIN public.syllabus_nodes parent ON parent.id = child.parent_id
WHERE child.subject_id != parent.subject_id;

-- 9. Duplicate sibling names
SELECT subject_id, parent_id, name, count(*)
FROM public.syllabus_nodes
GROUP BY subject_id, parent_id, name
HAVING count(*) > 1;

-- 10. Maximum depth
WITH RECURSIVE tree AS (
  SELECT id, subject_id, parent_id, 1 AS depth
  FROM public.syllabus_nodes WHERE parent_id IS NULL
  UNION ALL
  SELECT sn.id, sn.subject_id, sn.parent_id, t.depth + 1
  FROM public.syllabus_nodes sn
  JOIN tree t ON sn.parent_id = t.id
)
SELECT max(depth) AS max_depth FROM tree;

-- 11. Each class 6–12 has expected root (for NCERT subjects)
SELECT s.name AS subject, sn.class_level, sn.name AS root_name
FROM public.syllabus_nodes sn
JOIN public.subjects s ON s.id = sn.subject_id
WHERE sn.parent_id IS NULL
  AND sn.class_level IS NOT NULL
ORDER BY s.name, sn.class_level;

-- 12. Every child shares subject with parent
SELECT child.id, child.name
FROM public.syllabus_nodes child
JOIN public.syllabus_nodes parent ON parent.id = child.parent_id
WHERE child.subject_id != parent.subject_id;

-- 13. No unexpected NULL values
SELECT id, name, subject_id, parent_id, class_level
FROM public.syllabus_nodes
WHERE subject_id IS NULL
   OR name IS NULL
   OR created_at IS NULL;

-- 14. Flutter can load each subject (simulated query)
SELECT sn.*
FROM public.syllabus_nodes sn
WHERE sn.subject_id = (SELECT id FROM public.subjects WHERE name = 'Mathematics')
ORDER BY sn.name;

-- 15. Flutter can navigate root → child → leaf
-- Verify at least one chain of depth ≥ 3 exists
WITH RECURSIVE tree AS (
  SELECT id, subject_id, parent_id, name, 1 AS depth
  FROM public.syllabus_nodes WHERE parent_id IS NULL
  UNION ALL
  SELECT sn.id, sn.subject_id, sn.parent_id, sn.name, t.depth + 1
  FROM public.syllabus_nodes sn
  JOIN tree t ON sn.parent_id = t.id
)
SELECT * FROM tree WHERE depth >= 3 LIMIT 10;
```

---

## 12. SEED PHASES

### SEED-0: Schema/Data Verification

| Item | Detail |
|------|--------|
| **Input** | Current database state |
| **Action** | Run all Part 1 queries to verify constraints, indexes, RLS |
| **Expected output** | Complete constraint report |
| **Verification** | All queries return results |
| **Rollback** | N/A (read-only) |
| **Approval gate** | CONSTRAINT REPORT APPROVED |

### SEED-1: One Subject + One Class

| Item | Detail |
|------|--------|
| **Input** | One verified subject (e.g., Mathematics), one class (e.g., Class 6), verified chapter list |
| **Action** | Insert root node + chapters + topics for Class 6 only |
| **Expected output** | 1 root + N chapters + M topics |
| **Verification** | Run Part 11 validation for this subject only |
| **Rollback** | Delete nodes WHERE subject_id = (this subject) AND class_level = 'Class 6' |
| **Approval gate** | SINGLE CLASS SEED APPROVED |

### SEED-2: Verify Database Tree

| Item | Detail |
|------|--------|
| **Input** | SEED-1 results |
| **Action** | Run depth, orphan, cross-subject, duplicate queries |
| **Expected output** | All validation checks pass |
| **Verification** | Zero orphans, zero cross-subject, zero duplicates, correct depth |
| **Rollback** | N/A (read-only) |
| **Approval gate** | DATABASE TREE APPROVED |

### SEED-3: Verify Flutter Tree

| Item | Detail |
|------|--------|
| **Input** | SEED-1 results in database |
| **Action** | Run app, navigate subject → class → chapter → topic |
| **Expected output** | Flutter displays correct hierarchy |
| **Verification** | Visual inspection + app logs show correct node counts |
| **Rollback** | N/A (read-only) |
| **Approval gate** | FLUTTER TREE APPROVED |

### SEED-4: Expand Remaining Classes

| Item | Detail |
|------|--------|
| **Input** | SEED-3 approved, verified chapter lists for Classes 7–12 |
| **Action** | Insert remaining class roots + chapters + topics |
| **Expected output** | 7 class roots + chapters + topics per subject |
| **Verification** | Run full validation suite |
| **Rollback** | Delete nodes WHERE subject_id = (this subject) AND class_level IS NOT NULL |
| **Approval gate** | FULL SUBJECT APPROVED |

### SEED-5: Expand Remaining Subjects

| Item | Detail |
|------|--------|
| **Input** | SEED-4 approved, verified chapter lists for all subjects |
| **Action** | Seed remaining NCERT subjects, then non-NCERT subjects |
| **Expected output** | All 11 subjects populated |
| **Verification** | Run full validation suite |
| **Rollback** | Delete only seed-created rows (see Part 14) |
| **Approval gate** | FULL SEED APPROVED |

### SEED-6: Full Integrity Verification

| Item | Detail |
|------|--------|
| **Input** | SEED-5 completed |
| **Action** | Run all Part 11 queries + Flutter navigation test for every subject |
| **Expected output** | All 15 validation checks pass |
| **Verification** | Complete integrity report |
| **Rollback** | N/A (final verification) |
| **Approval gate** | SIGN-OFF |

---

## 13. ROLLBACK STRATEGY

### 13.1 Principle

Rollback must **never** delete:
- Existing subjects
- User-generated materials
- Test data
- Progress data
- Group data
- Profile data
- Any row not created by the seed process

### 13.2 Seed Row Identification

Every seed-created row can be identified by:
1. `created_at` timestamp (seed window)
2. `subject_id` (scope to specific subject)
3. `class_level` (scope to specific class)
4. Parent chain (descendants of seed root nodes)

### 13.3 Rollback by Phase

| Phase | Rollback Action |
|-------|----------------|
| SEED-1 | `DELETE FROM syllabus_nodes WHERE subject_id = :subj_id AND (class_level = 'Class 6' OR parent_id IN (SELECT id FROM syllabus_nodes WHERE subject_id = :subj_id AND class_level = 'Class 6'))` |
| SEED-4 | `DELETE FROM syllabus_nodes WHERE subject_id = :subj_id AND class_level IS NOT NULL` |
| SEED-5 | Delete per-subject: `DELETE FROM syllabus_nodes WHERE subject_id = :subj_id` |
| SEED-6 | N/A |

### 13.4 Verification After Rollback

```sql
-- Confirm subject still exists
SELECT * FROM subjects WHERE id = :subj_id;

-- Confirm no syllabus nodes remain for that subject
SELECT count(*) FROM syllabus_nodes WHERE subject_id = :subj_id;
-- Must return 0

-- Confirm other subjects unaffected
SELECT s.name, count(sn.id)
FROM subjects s
LEFT JOIN syllabus_nodes sn ON sn.subject_id = s.id
GROUP BY s.name;
```

---

## 14. RISKS

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing unique constraint on (subject_id, parent_id, name) | Duplicate rows on re-run | Use existence checks in seed script |
| Missing FK constraints | Orphan rows possible | Validate after seed |
| Science class 11–12 split confusion | Users may not understand combined structure | Use clear chapter names |
| Non-NCERT subjects forced into class structure | Artificial hierarchy | Use flat structure (Design B) |
| NCERT chapter list changes between versions | Stale data | Pin to specific NCERT version/year |
| Large topic counts (e.g., Math) | Performance concern | Flutter already loads all nodes per subject; should be fine for <1000 nodes |
| Current Affairs temporal nature | Data becomes stale | Seed with topic categories, not individual items |

---

## 15. UNKNOWN / NEEDS APPROVAL

| # | Unknown | Required Action |
|---|---------|-----------------|
| 1 | FK constraints on syllabus_nodes | Run Part 1 queries |
| 2 | Unique constraints on syllabus_nodes | Run Part 1 queries |
| 3 | Indexes on syllabus_nodes | Run Part 1 queries |
| 4 | Science: split or combined for Class 11–12? | Human decision required |
| 5 | NCERT version/year to use | Human decision required |
| 6 | Whether to include sub-topic level | Human decision required |
| 7 | Current Affairs structure | Human decision required |
| 8 | Reasoning topic taxonomy | Human decision required |
| 9 | Environment scope | Human decision required |
| 10 | Hindi: grammar vs literature vs both? | Human decision required |

---

## 16. APPROVAL GATES

Before any seed execution, the following must be explicitly approved:

| Gate | Status | Approved By | Date |
|------|--------|-------------|------|
| 1. Hierarchy convention (subject → class → chapter → topic) | PENDING | — | — |
| 2. Subject strategy (per-subject structure) | PENDING | — | — |
| 3. Naming convention (Class N, English, NCERT titles) | PENDING | — | — |
| 4. Verified syllabus sources (NCERT chapter lists) | PENDING | — | — |
| 5. Seed mechanism (CTE-based, existence checks) | PENDING | — | — |
| 6. Idempotency strategy (check-before-insert) | PENDING | — | — |
| 7. Rollback strategy (per-phase, per-subject) | PENDING | — | — |
| 8. Science structure (combined vs split) | PENDING | — | — |
| 9. Non-NCERT subject structures | PENDING | — | — |

---

## 17. FINAL REPORT

### R3.5 STATUS: SPECIFICATION ONLY

**A. CONFIRMED FACTS:**
- 11 subjects exist in `public.subjects`
- 2 syllabus_nodes exist, both Hindi
- Schema: `id`, `subject_id`, `parent_id`, `class_level`, `name`, `created_at`
- `parent_id` = self-referencing tree relationship
- `parent_id IS NULL` = root node
- `class_level` is nullable display-only text
- Flutter queries and JSON mappings are correct
- RLS allows authenticated SELECT
- Missing data is the root cause of empty syllabus views
- No seed/import system exists
- No SQL files, migration files, or seed scripts exist in repo

**B. PROPOSED DESIGN:**
- Generic self-referencing tree scoped by `subject_id`
- NCERT subjects: subject → class root → chapter → topic → subtopic (optional)
- Non-NCERT subjects: flat or 2-level topic structure
- `class_level` populated only on class root nodes
- English naming with "Class N" format
- All nodes carry the same `subject_id`

**C. UNKNOWN / NEEDS APPROVAL:**
- FK/unique/index constraints (must run Part 1 queries)
- Science class 11–12 structure
- NCERT version/year
- Non-NCERT subject structures
- Sub-topic level decision

**D. DATA SOURCE REQUIREMENTS:**
- Official NCERT textbook tables of contents for each class/subject
- Verified chapter and topic names
- Language and version confirmation

**E. FUTURE SEED PLAN:**
- SEED-0 → SEED-1 → SEED-2 → SEED-3 → SEED-4 → SEED-5 → SEED-6
- Each phase requires explicit approval before next

**F. VALIDATION PLAN:**
- 15 post-seed validation queries defined
- Flutter navigation verification included

**G. RISKS:**
- Missing constraints may allow duplicates
- Science structural complexity
- NCERT version staleness
- Non-NCERT subject fit

**H. FILES CREATED:**
- `docs/R3_5_SYLLABUS_DATA_SPECIFICATION.md` (this file)

**I. FILES MODIFIED:**
- NONE

**J. DATABASE CHANGES:**
- NONE

**K. TESTS RUN:**
- NONE (read-only specification phase)

**L. FINAL RECOMMENDATION:**
- Run Part 1 constraint verification queries before any seed work
- Obtain human approval for all 9 gates
- Begin with SEED-1 (one subject, one class) after approval
- Never proceed to next phase without explicit approval

---

**HARD STOP — R3.5 COMPLETE**

This specification is ready for human review and approval. No further action should be taken until all approval gates are cleared.

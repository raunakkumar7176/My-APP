# R4.7.5A — LIVE SUPABASE DATABASE DISCOVERY

**Date:** 2026-09-14
**Status:** PENDING — AWAITS LIVE DATABASE EXECUTION
**Mode:** Read-only. No modifications.

---

## EXECUTION INSTRUCTIONS

1. Open Supabase Dashboard → SQL Editor
2. Copy entire contents of `migrations/R4_7_5A_live_discovery.sql`
3. Execute all queries
4. Copy ALL results (every section)
5. Paste results into this document under the corresponding sections below
6. Mark each section as COMPLETE after pasting results

---

## 1. Executive Summary

**Status:** PENDING — Awaiting live database discovery execution.

**What We Need To Know:**
1. Do `rpc_save_answers`, `rpc_submit_attempt`, `fn_score_attempt` exist in the live database?
2. What columns actually exist on each table?
3. Is RLS enabled on `attempts`, `answers`, `results`?
4. What is the actual `_fn_start_attempt_core` source code?
5. What columns exist on `results` (specifically: subject_breakdown, topic_breakdown, accuracy, score, max_score)?

**Discovery SQL File:** `migrations/R4_7_5A_live_discovery.sql`

---

## 2. Live Schema

### 2.1 tests columns
**Status:** PENDING
```
[Paste query 1.1 results here]
```

### 2.2 questions columns
**Status:** PENDING
```
[Paste query 1.2 results here]
```

### 2.3 attempts columns
**Status:** PENDING
```
[Paste query 1.3 results here]
```

### 2.4 answers columns
**Status:** PENDING
```
[Paste query 1.4 results here]
```

### 2.5 results columns
**Status:** PENDING
```
[Paste query 1.5 results here]
```

### 2.6 ai_reports columns
**Status:** PENDING
```
[Paste query 1.6 results here]
```

### 2.7 test_syllabus columns
**Status:** PENDING
```
[Paste query 1.7 results here]
```

### 2.8 subjects columns
**Status:** PENDING
```
[Paste query 1.8 results here]
```

### 2.9 syllabus_nodes columns
**Status:** PENDING
```
[Paste query 1.9 results here]
```

### 2.10 Constraints
**Status:** PENDING
```
[Paste query 1.12-1.16 results here]
```

### 2.11 Indexes
**Status:** PENDING
```
[Paste query 1.17 results here]
```

---

## 3. Live Enums

### 3.1 test_status
**Status:** PENDING
```
[Paste query 2.1 results here]
```

### 3.2 attempt_status
**Status:** PENDING
```
[Paste query 2.2 results here]
```

### 3.3 question_type
**Status:** PENDING
```
[Paste query 2.3 results here]
```

### 3.4 difficulty_level
**Status:** PENDING
```
[Paste query 2.4 results here]
```

### 3.5 question_status
**Status:** PENDING
```
[Paste query 2.5 results here]
```

### 3.6 All enums
**Status:** PENDING
```
[Paste query 2.7 results here]
```

---

## 4. Live RLS

### 4.1 RLS Status
**Status:** PENDING
```
[Paste query 3.1 results here]
```

### 4.2 All Policies
**Status:** PENDING
```
[Paste query 3.2 results here]
```

---

## 5. Live Privileges

**Status:** PENDING
```
[Paste queries 4.1-4.5 results here]
```

---

## 6. Live Functions

### 6.1 Target Function Existence
**Status:** PENDING
```
[Paste query 5.1 results here]
```

### 6.2 All Public Functions
**Status:** PENDING
```
[Paste query 5.2 results here]
```

### 6.3 Execute Privileges
**Status:** PENDING
```
[Paste query 5.3 results here]
```

---

## 7. Live Function Definitions

### 7.1 _fn_start_attempt_core
**Status:** PENDING
```
[Paste query 6.1 results here]
```

### 7.2 rpc_start_attempt
**Status:** PENDING
```
[Paste query 6.2 results here]
```

### 7.3 rpc_start_attempt_by_code
**Status:** PENDING
```
[Paste query 6.3 results here]
```

### 7.4 rpc_save_answers
**Status:** PENDING
```
[Paste query 6.4 results here]
```

### 7.5 rpc_submit_attempt
**Status:** PENDING
```
[Paste query 6.5 results here]
```

### 7.6 fn_score_attempt
**Status:** PENDING
```
[Paste query 6.6 results here]
```

### 7.7 fn_can_access_test
**Status:** PENDING
```
[Paste query 6.7 results here]
```

### 7.8 get_test_questions_safe
**Status:** PENDING
```
[Paste query 6.8 results here]
```

### 7.9 questions_safe view
**Status:** PENDING
```
[Paste query 6.12 results here]
```

---

## 8. Attempt Number Audit

### 8.1 Unique Constraint
**Status:** PENDING
```
[Paste query 7.1 results here]
```

### 8.2 Attempt Number Distribution
**Status:** PENDING
```
[Paste query 7.3 results here]
```

### 8.3 Multiple Attempts Per Test
**Status:** PENDING
```
[Paste query 7.4 results here]
```

**Analysis:**
- Is attempt_number explicitly calculated in `_fn_start_attempt_core`?
- What value is inserted for attempt_number?
- Does the function read COUNT of existing attempts?

---

## 9. Max Attempts Audit

### 9.1 max_attempts Distribution
**Status:** PENDING
```
[Paste query 8.1 results here]
```

**Analysis:**
- Is max_attempts read by `_fn_start_attempt_core`?
- Is it enforced anywhere?

---

## 10. Test Lifecycle Audit

### 10.1 Test Statuses in Use
**Status:** PENDING
```
[Paste query 9.1 results here]
```

**Contradictions to Check:**
- Does `_fn_start_attempt_core` reference statuses not in the enum?
- What statuses does the function check?

---

## 11. Attempt Lifecycle Audit

### 11.1 Attempt Statuses in Use
**Status:** PENDING
```
[Paste query 10.1 results here]
```

**Contradictions to Check:**
- Does the function reference 'active' status? (not in enum)
- Does the function reference 'auto_submitted' status? (not in enum)
- Does the function reference 'scored' status? (not in enum)

---

## 12. Answers Audit

**Status:** PENDING
```
[Paste query 1.4 results here]
```

**Key Questions:**
- Is the column `selected_option_id` or `selected_option`?
- Does `text_answer` exist?
- Does `is_marked_for_review` exist?
- Does `is_answered` exist?

---

## 13. Questions Security Audit

**Status:** PENDING

**Key Questions:**
- Can authenticated student obtain correct answer pre-submission?
- Does `questions_safe` strip `is_correct`?
- Does `get_test_questions_safe` use `questions_safe`?
- Is there a post-submission correctness endpoint?

---

## 14. Results Audit

### 14.1 Results Columns
**Status:** PENDING
```
[Paste query 1.5 results here]
```

**Key Questions:**
- Does `subject_breakdown` column exist?
- Does `topic_breakdown` column exist?
- Does `accuracy` column exist?
- Does `score` column exist?
- Does `max_score` column exist?
- Does `rank` column exist?
- Does `computed_at` exist or only `generated_at`?
- Does `difficulty_breakdown` exist?

---

## 15. Scoring Audit

### 15.1 fn_score_attempt Source
**Status:** PENDING
```
[Paste query 6.6 results here]
```

**Key Questions:**
- Does it create result row?
- Does it populate subject_breakdown?
- Does it populate topic_breakdown?
- Does it calculate accuracy?
- Does it calculate score/max_score?
- Does it use correct_option from questions?
- Does it calculate negative marking?

---

## 16. Submission Flow

**Status:** PENDING

**Trace:**
```
Flutter: AnswerService.saveAnswers()
  → rpc_save_answers [EXISTS? Y/N]

Flutter: AttemptService.submitAttempt()
  → rpc_submit_attempt [EXISTS? Y/N]
  → fn_score_attempt [EXISTS? Y/N]
  → Returns Result JSONB [ACTUAL SHAPE: ?]
```

---

## 17. Post-Submission Review Audit

**Status:** PENDING

**Search Results:**
```
[Paste query 13.1 results here]
```

**Key Questions:**
- Does any function/view provide per-question correctness?
- Is there a `rpc_get_question_review` or similar?
- Can correct_option be revealed safely after submission?

---

## 18. Migration vs Live Diff

| Object | Migration Says | Live DB Says | Difference |
|--------|---------------|-------------|------------|
| tests.duration_minutes | duration_minutes (R4.1) | PENDING | |
| tests.start_at | start_at (R4.1) | PENDING | |
| tests.end_at | end_at (R4.1) | PENDING | |
| tests.duration_sec | Referenced in RPC | PENDING | |
| tests.marks_per_question | Referenced in RPC | PENDING | |
| tests.test_mode | Referenced in RPC | PENDING | |
| tests.access_code | Referenced in RPC | PENDING | |
| tests.join_code | Referenced in RPC | PENDING | |
| tests.is_soft_deleted | Referenced in RPC | PENDING | |
| tests.allow_late_join | Referenced in RPC | PENDING | |
| tests.max_participants | Referenced in RPC | PENDING | |
| tests.config | Referenced in RPC | PENDING | |
| tests.settings | Referenced in RPC | PENDING | |
| tests.max_attempts | R4.1: default 1 | PENDING | |
| questions.question_text | R4.1: question_text | PENDING | |
| questions.question | Referenced in RPC | PENDING | |
| questions.ordinal | Referenced in RPC | PENDING | |
| questions.status | Referenced in RPC | PENDING | |
| questions.is_active | R4.1: is_active | PENDING | |
| questions.subject_id | Referenced in RPC | PENDING | |
| questions.topic_node_id | Referenced in RPC | PENDING | |
| questions.source_batch | Referenced in RPC | PENDING | |
| questions.bank_id | Referenced in RPC | PENDING | |
| attempts.deadline_at | Referenced in function | PENDING | |
| results.subject_breakdown | NOT in R4.1 | PENDING | |
| results.topic_breakdown | NOT in R4.1 | PENDING | |
| results.accuracy | NOT in R4.1 | PENDING | |
| results.score | NOT in R4.1 | PENDING | |
| results.max_score | NOT in R4.1 | PENDING | |
| results.rank | NOT in R4.1 | PENDING | |
| results.computed_at | NOT in R4.1 (has generated_at) | PENDING | |

---

## 19. Live vs Flutter Diff

| Flutter Field | Live DB Column | Status |
|---------------|---------------|--------|
| Test.durationSec | PENDING | |
| Test.marksPerQuestion | PENDING | |
| Test.testMode | PENDING | |
| Test.accessCode | PENDING | |
| Test.joinCode | PENDING | |
| Test.isSoftDeleted | PENDING | |
| Test.allowLateJoin | PENDING | |
| Test.maxParticipants | PENDING | |
| Test.maxAttempts | PENDING | |
| Question.ordinal | PENDING | |
| Question.question | PENDING | |
| Question.status | PENDING | |
| Question.subjectId | PENDING | |
| Question.topicNodeId | PENDING | |
| Question.sourceBatch | PENDING | |
| Question.bankId | PENDING | |
| Attempt.deadlineAt | PENDING | |
| Attempt.integrityEventCount | PENDING | |
| Attempt.autoSubmitThreshold | PENDING | |
| Result.score | PENDING | |
| Result.maxScore | PENDING | |
| Result.accuracy | PENDING | |
| Result.rank | PENDING | |
| Result.subjectBreakdown | PENDING | |
| Result.topicBreakdown | PENDING | |
| Result.computedAt | PENDING | |

---

## 20. Repeat Test Verdict

**Based on live evidence only:**

A. Can repeat test currently work? **PENDING**
B. If not, exactly why? **PENDING**
C. Is attempt_number the blocker? **PENDING**
D. Is max_attempts enforced? **PENDING**
E. Any other blocker? **PENDING**

---

## 21. Analytics Verdict

| Feature | Column Exists | Populated | Status |
|---------|--------------|-----------|--------|
| Subject analysis | PENDING | PENDING | PENDING |
| Topic analysis | PENDING | PENDING | PENDING |
| Difficulty analysis | PENDING | PENDING | PENDING |
| Accuracy | PENDING | PENDING | PENDING |
| Score/max_score | PENDING | PENDING | PENDING |
| Rank | PENDING | PENDING | PENDING |
| Mistake analysis | PENDING | PENDING | PENDING |

---

## 22. Security Verdict

| Area | Status |
|------|--------|
| ANSWER KEY PRE-SUBMISSION | PENDING |
| ATTEMPTS RLS | PENDING |
| ANSWERS RLS | PENDING |
| RESULTS RLS | PENDING |
| SERVER SCORING | PENDING |
| POST-SUBMISSION REVIEW | PENDING |

---

## 23. Exact Blockers

**PENDING — After live discovery execution.**

---

## 24. Recommended Next Implementation Phase

**PENDING — After live discovery execution.**

---

## VERIFICATION

DATABASE MODIFIED: NO
RLS MODIFIED: NO
RPC MODIFIED: NO
FUNCTION MODIFIED: NO
FLUTTER MODIFIED: NO
DATA MODIFIED: NO
AI CALLS: 0

**LIVE DISCOVERY STATUS: PENDING — AWAITS EXECUTION**

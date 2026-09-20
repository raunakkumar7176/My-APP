# AI-Generated Test V1 Implementation Report

**Date:** 2026-09-20  
**Scope:** "Via AI Generated" test creation flow (V1) — MCQ questions only

---

## 1. Architecture Overview

### Flow
```
Flutter App → HTTP POST → Next.js API Route → AI API (OpenAI-compatible) → Response
     ↓                                                           ↓
  Review UI ← validated questions ← validation + quota check ← AI response
     ↓
  TestCreationController → existing RPCs (create_draft, add_questions, etc.)
```

### Security Principle
**No API keys in Flutter.** All AI calls happen server-side in Next.js. The Flutter app sends the user's Supabase JWT via `Authorization: Bearer` header. The API route validates auth, permissions, and quota before calling the AI.

---

## 2. Files Created

| File | Purpose |
|------|---------|
| `My-Prepration/src/app/api/ai/generate-questions/route.ts` | Next.js POST API route — server-side AI pipeline |
| `lib/features/test/data/ai_generation_repository.dart` | Flutter HTTP client + data models |
| `lib/features/test/screens/ai_generation_screen.dart` | Flutter 3-step wizard UI (Configure → Generate → Review) |

## 3. Files Modified

| File | Changes |
|------|---------|
| `lib/features/test/widgets/question_source_step.dart` | `QuestionSource.ai` enabled (`isAvailable = true`), added `onAiQuestionsSelected` callback, `testMode`/`subject`/`topic`/`chapter`/`marksPerQuestion` params |
| `lib/features/test/screens/test_creation_screen.dart` | Wired `onAiQuestionsSelected` callback, `_handleAiQuestionsSelected()` method |
| `lib/app/app_router.dart` | Added `/tests/create/ai-generate` route accepting `AiGenerationPrefill` as extra |
| `lib/app/app_config.dart` | Added `nextApiUrl` field with static `_currentConfig` + `initialize()` |
| `lib/main.dart` | Added `AppConfig.initialize(config)` call |
| `pubspec.yaml` | Added `http: ^1.2.2` dependency |

## 4. Files Fixed (Pre-existing)

| File | Fix |
|------|-----|
| `test/group/group_test_results_test.dart:660` | Added missing `leaderboard()` method to `_Delegating` class |

---

## 5. Next.js API Route Details

**Endpoint:** `POST /api/ai/generate-questions`

### Request Body
```json
{
  "subject": "Mathematics",
  "topic": "Algebra",
  "chapter": "Class 12",
  "questionCount": 10,
  "difficulty": "mixed",
  "difficultyDistribution": { "easy": 3, "medium": 4, "hard": 3 },
  "language": "en",
  "questionType": "mcq",
  "marksPerQuestion": 1,
  "groupId": null,
  "testMode": "self",
  "sourceText": null,
  "title": "Algebra Test"
}
```

### Response
```json
{
  "questions": [
    {
      "id": "ai_1695000000000_0",
      "question": "...",
      "options": ["A", "B", "C", "D"],
      "correct_option": 0,
      "explanation": "...",
      "subject": "Mathematics",
      "topic": "Algebra",
      "difficulty": "medium",
      "language": "en",
      "_status": "VALID",
      "_confidence": 0.92
    }
  ],
  "summary": { "requested": 10, "generated": 10, "valid": 8, "needsReview": 2, "invalid": 0 },
  "quota": { "usedToday": 1, "remaining": 2, "limit": 3, "canGenerate": true },
  "cacheHit": false,
  "tokensIn": 1200,
  "tokensOut": 3400,
  "model": "gpt-5.6-luna",
  "promptVersion": "AI_QUESTION_PROMPT_V1"
}
```

### Validation (Server-side)
- Question count: 1–30
- Language: `en`, `hi`, `hinglish`
- Difficulty: `easy`, `medium`, `hard`, `mixed`
- Question type: MCQ only (V1)
- Each question validated: 4 options, valid correct_answer (A-D), question length ≥ 10 chars
- Duplicate detection within batch (normalized text comparison)
- Status per question: `VALID`, `NEEDS_REVIEW`, `INVALID`
- Confidence score: 0.2–0.92

---

## 6. AI Pipeline (Reused from Existing)

- **Gateway:** `https://api.experientiallabs.ai/v1` (OpenAI-compatible)
- **Model:** `gpt-5.6-luna`
- **Prompt builder:** `buildQuestionPrompt()` from `src/lib/ai/gemini.ts`
- **Schema:** `questionBatchSchema` (Zod validation)
- **Prompt versioning:** `AI_QUESTION_PROMPT_V1` — change version to invalidate cache

---

## 7. Quota & Caching

- **Daily limit:** `DAILY_AI_GENERATIONS_LIMIT` (default 3/day)
- **Cache key:** version + subject + topic + difficulty + language + count + source hash
- **Idempotency:** `buildIdempotencyKey(userId, cacheKey)` — prevents duplicate in-flight requests
- **Cache TTL:** stored in `ai_response_cache` table, checked on each request
- **Job tracking:** `ai_jobs` table — status: processing → completed/failed

---

## 8. Review Flow (Flutter)

### Steps
1. **Configure:** Subject (dropdown + custom), topic, chapter, count (1–30), difficulty (mixed/easy/medium/hard), language (en/hi/hinglish), marks
2. **Generate:** Loading spinner, calls API, handles errors
3. **Review:** Question cards with:
   - Status badge (VALID/NEEDS_REVIEW/INVALID)
   - Confidence percentage
   - Difficulty label
   - Options with correct answer highlighted
   - Explanation
   - Action buttons: Approve, Reject, Move Up/Down, Delete
   - Approve All button

### Auto-approval
- VALID questions are auto-approved on generation
- NEEDS_REVIEW and INVALID are left for manual review

### Completion
- Returns `AiGenerationComplete` with approved `QuestionDraft` list and difficulty distribution
- These are appended to `localQuestions` in `TestCreationController` via the existing callback

---

## 9. Permissions

### Checked Server-side (API Route)
| Permission | When |
|------------|------|
| `CREATE_TEST` | Group mode tests (`testMode == "group"`) |

### Checked Client-side
- User must be authenticated (JWT in Supabase session)
- Group membership verified via `group_members` table query

### Not checked (V1 — acceptable)
- `GENERATE_QUESTIONS` — not enforced server-side for AI generation (quota serves as rate limiter)
- `REVIEW_QUESTIONS` — review happens client-side before test creation

---

## 10. Answer Key Security

- **Server-side:** Correct answer returned as `correct_option` (0-indexed) in the API response
- **Client-side:** Options shown with correct answer highlighted during review only
- **At creation:** `QuestionDraft.correctOptionIndex` stored in local state, submitted via existing `create_question_draft` RPC
- **During test:** Answer options shuffled client-side; correct answer sent in encrypted payload

**V1 limitation:** The AI response is sent over HTTPS. The correct answer is visible in the HTTP response body during the generation call. This is acceptable for V1 since:
1. The user is the test creator (trusted)
2. HTTPS prevents network interception
3. No answer key is published until the creator explicitly publishes the test

---

## 11. Token/Cost Controls

- **Max questions per request:** 30 (enforced both client and server)
- **Daily limit:** 3 generations/day (configurable via `DAILY_AI_GENERATIONS_LIMIT`)
- **Source material:** Max 500KB input, truncated to 9000 chars, sanitized (no HTML, no API keys)
- **Cache:** Repeated identical requests use cached results (no new AI tokens)
- **Prompt version:** Changing `AI_QUESTION_PROMPT_V1` invalidates all cached responses

---

## 12. Analyze Results

```
flutter analyze (changed files):
  0 errors, 0 warnings, 2 info-level hints (prefer_const_constructors, curly braces)
```

---

## 13. Test Results

```
flutter test test/features/test/:
  65/65 passed ✓

flutter test test/group/group_test_results_test.dart:
  23/23 passed ✓ (after fixing missing leaderboard() method)
```

### Pre-existing Test Fix
`test/group/group_test_results_test.dart` — `_Delegating` class was missing the `leaderboard()` method required by `ResultRepository`. Added delegation to `inner.leaderboard(testId)`.

---

## 14. Known Limitations (V1)

| Limitation | Impact | Future Fix |
|------------|--------|------------|
| MCQ only | True/False, Short Answer, Numeric not supported | Extend prompt + validation |
| No source material upload | Text only; no PDF/image processing | Add file upload + OCR |
| No answer key export | Can't download answer key as PDF/CSV | Add export feature |
| No question bank storage | AI questions exist only in the draft | Add `ai_generated_questions` table |
| No AI model selection | Hardcoded to `gpt-5.6-luna` | Add model picker |
| No question editing | Can approve/reject but not edit text inline | Add inline editor |
| 3/day quota | May be too restrictive for power users | Tiered quotas by role |

---

## 15. OWNER APPLY REQUIRED Items

| Item | Location | Description |
|------|----------|-------------|
| `NEXT_API_URL` dart-define | `lib/app/app_config.dart:4` | Must be set at build time: `flutter build apk --dart-define=NEXT_API_URL=https://my-prepration.vercel.app` |
| `.env` variable | `My-Prepration/.env.local` | Ensure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are set |
| Quota limit | `My-Prepration/src/lib/ai/gemini.ts` | `DAILY_AI_GENERATIONS_LIMIT` — adjust if needed |
| Prompt version | `My-Prepration/src/app/api/ai/generate-questions/route.ts:22` | `AI_QUESTION_PROMPT_V1` — increment to invalidate cache after prompt changes |

---

## 16. Git Commit

```bash
git add -A
git commit -m "feat(test): implement via ai generated v1

- Next.js server-side API route for AI question generation
- Flutter AI generation repository (HTTP client)
- Flutter AI generation screen (3-step wizard)
- Wire AI source into test creation flow
- Add AppConfig.nextApiUrl for server-side API calls
- Fix pre-existing test (missing leaderboard method)
```

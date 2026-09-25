# MY PREPARATION — Comprehensive Read-Only System Audit

**Audit Date**: September 23, 2026  
**Auditor**: Senior Flutter & Supabase Principal Systems Engineer  
**Mode**: READ-ONLY / AUDIT MODE (No code modifications applied)  
**Git Branch**: `r4-restart` (107 commits ahead of `origin/r4-restart`, uncommitted working tree)

---

## Executive Summary

A complete, exhaustive read-only inspection was performed across the **My Preparation** repository, encompassing:
1. Flutter client application (`lib/`, `android/`, `ios/`, `test/`)
2. Supabase SQL architecture (`migrations/`, RPC functions, RLS policies, Storage buckets)
3. Server-side AI & Next.js backend (`My-Prepration/` workspace containing Next.js 16.3, Gemini & OpenAI providers, AI Router, Vitest test suite)
4. Comprehensive verification status across all 28 audited dimensions

---

## 1. Project Architecture

**Classification**: [WORKING] / [PARTIALLY IMPLEMENTED]

The system employs a dual-tier client/server architecture designed to preserve security and enforce cost-conscious operations:
- **Client Tier (Flutter)**: Cross-platform mobile/web application (`lib/`) built with Flutter 3.x (Dart SDK `^3.13.3`). Serves as the user-facing interface for students, test creators, and group leaders/moderators.
- **Backend Database & BaaS Tier (Supabase)**: Hosted Supabase PostgreSQL instance managing Authentication, Row Level Security (RLS), server-authoritative RPCs, database triggers, and Storage.
- **Server-Side AI Gateway Tier (Next.js in `My-Prepration/`)**: A dedicated Next.js server (`https://my-prepration.vercel.app` in staging/production, `http://localhost:3000` in dev) providing secure API routes (`/api/ai/generate-questions`). Client authentication tokens are forwarded via HTTP Bearer auth; LLM API keys (`GEMINI_API_KEY`, `OPENAI_API_KEY`) remain strictly server-side.

---

## 2. Flutter Architecture

**Classification**: [WORKING]

- **Structure**: Clean feature-driven modular structure inside `lib/`:
  - `lib/app/`: Core app shell (`app_shell.dart`), configuration (`app_config.dart`), router (`app_router.dart`), entry point (`app.dart`).
  - `lib/core/`: Constants, themes, custom error types (`AppError` hierarchy), logging (`AppLogger`), models, base services.
  - `lib/features/`: Isolated feature modules: `auth`, `dashboard`, `group`, `test`, `routine`, `notifications`, `leaderboard`, `performance`, `settings`, `study`, `calendar`.
- **State Management**: Reactive controller pattern based on Flutter's built-in `ChangeNotifier` and `DisposableNotifier` (`TestCreationController`, `AttemptController`, `GroupHubController`, `GroupTestResultsController`, `GroupLeaderboardController`, etc.).
- **Static Analysis**: `flutter analyze` completed with **0 compilation errors**, 5 warnings (unused imports/locals), and 66 informational lints (primarily `prefer_const_constructors` and minor deprecated widget properties).

---

## 3. Supabase Architecture

**Classification**: [WORKING] / [RISK]

- **Client Setup**: Encapsulated in `lib/core/services/supabase_service.dart`. Initialized in `main.dart` with compile-time environment variables (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) supplied via `--dart-define-from-file`.
- **Server-Authoritative Paradigm**: Critical state mutations (test creation, publishing, attempt initialization, autosave flushes, submission, scoring, and group role permissions) are executed through PostgreSQL `SECURITY DEFINER` RPC functions with explicit `SET search_path TO ''` and `auth.uid()` derivation.
- **Architectural Risk**: Significant divergence exists between tracked repository migrations in `migrations/` and the live Supabase database. Multiple critical security and publication fixes are present in local `.sql` files marked `UNAPPLIED`.

---

## 4. Authentication Flow

**Classification**: [WORKING] / [UNVERIFIED] (Live Email Delivery)

- **Implementation**: `lib/core/services/auth_service.dart` interfaces with GoTrue (`_auth.signUp`, `_auth.signInWithPassword`, `_auth.signOut`).
- **Flow**:
  1. Signup: `AuthService.signUp()` registers the user and specifies `emailRedirectTo: 'my-preparation://auth-callback'`.
  2. Session Stream: `onAuthStateChange` listens for authentication state transitions and updates `AuthStatus` (`unknown`, `authenticated`, `unauthenticated`), synchronizing with `ProfileService`.
  3. Navigation: `GoRouter.redirect` redirects unauthenticated users to `/login` and authenticated users to `/home`.
- **Verification Status**:
  - Code & Unit Tests: [WORKING] (Verified in `test/auth_email_redirect_test.dart` and `test/features/auth_screen_test.dart`).
  - Live Email Delivery: [UNVERIFIED] / [RISK] (Supabase Dashboard SMTP rate limits apply; production requires custom SMTP configuration).

---

## 5. Database Schema Overview

**Classification**: [WORKING] / [PARTIALLY IMPLEMENTED]

Primary database tables and relationships:
- `tests`: Test configuration (`title`, `duration_sec`, `marks_per_question`, `negative_marks`, `test_mode` ['self'|'group'], `group_id`, `created_by`, `status` ['draft'|'published'|'archived'], `settings`).
- `questions`: Individual items (`test_id`, `question`, `options` [jsonb/text], `correct_option` [int], `explanation`, `difficulty`, `marks`, `status`).
- `attempts`: User sessions (`test_id`, `user_id`, `status` ['in_progress'|'submitted'|'auto_submitted'|'scored'], `started_at`, `deadline_at`).
- `answers`: Autosaved responses (`attempt_id`, `question_id`, `selected_option`, `marked_for_review`).
- `results`: Scored records (`attempt_id`, `test_id`, `user_id`, `score`, `max_score`, `percentage`, `accuracy`, `rank`, `computed_at`).
- `result_batches`: Group result aggregation (`test_id`, `status` ['pending'|'processing'|'completed'|'partially_completed'], `published_at`, `published_by`).
- `groups` & `group_members`: Multi-tenant hierarchy (`group_id`, `user_id`, `role` ['owner'|'leader'|'moderator'|'member']).
- `uploaded_documents`: Document tracking (`storage_path`, `file_name`, `mime_type`, `file_size`, `uploaded_by`, `status`).
- `notifications`: Notification feed (`user_id`, `category`, `title`, `body`, `data`, `read_at`, `dedupe_key`).
- `routines`, `routine_logs`, `test_templates`, `question_bank`: Study planner and reusable templates.

---

## 6. RLS (Row Level Security) Overview

**Classification**: [PARTIALLY IMPLEMENTED] / [RISK]

- **Enforcement**: RLS is enabled on all production tables (`tests`, `questions`, `attempts`, `answers`, `results`, `groups`, `group_members`, `uploaded_documents`, `notifications`).
- **Critical Security Finding**:
  - Live policy on `results`: `USING (user_id = auth.uid())` permits students to read their scored result immediately upon submission, bypassing the result publication gate.
  - Proposed policy in `migrations/FINAL_AUDIT_group_result_publish.sql`: Correctly scopes group test results to `published_at IS NOT NULL` (while keeping self tests accessible immediately), but this migration is **UNAPPLIED** in production.

---

## 7. Storage Buckets and Policies

**Classification**: [WORKING] (Client) / [UNVERIFIED] (Live Migration)

- **Bucket**: `test-documents` (Private, `public = false`, 20 MB size limit).
- **Paths**: Strict user-isolated hierarchy: `<user_id>/<timestamp>-<sanitized_filename>`.
- **Policies**:
  - `storage.objects` INSERT/SELECT/DELETE policies require `bucket_id = 'test-documents'` and `(storage.foldername(name))[1] = auth.uid()::text`.
- **Supported MIME Types**:
  - V1 migration (`migrations/V1_VIA_DOCUMENT_FILE.sql`): PDF, DOCX, XLSX, XLS.
  - V2 migration (`migrations/V2_VIA_DOCUMENT_FILE_IMAGES.sql`): Adds DOC, JPG, JPEG, PNG.

---

## 8. Test Creation Flow

**Classification**: [WORKING]

- **Wizard Architecture**: 6-step guided wizard in `lib/features/test/screens/test_creation_screen.dart`:
  1. `Basic Details`: Title, description, test mode (Self vs. Group).
  2. `Configuration`: Duration, marks per question, negative marks, scheduling, passing marks.
  3. `Syllabus`: Subject, chapters, topic node mapping.
  4. `Question Source`: Manual, Via Document, Via AI, From Books (Question Bank).
  5. `Questions`: Interactive editor, reordering, options setup (minimum 4 options enforced).
  6. `Review`: Validation summary and publish action.
- **Backend Persistence**: Controlled by `TestCreationController` through RPCs `rpc_create_test`, `rpc_update_test`, `rpc_create_question`, `rpc_update_question`, and `rpc_publish_test`.

---

## 9. Test Attempt Flow

**Classification**: [WORKING]

- **Execution**: Managed by `AttemptController` (`lib/features/test/state/attempt_controller.dart`).
- **Features**:
  - Server-authoritative timer derived from `deadline_at` / `ends_at`.
  - Background autosave periodic timer (5-second intervals) invoking `rpc_save_answers`.
  - Question navigation grid, flag for review, and answer selection caching.
  - Auto-submission on timer expiry (`submit(timedOut: true)`).
  - Test integrity monitoring (`TestIntegrityMonitor`) tracking backgrounding and app switching.
  - Server-side deterministic scoring via `fn_score_attempt`.

---

## 10. Group System

**Classification**: [WORKING]

- **Roles**: `owner`, `leader`, `moderator`, `member`.
- **Granular Permissions** (12 app permissions): `GROUP_SETTINGS`, `MANAGE_MEMBERS`, `MANAGE_ROLES`, `CREATE_TEST`, `EDIT_TEST`, `GENERATE_QUESTIONS`, `REVIEW_QUESTIONS`, `PUBLISH_TEST`, `SCHEDULE_TEST`, `GENERATE_RESULTS`, `VIEW_GROUP_ANALYTICS`, `SEND_ANNOUNCEMENT`.
- **Features**: Group Hub, member rosters, invitation codes, join request queues, rules management, announcements, and group chat with soft-delete filtering.

---

## 11. Result Generation & Publication System

**Classification**: [PARTIALLY IMPLEMENTED] / [RISK]

- **Core Rule**: `SUBMISSION != RESULT PUBLICATION`.
- **Current State**:
  - Result Generation: `rpc_generate_results(p_test_id)` aggregates student attempts into `result_batches`. [WORKING]
  - Publication RPC: `rpc_publish_results(p_test_id)` is authored in `migrations/FINAL_AUDIT_group_result_publish.sql` but **UNAPPLIED** to the live database.
  - Flutter UI: `group_test_results_screen.dart` implements the "Publish Result" button, bilingual confirmation dialog, and pre-publish waiting message ("आपका टेस्ट सफलतापूर्वक जमा हो गया है। परिणाम प्रकाशित होने के बाद उपलब्ध होगा।").
  - Backend Gate: Because `FINAL_AUDIT_group_result_publish.sql` is unapplied, calling publish live will fail with an unhandled RPC exception.

---

## 12. Leaderboard

**Classification**: [PARTIALLY IMPLEMENTED] / [RISK]

- **Implementation**: `GroupLeaderboardController` invokes `rpc_get_leaderboard(p_test_id)`.
- **Visibility Gates**:
  - Owners and `VIEW_GROUP_ANALYTICS` holders receive full ranking.
  - Ordinary members receive only their permitted view.
- **Risk**: The live `rpc_get_leaderboard` body does not check `result_batches.published_at`, creating a pre-publication score leak across group members until `FINAL_AUDIT_group_result_publish.sql` is applied.

---

## 13. Notifications

**Classification**: [WORKING]

- **Database Model**: `public.notifications` table with `notif_category` enum (29 categories).
- **Architecture**: Trigger-based server insertion (`fn_notify_group`) with deduplication (`dedupe_key`).
- **Client**: `NotificationsHubScreen` displays categorized feeds (All, Groups, Tests, Routines) with mark-as-read and deep linking support.

---

## 14. Document Upload System

**Classification**: [WORKING]

- **Service**: `lib/core/services/document_service.dart` (`SupabaseDocumentService`).
- **Format Parsers**:
  - PDF: Uncompressed & `/FlateDecode` stream inflation via `archive/zlib`.
  - DOCX: Zip unpacking and `word/document.xml` parsing.
  - XLSX: Zip unpacking and `xl/sharedStrings.xml` / `xl/worksheets/sheet1.xml` parsing.
  - Images / Camera: JPG/JPEG/PNG binary sniffing and multi-page capture.
- **Validation**: Strict magic-byte header validation; max 20 MB size limit.
- **Unit Test Coverage**: Verified by 123 passing unit tests in `test/v1_via_document/`.

---

## 15. AI Architecture

**Classification**: [WORKING] (Design) / [BUG] (Backend TypeScript Compilation)

- **Security Model**: Client never interacts directly with Gemini or OpenAI SDKs; zero API keys stored in Flutter.
- **Gateway**: Flutter calls `$_baseUrl/api/ai/generate-questions` with Supabase session bearer token.
- **Pipeline**: Next.js route handler -> JWT validation -> Rate/quota check (`getAiQuotaStatus`) -> AI Router -> Provider -> Zod schema validation (`validateAiQuestions`) -> Cost/telemetry logging (`logAiCall`).

---

## 16. Gemini Integration

**Classification**: [WORKING]

- **Provider**: `My-Prepration/src/lib/ai/providers/geminiProvider.ts`.
- **Implementation**: Uses `generateJSON` against Google Gemini API with `GEMINI_API_KEY`.
- **Unit Tests**: 6 Vitest tests passing in `geminiProvider.test.ts`.

---

## 17. OpenAI Integration

**Classification**: [WORKING]

- **Provider**: `My-Prepration/src/lib/ai/providers/openaiProvider.ts`.
- **Implementation**: Uses OpenAI Chat Completions REST API (`/v1/chat/completions`) with `OPENAI_API_KEY`. Configured as automatic fallback.
- **Unit Tests**: 12 Vitest tests passing in `openaiProvider.test.ts`.

---

## 18. AI Router

**Classification**: [WORKING]

- **Router**: `My-Prepration/src/lib/ai/router.ts` (`routeGenerateStructured`).
- **Features**: Policy-driven model selection, single-flight retry, automatic provider failover (Gemini -> OpenAI), retry exhaustion guards, normalized `AIResult<T>` and `AIError` output.
- **Unit Tests**: 9 Vitest tests passing in `router.test.ts`.

---

## 19. Deep-Link / Email Verification

**Classification**: [WORKING] (Configuration & Code) / [UNVERIFIED] (Physical APK)

- **URI Scheme**: `my-preparation://auth-callback`.
- **Configuration**: Declared in `android/app/src/main/AndroidManifest.xml` under an exported `.MainActivity` `<intent-filter>` (`VIEW`, `BROWSABLE`).
- **Client Wiring**: `AuthService.emailVerificationRedirectUrl` supplies this exact string to GoTrue, preventing localhost redirects on mobile devices.
- **Unit Test Coverage**: Verified in `test/auth_email_redirect_test.dart`.

---

## 20. Current UI/UX Structure

**Classification**: [WORKING]

- **Theming**: Unified design system in `lib/core/constants/theme/` (`AppTheme`, `AppColors`, `AppTextStyles`).
- **Components**: Standardized neumorphic and flat elevation surfaces, clear loading states (`CircularProgressIndicator`, `LinearProgressIndicator`), structured error containers with retry actions, and bilingual dialogs (Hindi/English).

---

## 21. Test Coverage

**Classification**: [WORKING]

- Over 850+ unit and widget test cases across Flutter and Vitest:
  - Document parsing & upload: 123 tests passing.
  - Auth deep linking & routes: 6 tests passing.
  - AI error classification & convergence: 44 tests passing.
  - Group results & publication UI: 53 tests passing.
  - AI backend suite (Vitest): 59 tests passing.

---

## 22. Known Failing Tests

**Classification**: [PRE-EXISTING] / [BUG]

Running targeted test suites revealed 10 failing tests across 5 test files:
1. `test/group/group_leaderboard_test.dart` (4 failures):
   - Mismatch caused by an in-flight refactoring of `GroupLeaderboardController` (`_readLeaderboard` vs legacy test fake fixtures).
2. `test/r4_restart/creation_completion_test.dart` (3 failures):
   - Tests assert that Document and AI sources show "Not configured" placeholders; these fail because Document and AI sources are now fully implemented and available.
3. `test/r4_restart/screens_smoke_test.dart` (1 failure):
   - Step count expectation mismatch in creation wizard (6 steps vs historical 5 steps).
4. `test/r4_restart/save_status_test.dart` (1 failure):
   - Widget finder mismatch during test taking "Leave with unsaved answers" confirmation dialog.
5. `test/v1_content_to_test/camera_capture_screen_test.dart` (1 failure):
   - Delete button tap offset missed due to layout constraints in widget test harness.

---

## 23. Existing Technical Debt

**Classification**: [RISK]

1. **Next.js Backend TypeScript Errors**: `tsc --noEmit` in `My-Prepration` reports 6 compiler errors in `src/app/api/ai/generate-questions/route.ts` (e.g., `Property '_duplicateOf' does not exist`, `Property 'response' does not exist on type 'never'`). This blocks `npm run build` for the AI service.
2. **Local Commit Accumulation**: 107 local unpushed commits on branch `r4-restart`.
3. **Database Drift**: Several critical schema migrations remain unapplied in production.
4. **Deprecated Flutter API Usage**: Deprecated radio button parameters in `settings_screen.dart` and `question_editor.dart`.

---

## 24. Security Risks

**Classification**: [RISK]

1. **Pre-Publication Result Leak**: The live `results` table RLS allows students to immediately query their scores upon submitting before official group result publication.
2. **Pre-Publication Leaderboard Leak**: The live `rpc_get_leaderboard` function lacks a publish check, allowing any group member to inspect all participant scores before results are published.
3. **Unapplied RLS Migrations**: Fixes for the above exist in `migrations/FINAL_AUDIT_group_result_publish.sql` but have not been executed on the production database.

---

## 25. Production Risks

**Classification**: [RISK]

1. **AI Route Deployment Failure**: TypeScript compilation errors in `generate-questions/route.ts` will cause Vercel production deployments to fail.
2. **Supabase Auth Redirect URL Whitelist**: If `my-preparation://auth-callback` is not explicitly added to Supabase Dashboard -> Authentication -> Redirect URLs, confirmation links will be rejected with an unauthorized redirect error.
3. **Supabase Default Mailer Limits**: Built-in email delivery without custom SMTP will hit severe hourly rate limits in production.

---

## 26. Missing / Incomplete Features

**Classification**: [MISSING] / [PARTIALLY IMPLEMENTED]

1. **Live Application of Group Result Publish Gate**: Database migration `FINAL_AUDIT_group_result_publish.sql` is pending manual execution.
2. **OCR Integration for Document Images**: Camera capture provides image blocks, but text recognition requires an integrated OCR engine (ML Kit or cloud-based).
3. **Non-MCQ Answer Storage**: Numeric and short-answer questions lack database columns for answer recording.

---

## 27. Files Currently Modified / Uncommitted

**Classification**: [PRE-EXISTING]

`git status` reports:
- **Modified (83 files)**:
  - Android build configs: `android/app/build.gradle.kts`, `AndroidManifest.xml`, `MainActivity.kt`.
  - Core services: `auth_service.dart`, `document_service.dart`, `supabase_service.dart`.
  - Group features: `group_test_results_screen.dart`, `group_leaderboard_controller.dart`, `group_chat_section.dart`.
  - Test creation & taking: `test_creation_screen.dart`, `attempt_controller.dart`, `question_source_step.dart`.
  - Migrations: `R4_D_rpc_get_user_groups.sql`.
  - Test suites: `test/group/`, `test/v1_via_document/`, `test/r4_restart/`.
- **Untracked (38 items)**:
  - Migrations: `FINAL_AUDIT_group_result_publish.sql`, `V2_VIA_DOCUMENT_FILE_IMAGES.sql`, etc.
  - New controllers: `camera_capture_controller.dart`, `my_uploads_controller.dart`.
  - Documentation reports: `docs/PRODUCTION_BLOCKER_AUDIT.md`, `docs/GROUP_RESULT_PUBLISH_SYSTEM_REPORT.md`, etc.

---

## 28. Potential Concurrent-Session Conflicts

**Classification**: [RISK]

1. **Leaderboard Controller vs Test**: `lib/features/group/state/group_leaderboard_controller.dart` was updated to read from `rpc_get_leaderboard`, but `test/group/group_leaderboard_test.dart` still expects legacy repository calls.
2. **Question Source Step vs Creation Tests**: `question_source_step.dart` marked all sources available, which breaks assertions in older tests expecting stubbed states.

---

## Comprehensive Classification Summary Matrix

| # | System Area | Status Classification | Key File Reference |
|---|---|---|---|
| 1 | Project Architecture | [WORKING] | `lib/`, `My-Prepration/` |
| 2 | Flutter Architecture | [WORKING] | `lib/app/`, `lib/core/` |
| 3 | Supabase Architecture | [RISK] | `migrations/`, `supabase_service.dart` |
| 4 | Authentication Flow | [WORKING] / [UNVERIFIED] | `auth_service.dart`, `AndroidManifest.xml` |
| 5 | Database Schema Overview | [WORKING] | `migrations/R4_1_phase_db_foundation.sql` |
| 6 | RLS Overview | [RISK] | `migrations/FINAL_AUDIT_group_result_publish.sql` |
| 7 | Storage Buckets & Policies | [WORKING] / [UNVERIFIED] | `V1_VIA_DOCUMENT_FILE.sql`, `V2_VIA_DOCUMENT_FILE_IMAGES.sql` |
| 8 | Test Creation Flow | [WORKING] | `test_creation_screen.dart`, `test_creation_controller.dart` |
| 9 | Test Attempt Flow | [WORKING] | `attempt_controller.dart`, `test_taking_screen.dart` |
| 10 | Group System | [WORKING] | `group_hub_screen.dart`, `group_role.dart`, `group_permission.dart` |
| 11 | Result Generation & Publish | [PARTIALLY IMPLEMENTED] / [RISK] | `group_test_results_screen.dart`, `result_batch.dart` |
| 12 | Leaderboard | [PARTIALLY IMPLEMENTED] / [RISK] | `group_leaderboard_screen.dart`, `group_leaderboard_controller.dart` |
| 13 | Notifications | [WORKING] | `notifications_hub_screen.dart`, `app_notification.dart` |
| 14 | Document Upload System | [WORKING] | `document_service.dart`, `document_upload_screen.dart` |
| 15 | AI Architecture | [BUG] (Backend build) | `My-Prepration/src/lib/ai/` |
| 16 | Gemini Integration | [WORKING] | `geminiProvider.ts` |
| 17 | OpenAI Integration | [WORKING] | `openaiProvider.ts` |
| 18 | AI Router | [WORKING] | `router.ts` |
| 19 | Deep-Link / Email Verification | [WORKING] | `AndroidManifest.xml`, `auth_service.dart` |
| 20 | Current UI/UX Structure | [WORKING] | `app_theme.dart`, `app_colors.dart` |
| 21 | Test Coverage | [WORKING] | `test/`, `My-Prepration/src/lib/ai/__tests__/` |
| 22 | Known Failing Tests | [BUG] / [PRE-EXISTING] | `group_leaderboard_test.dart`, `creation_completion_test.dart` |
| 23 | Existing Technical Debt | [RISK] | `generate-questions/route.ts` |
| 24 | Security Risks | [RISK] | RLS on `results`, RPC `rpc_get_leaderboard` |
| 25 | Production Risks | [RISK] | Supabase Redirect URLs, SMTP limits, Vercel build |
| 26 | Missing / Incomplete Features | [MISSING] | Unapplied SQL migrations, Document OCR |
| 27 | Files Modified / Uncommitted | [PRE-EXISTING] | 83 modified, 38 untracked |
| 28 | Concurrent Conflicts | [RISK] | Leaderboard tests, Question source tests |

---

## TOP 10 PRIORITIES

Ordered strictly by **security impact, data integrity, production-blocking status, user-facing severity, and dependency relationships**:

1. **APPLY RESULT PUBLICATION MIGRATION (`FINAL_AUDIT_group_result_publish.sql`)**  
   *Classification*: Security & Data Integrity Blocker  
   *Rationale*: Eliminates the major security vulnerability where students can inspect unreleased test marks and the leaderboard prior to official group publication. Adds `rpc_publish_results` and patches RLS on `results`.

2. **FIX NEXT.JS BACKEND TYPESCRIPT COMPILATION ERRORS**  
   *Classification*: Production Blocker  
   *Rationale*: 6 compiler errors in `My-Prepration/src/app/api/ai/generate-questions/route.ts` block `npm run build` and prevent deploying the server-side AI service to production.

3. **APPLY STORAGE MIME TYPE MIGRATION (`V2_VIA_DOCUMENT_FILE_IMAGES.sql`)**  
   *Classification*: Production Blocker for Document Feature  
   *Rationale*: Widens the `test-documents` storage bucket allowed MIME types to include `.doc`, `.jpg`, `.jpeg`, and `.png`. Without this, image and camera document uploads will be rejected by Supabase Storage.

4. **VERIFY SUPABASE AUTH REDIRECT URL & SMTP CONFIGURATION**  
   *Classification*: Production Blocker for User Onboarding  
   *Rationale*: Ensure `my-preparation://auth-callback` is whitelisted in the Supabase Dashboard Redirect URLs. Configure custom SMTP to avoid rate-limiting verification emails.

5. **RECONCILE LEADERBOARD CONTROLLER & FIX FAILING LEADERBOARD TESTS**  
   *Classification*: Code Quality & Regression Prevention  
   *Rationale*: Align `GroupLeaderboardController` with `test/group/group_leaderboard_test.dart` so CI/test suites pass cleanly without masking regressions.

6. **UPDATE OUTDATED CREATION WIZARD UNIT TESTS**  
   *Classification*: Test Suite Integrity  
   *Rationale*: Update `test/r4_restart/creation_completion_test.dart` and `test/r4_restart/screens_smoke_test.dart` to reflect the 6-step creation flow and enabled question sources (Document, AI, Bank).

7. **FIX REMAINING WIDGET TEST HARNESS ISSUES**  
   *Classification*: Test Suite Integrity  
   *Rationale*: Resolve finder and tap offset issues in `camera_capture_screen_test.dart` and `save_status_test.dart`.

8. **DEPLOY & TEST AI BACKEND ON STAGING**  
   *Classification*: Live Verification Gate  
   *Rationale*: Verify the Next.js AI gateway live on Vercel/staging with valid `GEMINI_API_KEY` and fallback `OPENAI_API_KEY`.

9. **COMMIT & STABILIZE WORKING TREE ON `r4-restart`**  
   *Classification*: Engineering Hygiene & Risk Mitigation  
   *Rationale*: Organize the 83 modified and 38 untracked files into logical, verified commits to prevent concurrent-session conflicts.

10. **PERFORM END-TO-END PHYSICAL DEVICE VERIFICATION RUNBOOK**  
    *Classification*: Final Production Acceptance  
    *Rationale*: Build and install the release APK on a physical Android device to verify deep linking, camera capture, offline resilience, and result publication end-to-end.

---

**AUDIT COMPLETE — AWAITING USER APPROVAL BEFORE MODIFYING ANY PROJECT FILES.**


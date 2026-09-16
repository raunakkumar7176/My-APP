# R4.5.2 — Test Creation Write Service Layer

## Status: PASS

## Summary

Implemented Flutter service layer methods connecting to the 8 verified R4.5.1 RPCs for test creation write workflow. All methods follow existing project conventions: static methods, `p_*` named parameters, `AppError` hierarchy, `AppLogger` logging, and Supabase error mapping.

## Files Modified

| File | Change |
|------|--------|
| `lib/core/services/test_service.dart` | Added `createTest`, `updateTest`, `publishTest`, `addTestSyllabus`, `removeTestSyllabus` + `@visibleForTesting` param builders |
| `lib/core/services/question_service.dart` | Added `createQuestion`, `updateQuestion`, `deleteQuestion`, `getQuestionById` + `@visibleForTesting` param builders + `questionTypeToRpc` |
| `lib/core/services/supabase_service.dart` | Added `@visibleForTesting setClientForTesting` for test injection |
| `lib/core/models/question.dart` | Extended `_parseQuestionType` to handle live RPC values (`mcq`, `tf`, `num`, `short`) |
| `test/r4_5_2_service_test.dart` | **NEW** — 38 unit tests for param builders, type conversion, error mapping, correct_option exclusion |
| `test/widget_test.dart` | Recreated model tests (Subject, SyllabusNode, Question, Test, TestSyllabus) |
| `pubspec.yaml` | No dependency changes (mocktail was added then removed; not needed) |

## RPC Mapping

| Dart Method | RPC Name | Required Params |
|-------------|----------|-----------------|
| `TestService.createTest` | `rpc_create_test` | `p_title` |
| `TestService.updateTest` | `rpc_update_test` | `p_test_id` |
| `TestService.publishTest` | `rpc_publish_test` | `p_test_id` |
| `TestService.addTestSyllabus` | `rpc_add_test_syllabus` | `p_test_id`, `p_syllabus_node_id` |
| `TestService.removeTestSyllabus` | `rpc_remove_test_syllabus` | `p_test_id`, `p_syllabus_node_id` |
| `QuestionService.createQuestion` | `rpc_create_question` | `p_test_id`, `p_question` |
| `QuestionService.updateQuestion` | `rpc_update_question` | `p_question_id` |
| `QuestionService.deleteQuestion` | `rpc_delete_question` | `p_question_id` |

## QuestionType Mapping (Model → RPC)

| Model Enum | RPC Text |
|------------|----------|
| `mcqSingle` | `mcq` |
| `mcqMultiple` | `mcq` |
| `trueFalse` | `tf` |
| `integer` | `num` |
| `shortAnswer` | `short` |

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test` | 50/50 passed |
| `flutter build apk --debug` | Success (`app-debug.apk` built) |

## Test Coverage (38 tests in `r4_5_2_service_test.dart`)

- **Param builders**: createTest (3), updateTest (2), publishTest (1), addTestSyllabus (2), removeTestSyllabus (1)
- **QuestionType conversion**: mcqSingle, mcqMultiple, trueFalse, integer, shortAnswer, null, unknown (7)
- **Question param builders**: createQuestion (7), updateQuestion (2), deleteQuestion (1)
- **Error mapping**: TestService (4), QuestionService (4)
- **correct_option exclusion**: 2 tests verifying it's absent from `toJson()` and model parsing handles live RPC values

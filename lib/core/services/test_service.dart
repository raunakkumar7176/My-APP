import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/test.dart';
import '../models/test_syllabus.dart';
import 'supabase_service.dart';

final class TestService {
  TestService._();

  static SupabaseQueryBuilder get _db => SupabaseService.client.from('tests');

  // ─── READ ────────────────────────────────────────────────

  static Future<Test?> getTestById(String testId) async {
    try {
      final response = await _db
          .select()
          .eq('id', testId)
          .eq('is_soft_deleted', false)
          .maybeSingle();

      if (response == null) return null;
      return Test.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.error('getTestById PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getTestById unexpected error: $e');
      throw const DataError(message: 'Failed to load test. Please try again.');
    }
  }

  static Future<List<Test>> getAccessibleTests({
    String? subjectId,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    AppLogger.info(
        'getAccessibleTests: userId=${userId ?? "NULL"}, subjectId=$subjectId, status=$status, limit=$limit, offset=$offset');
    try {
      var query = _db.select().eq('is_soft_deleted', false);

      if (subjectId != null) {
        query = query.eq('subject_id', subjectId);
      }
      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (response as List<dynamic>)
          .map((json) => Test.fromJson(json as Map<String, dynamic>))
          .toList();
      AppLogger.info('getAccessibleTests: returned ${list.length} rows');
      return list;
    } on PostgrestException catch (e) {
      AppLogger.error(
          'getAccessibleTests PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e, st) {
      if (e is AppError) rethrow;
      AppLogger.error(
          'getAccessibleTests unexpected error: runtimeType=${e.runtimeType}, error=$e',
          stackTrace: st);
      throw const DataError(message: 'Failed to load tests. Please try again.');
    }
  }

  static Future<List<Test>> getMyDrafts({
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    AppLogger.info(
        'getMyDrafts: userId=${userId ?? "NULL"}, limit=$limit, offset=$offset');
    if (userId == null) {
      AppLogger.error('getMyDrafts: currentUser is NULL — not authenticated');
      throw const AuthError(message: 'You must be logged in to view drafts.');
    }

    try {
      AppLogger.info('getMyDrafts: querying tests WHERE is_soft_deleted=false, status=draft, created_by=$userId');
      final response = await _db
          .select()
          .eq('is_soft_deleted', false)
          .eq('status', 'draft')
          .eq('created_by', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (response as List<dynamic>)
          .map((json) => Test.fromJson(json as Map<String, dynamic>))
          .toList();
      AppLogger.info('getMyDrafts: returned ${list.length} rows');
      for (var i = 0; i < list.length; i++) {
        final t = list[i];
        AppLogger.info(
            'getMyDrafts: row[$i] id=${t.id}, title=${t.title}, status=${t.status.name}, group_id=${t.groupId}, created_by=${t.createdBy}, updated_at=${t.updatedAt}');
      }
      return list;
    } on PostgrestException catch (e) {
      AppLogger.error(
          'getMyDrafts PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e, st) {
      if (e is AppError) rethrow;
      AppLogger.error(
          'getMyDrafts unexpected error: runtimeType=${e.runtimeType}, error=$e',
          stackTrace: st);
      throw const DataError(message: 'Failed to load drafts. Please try again.');
    }
  }

  // ─── CREATE ──────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildCreateTestParams({
    required String title,
    String? description,
    int? durationSec,
    double? marksPerQuestion,
    double? negativeMarks,
    String? testMode,
    String? creationMethod,
    String? groupId,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxParticipants,
    bool? allowLateJoin,
    Map<String, dynamic>? config,
    Map<String, dynamic>? settings,
    String? accessCode,
    String? joinCode,
  }) {
    final params = <String, dynamic>{
      'p_title': title,
    };
    if (description != null) params['p_description'] = description;
    if (durationSec != null) params['p_duration_sec'] = durationSec;
    if (marksPerQuestion != null) {
      params['p_marks_per_question'] = marksPerQuestion;
    }
    if (negativeMarks != null) params['p_negative_marks'] = negativeMarks;
    if (testMode != null) params['p_test_mode'] = testMode;
    if (creationMethod != null) params['p_creation_method'] = creationMethod;
    if (groupId != null) params['p_group_id'] = groupId;
    if (startsAt != null) params['p_starts_at'] = startsAt.toIso8601String();
    if (endsAt != null) params['p_ends_at'] = endsAt.toIso8601String();
    if (maxParticipants != null) {
      params['p_max_participants'] = maxParticipants;
    }
    if (allowLateJoin != null) params['p_allow_late_join'] = allowLateJoin;
    if (config != null) params['p_config'] = config;
    if (settings != null) params['p_settings'] = settings;
    if (accessCode != null) params['p_access_code'] = accessCode;
    if (joinCode != null) params['p_join_code'] = joinCode;
    return params;
  }

  static Future<Test> createTest({
    required String title,
    String? description,
    int? durationSec,
    double? marksPerQuestion,
    double? negativeMarks,
    String? testMode,
    String? creationMethod,
    String? groupId,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxParticipants,
    bool? allowLateJoin,
    Map<String, dynamic>? config,
    Map<String, dynamic>? settings,
    String? accessCode,
    String? joinCode,
  }) async {
    try {
      final params = buildCreateTestParams(
        title: title,
        description: description,
        durationSec: durationSec,
        marksPerQuestion: marksPerQuestion,
        negativeMarks: negativeMarks,
        testMode: testMode,
        creationMethod: creationMethod,
        groupId: groupId,
        startsAt: startsAt,
        endsAt: endsAt,
        maxParticipants: maxParticipants,
        allowLateJoin: allowLateJoin,
        config: config,
        settings: settings,
        accessCode: accessCode,
        joinCode: joinCode,
      );

      AppLogger.info('createTest: calling rpc_create_test');
      final response = await SupabaseService.client
          .rpc('rpc_create_test', params: params);

      final data = response as Map<String, dynamic>;
      final testId = data['test_id'] as String;
      AppLogger.info('createTest: created test $testId');

      final test = await getTestById(testId);
      if (test == null) {
        throw const DataError(
            message: 'Test created but failed to load. Please refresh.');
      }
      return test;
    } on PostgrestException catch (e) {
      AppLogger.error('createTest PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('createTest unexpected error: $e');
      throw const DataError(message: 'Failed to create test. Please try again.');
    }
  }

  // ─── UPDATE ──────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildUpdateTestParams({
    required String testId,
    String? title,
    String? description,
    int? durationSec,
    double? marksPerQuestion,
    double? negativeMarks,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxParticipants,
    bool? allowLateJoin,
    Map<String, dynamic>? config,
    Map<String, dynamic>? settings,
    String? accessCode,
    String? joinCode,
  }) {
    final params = <String, dynamic>{
      'p_test_id': testId,
    };
    if (title != null) params['p_title'] = title;
    if (description != null) params['p_description'] = description;
    if (durationSec != null) params['p_duration_sec'] = durationSec;
    if (marksPerQuestion != null) {
      params['p_marks_per_question'] = marksPerQuestion;
    }
    if (negativeMarks != null) params['p_negative_marks'] = negativeMarks;
    if (startsAt != null) params['p_starts_at'] = startsAt.toIso8601String();
    if (endsAt != null) params['p_ends_at'] = endsAt.toIso8601String();
    if (maxParticipants != null) {
      params['p_max_participants'] = maxParticipants;
    }
    if (allowLateJoin != null) params['p_allow_late_join'] = allowLateJoin;
    if (config != null) params['p_config'] = config;
    if (settings != null) params['p_settings'] = settings;
    if (accessCode != null) params['p_access_code'] = accessCode;
    if (joinCode != null) params['p_join_code'] = joinCode;
    return params;
  }

  static Future<Test> updateTest({
    required String testId,
    String? title,
    String? description,
    int? durationSec,
    double? marksPerQuestion,
    double? negativeMarks,
    DateTime? startsAt,
    DateTime? endsAt,
    int? maxParticipants,
    bool? allowLateJoin,
    Map<String, dynamic>? config,
    Map<String, dynamic>? settings,
    String? accessCode,
    String? joinCode,
  }) async {
    try {
      final params = buildUpdateTestParams(
        testId: testId,
        title: title,
        description: description,
        durationSec: durationSec,
        marksPerQuestion: marksPerQuestion,
        negativeMarks: negativeMarks,
        startsAt: startsAt,
        endsAt: endsAt,
        maxParticipants: maxParticipants,
        allowLateJoin: allowLateJoin,
        config: config,
        settings: settings,
        accessCode: accessCode,
        joinCode: joinCode,
      );

      AppLogger.info('updateTest: calling rpc_update_test for $testId');
      await SupabaseService.client
          .rpc('rpc_update_test', params: params);

      final test = await getTestById(testId);
      if (test == null) {
        throw const DataError(
            message: 'Test updated but failed to load. Please refresh.');
      }
      return test;
    } on PostgrestException catch (e) {
      AppLogger.error('updateTest PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('updateTest unexpected error: $e');
      throw const DataError(message: 'Failed to update test. Please try again.');
    }
  }

  // ─── PUBLISH ─────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildPublishTestParams(String testId) {
    return {'p_test_id': testId};
  }

  static Future<Test> publishTest(String testId) async {
    try {
      AppLogger.info('publishTest: calling rpc_publish_test for $testId');
      await SupabaseService.client
          .rpc('rpc_publish_test', params: buildPublishTestParams(testId));

      final test = await getTestById(testId);
      if (test == null) {
        throw const DataError(
            message: 'Test published but failed to load. Please refresh.');
      }
      return test;
    } on PostgrestException catch (e) {
      AppLogger.error('publishTest PostgrestException: ${e.message}');
      // Publish-specific mapping: the generic mapper turned server validation
      // messages (e.g. "at least one approved question") into
      // "Something went wrong", hiding the real cause from the user.
      throw DataError(message: mapPublishError(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('publishTest unexpected error: $e');
      throw const DataError(message: 'Failed to publish test. Please try again.');
    }
  }

  // ─── SYLLABUS ────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildAddTestSyllabusParams({
    required String testId,
    required String syllabusNodeId,
    List<String>? materialIds,
  }) {
    final params = <String, dynamic>{
      'p_test_id': testId,
      'p_syllabus_node_id': syllabusNodeId,
    };
    if (materialIds != null) params['p_material_ids'] = materialIds;
    return params;
  }

  static Future<TestSyllabus> addTestSyllabus({
    required String testId,
    required String syllabusNodeId,
    List<String>? materialIds,
  }) async {
    try {
      final params = buildAddTestSyllabusParams(
        testId: testId,
        syllabusNodeId: syllabusNodeId,
        materialIds: materialIds,
      );

      AppLogger.info('addTestSyllabus: calling rpc_add_test_syllabus');
      final response = await SupabaseService.client
          .rpc('rpc_add_test_syllabus', params: params);

      final data = response as Map<String, dynamic>;
      AppLogger.info(
          'addTestSyllabus: added syllabus node $syllabusNodeId to test $testId');

      return TestSyllabus(
        id: '',
        testId: data['test_id'] as String? ?? testId,
        syllabusNodeId: data['syllabus_node_id'] as String? ?? syllabusNodeId,
        materialIds: materialIds,
        createdAt: DateTime.now(),
      );
    } on PostgrestException catch (e) {
      AppLogger.error('addTestSyllabus PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('addTestSyllabus unexpected error: $e');
      throw const DataError(
          message: 'Failed to add syllabus. Please try again.');
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildRemoveTestSyllabusParams({
    required String testId,
    required String syllabusNodeId,
  }) {
    return {
      'p_test_id': testId,
      'p_syllabus_node_id': syllabusNodeId,
    };
  }

  static Future<void> removeTestSyllabus({
    required String testId,
    required String syllabusNodeId,
  }) async {
    try {
      AppLogger.info('removeTestSyllabus: calling rpc_remove_test_syllabus');
      await SupabaseService.client.rpc(
          'rpc_remove_test_syllabus',
          params: buildRemoveTestSyllabusParams(
            testId: testId,
            syllabusNodeId: syllabusNodeId,
          ));
      AppLogger.info(
          'removeTestSyllabus: removed syllabus node $syllabusNodeId from test $testId');
    } on PostgrestException catch (e) {
      AppLogger.error('removeTestSyllabus PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('removeTestSyllabus unexpected error: $e');
      throw const DataError(
          message: 'Failed to remove syllabus. Please try again.');
    }
  }

  // ─── READ SYLLABUS ──────────────────────────────────────

  static Future<List<TestSyllabus>> getTestSyllabus(String testId) async {
    try {
      final response = await SupabaseService.client
          .from('test_syllabus')
          .select()
          .eq('test_id', testId);

      return (response as List<dynamic>)
          .map((json) => TestSyllabus.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getTestSyllabus PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getTestSyllabus unexpected error: $e');
      throw const DataError(
          message: 'Failed to load test syllabus. Please try again.');
    }
  }

  // ─── DELETE (soft) ───────────────────────────────────────

  static Future<void> deleteTest(String testId) async {
    try {
      AppLogger.info('deleteTest: soft-deleting test $testId');
      await _db.update({
        'is_soft_deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', testId);
      AppLogger.info('deleteTest: deleted test $testId');
    } on PostgrestException catch (e) {
      AppLogger.error('deleteTest PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('deleteTest unexpected error: $e');
      throw const DataError(message: 'Failed to delete test. Please try again.');
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────

  @visibleForTesting
  static String mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to perform this action.';
    }
    if (lower.contains('row-level security') || lower.contains('rls')) {
      return 'You do not have permission to view these tests.';
    }
    if (lower.contains('not found')) {
      return 'Test not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  static String _mapErrorMessage(String message) => mapErrorMessage(message);

  static String mapPublishError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to publish this test.';
    }
    // Live rpc_publish_test message: "Test must have at least one approved
    // question to publish". A draft can have questions that are all still
    // pending review, so do not tell the user to add questions.
    if (lower.contains('no approved question') ||
        lower.contains('at least one approved')) {
      return 'Approve all questions before publishing '
          '(Edit Test → Review → Approve).';
    }
    if (lower.contains('no questions')) {
      return 'Add at least one question before publishing.';
    }
    if (lower.contains('invalid test') || lower.contains('configuration')) {
      return 'Fix the test configuration before publishing.';
    }
    if (lower.contains('group') && lower.contains('select')) {
      return 'Select a group for Group Test mode.';
    }
    if (lower.contains('duration') || lower.contains('timing')) {
      return 'Enter a valid duration for the test.';
    }
    if (lower.contains('duplicate') || lower.contains('ordinal')) {
      return 'Fix duplicate question numbers before publishing.';
    }
    if (lower.contains('syllabus') || lower.contains('node')) {
      return 'Fix syllabus references before publishing.';
    }
    if (lower.contains('not found')) {
      return 'Test not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('session') || lower.contains('unauthorized') || lower.contains('auth')) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Failed to publish test. Please try again.';
  }

  static String mapStartAttemptError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You cannot access this test.';
    }
    if (lower.contains('not started') || lower.contains('has not started')) {
      return 'This test has not started yet.';
    }
    if (lower.contains('ended') || lower.contains('expired') || lower.contains('closed')) {
      return 'This test has ended.';
    }
    if (lower.contains('cancelled')) {
      return 'This test has been cancelled.';
    }
    if (lower.contains('already') && lower.contains('attempt')) {
      return 'You already have an active attempt for this test.';
    }
    if (lower.contains('max') && lower.contains('participant')) {
      return 'This test has reached its maximum number of participants.';
    }
    if (lower.contains('not found')) {
      return 'Test not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('session') || lower.contains('unauthorized') || lower.contains('auth')) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Failed to start test. Please try again.';
  }
}

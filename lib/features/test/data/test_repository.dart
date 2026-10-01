import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../../../core/models/test_syllabus.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Values the creation flow persists for a test. `testMode`/`settings` are
/// produced by `BackendMapping` — never hand-written here.
class TestWriteInput {
  const TestWriteInput({
    required this.title,
    this.description,
    this.durationSec,
    this.marksPerQuestion,
    this.negativeMarks,
    this.testMode,
    this.groupId,
    this.startsAt,
    this.endsAt,
    this.maxParticipants,
    this.allowLateJoin,
    this.settings,
    this.config,
    this.accessCode,
    this.joinCode,
    this.creationMethod = 'manual',
  });

  final String title;
  final String? description;
  final int? durationSec;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final String? testMode;
  final String? groupId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxParticipants;
  final bool? allowLateJoin;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? config;
  final String? accessCode;
  final String? joinCode;

  /// The creation method for this test: 'manual', 'upload', 'ai', or 'mixed'.
  final String creationMethod;

  /// `rpc_create_test` params (`p_test_mode` etc.). Null fields are omitted so
  /// server defaults apply.
  Map<String, dynamic> toCreateParams() => {
    'p_title': title,
    if (description != null) 'p_description': description,
    if (durationSec != null) 'p_duration_sec': durationSec,
    if (marksPerQuestion != null) 'p_marks_per_question': marksPerQuestion,
    if (negativeMarks != null) 'p_negative_marks': negativeMarks,
    if (testMode != null) 'p_test_mode': testMode,
    'p_creation_method': creationMethod,
    if (groupId != null) 'p_group_id': groupId,
    if (startsAt != null) 'p_starts_at': startsAt!.toUtc().toIso8601String(),
    if (endsAt != null) 'p_ends_at': endsAt!.toUtc().toIso8601String(),
    if (maxParticipants != null) 'p_max_participants': maxParticipants,
    if (allowLateJoin != null) 'p_allow_late_join': allowLateJoin,
    if (config != null) 'p_config': config,
    if (settings != null) 'p_settings': settings,
    if (accessCode != null) 'p_access_code': accessCode,
    if (joinCode != null) 'p_join_code': joinCode,
  };

  /// `rpc_update_test` params. Mode and group cannot change after creation
  /// (the RPC has no such params).
  Map<String, dynamic> toUpdateParams(String testId) => {
    'p_test_id': testId,
    'p_title': title,
    if (description != null) 'p_description': description,
    if (durationSec != null) 'p_duration_sec': durationSec,
    if (marksPerQuestion != null) 'p_marks_per_question': marksPerQuestion,
    if (negativeMarks != null) 'p_negative_marks': negativeMarks,
    if (startsAt != null) 'p_starts_at': startsAt!.toUtc().toIso8601String(),
    if (endsAt != null) 'p_ends_at': endsAt!.toUtc().toIso8601String(),
    if (maxParticipants != null) 'p_max_participants': maxParticipants,
    if (allowLateJoin != null) 'p_allow_late_join': allowLateJoin,
    if (config != null) 'p_config': config,
    if (settings != null) 'p_settings': settings,
    if (accessCode != null) 'p_access_code': accessCode,
    if (joinCode != null) 'p_join_code': joinCode,
  };
}

abstract interface class TestRepository {
  Future<Test?> getById(String testId);

  /// Tests visible to the current user under RLS (server decides
  /// visibility); categorisation happens in the domain.
  Future<List<Test>> listAccessible({int limit = 100});

  Future<List<Test>> listMyDrafts({int limit = 50});

  /// Test ids the caller has at least one completed (submitted/
  /// auto_submitted/scored) attempt for — used to also surface a
  /// still-reattemptable test under the "Previous" listing tab as attempt
  /// history, without removing it from "Upcoming" (it's still startable).
  Future<Set<String>> myAttemptedTestIds();

  /// Non-deleted tests assigned to [groupId], newest first. RLS limits
  /// visibility to group members; the server enforces this.
  Future<List<Test>> listByGroup(String groupId, {int limit = 100});

  /// `rpc_create_test` returns only `test_id`, so the created row is read
  /// once here (the single read-after-write in the test system).
  Future<Test> create(TestWriteInput input);

  Future<void> update(String testId, TestWriteInput input);

  Future<void> publish(String testId);

  /// `rpc_set_test_shuffle_questions(p_test_id, p_shuffle)` — the only
  /// writer of the `tests.shuffle_questions` COLUMN (draft-only on the
  /// server). Callers must not treat a failure as fatal: the attempt engine
  /// also reads the `settings.shuffle_questions` mirror, so the feature
  /// still works while this RPC is unavailable.
  Future<void> setShuffleQuestions(String testId, bool shuffle);

  /// Draft-only soft delete via `rpc_delete_test` (creator, status = draft,
  /// not already deleted — all enforced by the server). Nothing is
  /// physically removed.
  Future<void> deleteDraft(String testId, {String? reason});

  Future<List<TestSyllabus>> syllabusFor(String testId);

  Future<void> addSyllabus(String testId, String nodeId);

  Future<void> removeSyllabus(String testId, String nodeId);

  // ── Group test management (G10) ──

  /// One group's tests, newest first, finite. Soft-deleted rows are NOT
  /// filtered client-side: the live SELECT policies decide — members see
  /// non-deleted group tests (`member read tests`), the creator additionally
  /// sees their own soft-deleted/archived ones (`creator sees soft-deleted`).
  Future<List<Test>> listForGroup(String groupId, {int limit = 100});

  /// `fn_soft_delete_test(p_test, p_reason)` — live archive: creator OR
  /// (group owner OR EDIT_TEST); refused for live/scheduled; sets
  /// status = archived + is_soft_deleted, keeps attempts/answers/results.
  Future<void> archive(String testId, {String? reason});
}

class SupabaseTestRepository implements TestRepository {
  const SupabaseTestRepository();

  SupabaseClient get _client => SupabaseService.client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<Test?> getById(String testId) => _guard(() async {
    final row = await _client
        .from('tests')
        .select()
        .eq('id', testId)
        .eq('is_soft_deleted', false)
        .maybeSingle();
    return row == null ? null : Test.fromJson(row);
  }, TestErrorContext.load);

  @override
  Future<List<Test>> listAccessible({int limit = 100}) => _guard(() async {
    final rows = await _client
        .from('tests')
        .select()
        .eq('is_soft_deleted', false)
        .order('created_at', ascending: false)
        .range(0, limit - 1);
    return _rows(rows);
  }, TestErrorContext.load);

  @override
  Future<List<Test>> listMyDrafts({int limit = 50}) => _guard(() async {
    final uid = _requireUser();
    final rows = await _client
        .from('tests')
        .select()
        .eq('is_soft_deleted', false)
        .eq('status', 'draft')
        .eq('created_by', uid)
        .order('created_at', ascending: false)
        .range(0, limit - 1);
    return _rows(rows);
  }, TestErrorContext.load);

  @override
  Future<Set<String>> myAttemptedTestIds() => _guard(() async {
    final response = await _client.rpc('rpc_my_attempted_test_ids');
    AppLogger.rpcShape('rpc_my_attempted_test_ids', response);
    if (response == null) return const <String>{};
    final list = response is List ? response : [response];
    return {
      for (final r in list)
        if (r is Map && r['test_id'] != null) r['test_id'].toString(),
    };
  }, TestErrorContext.load);

  @override
  Future<List<Test>> listByGroup(String groupId, {int limit = 100}) =>
      _guard(() async {
        final rows = await _client
            .from('tests')
            .select()
            .eq('is_soft_deleted', false)
            .eq('group_id', groupId)
            .order('created_at', ascending: false)
            .range(0, limit - 1);
        return _rows(rows);
      }, TestErrorContext.load);

  @override
  Future<Test> create(TestWriteInput input) => _guard(() async {
    final response = await _client.rpc(
      'rpc_create_test',
      params: input.toCreateParams(),
    );
    AppLogger.rpcShape('rpc_create_test', response);
    final id = _idFrom(response, 'test_id');
    final test = await getById(id);
    if (test == null) {
      throw const DataError(
        message: 'Test created but could not be loaded. Please refresh.',
      );
    }
    return test;
  }, TestErrorContext.save);

  @override
  Future<void> update(String testId, TestWriteInput input) => _guard(() async {
    final response = await _client.rpc(
      'rpc_update_test',
      params: input.toUpdateParams(testId),
    );
    AppLogger.rpcShape('rpc_update_test', response);
  }, TestErrorContext.save);

  @override
  Future<void> publish(String testId) => _guard(() async {
    final response = await _client.rpc(
      'rpc_publish_test',
      params: {'p_test_id': testId},
    );
    AppLogger.rpcShape('rpc_publish_test', response);
  }, TestErrorContext.publish);

  @override
  Future<void> setShuffleQuestions(String testId, bool shuffle) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_set_test_shuffle_questions',
          params: {'p_test_id': testId, 'p_shuffle': shuffle},
        );
        AppLogger.rpcShape('rpc_set_test_shuffle_questions', response);
      }, TestErrorContext.save);

  @override
  Future<void> deleteDraft(String testId, {String? reason}) => _guard(() async {
    final response = await _client.rpc(
      'rpc_delete_test',
      params: {
        'p_test_id': testId,
        // Live: rpc_delete_test(p_test_id uuid, p_reason text DEFAULT NULL).
        if (reason != null && reason.trim().isNotEmpty)
          'p_reason': reason.trim(),
      },
    );
    AppLogger.rpcShape('rpc_delete_test', response);
    if (!deletedFromResponse(response)) {
      throw const DataError(
        message: 'The server did not confirm the deletion.',
      );
    }
  }, TestErrorContext.delete);

  /// `rpc_delete_test` returns `{test_id, deleted: true}`; anything else is
  /// not treated as success (no misleading "deleted" feedback).
  static bool deletedFromResponse(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    return data is Map && data['deleted'] == true;
  }

  @override
  Future<List<TestSyllabus>> syllabusFor(String testId) => _guard(() async {
    final rows = await _client
        .from('test_syllabus')
        .select()
        .eq('test_id', testId);
    return (rows as List)
        .map((r) => TestSyllabus.fromJson(r as Map<String, dynamic>))
        .toList();
  }, TestErrorContext.load);

  @override
  Future<void> addSyllabus(String testId, String nodeId) => _guard(() async {
    await _client.rpc(
      'rpc_add_test_syllabus',
      params: {'p_test_id': testId, 'p_syllabus_node_id': nodeId},
    );
  }, TestErrorContext.save);

  @override
  Future<void> removeSyllabus(String testId, String nodeId) => _guard(() async {
    await _client.rpc(
      'rpc_remove_test_syllabus',
      params: {'p_test_id': testId, 'p_syllabus_node_id': nodeId},
    );
  }, TestErrorContext.save);

  // ── Group test management (G10) ──

  @override
  Future<List<Test>> listForGroup(String groupId, {int limit = 100}) =>
      _guard(() async {
        final rows = await _client
            .from('tests')
            .select()
            .eq('group_id', groupId)
            .order('created_at', ascending: false)
            .range(0, limit - 1);
        AppLogger.rpcShape('tests.select(group)', rows);
        return _rows(rows);
      }, TestErrorContext.load);

  @override
  Future<void> archive(String testId, {String? reason}) => _guard(() async {
    final response = await _client.rpc(
      'fn_soft_delete_test',
      params: {
        'p_test': testId,
        'p_reason': reason == null || reason.trim().isEmpty
            ? null
            : reason.trim(),
      },
    );
    AppLogger.rpcShape('fn_soft_delete_test', response);
  }, TestErrorContext.delete);

  // ── helpers ──

  String _requireUser() {
    final uid = _userId;
    if (uid == null) {
      throw const AuthError(message: 'You must be logged in.');
    }
    return uid;
  }

  static List<Test> _rows(dynamic rows) => (rows as List)
      .map((r) => Test.fromJson(r as Map<String, dynamic>))
      .toList();

  /// Extracts an id from the jsonb an RPC returns (`{test_id: ...}`, a bare
  /// string, or a one-element list of either).
  static String _idFrom(dynamic response, String key) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is Map && data[key] is String) return data[key] as String;
    if (data is String && data.isNotEmpty) return data;
    throw const DataError(message: 'Unexpected response from server.');
  }

  static Future<T> _guard<T>(
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'TestRepository PostgrestException: code=${e.code}, '
        'message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('TestRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}

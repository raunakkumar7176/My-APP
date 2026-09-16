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

  /// `rpc_create_test` params (`p_test_mode` etc.). Null fields are omitted so
  /// server defaults apply.
  Map<String, dynamic> toCreateParams() => {
        'p_title': title,
        if (description != null) 'p_description': description,
        if (durationSec != null) 'p_duration_sec': durationSec,
        if (marksPerQuestion != null) 'p_marks_per_question': marksPerQuestion,
        if (negativeMarks != null) 'p_negative_marks': negativeMarks,
        if (testMode != null) 'p_test_mode': testMode,
        'p_creation_method': 'manual',
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

  /// `rpc_create_test` returns only `test_id`, so the created row is read
  /// once here (the single read-after-write in the test system).
  Future<Test> create(TestWriteInput input);

  Future<void> update(String testId, TestWriteInput input);

  Future<void> publish(String testId);

  Future<List<TestSyllabus>> syllabusFor(String testId);

  Future<void> addSyllabus(String testId, String nodeId);

  Future<void> removeSyllabus(String testId, String nodeId);
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
  Future<Test> create(TestWriteInput input) => _guard(() async {
        final response =
            await _client.rpc('rpc_create_test', params: input.toCreateParams());
        AppLogger.rpcShape('rpc_create_test', response);
        final id = _idFrom(response, 'test_id');
        final test = await getById(id);
        if (test == null) {
          throw const DataError(
              message: 'Test created but could not be loaded. Please refresh.');
        }
        return test;
      }, TestErrorContext.save);

  @override
  Future<void> update(String testId, TestWriteInput input) => _guard(() async {
        final response = await _client.rpc('rpc_update_test',
            params: input.toUpdateParams(testId));
        AppLogger.rpcShape('rpc_update_test', response);
      }, TestErrorContext.save);

  @override
  Future<void> publish(String testId) => _guard(() async {
        final response =
            await _client.rpc('rpc_publish_test', params: {'p_test_id': testId});
        AppLogger.rpcShape('rpc_publish_test', response);
      }, TestErrorContext.publish);

  @override
  Future<List<TestSyllabus>> syllabusFor(String testId) => _guard(() async {
        final rows =
            await _client.from('test_syllabus').select().eq('test_id', testId);
        return (rows as List)
            .map((r) => TestSyllabus.fromJson(r as Map<String, dynamic>))
            .toList();
      }, TestErrorContext.load);

  @override
  Future<void> addSyllabus(String testId, String nodeId) => _guard(() async {
        await _client.rpc('rpc_add_test_syllabus', params: {
          'p_test_id': testId,
          'p_syllabus_node_id': nodeId,
        });
      }, TestErrorContext.save);

  @override
  Future<void> removeSyllabus(String testId, String nodeId) =>
      _guard(() async {
        await _client.rpc('rpc_remove_test_syllabus', params: {
          'p_test_id': testId,
          'p_syllabus_node_id': nodeId,
        });
      }, TestErrorContext.save);

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
    final data = response is List && response.isNotEmpty ? response.first : response;
    if (data is Map && data[key] is String) return data[key] as String;
    if (data is String && data.isNotEmpty) return data;
    throw const DataError(message: 'Unexpected response from server.');
  }

  static Future<T> _guard<T>(
      Future<T> Function() body, TestErrorContext context) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('TestRepository PostgrestException: code=${e.code}, '
          'message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('TestRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test_template.dart';
import '../../../core/services/supabase_service.dart';

/// G19 — Repository for test template CRUD operations.
///
/// RLS enforces authorization server-side:
/// - Personal templates: owner-only access
/// - Group templates: member read, owner/leader with CREATE_TEST manage
abstract interface class TestTemplateRepository {
  Future<List<TestTemplate>> listMy({int limit = 50});
  Future<List<TestTemplate>> listForGroup(String groupId, {int limit = 50});
  Future<TestTemplate?> getById(String id);
  Future<TestTemplate> create(TestTemplateInput input);
  Future<void> update(String id, TestTemplateInput input);
  Future<void> delete(String id);
}

class SupabaseTestTemplateRepository implements TestTemplateRepository {
  const SupabaseTestTemplateRepository();

  SupabaseClient get _client => SupabaseService.client;
  String? get _userId => _client.auth.currentUser?.id;

  String _requireUser() {
    final uid = _userId;
    if (uid == null) {
      throw const AuthError(message: 'You must be logged in.');
    }
    return uid;
  }

  @override
  Future<List<TestTemplate>> listMy({int limit = 50}) => _guard(() async {
    final uid = _requireUser();
    final rows = await _client
        .from('test_templates')
        .select()
        .eq('created_by', uid)
        .order('created_at', ascending: false)
        .range(0, limit - 1);
    return _rows(rows);
  });

  @override
  Future<List<TestTemplate>> listForGroup(
    String groupId, {
    int limit = 50,
  }) => _guard(() async {
    final rows = await _client
        .from('test_templates')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .range(0, limit - 1);
    return _rows(rows);
  });

  @override
  Future<TestTemplate?> getById(String id) => _guard(() async {
    final rows = await _client
        .from('test_templates')
        .select()
        .eq('id', id)
        .maybeSingle();
    return rows == null ? null : TestTemplate.fromJson(rows);
  });

  @override
  Future<TestTemplate> create(TestTemplateInput input) => _guard(() async {
    final uid = _requireUser();
    final params = input.toInsertParams(uid);
    final rows = await _client
        .from('test_templates')
        .insert(params)
        .select()
        .single();
    final template = TestTemplate.fromJson(rows);
    AppLogger.rpcShape('test_templates.insert', template.id);
    return template;
  });

  @override
  Future<void> update(String id, TestTemplateInput input) => _guard(() async {
    final params = input.toUpdateParams();
    await _client.from('test_templates').update(params).eq('id', id);
    AppLogger.rpcShape('test_templates.update', id);
  });

  @override
  Future<void> delete(String id) => _guard(() async {
    await _client.from('test_templates').delete().eq('id', id);
    AppLogger.rpcShape('test_templates.delete', id);
  });

  static List<TestTemplate> _rows(dynamic rows) => (rows as List)
      .map((r) => TestTemplate.fromJson(r as Map<String, dynamic>))
      .toList();

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'TestTemplateRepository PostgrestException: code=${e.code}, '
        'message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw DataError(
        message: _mapError(e.message),
      );
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error(
        'TestTemplateRepository unexpected: $e',
        stackTrace: st,
      );
      throw DataError(
        message: _mapError(e.toString()),
      );
    }
  }

  static String _mapError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('not_authenticated') || lower.contains('jwt')) {
      return 'Your session has expired. Please log in again.';
    }
    if (lower.contains('not_authorized') ||
        lower.contains('permission') ||
        lower.contains('denied') ||
        lower.contains('row-level security')) {
      return 'You do not have permission to perform this action.';
    }
    if (lower.contains('not found') || lower.contains('template_not_found')) {
      return 'Template not found.';
    }
    if (lower.contains('duplicate') || lower.contains('unique')) {
      return 'A template with this name already exists.';
    }
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (raw.length > 10 && raw.length < 140) return raw;
    return 'Something went wrong. Please try again.';
  }
}

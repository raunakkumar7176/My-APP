import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Groups the current user belongs to (server decides membership via
/// `rpc_get_user_groups`). No create/join exists in the client yet.
abstract interface class GroupRepository {
  Future<List<Group>> myGroups();
}

class SupabaseGroupRepository implements GroupRepository {
  const SupabaseGroupRepository();

  @override
  Future<List<Group>> myGroups() async {
    try {
      final response = await SupabaseService.client.rpc('rpc_get_user_groups');
      AppLogger.rpcShape('rpc_get_user_groups', response);
      if (response == null) return const [];
      final list = response is List ? response : [response];
      return [
        for (final r in list) Group.fromJson(r as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      AppLogger.error('GroupRepository PostgrestException: ${e.message}');
      throw DataError(
          message: TestErrors.map(e.message, context: TestErrorContext.load));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('GroupRepository unexpected: $e', stackTrace: st);
      throw DataError(
          message: TestErrors.map(e.toString(), context: TestErrorContext.load));
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/app_tutorial.dart';

/// Reads from the public, read-only `app_tutorials` table (0100) —
/// content is managed server-side, never written from the client.
abstract interface class TutorialRepository {
  Future<List<AppTutorial>> all();
}

class SupabaseTutorialRepository implements TutorialRepository {
  const SupabaseTutorialRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<AppTutorial>> all() async {
    try {
      final rows = await _client
          .from('app_tutorials')
          .select()
          .eq('is_active', true)
          .order('category')
          .order('display_order');
      return (rows as List)
          .map((r) => AppTutorial.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      AppLogger.error('TutorialRepository.all failed: $e', stackTrace: st);
      return const [];
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import '../models/academic_special_day.dart';
import 'supabase_service.dart';

/// Reads `public.academic_special_days` (migration 0068). Read-only,
/// authenticated-readable reference data — failures degrade to "no special
/// day today" rather than surfacing an error, since this is a nice-to-have
/// enrichment, never a blocking dependency for the Dashboard or Calendar.
abstract final class AcademicSpecialDayService {
  static SupabaseClient get _client => SupabaseService.client;

  /// The single matching day for [day]/[month] (today, usually), via
  /// `rpc_get_daily_academic_day`. Null when there is none.
  static Future<AcademicSpecialDay?> getForDate({required int day, required int month}) async {
    try {
      final rows = await _client.rpc(
        'rpc_get_daily_academic_day',
        params: {'p_day': day, 'p_month': month},
      ) as List<dynamic>;
      if (rows.isEmpty) return null;
      return AcademicSpecialDay.fromJson(Map<String, dynamic>.from(rows.first as Map));
    } catch (e) {
      AppLogger.warning('AcademicSpecialDayService.getForDate failed: $e');
      return null;
    }
  }

  /// Every special day falling in [month] (1-12), for painting the
  /// calendar's star dots across a whole visible month in one query.
  static Future<List<AcademicSpecialDay>> getForMonth(int month) async {
    try {
      final rows = await _client
          .from('academic_special_days')
          .select()
          .eq('month', month)
          .order('day');
      return (rows as List)
          .map((r) => AcademicSpecialDay.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      AppLogger.warning('AcademicSpecialDayService.getForMonth failed: $e');
      return const [];
    }
  }
}

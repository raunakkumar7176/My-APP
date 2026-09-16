import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/syllabus_node.dart';
import 'supabase_service.dart';

final class SyllabusService {
  SyllabusService._();

  static SupabaseQueryBuilder get _db => SupabaseService.client.from('syllabus_nodes');

  static Future<List<SyllabusNode>> loadNodesForSubject(String subjectId) async {
    try {
      final response = await _db
          .select('id, subject_id, parent_id, class_level, name, created_at')
          .eq('subject_id', subjectId)
          .order('name', ascending: true);

      final nodes = (response as List<dynamic>)
          .map((json) => SyllabusNode.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${nodes.length} syllabus nodes for subject $subjectId.');
      return nodes;
    } on PostgrestException catch (e) {
      AppLogger.error('Syllabus load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Syllabus load unexpected error: $e');
      throw const DataError(message: 'Failed to load syllabus. Please try again.');
    }
  }

  static Future<List<SyllabusNode>> loadChildNodes(String parentId) async {
    try {
      final response = await _db
          .select('id, subject_id, parent_id, class_level, name, created_at')
          .eq('parent_id', parentId)
          .order('name', ascending: true);

      final nodes = (response as List<dynamic>)
          .map((json) => SyllabusNode.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${nodes.length} child nodes for parent $parentId.');
      return nodes;
    } on PostgrestException catch (e) {
      AppLogger.error('Syllabus child load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Syllabus child load unexpected error: $e');
      throw const DataError(message: 'Failed to load syllabus. Please try again.');
    }
  }

  static List<SyllabusNode> buildTree(List<SyllabusNode> allNodes) {
    return allNodes.where((node) => node.isRoot).toList();
  }

  static List<SyllabusNode> getChildren(
      List<SyllabusNode> allNodes, String parentId) {
    return allNodes.where((node) => node.parentId == parentId).toList();
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view syllabus.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load syllabus. Please try again.';
  }
}

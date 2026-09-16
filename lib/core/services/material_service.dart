import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/material_chunk.dart';
import '../models/study_material.dart';
import 'supabase_service.dart';

final class MaterialService {
  MaterialService._();

  static SupabaseQueryBuilder get _materialsDb =>
      SupabaseService.client.from('study_materials');
  static SupabaseQueryBuilder get _nodeMaterialsDb =>
      SupabaseService.client.from('node_materials');
  static SupabaseQueryBuilder get _chunksDb =>
      SupabaseService.client.from('material_chunks');

  static Future<List<StudyMaterial>> loadMaterialsForNode(String nodeId) async {
    try {
      final linksResponse = await _nodeMaterialsDb
          .select('material_id')
          .eq('node_id', nodeId);

      if (linksResponse.isEmpty) return [];

      final materialIds = (linksResponse as List<dynamic>)
          .map((link) => link['material_id'] as String)
          .toList();

      final materialsResponse = await _materialsDb
          .select('id, group_id, uploaded_by, title, storage_path, mime_type, status, created_at')
          .inFilter('id', materialIds)
          .order('created_at', ascending: false);

      final materials = (materialsResponse as List<dynamic>)
          .map((json) => StudyMaterial.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${materials.length} materials for node $nodeId.');
      return materials;
    } on PostgrestException catch (e) {
      AppLogger.error('Material load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Material load unexpected error: $e');
      throw const DataError(message: 'Failed to load materials. Please try again.');
    }
  }

  static Future<List<MaterialChunk>> loadChunksForMaterial(String materialId) async {
    try {
      final response = await _chunksDb
          .select('id, material_id, idx, content')
          .eq('material_id', materialId)
          .order('idx', ascending: true);

      final chunks = (response as List<dynamic>)
          .map((json) => MaterialChunk.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${chunks.length} chunks for material $materialId.');
      return chunks;
    } on PostgrestException catch (e) {
      AppLogger.error('Chunks load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Chunks load unexpected error: $e');
      throw const DataError(message: 'Failed to load material content. Please try again.');
    }
  }

  static String getFullContent(List<MaterialChunk> chunks) {
    final sorted = List<MaterialChunk>.from(chunks)
      ..sort((a, b) => a.idx.compareTo(b.idx));
    return sorted.map((c) => c.content).join('\n\n');
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view materials.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load materials. Please try again.';
  }
}

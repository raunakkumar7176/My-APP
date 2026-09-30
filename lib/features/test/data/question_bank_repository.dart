import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question_bank_item.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';
import '../models/question_draft.dart';

/// Repository for interacting with the `question_bank` table.
///
/// SECURITY:
/// - All reads go through RLS which enforces GENERATE_QUESTIONS or REVIEW_QUESTIONS
/// - `correct_option` is only returned for users with proper permissions
/// - Students cannot directly access the question bank (RLS enforced)
/// - This repository never bypasses RLS
abstract interface class QuestionBankRepository {
  /// Lists bank questions with server-side filtering and pagination.
  ///
  /// RLS ensures only users with GENERATE_QUESTIONS or REVIEW_QUESTIONS
  /// permission can access this data.
  Future<QuestionBankPage> list(QuestionBankFilter filter);

  /// Gets a single bank question by ID.
  ///
  /// Returns null if not found or access denied by RLS.
  Future<QuestionBankItem?> getById(String id);

  /// Gets count of available bank questions matching filters.
  ///
  /// Used by the UI to show "X available" before cloning into a test.
  Future<int> getAvailableCount({
    String? subjectName,
    String? chapter,
    String? difficulty,
    String? language,
    bool pyqOnly = false,
  });

  /// Creates a new question in the bank.
  ///
  /// Requires GENERATE_QUESTIONS or REVIEW_QUESTIONS permission (enforced by RLS).
  /// Returns the created question ID.
  Future<String> create({
    required String question,
    required List<QuestionBankOption> options,
    required int correctOption,
    String explanation = '',
    String? subjectId,
    String subjectName = '',
    String chapter = '',
    String? topicNodeId,
    String difficulty = 'medium',
    String language = 'en',
    String questionType = 'mcq',
    String source = 'manual',
  });

  /// Updates an existing bank question.
  ///
  /// Requires ownership or REVIEW_QUESTIONS permission (enforced by RLS).
  Future<void> update({
    required String id,
    String? question,
    List<QuestionBankOption>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? status,
  });

  /// Archives a bank question (sets archived_at timestamp).
  ///
  /// Requires ownership or REVIEW_QUESTIONS permission (enforced by RLS).
  Future<void> archive(String id);

  /// Restores an archived bank question (clears archived_at timestamp).
  ///
  /// Requires REVIEW_QUESTIONS permission (enforced by RLS).
  Future<void> restore(String id);

  /// Checks for duplicate questions in the bank.
  ///
  /// Returns list of potential duplicates matching the question text.
  Future<List<QuestionBankItem>> checkDuplicates(String questionText);

  /// Clones approved bank questions into a test.
  ///
  /// This is a snapshot operation - bank questions are copied into the test's
  /// questions table with bank_id set for provenance tracking.
  /// Only APPROVED bank content can be cloned (governance enforced server-side).
  ///
  /// Returns the number of questions cloned.
  Future<int> cloneToTest({
    required String testId,
    required List<String> bankIds,
    int marksPerQuestion = 1,
  });

  /// Saves drafts to question bank using `rpc_save_drafts_to_question_bank`.
  Future<QuestionBankSaveResult> saveDrafts({
    required List<QuestionDraft> drafts,
    String? subjectId,
    String? chapterId,
    String source = 'upload',
    String status = 'pending_review',
  });
}

/// Result of saving drafts into the question bank.
class QuestionBankSaveResult {
  const QuestionBankSaveResult({
    required this.total,
    required this.savedCount,
    required this.savedIds,
    required this.skippedDuplicateCount,
    required this.skippedDuplicates,
  });

  factory QuestionBankSaveResult.fromJson(Map<String, dynamic> json) {
    final rawSaved = json['saved_ids'];
    final savedIds = rawSaved is List
        ? rawSaved.map((e) => e.toString()).toList()
        : const <String>[];

    final rawSkipped = json['skipped_duplicates'];
    final skippedDuplicates = rawSkipped is List
        ? rawSkipped
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];

    return QuestionBankSaveResult(
      total: (json['total'] as num?)?.toInt() ?? 0,
      savedCount: (json['saved_count'] as num?)?.toInt() ?? 0,
      savedIds: savedIds,
      skippedDuplicateCount:
          (json['skipped_duplicate_count'] as num?)?.toInt() ?? 0,
      skippedDuplicates: skippedDuplicates,
    );
  }

  final int total;
  final int savedCount;
  final List<String> savedIds;
  final int skippedDuplicateCount;
  final List<Map<String, dynamic>> skippedDuplicates;
}

class SupabaseQuestionBankRepository implements QuestionBankRepository {
  const SupabaseQuestionBankRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<QuestionBankPage> list(QuestionBankFilter filter) => _guard(() async {
    final limit = filter.pageSize;
    final offset = filter.offset;

    // Build the query: from → select → filters → order → range
    var query = _client
        .from('question_bank')
        .select('*, profiles!question_bank_created_by_fkey(full_name)');

    // Apply filters (server-side) BEFORE order/range
    if (filter.search != null && filter.search!.trim().isNotEmpty) {
      query = query.ilike('question', '%${filter.search!.trim()}%');
    }
    if (filter.status != null && filter.status!.isNotEmpty) {
      query = query.eq('status', filter.status!);
    }
    if (filter.subjectId != null && filter.subjectId!.isNotEmpty) {
      query = query.eq('subject_id', filter.subjectId!);
    }
    if (filter.subjectName != null && filter.subjectName!.isNotEmpty) {
      query = query.ilike('subject_name', '%${filter.subjectName!.trim()}%');
    }
    if (filter.chapter != null && filter.chapter!.isNotEmpty) {
      query = query.ilike('chapter', '%${filter.chapter!.trim()}%');
    }
    if (filter.topicNodeId != null && filter.topicNodeId!.isNotEmpty) {
      query = query.eq('topic_node_id', filter.topicNodeId!);
    }
    if (filter.difficulty != null &&
        filter.difficulty!.isNotEmpty &&
        filter.difficulty != 'mixed') {
      query = query.eq('difficulty', filter.difficulty!);
    }
    if (filter.language != null && filter.language!.isNotEmpty) {
      query = query.eq('language', filter.language!);
    }
    if (filter.questionType != null && filter.questionType!.isNotEmpty) {
      query = query.eq('question_type', filter.questionType!);
    }
    if (filter.source != null && filter.source!.isNotEmpty) {
      query = query.eq('source', filter.source!);
    }
    if (filter.pyqOnly) {
      query = query.eq('is_pyq', true);
    }

    // Apply order and range for paginated data
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    // For total count, we use a separate head query with the same filters
    // We'll estimate total from the data returned (offset + items.length for
    // a simple approach). The real total is computed separately.
    final countQuery = _client.from('question_bank').select('id');

    // Apply same filters for count
    var filteredCountQuery = countQuery;
    if (filter.search != null && filter.search!.trim().isNotEmpty) {
      filteredCountQuery = filteredCountQuery.ilike(
        'question',
        '%${filter.search!.trim()}%',
      );
    }
    if (filter.status != null && filter.status!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq('status', filter.status!);
    }
    if (filter.subjectId != null && filter.subjectId!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq(
        'subject_id',
        filter.subjectId!,
      );
    }
    if (filter.subjectName != null && filter.subjectName!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.ilike(
        'subject_name',
        '%${filter.subjectName!.trim()}%',
      );
    }
    if (filter.chapter != null && filter.chapter!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.ilike(
        'chapter',
        '%${filter.chapter!.trim()}%',
      );
    }
    if (filter.topicNodeId != null && filter.topicNodeId!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq(
        'topic_node_id',
        filter.topicNodeId!,
      );
    }
    if (filter.difficulty != null &&
        filter.difficulty!.isNotEmpty &&
        filter.difficulty != 'mixed') {
      filteredCountQuery = filteredCountQuery.eq(
        'difficulty',
        filter.difficulty!,
      );
    }
    if (filter.language != null && filter.language!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq('language', filter.language!);
    }
    if (filter.questionType != null && filter.questionType!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq(
        'question_type',
        filter.questionType!,
      );
    }
    if (filter.source != null && filter.source!.isNotEmpty) {
      filteredCountQuery = filteredCountQuery.eq('source', filter.source!);
    }
    if (filter.pyqOnly) {
      filteredCountQuery = filteredCountQuery.eq('is_pyq', true);
    }

    // Execute count query (fetch all ids, count client-side)
    final countData = await filteredCountQuery;
    final total = (countData as List<dynamic>).length;

    final items = (data as List<dynamic>)
        .map((row) => QuestionBankItem.fromJson(row as Map<String, dynamic>))
        .toList();

    return QuestionBankPage(
      items: items,
      total: total,
      offset: offset,
      pageSize: limit,
    );
  }, TestErrorContext.load);

  @override
  Future<QuestionBankItem?> getById(String id) => _guard(() async {
    final data = await _client
        .from('question_bank')
        .select('*, profiles!question_bank_created_by_fkey(full_name)')
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    return QuestionBankItem.fromJson(data);
  }, TestErrorContext.load);

  @override
  Future<int> getAvailableCount({
    String? subjectName,
    String? chapter,
    String? difficulty,
    String? language,
    bool pyqOnly = false,
  }) => _guard(() async {
    // fn_bank_available has no PYQ parameter (no live signature accepts one);
    // go straight to the direct query when that filter is requested rather
    // than silently ignoring it via the RPC.
    if (!pyqOnly) {
      try {
        final response = await _client.rpc(
          'fn_bank_available',
          params: {
            'p_subject_name': subjectName ?? '',
            'p_chapter': chapter ?? '',
            'p_difficulty': difficulty ?? '',
            'p_language': language ?? '',
          },
        );
        return (response as num?)?.toInt() ?? 0;
      } catch (e) {
        AppLogger.warning(
          'fn_bank_available RPC failed, using PostgREST count: $e',
        );
      }
    }
    var query = _client
        .from('question_bank')
        .select('id')
        .eq('status', 'approved');

    if (subjectName != null && subjectName.isNotEmpty) {
      query = query.ilike('subject_name', '%${subjectName.trim()}%');
    }
    if (chapter != null && chapter.isNotEmpty) {
      query = query.ilike('chapter', '%${chapter.trim()}%');
    }
    if (difficulty != null &&
        difficulty.isNotEmpty &&
        difficulty != 'mixed') {
      query = query.eq('difficulty', difficulty);
    }
    if (language != null && language.isNotEmpty) {
      query = query.eq('language', language);
    }
    if (pyqOnly) {
      query = query.eq('is_pyq', true);
    }

    final response = await query;
    return (response as List<dynamic>).length;
  }, TestErrorContext.load);

  @override
  Future<String> create({
    required String question,
    required List<QuestionBankOption> options,
    required int correctOption,
    String explanation = '',
    String? subjectId,
    String subjectName = '',
    String chapter = '',
    String? topicNodeId,
    String difficulty = 'medium',
    String language = 'en',
    String questionType = 'mcq',
    String source = 'manual',
  }) => _guard(() async {
    final data = await _client
        .from('question_bank')
        .insert({
          'question': question,
          'options': options.map((o) => {'text': o.text}).toList(),
          'correct_option': correctOption,
          'explanation': explanation,
          'subject_id': ?subjectId,
          'subject_name': subjectName,
          'chapter': chapter,
          'topic_node_id': ?topicNodeId,
          'difficulty': difficulty,
          'language': language,
          'question_type': questionType,
          'source': source,
        })
        .select('id')
        .single();

    final id = data['id'] as String;
    AppLogger.info('Created bank question: $id');
    return id;
  }, TestErrorContext.save);

  @override
  Future<void> update({
    required String id,
    String? question,
    List<QuestionBankOption>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? status,
  }) => _guard(() async {
    final updates = <String, dynamic>{};
    if (question != null) updates['question'] = question;
    if (options != null) {
      updates['options'] = options.map((o) => {'text': o.text}).toList();
    }
    if (correctOption != null) updates['correct_option'] = correctOption;
    if (explanation != null) updates['explanation'] = explanation;
    if (subjectId != null) updates['subject_id'] = subjectId;
    if (subjectName != null) updates['subject_name'] = subjectName;
    if (chapter != null) updates['chapter'] = chapter;
    if (topicNodeId != null) updates['topic_node_id'] = topicNodeId;
    if (difficulty != null) updates['difficulty'] = difficulty;
    if (language != null) updates['language'] = language;
    if (questionType != null) updates['question_type'] = questionType;
    if (status != null) updates['status'] = status;

    if (updates.isEmpty) return;

    await _client.from('question_bank').update(updates).eq('id', id);
    AppLogger.info('Updated bank question: $id');
  }, TestErrorContext.save);

  @override
  Future<void> archive(String id) => _guard(() async {
    await _client
        .from('question_bank')
        .update({
          'archived_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'archived',
        })
        .eq('id', id);
    AppLogger.info('Archived bank question: $id');
  }, TestErrorContext.save);

  @override
  Future<void> restore(String id) => _guard(() async {
    await _client
        .from('question_bank')
        .update({'archived_at': null, 'status': 'pending_review'})
        .eq('id', id);
    AppLogger.info('Restored bank question: $id');
  }, TestErrorContext.save);

  @override
  Future<List<QuestionBankItem>> checkDuplicates(String questionText) => _guard(
    () async {
      final normalizedKey = questionText.toLowerCase().trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

      final data = await _client
          .from('question_bank')
          .select()
          .eq('duplicate_key', normalizedKey)
          .limit(10);

      return (data as List<dynamic>)
          .map((row) => QuestionBankItem.fromJson(row as Map<String, dynamic>))
          .toList();
    },
    TestErrorContext.load,
  );

  @override
  Future<int> cloneToTest({
    required String testId,
    required List<String> bankIds,
    int marksPerQuestion = 1,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_clone_bank_questions',
      params: {
        'p_test_id': testId,
        'p_bank_ids': bankIds,
        'p_marks_per_question': marksPerQuestion,
      },
    );

    AppLogger.rpcShape('rpc_clone_bank_questions', response);

    if (response is Map && response['cloned'] is num) {
      return (response['cloned'] as num).toInt();
    }

    return 0;
  }, TestErrorContext.save);

  @override
  Future<QuestionBankSaveResult> saveDrafts({
    required List<QuestionDraft> drafts,
    String? subjectId,
    String? chapterId,
    String source = 'upload',
    String status = 'pending_review',
  }) => _guard(() async {
    final payload = drafts.map((d) {
      return {
        'question': d.questionText,
        'options': d.options.map((o) => {'id': o.id, 'text': o.text}).toList(),
        'correct_option': d.correctOptionIndex ?? 0,
        'explanation': d.explanation,
        'subject_id': d.subjectId ?? subjectId,
        'chapter_id': chapterId,
        'topic_id': d.topicNodeId,
        'source': source,
      };
    }).toList();

    final response = await _client.rpc(
      'rpc_save_drafts_to_question_bank',
      params: {
        'p_drafts': payload,
        'p_subject_id': subjectId,
        'p_chapter_id': chapterId,
        'p_source': source,
        'p_status': status,
      },
    );

    AppLogger.rpcShape('rpc_save_drafts_to_question_bank', response);

    return QuestionBankSaveResult.fromJson(
      response is Map ? Map<String, dynamic>.from(response) : {},
    );
  }, TestErrorContext.save);

  static Future<T> _guard<T>(
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'QuestionBankRepository PostgrestException: ${e.message}',
      );
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('QuestionBankRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}

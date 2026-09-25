import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/content_block.dart';
import '../domain/continue_learning.dart';
import '../domain/study_chapter.dart';
import '../domain/study_question.dart';
import '../domain/study_subject.dart';
import '../domain/study_topic.dart';

/// Contract defining the Study System repository operations.
abstract interface class StudyRepository {
  /// Fetches all active study subjects with localized names and chapter counts.
  Future<List<StudySubject>> fetchSubjects({required String languageCode});

  /// Fetches all chapters belonging to [subjectId] with localization and progress.
  Future<List<StudyChapter>> fetchChapters({
    required String subjectId,
    required String languageCode,
    String? userId,
  });

  /// Fetches a single chapter by ID.
  Future<StudyChapter> fetchChapterById({
    required String chapterId,
    required String languageCode,
    String? userId,
  });

  /// Fetches all topics for [chapterId] with localization and user completion state.
  Future<List<StudyTopic>> fetchTopics({
    required String chapterId,
    required String languageCode,
    String? userId,
  });

  /// Fetches a single topic by ID.
  Future<StudyTopic> fetchTopicById({
    required String topicId,
    required String languageCode,
  });

  /// Fetches all structured content blocks for [topicId] in requested [languageCode]
  /// with automatic fallback to English if unavailable.
  Future<List<ContentBlock>> fetchContentBlocks({
    required String topicId,
    required String languageCode,
  });

  /// Toggles completion status of a topic for the authenticated user.
  Future<void> toggleTopicCompletion({
    required String topicId,
    required String chapterId,
    required String userId,
    required bool isCompleted,
  });

  /// Fetches questions for a chapter for practice/learning with pagination.
  Future<List<StudyQuestion>> fetchChapterQuestions({
    required String chapterId,
    required String languageCode,
    int limit = 20,
    int offset = 0,
  });

  /// Fetches questions for a topic for practice/learning with fallback to chapter questions.
  Future<List<StudyQuestion>> fetchTopicQuestions({
    required String topicId,
    String? chapterId,
    required String languageCode,
    int limit = 30,
    int offset = 0,
  });

  /// Retrieves the most recent study progress snapshot for the user.
  Future<ContinueLearningSnapshot?> fetchRecentStudyProgress({
    required String userId,
    required String languageCode,
  });

  /// Retrieves study progress counts (completed topics, chapters, subjects).
  Future<StudyProgressSummary> fetchStudySummary({required String userId});
}

/// Supabase implementation of [StudyRepository].
class SupabaseStudyRepository implements StudyRepository {
  const SupabaseStudyRepository({SupabaseClient? client})
    : _clientInstance = client;

  final SupabaseClient? _clientInstance;

  SupabaseClient get _client => _clientInstance ?? SupabaseService.client;

  @override
  Future<List<StudySubject>> fetchSubjects({
    required String languageCode,
  }) async {
    try {
      final response = await _client
          .from('subjects')
          .select(
            'id, name, slug, icon, order_index, is_active, status, '
            'subject_translations(language, name, description), '
            'chapters(id, is_active, status)',
          )
          .eq('is_active', true)
          .or('status.eq.published,status.is.null')
          .order('order_index', ascending: true);

      final list = (response as List<dynamic>)
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            // Count active published chapters
            if (map['chapters'] is List) {
              final chList = map['chapters'] as List;
              map['chapter_count'] = chList.where((c) {
                if (c is Map) {
                  final active = c['is_active'] as bool? ?? true;
                  final status = c['status'] as String? ?? 'published';
                  return active && status == 'published';
                }
                return true;
              }).length;
            }
            return StudySubject.fromMap(map, languageCode: languageCode);
          })
          // Filter to subjects with non-empty names
          .where((s) => s.name.trim().isNotEmpty)
          .toList();

      return list;
    } on PostgrestException catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchSubjects: ${e.message}');
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchSubjects error: $e');
      throw DataError(message: 'Failed to load study subjects: $e');
    }
  }

  @override
  Future<List<StudyChapter>> fetchChapters({
    required String subjectId,
    required String languageCode,
    String? userId,
  }) async {
    try {
      final response = await _client
          .from('chapters')
          .select(
            'id, subject_id, chapter_key, part_key, part_order_index, order_index, is_active, status, version, '
            'chapter_translations(language, title, description, part_title), '
            'topics(id)',
          )
          .eq('subject_id', subjectId)
          .eq('is_active', true)
          .eq('status', 'published')
          .order('part_order_index', ascending: true)
          .order('order_index', ascending: true);

      final rawChapters = response as List<dynamic>;

      // If user is authenticated, query progress to calculate percentage
      final completedTopicsPerChapter = <String, int>{};
      if (userId != null && userId.isNotEmpty) {
        try {
          final progressRes = await _client
              .from('user_study_progress')
              .select('chapter_id, topic_id')
              .eq('user_id', userId)
              .eq('is_completed', true);

          for (final row in progressRes as List<dynamic>) {
            final chapId = row['chapter_id'] as String?;
            if (chapId != null) {
              completedTopicsPerChapter.update(
                chapId,
                (val) => val + 1,
                ifAbsent: () => 1,
              );
            }
          }
        } catch (e) {
          AppLogger.warning(
            'Could not load user_study_progress for chapters: $e',
          );
        }
      }

      return rawChapters.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final chapId = map['id'] as String;
        final totalTopics = (map['topics'] is List)
            ? (map['topics'] as List).length
            : 0;
        final completed = completedTopicsPerChapter[chapId] ?? 0;
        final progress = totalTopics > 0
            ? ((completed / totalTopics) * 100).clamp(0.0, 100.0)
            : 0.0;
        map['progress_percentage'] = progress;

        return StudyChapter.fromMap(map, languageCode: languageCode);
      }).toList();
    } on PostgrestException catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchChapters: ${e.message}');
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchChapters error: $e');
      throw DataError(message: 'Failed to load study chapters: $e');
    }
  }

  @override
  Future<StudyChapter> fetchChapterById({
    required String chapterId,
    required String languageCode,
    String? userId,
  }) async {
    try {
      final response = await _client
          .from('chapters')
          .select(
            'id, subject_id, chapter_key, order_index, is_active, status, version, '
            'chapter_translations(language, title, description), '
            'topics(id)',
          )
          .eq('id', chapterId)
          .single();

      final map = Map<String, dynamic>.from(response);

      if (userId != null && userId.isNotEmpty) {
        try {
          final progressRes = await _client
              .from('user_study_progress')
              .select('topic_id')
              .eq('user_id', userId)
              .eq('chapter_id', chapterId)
              .eq('is_completed', true);

          final totalTopics = (map['topics'] is List)
              ? (map['topics'] as List).length
              : 0;
          final completed = (progressRes as List<dynamic>).length;
          final progress = totalTopics > 0
              ? ((completed / totalTopics) * 100).clamp(0.0, 100.0)
              : 0.0;
          map['progress_percentage'] = progress;
        } catch (_) {}
      }

      return StudyChapter.fromMap(map, languageCode: languageCode);
    } on PostgrestException catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchChapterById: ${e.message}');
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchChapterById error: $e');
      throw DataError(message: 'Failed to load chapter: $e');
    }
  }

  @override
  Future<List<StudyTopic>> fetchTopics({
    required String chapterId,
    required String languageCode,
    String? userId,
  }) async {
    try {
      final response = await _client
          .from('topics')
          .select(
            'id, chapter_id, topic_key, order_index, estimated_minutes, is_active, status, '
            'topic_translations(language, title, summary)',
          )
          .eq('chapter_id', chapterId)
          .eq('is_active', true)
          .eq('status', 'published')
          .order('order_index', ascending: true);

      final rawTopics = response as List<dynamic>;

      // Track completed topics if authenticated
      final completedTopicIds = <String>{};
      if (userId != null && userId.isNotEmpty) {
        try {
          final progressRes = await _client
              .from('user_study_progress')
              .select('topic_id')
              .eq('user_id', userId)
              .eq('chapter_id', chapterId)
              .eq('is_completed', true);

          for (final row in progressRes as List<dynamic>) {
            final tId = row['topic_id'] as String?;
            if (tId != null) completedTopicIds.add(tId);
          }
        } catch (e) {
          AppLogger.warning(
            'Could not load user_study_progress for topics: $e',
          );
        }
      }

      return rawTopics.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final topicId = map['id'] as String;
        final isCompleted = completedTopicIds.contains(topicId);
        return StudyTopic.fromMap(
          map,
          languageCode: languageCode,
          isCompleted: isCompleted,
        );
      }).toList();
    } on PostgrestException catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchTopics: ${e.message}');
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchTopics error: $e');
      throw DataError(message: 'Failed to load study topics: $e');
    }
  }

  @override
  Future<StudyTopic> fetchTopicById({
    required String topicId,
    required String languageCode,
  }) async {
    try {
      final response = await _client
          .from('topics')
          .select(
            'id, chapter_id, topic_key, order_index, estimated_minutes, is_active, status, '
            'topic_translations(language, title, summary)',
          )
          .eq('id', topicId)
          .single();

      return StudyTopic.fromMap(response, languageCode: languageCode);
    } on PostgrestException catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchTopicById: ${e.message}');
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchTopicById error: $e');
      throw DataError(message: 'Failed to load topic: $e');
    }
  }

  @override
  Future<List<ContentBlock>> fetchContentBlocks({
    required String topicId,
    required String languageCode,
  }) async {
    try {
      final res = await _client
          .from('content_blocks')
          .select('*')
          .eq('topic_id', topicId)
          .eq('is_active', true)
          .eq('status', 'published')
          .order('order_index', ascending: true);

      final allItems = (res as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      // 1. Filter by requested languageCode
      var matching = allItems
          .where((item) => item['language'] == languageCode)
          .toList();

      // 2. Fallback to English if requested language returned 0 blocks
      if (matching.isEmpty && languageCode != 'en') {
        matching = allItems.where((item) => item['language'] == 'en').toList();
      }

      // 3. Fallback to any available blocks if still empty
      if (matching.isEmpty) {
        matching = allItems;
      }

      return matching.map((item) => ContentBlock.fromMap(item)).toList();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.fetchContentBlocks: ${e.message}',
      );
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchContentBlocks error: $e');
      throw DataError(message: 'Failed to load content blocks: $e');
    }
  }

  @override
  Future<void> toggleTopicCompletion({
    required String topicId,
    required String chapterId,
    required String userId,
    required bool isCompleted,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('user_study_progress').upsert({
        'user_id': userId,
        'chapter_id': chapterId,
        'topic_id': topicId,
        'is_completed': isCompleted,
        'last_studied_at': now,
        'updated_at': now,
      }, onConflict: 'user_id, topic_id');
    } on PostgrestException catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.toggleTopicCompletion: ${e.message}',
      );
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.toggleTopicCompletion error: $e',
      );
      throw DataError(message: 'Failed to update study progress: $e');
    }
  }

  @override
  Future<List<StudyQuestion>> fetchChapterQuestions({
    required String chapterId,
    required String languageCode,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      const selectCols =
          'id, chapter_id, topic_id, question, options, correct_option, explanation, difficulty, language, status';

      // 1. Query for chapter questions matching active language
      final response = await _client
          .from('question_bank')
          .select(selectCols)
          .eq('chapter_id', chapterId)
          .eq('language', languageCode)
          .eq('status', 'approved')
          .order('created_at', ascending: true)
          .range(offset, offset + limit - 1);

      var list = response as List<dynamic>;

      // 2. Bilingual fallback: if active language returned 0 questions, check English
      if (list.isEmpty && languageCode != 'en') {
        final fallbackEn = await _client
            .from('question_bank')
            .select(selectCols)
            .eq('chapter_id', chapterId)
            .eq('language', 'en')
            .eq('status', 'approved')
            .order('created_at', ascending: true)
            .range(offset, offset + limit - 1);
        list = fallbackEn as List<dynamic>;
      }

      // 3. Fallback to any language for this chapter if still empty
      if (list.isEmpty) {
        final fallbackAny = await _client
            .from('question_bank')
            .select(selectCols)
            .eq('chapter_id', chapterId)
            .eq('status', 'approved')
            .order('created_at', ascending: true)
            .range(offset, offset + limit - 1);
        list = fallbackAny as List<dynamic>;
      }

      final mapped = list
          .map(
            (item) => StudyQuestion.fromMap(
              item as Map<String, dynamic>,
              languageCode: languageCode,
            ),
          )
          .toList();

      return mapped;
    } on PostgrestException catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.fetchChapterQuestions: ${e.message}',
      );
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.fetchChapterQuestions error: $e',
      );
      throw DataError(message: 'Failed to load chapter questions: $e');
    }
  }

  @override
  Future<List<StudyQuestion>> fetchTopicQuestions({
    required String topicId,
    String? chapterId,
    required String languageCode,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      const selectCols =
          'id, chapter_id, topic_id, question, options, correct_option, explanation, difficulty, language, status';

      // 1. Query by topic_id and active language
      final response = await _client
          .from('question_bank')
          .select(selectCols)
          .eq('topic_id', topicId)
          .eq('language', languageCode)
          .eq('status', 'approved')
          .order('created_at', ascending: true)
          .range(offset, offset + limit - 1);

      var list = response as List<dynamic>;

      // 2. Fallback to English if active language yielded no results
      if (list.isEmpty && languageCode != 'en') {
        final fallbackEn = await _client
            .from('question_bank')
            .select(selectCols)
            .eq('topic_id', topicId)
            .eq('language', 'en')
            .eq('status', 'approved')
            .order('created_at', ascending: true)
            .range(offset, offset + limit - 1);
        list = fallbackEn as List<dynamic>;
      }

      // 3. Fallback to chapter questions if topic specifically has 0 questions
      if (list.isEmpty && chapterId != null && chapterId.isNotEmpty) {
        return await fetchChapterQuestions(
          chapterId: chapterId,
          languageCode: languageCode,
          limit: limit,
          offset: offset,
        );
      }

      return list
          .map(
            (item) => StudyQuestion.fromMap(
              item as Map<String, dynamic>,
              languageCode: languageCode,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'SupabaseStudyRepository.fetchTopicQuestions: ${e.message}',
      );
      throw DataError(message: e.message);
    } catch (e) {
      AppLogger.error('SupabaseStudyRepository.fetchTopicQuestions error: $e');
      throw DataError(message: 'Failed to load topic practice questions: $e');
    }
  }

  @override
  Future<ContinueLearningSnapshot?> fetchRecentStudyProgress({
    required String userId,
    required String languageCode,
  }) async {
    try {
      final response = await _client
          .from('user_study_progress')
          .select(
            'topic_id, chapter_id, last_studied_at, '
            'chapters(id, subject_id, chapter_translations(language, title), subjects(id, subject_translations(language, name))), '
            'topics(id, topic_translations(language, title))',
          )
          .eq('user_id', userId)
          .order('last_studied_at', ascending: false)
          .limit(1);

      final list = response as List<dynamic>;
      if (list.isEmpty) return null;

      final row = list.first as Map<String, dynamic>;
      final chapterMap = row['chapters'] as Map<String, dynamic>? ?? {};
      final subjectMap = chapterMap['subjects'] as Map<String, dynamic>? ?? {};
      final topicMap = row['topics'] as Map<String, dynamic>? ?? {};

      // Resolve subject name
      String subjectName = 'Subject';
      final sTrans = subjectMap['subject_translations'] as List<dynamic>?;
      if (sTrans != null && sTrans.isNotEmpty) {
        final match = sTrans.firstWhere(
          (t) => t['language'] == languageCode,
          orElse: () => sTrans.firstWhere(
            (t) => t['language'] == 'en',
            orElse: () => sTrans.first,
          ),
        );
        subjectName = match['name'] ?? subjectName;
      }

      // Resolve chapter title
      String chapterTitle = 'Chapter';
      final cTrans = chapterMap['chapter_translations'] as List<dynamic>?;
      if (cTrans != null && cTrans.isNotEmpty) {
        final match = cTrans.firstWhere(
          (t) => t['language'] == languageCode,
          orElse: () => cTrans.firstWhere(
            (t) => t['language'] == 'en',
            orElse: () => cTrans.first,
          ),
        );
        chapterTitle = match['title'] ?? chapterTitle;
      }

      // Resolve topic title
      String topicTitle = 'Topic';
      final tTrans = topicMap['topic_translations'] as List<dynamic>?;
      if (tTrans != null && tTrans.isNotEmpty) {
        final match = tTrans.firstWhere(
          (t) => t['language'] == languageCode,
          orElse: () => tTrans.firstWhere(
            (t) => t['language'] == 'en',
            orElse: () => tTrans.first,
          ),
        );
        topicTitle = match['title'] ?? topicTitle;
      }

      final lastStudiedStr = row['last_studied_at'] as String?;
      final lastStudied = lastStudiedStr != null
          ? DateTime.tryParse(lastStudiedStr)
          : null;

      return ContinueLearningSnapshot(
        subjectId: (chapterMap['subject_id'] as String?) ?? '',
        subjectName: subjectName,
        chapterId: (row['chapter_id'] as String?) ?? '',
        chapterTitle: chapterTitle,
        topicId: (row['topic_id'] as String?) ?? '',
        topicTitle: topicTitle,
        progressPercentage: 50.0,
        lastStudiedAt: lastStudied,
      );
    } catch (e) {
      AppLogger.warning('SupabaseStudyRepository.fetchRecentStudyProgress: $e');
      return null;
    }
  }

  @override
  Future<StudyProgressSummary> fetchStudySummary({
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('user_study_progress')
          .select('chapter_id, topic_id')
          .eq('user_id', userId)
          .eq('is_completed', true);

      final list = response as List<dynamic>;
      final completedTopicIds = <String>{};
      final completedChapterIds = <String>{};

      for (final r in list) {
        final t = r['topic_id'] as String?;
        final c = r['chapter_id'] as String?;
        if (t != null) completedTopicIds.add(t);
        if (c != null) completedChapterIds.add(c);
      }

      return StudyProgressSummary(
        completedTopicsCount: completedTopicIds.length,
        completedChaptersCount: completedChapterIds.length,
        activeSubjectsCount: completedChapterIds.isNotEmpty ? 1 : 0,
      );
    } catch (e) {
      AppLogger.warning('SupabaseStudyRepository.fetchStudySummary: $e');
      return const StudyProgressSummary();
    }
  }
}

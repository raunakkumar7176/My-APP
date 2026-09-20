import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/app_config.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question.dart';
import '../../../core/services/supabase_service.dart';
import '../../test/models/question_draft.dart';

/// Represents a single AI-generated question in the review stage.
class AiGeneratedQuestion {
  const AiGeneratedQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctOption,
    this.explanation = '',
    this.subject = '',
    this.topic = '',
    this.difficulty = 'medium',
    this.language = 'en',
    this.status = 'VALID',
    this.reason,
    this.confidence = 0.92,
    this.duplicateOf,
  });

  final String id;
  final String question;
  final List<String> options;
  final int correctOption;
  final String explanation;
  final String subject;
  final String topic;
  final String difficulty;
  final String language;
  final String status; // VALID, NEEDS_REVIEW, INVALID
  final String? reason;
  final double confidence;
  final int? duplicateOf;

  bool get isValid => status == 'VALID';
  bool get needsReview => status == 'NEEDS_REVIEW';
  bool get isInvalid => status == 'INVALID';

  /// Convert to a QuestionDraft for insertion into the test creation flow.
  QuestionDraft toQuestionDraft({
    required int marks,
    String? negativeMarks,
  }) {
    return QuestionDraft(
      questionText: question,
      options: options
          .map((o) => QuestionOptionDraft(text: o))
          .toList(),
      correctOptionIndex: correctOption,
      explanation: explanation,
      difficulty: _parseDifficulty(difficulty),
      marks: marks,
      negativeMarks: negativeMarks != null ? double.tryParse(negativeMarks) : null,
      language: language,
    );
  }

  static DifficultyLevel _parseDifficulty(String d) {
    switch (d) {
      case 'easy':
        return DifficultyLevel.easy;
      case 'hard':
        return DifficultyLevel.hard;
      default:
        return DifficultyLevel.medium;
    }
  }

  AiGeneratedQuestion copyWith({
    String? id,
    String? question,
    List<String>? options,
    int? correctOption,
    String? explanation,
    String? subject,
    String? topic,
    String? difficulty,
    String? language,
    String? status,
    String? reason,
    double? confidence,
    int? duplicateOf,
  }) {
    return AiGeneratedQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      options: options ?? this.options,
      correctOption: correctOption ?? this.correctOption,
      explanation: explanation ?? this.explanation,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
      language: language ?? this.language,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      confidence: confidence ?? this.confidence,
      duplicateOf: duplicateOf ?? this.duplicateOf,
    );
  }

  factory AiGeneratedQuestion.fromJson(Map<String, dynamic> json) {
    return AiGeneratedQuestion(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((o) => o.toString())
              .toList() ??
          [],
      correctOption: json['correct_option'] as int? ?? 0,
      explanation: json['explanation'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'medium',
      language: json['language'] as String? ?? 'en',
      status: json['_status'] as String? ?? 'VALID',
      reason: json['_reason'] as String?,
      confidence: (json['_confidence'] as num?)?.toDouble() ?? 0.92,
      duplicateOf: json['_duplicate_of'] as int?,
    );
  }
}

/// Summary of an AI generation request.
class AiGenerationSummary {
  const AiGenerationSummary({
    required this.requested,
    required this.generated,
    required this.valid,
    required this.needsReview,
    required this.invalid,
  });

  final int requested;
  final int generated;
  final int valid;
  final int needsReview;
  final int invalid;

  factory AiGenerationSummary.fromJson(Map<String, dynamic> json) {
    return AiGenerationSummary(
      requested: json['requested'] as int? ?? 0,
      generated: json['generated'] as int? ?? 0,
      valid: json['valid'] as int? ?? 0,
      needsReview: json['needsReview'] as int? ?? 0,
      invalid: json['invalid'] as int? ?? 0,
    );
  }
}

/// Quota status for AI generation.
class AiQuotaStatus {
  const AiQuotaStatus({
    required this.usedToday,
    required this.remaining,
    required this.limit,
    required this.canGenerate,
  });

  final int usedToday;
  final int remaining;
  final int limit;
  final bool canGenerate;

  factory AiQuotaStatus.fromJson(Map<String, dynamic> json) {
    return AiQuotaStatus(
      usedToday: json['usedToday'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      limit: json['limit'] as int? ?? 3,
      canGenerate: json['canGenerate'] as bool? ?? false,
    );
  }
}

/// Result of an AI generation request.
class AiGenerationResult {
  const AiGenerationResult({
    required this.questions,
    required this.summary,
    required this.quota,
    this.cacheHit = false,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.model = '',
  });

  final List<AiGeneratedQuestion> questions;
  final AiGenerationSummary summary;
  final AiQuotaStatus quota;
  final bool cacheHit;
  final int tokensIn;
  final int tokensOut;
  final String model;
}

/// Repository for AI question generation.
///
/// Calls the Next.js server-side API route which handles the actual AI call.
/// No API keys are stored or used client-side.
class AiGenerationRepository {
  const AiGenerationRepository();

  /// The base URL of the Next.js API, derived from AppConfig.
  String get _baseUrl => AppConfig.current.nextApiUrl;

  /// Generates questions via the server-side AI pipeline.
  ///
  /// Throws [AppError] on failure.
  Future<AiGenerationResult> generateQuestions({
    required String subject,
    required String topic,
    String? chapter,
    required int questionCount,
    required String difficulty,
    Map<String, int>? difficultyDistribution,
    required String language,
    String questionType = 'mcq',
    double marksPerQuestion = 1,
    String? groupId,
    String testMode = 'self',
    String? sourceText,
    String? title,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) {
      throw const AuthError(message: 'You must be logged in to generate questions.');
    }

    final uri = Uri.parse('$_baseUrl/api/ai/generate-questions');
    final body = jsonEncode({
      'subject': subject,
      'topic': topic,
      'chapter': chapter ?? '',
      'questionCount': questionCount,
      'difficulty': difficulty,
      'difficultyDistribution': difficultyDistribution,
      'language': language,
      'questionType': questionType,
      'marksPerQuestion': marksPerQuestion,
      'groupId': groupId,
      'testMode': testMode,
      'sourceText': sourceText,
      'title': title,
    });

    AppLogger.info('AI generation request: $subject > $topic ($questionCount questions)');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: body,
      ).timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        final error = data['error'] as String? ?? 'Generation failed';
        AppLogger.error('AI generation failed (${response.statusCode}): $error');
        throw DataError(message: error);
      }

      if (data['error'] != null) {
        throw DataError(message: data['error'] as String);
      }

      final questions = (data['questions'] as List<dynamic>? ?? [])
          .map((q) => AiGeneratedQuestion.fromJson(q as Map<String, dynamic>))
          .toList();

      final summary = data['summary'] != null
          ? AiGenerationSummary.fromJson(data['summary'] as Map<String, dynamic>)
          : AiGenerationSummary(
              requested: questionCount,
              generated: questions.length,
              valid: questions.where((q) => q.isValid).length,
              needsReview: questions.where((q) => q.needsReview).length,
              invalid: questions.where((q) => q.isInvalid).length,
            );

      final quota = data['quota'] != null
          ? AiQuotaStatus.fromJson(data['quota'] as Map<String, dynamic>)
          : const AiQuotaStatus(
              usedToday: 0,
              remaining: 3,
              limit: 3,
              canGenerate: true,
            );

      AppLogger.info(
        'AI generation complete: ${questions.length} questions '
        '(${summary.valid} valid, ${summary.needsReview} review, ${summary.invalid} invalid)',
      );

      return AiGenerationResult(
        questions: questions,
        summary: summary,
        quota: quota,
        cacheHit: data['cacheHit'] as bool? ?? false,
        tokensIn: data['tokensIn'] as int? ?? 0,
        tokensOut: data['tokensOut'] as int? ?? 0,
        model: data['model'] as String? ?? '',
      );
    } on AppError {
      rethrow;
    } catch (e) {
      AppLogger.error('AI generation unexpected error: $e');
      throw DataError(message: 'Network error. Please check your connection and try again.');
    }
  }
}

import 'dart:convert';

import '../models/question_draft.dart';

/// Result of validating/parsing a pasted JSON question payload. Never
/// partially succeeds silently: either every object in the array is valid
/// and [drafts] is populated, or [errors] explains exactly what is wrong
/// (which index, which field) so the user can fix their paste.
final class JsonQuestionParseResult {
  const JsonQuestionParseResult({this.drafts = const [], this.errors = const []});

  final List<QuestionDraft> drafts;
  final List<String> errors;

  bool get isValid => errors.isEmpty && drafts.isNotEmpty;
}

/// Parses and validates a raw JSON string pasted by the creator into a list
/// of [QuestionDraft]s. Accepts either a single question object or a JSON
/// array of them. Required schema per question:
///   { "question": string, "options": [string, string, string, string],
///     "correct_option": 0-3, "explanation": string (optional) }
/// Nothing is guessed: a missing/malformed field is reported, never
/// defaulted to a fabricated value (e.g. a missing `correct_option` is a
/// validation error, not silently 0).
abstract final class JsonQuestionParser {
  static JsonQuestionParseResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const JsonQuestionParseResult(errors: ['Paste some JSON first.']);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      return JsonQuestionParseResult(errors: ['Invalid JSON: ${e.message}']);
    }

    final rawItems = decoded is List
        ? decoded
        : decoded is Map
            ? [decoded]
            : null;
    if (rawItems == null) {
      return const JsonQuestionParseResult(
        errors: ['Expected a JSON object or an array of question objects.'],
      );
    }
    if (rawItems.isEmpty) {
      return const JsonQuestionParseResult(errors: ['The array is empty.']);
    }

    final drafts = <QuestionDraft>[];
    final errors = <String>[];

    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      final label = 'Question ${i + 1}';
      if (item is! Map) {
        errors.add('$label: expected a JSON object.');
        continue;
      }
      final map = Map<String, dynamic>.from(item);

      final question = map['question'];
      if (question is! String || question.trim().isEmpty) {
        errors.add('$label: "question" must be a non-empty string.');
        continue;
      }

      final rawOptions = map['options'];
      if (rawOptions is! List || rawOptions.length != 4) {
        errors.add('$label: "options" must be an array of exactly 4 strings.');
        continue;
      }
      final options = <QuestionOptionDraft>[];
      var optionsOk = true;
      for (var j = 0; j < rawOptions.length; j++) {
        final o = rawOptions[j];
        if (o is! String || o.trim().isEmpty) {
          errors.add('$label: option ${j + 1} must be a non-empty string.');
          optionsOk = false;
          break;
        }
        options.add(QuestionOptionDraft(text: o));
      }
      if (!optionsOk) continue;

      final rawCorrect = map['correct_option'];
      final correctOption = rawCorrect is int
          ? rawCorrect
          : rawCorrect is num
              ? rawCorrect.toInt()
              : null;
      if (correctOption == null || correctOption < 0 || correctOption > 3) {
        errors.add('$label: "correct_option" must be an integer 0-3.');
        continue;
      }

      final explanation = map['explanation'];
      if (explanation != null && explanation is! String) {
        errors.add('$label: "explanation" must be a string if present.');
        continue;
      }

      drafts.add(QuestionDraft(
        questionText: question.trim(),
        options: options,
        correctOptionIndex: correctOption,
        explanation: (explanation as String?)?.trim(),
        source: 'manual',
      ));
    }

    if (errors.isNotEmpty) {
      return JsonQuestionParseResult(errors: errors);
    }
    return JsonQuestionParseResult(drafts: drafts);
  }
}

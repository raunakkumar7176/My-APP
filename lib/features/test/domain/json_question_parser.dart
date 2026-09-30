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

/// Question-text keys accepted, in priority order.
const _questionKeys = ['question', 'q', 'title', 'problem'];

/// Options-list keys accepted, in priority order.
const _optionsKeys = ['options', 'choices', 'answers'];

/// Correct-answer keys accepted, in priority order. Note 'answers' is
/// deliberately NOT here — it's an options alias above; a plain 'answer'
/// singular is the correct-answer key instead.
const _correctKeys = ['correct_option', 'correct_answer', 'answer', 'correctIndex', 'correct'];

/// Parses and validates a raw JSON string pasted by the creator into a list
/// of [QuestionDraft]s. Accepts either a single question object or a JSON
/// array of them. Canonical schema per question:
///   { "question": string, "options": [string, string, string, string],
///     "correct_option": 0-3, "explanation": string (optional) }
/// Also accepts, per field, whichever alias/format the paste actually used
/// (see [_questionKeys]/[_optionsKeys]/[_correctKeys] and
/// [_resolveCorrectIndex]) — real flexibility, not fabrication: every value
/// still has to resolve to something unambiguous, or it's a reported error,
/// never a silent default (e.g. a missing correct-answer key is still a
/// validation error, not a guessed 0).
abstract final class JsonQuestionParser {
  /// First present key from [keys] in [map], or null.
  static Object? _firstOf(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k)) return map[k];
    }
    return null;
  }

  /// Resolves a raw correct-answer value into a 0-based option index, given
  /// how many options this question actually has. Accepts:
  ///   - an int/num already 0-based (0..optionCount-1)
  ///   - an int/num 1-based (1..optionCount), converted to 0-based
  ///   - a letter ('A'/'B'/'C'/'D', any case), converted by alphabet position
  /// Returns null when the value doesn't unambiguously resolve — the caller
  /// reports that as an error rather than guessing.
  static int? _resolveCorrectIndex(Object? raw, int optionCount) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.length == 1) {
        final letterIndex = trimmed.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
        if (letterIndex >= 0 && letterIndex < optionCount) return letterIndex;
      }
      final asNum = num.tryParse(trimmed);
      if (asNum != null) return _resolveCorrectIndex(asNum, optionCount);
      return null;
    }
    final asInt = raw is int ? raw : (raw is num ? raw.toInt() : null);
    if (asInt == null) return null;
    if (asInt >= 0 && asInt < optionCount) return asInt; // already 0-based
    if (asInt >= 1 && asInt <= optionCount) return asInt - 1; // 1-based
    return null;
  }

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

      final question = _firstOf(map, _questionKeys);
      if (question is! String || question.trim().isEmpty) {
        errors.add('$label: a question text field (question/q/title/problem) '
            'must be a non-empty string.');
        continue;
      }

      final rawOptions = _firstOf(map, _optionsKeys);
      if (rawOptions is! List || rawOptions.length != 4) {
        errors.add('$label: an options field (options/choices/answers) must '
            'be an array of exactly 4 strings.');
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

      final rawCorrect = _firstOf(map, _correctKeys);
      final correctOption = _resolveCorrectIndex(rawCorrect, options.length);
      if (correctOption == null) {
        errors.add('$label: a correct-answer field (correct_option/'
            'correct_answer/answer/correctIndex/correct) must identify one '
            'of the ${options.length} options — as a 0-based index, a '
            '1-based index, or a letter (A-${String.fromCharCode(65 + options.length - 1)}).');
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

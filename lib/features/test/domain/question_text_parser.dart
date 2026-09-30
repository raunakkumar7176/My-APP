import '../models/question_draft.dart';

/// Result of parsing raw plain-text (e.g. copy-pasted straight out of
/// ChatGPT/Claude/Gemini) into [QuestionDraft]s. Mirrors
/// [JsonQuestionParseResult]'s never-partially-succeed contract: either
/// every question block in the paste parsed cleanly, or [errors] explains
/// exactly which block/line is wrong so the user can fix the paste (not a
/// silently-dropped question).
final class QuestionTextParseResult {
  const QuestionTextParseResult({this.drafts = const [], this.errors = const []});

  final List<QuestionDraft> drafts;
  final List<String> errors;

  bool get isValid => errors.isEmpty && drafts.isNotEmpty;
}

/// "Smart Paste" — a client-side parser for the free-form plain text any AI
/// chatbot naturally produces for an MCQ set, e.g.:
///
///   1. 1857 ki kranti kahan se shuru hui thi?
///   A. Meerut
///   B. Delhi
///   C. Kanpur
///   D. Jhansi
///   Ans: A
///   Exp: Yeh kranti 10 May 1857 ko Meerut se shuru hui thi.
///
/// No JSON, no schema the student has to know about — they just copy
/// whatever the AI wrote and paste it in. Blank lines separate questions;
/// a new question-number line also starts a new block even without a
/// blank line before it, since AI output is inconsistent about spacing.
abstract final class QuestionTextParser {
  // "1.", "1)", "Q1.", "Q1)", "Question 1:" — the leading question number.
  static final _questionLine = RegExp(
    r'^\s*(?:Q(?:uestion)?\s*)?\d+[\.\)\:]\s*(.+)$',
    caseSensitive: false,
  );

  // "A.", "A)", "(A)", "[A]" — up to 4 options, any of these bracket styles.
  static final _optionLine = RegExp(
    r'^\s*[\(\[]?([A-Da-d])[\)\.\]]\s*(.+)$',
  );

  static final _answerLine = RegExp(
    r'^\s*(?:Ans(?:wer)?|Correct(?:\s*Option)?)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
  );

  static final _explanationLine = RegExp(
    r'^\s*(?:Exp(?:lanation)?|Note)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
  );

  static QuestionTextParseResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const QuestionTextParseResult(errors: ['Paste some questions first.']);
    }

    final lines = trimmed.split('\n');
    final blocks = <List<String>>[];
    var current = <String>[];

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) {
          blocks.add(current);
          current = [];
        }
        continue;
      }
      // A new numbered question line always starts a fresh block, even
      // without a preceding blank line — AI output is inconsistent here.
      if (_questionLine.hasMatch(line) && current.isNotEmpty && _looksLikeNewQuestion(current)) {
        blocks.add(current);
        current = [line];
        continue;
      }
      current.add(line);
    }
    if (current.isNotEmpty) blocks.add(current);

    if (blocks.isEmpty) {
      return const QuestionTextParseResult(
        errors: ["Could not find any questions. Make sure each question starts with a number (e.g. '1.')."],
      );
    }

    final drafts = <QuestionDraft>[];
    final errors = <String>[];

    for (var i = 0; i < blocks.length; i++) {
      final label = 'Question ${i + 1}';
      final result = _parseBlock(blocks[i], label);
      if (result.error != null) {
        errors.add(result.error!);
      } else {
        drafts.add(result.draft!);
      }
    }

    if (errors.isNotEmpty) {
      return QuestionTextParseResult(errors: errors);
    }
    return QuestionTextParseResult(drafts: drafts);
  }

  /// A block only counts as "already has content" (so a bare option/answer
  /// line doesn't falsely trigger a new-question split) once it has a
  /// question line AND at least one option.
  static bool _looksLikeNewQuestion(List<String> block) {
    final hasQuestion = block.any(_questionLine.hasMatch);
    final hasOption = block.any(_optionLine.hasMatch);
    return hasQuestion && hasOption;
  }

  static ({QuestionDraft? draft, String? error}) _parseBlock(List<String> lines, String label) {
    String? questionText;
    final options = <String>[];
    String? rawAnswer;
    String? explanation;

    for (final line in lines) {
      final qMatch = _questionLine.firstMatch(line);
      if (qMatch != null && questionText == null) {
        questionText = qMatch.group(1)!.trim();
        continue;
      }
      final optMatch = _optionLine.firstMatch(line);
      if (optMatch != null) {
        final letter = optMatch.group(1)!.toUpperCase();
        final idx = letter.codeUnitAt(0) - 'A'.codeUnitAt(0);
        while (options.length <= idx) {
          options.add('');
        }
        options[idx] = optMatch.group(2)!.trim();
        continue;
      }
      final ansMatch = _answerLine.firstMatch(line);
      if (ansMatch != null) {
        rawAnswer = ansMatch.group(1)!.trim();
        continue;
      }
      final expMatch = _explanationLine.firstMatch(line);
      if (expMatch != null) {
        explanation = expMatch.group(1)!.trim();
        continue;
      }
      // A continuation line (question wrapped onto multiple lines, or an
      // explanation that spans several lines) — append to whichever field
      // was most recently being built.
      if (explanation != null) {
        explanation = '$explanation ${line.trim()}';
      } else if (rawAnswer == null && questionText != null && options.isEmpty) {
        questionText = '$questionText ${line.trim()}';
      }
    }

    if (questionText == null || questionText.isEmpty) {
      return (draft: null, error: '$label: could not find the question text.');
    }
    if (options.length < 2 || options.any((o) => o.isEmpty)) {
      return (
        draft: null,
        error: '$label: needs at least 2 complete options (A, B, ... each on its own line).',
      );
    }
    if (rawAnswer == null) {
      return (
        draft: null,
        error: '$label: could not find the correct answer (expected a line like "Ans: A").',
      );
    }

    final correctIndex = _resolveAnswerIndex(rawAnswer, options.length);
    if (correctIndex == null) {
      return (
        draft: null,
        error: '$label: the answer "$rawAnswer" does not match any of the '
            '${options.length} options (A-${String.fromCharCode(65 + options.length - 1)}).',
      );
    }

    return (
      draft: QuestionDraft(
        questionText: questionText,
        options: [for (final o in options) QuestionOptionDraft(text: o)],
        correctOptionIndex: correctIndex,
        explanation: explanation,
        source: 'manual',
      ),
      error: null,
    );
  }

  /// Accepts a bare letter ("A"), a letter with trailing junk ("A)"), or a
  /// 1-based/0-based number, same tolerant resolution as the JSON parser.
  static int? _resolveAnswerIndex(String raw, int optionCount) {
    final cleaned = raw.trim();
    final letterMatch = RegExp(r'^[\(\[]?([A-Da-d])').firstMatch(cleaned);
    if (letterMatch != null) {
      final idx = letterMatch.group(1)!.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
      if (idx >= 0 && idx < optionCount) return idx;
    }
    final asNum = num.tryParse(cleaned);
    if (asNum != null) {
      final n = asNum.toInt();
      if (n >= 0 && n < optionCount) return n; // 0-based
      if (n >= 1 && n <= optionCount) return n - 1; // 1-based
    }
    return null;
  }
}

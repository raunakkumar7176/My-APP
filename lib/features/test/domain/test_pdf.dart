import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/models/answer.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_analytics.dart';
import '../../../core/models/test.dart';
import 'attempt_history.dart';
import 'test_kind.dart';

/// Pure PDF builders (no I/O, no Supabase). Both take only data the caller
/// already loaded through the authorized paths:
///  - questions from `get_test_questions_safe` (never carry `correct_option`;
///    and the option model carries no correctness flag, so no key can leak);
///  - results from the user's own `results` row(s).
/// Nothing is derived beyond formatting: no rank/percentile/cutoff/labels.
abstract final class TestPdf {
  static const _base = pw.TextStyle(fontSize: 11);
  static const _bold = pw.TextStyle(
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
  );
  static const _h1 = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
  static const _h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);

  /// Same bundled Noto Sans Devanagari TTFs as `ExamReportPdfGenerator`, so
  /// Hindi/bilingual question text never falls back to a font with no
  /// Devanagari glyphs (the "dabba"/box bug) in the question paper, answer
  /// sheet, result report, or group result PDFs this class also builds.
  static const String _regularAssetPath =
      'assets/fonts/NotoSansDevanagari-Regular.ttf';
  static const String _boldAssetPath =
      'assets/fonts/NotoSansDevanagari-Bold.ttf';

  static Future<pw.Font> _loadFont({
    required String assetPath,
    required Future<pw.Font> Function() remote,
    required pw.Font Function() fallback,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      // Asset bundle unavailable (e.g. a non-Flutter test host).
    }
    try {
      final downloaded = await remote();
      if (downloaded is pw.TtfFont) return downloaded;
    } catch (_) {
      // Offline: fall through to the last resort.
    }
    return fallback();
  }

  static Future<pw.ThemeData> _pdfTheme() async {
    final regular = await _loadFont(
      assetPath: _regularAssetPath,
      remote: PdfGoogleFonts.notoSansDevanagariRegular,
      fallback: pw.Font.helvetica,
    );
    final bold = await _loadFont(
      assetPath: _boldAssetPath,
      remote: PdfGoogleFonts.notoSansDevanagariBold,
      fallback: pw.Font.helveticaBold,
    );
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    );
  }

  /// Student question paper. [subjectNames] maps subject id → name (optional).
  static Future<Uint8List> questionPaper({
    required Test test,
    required TestKind kind,
    required List<Question> questions,
    Map<String, String> subjectNames = const {},
    String? generatedFor,
  }) async {
    if (questions.isEmpty) {
      throw StateError('No questions to print.');
    }
    final pdfTheme = await _pdfTheme();
    final doc = pw.Document(title: test.title, author: 'My Preparation');
    final subjects = {
      for (final q in questions)
        if (q.subjectId != null) subjectNames[q.subjectId!] ?? q.subjectId!,
    };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pdfTheme,
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.Text(test.title, style: _h1),
          pw.SizedBox(height: 6),
          _kv('Test type', kind.label),
          _kv('Duration', _duration(test.durationSec)),
          _kv('Total questions', '${questions.length}'),
          if (test.marksPerQuestion != null)
            _kv('Marks per question', '${test.marksPerQuestion}'),
          if (test.negativeMarks != null && test.negativeMarks! > 0)
            _kv('Negative marks', '${test.negativeMarks}'),
          if (subjects.isNotEmpty) _kv('Subjects', subjects.join(', ')),
          if (generatedFor != null) _kv('Generated for', generatedFor),
          if (test.instructions != null &&
              test.instructions!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('Instructions', style: _h2),
            pw.Text(test.instructions!.trim(), style: _base),
          ],
          pw.SizedBox(height: 14),
          pw.Divider(),
          for (var i = 0; i < questions.length; i++)
            _question(i + 1, questions[i], subjectNames),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _question(
    int n,
    Question q,
    Map<String, String> subjectNames,
  ) {
    final meta = <String>[
      if (q.subjectId != null) subjectNames[q.subjectId!] ?? '',
      q.difficulty.name,
      '${q.marks} mark(s)',
    ].where((s) => s.isNotEmpty).join(' · ');
    final options = q.options ?? const <QuestionOption>[];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Q$n. ${q.question}', style: _bold),
          pw.Text(
            meta,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          for (var i = 0; i < options.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12, top: 2),
              child: pw.Text(
                '${String.fromCharCode(65 + i)}. ${options[i].text}',
                style: _base,
              ),
            ),
        ],
      ),
    );
  }

  /// Result report from the stored result row (+ history/delta when present).
  static Future<Uint8List> resultReport({
    required String studentName,
    required Test? test,
    required TestKind kind,
    required Result result,
    required int? attemptNumber,
    required DateTime? submittedAt,
    required List<SubjectBreakdownItem> subjects,
    required List<TopicBreakdownItem> topics,
    ResultDelta? deltaFromPrevious,
    int? previousAttemptNumber,
    List<AttemptHistoryEntry> history = const [],
    String? groupName,
  }) async {
    final pdfTheme = await _pdfTheme();
    final doc = pw.Document(
      title: 'Result — ${test?.title ?? 'Test'}',
      author: 'My Preparation',
    );
    String n(num? v) => v == null
        ? '--'
        : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));
    String signed(num? v) => v == null ? '--' : (v > 0 ? '+${n(v)}' : n(v));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pdfTheme,
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.Text('Result Report', style: _h1),
          pw.SizedBox(height: 6),
          _kv('Student', studentName),
          _kv('Test', test?.title ?? '--'),
          if (groupName != null) _kv('Group', groupName),
          _kv('Test type', kind.label),
          if (attemptNumber != null) _kv('Attempt', '$attemptNumber'),
          if (submittedAt != null) _kv('Submitted', _dateTime(submittedAt)),
          pw.SizedBox(height: 12),
          pw.Text('Score', style: _h2),
          _kv('Score', '${n(result.score)} / ${n(result.maxScore)}'),
          _kv(
            'Percentage',
            result.percentage == null ? '--' : '${n(result.percentage)}%',
          ),
          _kv(
            'Accuracy',
            result.accuracy == null ? '--' : '${n(result.accuracy)}%',
          ),
          _kv('Correct', '${result.correctCount ?? '--'}'),
          _kv('Wrong', '${result.wrongCount ?? '--'}'),
          _kv('Unanswered', '${result.unansweredCount ?? '--'}'),
          if (result.rank != null) _kv('Rank', '#${result.rank}'),
          if (test?.passingMarks != null && result.score != null) ...[
            _kv('Pass marks', n(test!.passingMarks)),
            _kv(
              'Result',
              result.score! >= test.passingMarks! ? 'PASS' : 'FAIL',
            ),
          ],
          if (subjects.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Subject breakdown', style: _h2),
            _table(
              ['Subject', 'Attempted', 'Correct', 'Wrong', 'Unanswered'],
              [
                for (final s in subjects)
                  [
                    s.subjectName,
                    '${s.attempted}',
                    '${s.correct}',
                    '${s.wrong}',
                    '${s.unanswered}',
                  ],
              ],
            ),
          ],
          if (topics.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Topic breakdown', style: _h2),
            _table(
              ['Topic', 'Attempted', 'Correct', 'Wrong', 'Unanswered'],
              [
                for (final t in topics)
                  [
                    t.topicName,
                    '${t.attempted}',
                    '${t.correct}',
                    '${t.wrong}',
                    '${t.unanswered}',
                  ],
              ],
            ),
          ],
          if (deltaFromPrevious != null && !deltaFromPrevious.isEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              previousAttemptNumber == null
                  ? 'Compared with previous attempt'
                  : 'Compared with attempt $previousAttemptNumber',
              style: _h2,
            ),
            if (deltaFromPrevious.score != null)
              _kv('Marks', signed(deltaFromPrevious.score)),
            if (deltaFromPrevious.percentage != null)
              _kv('Percentage', '${signed(deltaFromPrevious.percentage)} pts'),
            if (deltaFromPrevious.accuracy != null)
              _kv('Accuracy', '${signed(deltaFromPrevious.accuracy)} pts'),
            if (deltaFromPrevious.correct != null)
              _kv('Correct', signed(deltaFromPrevious.correct)),
            if (deltaFromPrevious.wrong != null)
              _kv('Wrong', signed(deltaFromPrevious.wrong)),
            if (deltaFromPrevious.unanswered != null)
              _kv('Unanswered', signed(deltaFromPrevious.unanswered)),
          ],
          if (history.length > 1) ...[
            pw.SizedBox(height: 12),
            pw.Text('Attempt history', style: _h2),
            _table(
              ['Attempt', 'Score', 'Percentage', 'Accuracy', 'Completed'],
              [
                for (final e in history)
                  [
                    e.attemptNumber == null ? '--' : '${e.attemptNumber}',
                    '${n(e.result.score)} / ${n(e.result.maxScore)}',
                    e.result.percentage == null
                        ? '--'
                        : '${n(e.result.percentage)}%',
                    e.result.accuracy == null
                        ? '--'
                        : '${n(e.result.accuracy)}%',
                    e.completedAt == null ? '--' : _dateTime(e.completedAt!),
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Scores are computed on the server from the stored answers. '
            'No rank, percentile or readiness figures are estimated.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// OMR-style answer sheet: one bubble row per question, dynamically sized
  /// to the test's actual question/option counts (never hardcoded to 100).
  /// Shows only what the student actually marked — [Answer.selectedOption] —
  /// never a correct/incorrect mark, because the backend never exposes
  /// `correct_option` to the client (see the class doc comment); marking
  /// correctness here would fabricate data the server has not certified.
  /// The Correct/Wrong/Unanswered summary is the server's own aggregate
  /// counts from [result], not a per-bubble judgement.
  static Future<Uint8List> answerSheet({
    required Test test,
    required TestKind kind,
    required List<Question> questions,
    required Map<String, Answer> answers,
    Result? result,
    DateTime? startedAt,
    DateTime? submittedAt,
    String? studentName,
  }) async {
    if (questions.isEmpty) {
      throw StateError('No questions to print.');
    }
    final pdfTheme = await _pdfTheme();
    final doc = pw.Document(title: '${test.title} — Answer Sheet', author: 'My Preparation');
    final maxOptions = questions.fold<int>(
      0,
      (m, q) => (q.options?.length ?? 0) > m ? q.options!.length : m,
    );
    final letters = maxOptions == 0 ? 4 : maxOptions;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pdfTheme,
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.Text('Answer Sheet', style: _h1),
          pw.SizedBox(height: 6),
          if (studentName != null) _kv('Student', studentName),
          _kv('Test', test.title),
          _kv('Test type', kind.label),
          _kv('Total questions', '${questions.length}'),
          if (submittedAt != null) _kv('Date', _dateTime(submittedAt)),
          if (startedAt != null && submittedAt != null)
            _kv('Time taken', _elapsed(submittedAt.difference(startedAt))),
          if (result != null) ...[
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Text('Correct: ${result.correctCount ?? '--'}', style: _bold),
                pw.SizedBox(width: 16),
                pw.Text('Wrong: ${result.wrongCount ?? '--'}', style: _bold),
                pw.SizedBox(width: 16),
                pw.Text('Unanswered: ${result.unansweredCount ?? '--'}', style: _bold),
              ],
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 6),
          // 3 questions per row (not 1) so a 100-question sheet fits in a
          // handful of pages instead of one bubble-row per page-line.
          pw.Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < questions.length; i++)
                pw.SizedBox(
                  width: (PdfPageFormat.a4.width - 64 - 24) / 3,
                  child: _bubbleRow(i + 1, questions[i], answers[questions[i].id], letters),
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _bubbleRow(int n, Question q, Answer? answer, int letters) {
    final selected = answer?.selectedOption;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 24, child: pw.Text('$n.', style: _bold)),
          for (var i = 0; i < letters; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 6),
              child: pw.Container(
                width: 18,
                height: 18,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                  color: selected == i ? PdfColors.grey800 : null,
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  String.fromCharCode(65 + i),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: selected == i ? PdfColors.white : PdfColors.grey700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _elapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  static pw.Widget _kv(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 130, child: pw.Text(k, style: _bold)),
        pw.Expanded(child: pw.Text(v, style: _base)),
      ],
    ),
  );

  static pw.Widget _table(List<String> header, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: header,
        data: rows,
        headerStyle: _bold,
        cellStyle: _base,
        cellAlignment: pw.Alignment.centerLeft,
      );

  static String _duration(int? seconds) {
    if (seconds == null) return '--';
    final m = seconds ~/ 60;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  static String _dateTime(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  /// One already-ranked row for [groupResult]. The rank and marks must come
  /// from the server's own authoritative dataset (e.g. `rpc_get_leaderboard`
  /// / the results table) — this builder never re-ranks or recomputes marks,
  /// it only formats what it is given. [passFail] is a plain string
  /// ('PASS'/'FAIL'/'--') the caller derives from `marks >= test.passingMarks`
  /// so the arithmetic stays visible at the call site rather than hidden in
  /// a second scoring engine here.
  static Future<Uint8List> groupResult({
    required Test test,
    required String groupName,
    required List<GroupResultRow> rows,
    int? participants,
    int? appeared,
    int? passed,
    int? failed,
    double? averagePercentage,
    double? highestPercentage,
    double? lowestPercentage,
    DateTime? generatedAt,
  }) async {
    final pdfTheme = await _pdfTheme();
    final doc = pw.Document(
      title: 'Group Result — ${test.title}',
      author: 'My Preparation',
    );
    String pct(double? v) => v == null ? '--' : '${v.toStringAsFixed(1)}%';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pdfTheme,
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.Text('Group Result', style: _h1),
          pw.SizedBox(height: 6),
          _kv('Test', test.title),
          _kv('Group', groupName),
          if (generatedAt != null) _kv('Generated', _dateTime(generatedAt)),
          pw.SizedBox(height: 12),
          pw.Text('Summary', style: _h2),
          if (participants != null) _kv('Participants', '$participants'),
          if (appeared != null) _kv('Appeared', '$appeared'),
          if (passed != null) _kv('Passed', '$passed'),
          if (failed != null) _kv('Failed', '$failed'),
          _kv('Average', pct(averagePercentage)),
          _kv('Highest', pct(highestPercentage)),
          _kv('Lowest', pct(lowestPercentage)),
          pw.SizedBox(height: 14),
          pw.Text('Ranked results', style: _h2),
          _table(
            [
              'Rank',
              'Student',
              'Marks',
              'Total',
              '%',
              'Correct',
              'Wrong',
              'Unanswered',
              'Result',
            ],
            [
              for (final r in rows)
                [
                  '${r.rank}',
                  r.studentName,
                  r.marks == null ? '--' : r.marks!.toStringAsFixed(0),
                  r.totalMarks == null ? '--' : r.totalMarks!.toStringAsFixed(0),
                  pct(r.percentage),
                  r.correctCount?.toString() ?? '--',
                  r.wrongCount?.toString() ?? '--',
                  r.unansweredCount?.toString() ?? '--',
                  r.passFail ?? '--',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Ranking and marks are taken as-is from the server\'s authoritative '
            'result dataset. This report never recomputes rank or scores.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }
}

/// A single already-ranked, already-scored row handed to [TestPdf.groupResult].
/// Every field is data the caller already obtained from the server's own
/// result/leaderboard dataset — this type carries no logic.
final class GroupResultRow {
  const GroupResultRow({
    required this.rank,
    required this.studentName,
    this.marks,
    this.totalMarks,
    this.percentage,
    this.correctCount,
    this.wrongCount,
    this.unansweredCount,
    this.passFail,
  });

  final int rank;
  final String studentName;
  final double? marks;
  final double? totalMarks;
  final double? percentage;
  final int? correctCount;
  final int? wrongCount;
  final int? unansweredCount;

  /// 'PASS' / 'FAIL' / null (unknown — e.g. no passing_marks configured).
  /// Computed by the caller from already-authoritative numbers
  /// (`marks >= test.passingMarks`), never re-derived here.
  final String? passFail;
}

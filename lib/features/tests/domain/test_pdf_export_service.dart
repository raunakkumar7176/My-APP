import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../presentation/widgets/common/test_card.dart';

/// One real topic-mastery row (subject or topic level). Every field must come
/// from a server-computed aggregate (e.g. `results.subject_breakdown` /
/// `topic_breakdown`) — never a per-question answer key, which the client
/// never receives (see `lib/features/test/domain/test_pdf.dart`). Omit this
/// row list entirely when the caller has no such aggregate; the scorecard
/// renders correctly without it.
final class TopicMasteryRow {
  const TopicMasteryRow({
    required this.name,
    required this.attempted,
    required this.correct,
  });

  final String name;
  final int attempted;
  final int correct;

  double get accuracy => attempted > 0 ? (correct / attempted) * 100 : 0;
  bool get isStrong => attempted > 0 && accuracy > 75;
  bool get needsRevision => attempted == 0 || accuracy < 50;
}

/// Builds the "Official Exam Scorecard" PDF for the Unified Test Ecosystem
/// (`lib/features/tests/`). Pure formatting only, exactly like the mature
/// `TestPdf` in `lib/features/test/domain/test_pdf.dart`: every value comes
/// from data the caller already has from the real `rpc_submit_and_score_test`
/// scorecard (carried on [TestCardData]) or the signed-in profile. Nothing is
/// computed, ranked or estimated here.
///
/// DELIBERATELY NOT IMPLEMENTED: a "Complete Solutions Booklet" showing the
/// candidate's answer against the correct answer per question. No live RPC
/// exposes `correct_option` to the client at any point — not during the
/// attempt, not after submission, not after result publication
/// (`get_test_questions_safe` strips it by design; `rpc_submit_and_score_test`
/// returns only the candidate's own `selected_option` snapshot). Building
/// that document today would mean fabricating an answer key client-side.
/// Add it once a real answer-reveal RPC exists (e.g. a
/// `rpc_get_attempt_review` gated on the attempt being scored and the test's
/// `is_result_published`), then extend this service — do not invent the data
/// here in the meantime.
abstract final class TestPdfExportService {
  static const _base = pw.TextStyle(fontSize: 11);
  static const _bold = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
  static const _h1 = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
  static const _h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);

  /// Builds the scorecard PDF bytes. [topicMastery] defaults to empty — pass
  /// real per-subject/topic aggregates when the caller has them; nothing is
  /// synthesized when it doesn't.
  static Future<Uint8List> buildScorecard({
    required TestCardData data,
    required String candidateName,
    String? studentCode,
    DateTime? generatedAt,
    List<TopicMasteryRow> topicMastery = const [],
  }) async {
    final doc = pw.Document(title: '${data.title} — Scorecard', author: 'My Preparation');
    final now = generatedAt ?? DateTime.now();
    final strong = topicMastery.where((t) => t.isStrong).toList();
    final revision = topicMastery.where((t) => t.needsRevision).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (ctx) => [
          pw.Text('My Preparation', style: _h1),
          pw.Text('Official Exam Scorecard', style: _h2),
          pw.SizedBox(height: 10),
          _kv('Test', data.title),
          _kv('Date', _dateTime(now)),
          _kv('Candidate', candidateName),
          if (studentCode != null && studentCode.isNotEmpty)
            _kv('Student ID', studentCode),
          pw.SizedBox(height: 14),
          pw.Text('Performance Summary', style: _h2),
          _kv(
            'Score Obtained',
            data.scoreObtained == null
                ? '--'
                : '${_n(data.scoreObtained)} / ${data.totalMarks.toInt()}',
          ),
          _kv(
            'Accuracy',
            data.accuracyPercentage == null
                ? '--'
                : '${_n(data.accuracyPercentage)}%',
          ),
          _kv('Time Taken', _timeTaken(data.startedAt, data.submittedAt)),
          _kv(
            'Cohort Rank',
            data.rank == null
                ? 'Not published yet'
                : '#${data.rank}${data.totalParticipants != null ? ' of ${data.totalParticipants}' : ''}',
          ),
          if (data.correctCount != null ||
              data.incorrectCount != null ||
              data.unansweredCount != null) ...[
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Text('Correct: ${data.correctCount ?? '--'}', style: _bold),
                pw.SizedBox(width: 16),
                pw.Text('Incorrect: ${data.incorrectCount ?? '--'}', style: _bold),
                pw.SizedBox(width: 16),
                pw.Text('Unanswered: ${data.unansweredCount ?? '--'}', style: _bold),
              ],
            ),
          ],
          if (data.marksPerQuestion != null || data.negativeMarks != null) ...[
            pw.SizedBox(height: 6),
            _kv('Marks per question', data.marksPerQuestion == null ? '--' : _n(data.marksPerQuestion)),
            _kv('Negative marking', data.negativeMarks == null ? '--' : _n(data.negativeMarks)),
          ],
          if (topicMastery.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Topic Mastery Breakdown', style: _h2),
            pw.SizedBox(height: 6),
            _table(
              ['Topic', 'Attempted', 'Correct', 'Accuracy', 'Status'],
              [
                for (final t in strong)
                  [t.name, '${t.attempted}', '${t.correct}', '${_n(t.accuracy)}%', 'Strong'],
                for (final t in revision)
                  [t.name, '${t.attempted}', '${t.correct}', '${_n(t.accuracy)}%', 'Needs Revision'],
              ],
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Score, accuracy and rank are computed and verified on the server. '
            'This report never recomputes or estimates them.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _n(num? v) {
    if (v == null) return '--';
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  static String _timeTaken(DateTime? started, DateTime? submitted) {
    if (started == null || submitted == null) return '--';
    final d = submitted.difference(started);
    if (d.isNegative) return '--';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  static String _dateTime(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year} ${two(l.hour)}:${two(l.minute)}';
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
}

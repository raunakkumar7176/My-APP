import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show TextStyle, FontWeight, FontStyle, Color, Colors, TextSpan;
import 'package:flutter/painting.dart' show TextPainter, TextDirection;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Candidate identification details for the official assessment report.
class ExamReportCandidateInfo {
  const ExamReportCandidateInfo({
    required this.fullName,
    required this.studentCode,
  });

  final String fullName;
  final String studentCode;
}

/// Metadata describing the evaluated examination.
class ExamReportTestMetadata {
  const ExamReportTestMetadata({
    required this.testTitle,
    required this.attemptDate,
    this.duration,
    this.timeTaken,
  });

  final String testTitle;
  final DateTime attemptDate;
  final Duration? duration;
  final Duration? timeTaken;
}

/// Summary scorecard metrics displayed in the performance matrix.
class ExamReportScorecard {
  const ExamReportScorecard({
    required this.totalQuestions,
    required this.attempted,
    required this.correct,
    required this.incorrect,
    required this.skipped,
    required this.totalMarks,
    this.maxMarks,
    required this.percentage,
    required this.accuracy,
    this.timeTaken,
  });

  final int totalQuestions;
  final int attempted;
  final int correct;
  final int incorrect;
  final int skipped;
  final double totalMarks;
  final double? maxMarks;
  final double percentage;
  final double accuracy;
  final Duration? timeTaken;
}

/// A single question with the student's marked answer, evaluation, and explanation.
class ExamReportQuestionResponse {
  const ExamReportQuestionResponse({
    required this.index,
    required this.questionText,
    required this.options,
    this.userOption,
    this.correctOption,
    this.isCorrect,
    this.explanation,
  });

  final int index;
  final String questionText;
  final List<String> options;
  final String? userOption;
  final String? correctOption;
  final bool? isCorrect;
  final String? explanation;
}

class _DevanagariRenderResult {
  const _DevanagariRenderResult({
    required this.image,
    required this.width,
    required this.height,
  });

  final pw.MemoryImage image;
  final double width;
  final double height;
}

/// Generates a comprehensive, consolidated 2-column examination report card PDF
/// with full Devanagari (Hindi) font support and a subtle app logo watermark.
abstract final class ExamReportPdfGenerator {
  static const List<String> _devanagariFontFallbacks = [
    'NotoSansDevanagari',
    'Noto Sans Devanagari',
    'Nirmala UI',
    'Mangal',
  ];

  /// Checks whether a string contains Devanagari Unicode codepoints (U+0900..U+097F).
  static bool hasDevanagari(String text) =>
      RegExp(r'[\u0900-\u097F]').hasMatch(text);

  /// Renders a Flutter [TextSpan] containing complex Devanagari script via
  /// Flutter's native HarfBuzz text shaping engine to a crisp high-DPI image.
  static Future<_DevanagariRenderResult?> _renderSpanToPng(
    TextSpan span, {
    required double maxWidth,
    double pixelRatio = 3.0,
  }) async {
    try {
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: maxWidth);

      final width = (tp.width * pixelRatio).ceil().clamp(1, 4000);
      final height = (tp.height * pixelRatio).ceil().clamp(1, 4000);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(pixelRatio, pixelRatio);
      tp.paint(canvas, ui.Offset.zero);

      final picture = recorder.endRecording();
      final img = await picture.toImage(width, height);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      return _DevanagariRenderResult(
        image: pw.MemoryImage(byteData.buffer.asUint8List()),
        width: tp.width,
        height: tp.height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Builds a Devanagari-aware text widget that uses the native-rendered image
  /// for visual rendering (fixing misplaced matras and broken conjuncts) while
  /// maintaining an invisible text layer for copy/search and semantic tests.
  static Future<pw.Widget?> _prepareTextWidget({
    required String text,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    Color color = Colors.black,
    required double maxWidth,
  }) async {
    final span = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: color,
        fontFamily: 'NotoSansDevanagari',
        fontFamilyFallback: _devanagariFontFallbacks,
      ),
    );
    final rendered = await _renderSpanToPng(span, maxWidth: maxWidth);
    if (rendered == null) return null;

    final rawTextWidget = pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight == FontWeight.bold
            ? pw.FontWeight.bold
            : pw.FontWeight.normal,
        fontStyle: fontStyle == FontStyle.italic
            ? pw.FontStyle.italic
            : pw.FontStyle.normal,
      ),
    );

    return pw.Stack(
      children: [
        pw.Image(rendered.image, width: rendered.width, height: rendered.height),
        pw.Positioned.fill(
          child: pw.Opacity(opacity: 0, child: rawTextWidget),
        ),
      ],
    );
  }

  /// Bundled Noto Sans Devanagari TTFs — used first so Hindi/Bilingual text
  /// never falls back to a font without Devanagari glyphs (the "dabba" bug).
  static const String _regularAssetPath =
      'assets/fonts/NotoSansDevanagari-Regular.ttf';
  static const String _boldAssetPath =
      'assets/fonts/NotoSansDevanagari-Bold.ttf';

  /// Bundled asset → Google Fonts download → Helvetica (last resort).
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
      // PdfGoogleFonts swallows network failures and hands back a Type1
      // Helvetica, which has no Devanagari glyphs — reject it.
      if (downloaded is pw.TtfFont) return downloaded;
    } catch (_) {
      // Offline: fall through to the last resort.
    }
    return fallback();
  }

  /// Generates the raw PDF bytes for the report card.
  static Future<Uint8List> generate({
    required ExamReportCandidateInfo candidateInfo,
    required ExamReportTestMetadata testMetadata,
    required ExamReportScorecard testResult,
    required List<ExamReportQuestionResponse> testQuestionsWithResponses,
    pw.MemoryImage? logoImage,
    pw.Font? fontRegular,
    pw.Font? fontBold,
  }) async {
    // 1. Initialize Devanagari fonts to prevent square boxes ('dabba') for
    //    Hindi/Bilingual content. Priority: explicitly supplied fonts →
    //    bundled TTF assets (offline safe) → Google Fonts download →
    //    Helvetica last resort.
    final regular =
        fontRegular ??
        await _loadFont(
          assetPath: _regularAssetPath,
          remote: PdfGoogleFonts.notoSansDevanagariRegular,
          fallback: pw.Font.helvetica,
        );
    final bold =
        fontBold ??
        await _loadFont(
          assetPath: _boldAssetPath,
          remote: PdfGoogleFonts.notoSansDevanagariBold,
          fallback: pw.Font.helveticaBold,
        );

    // Noto Sans Devanagari ships no italic cuts; pointing the italic styles
    // at the same TTF keeps Hindi explanations from degrading to
    // Helvetica-Oblique (which cannot draw Devanagari at all).
    final pdfTheme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    );

    // 2. Load branding logo if not supplied
    pw.MemoryImage? logo = logoImage;
    if (logo == null) {
      try {
        final byteData = await rootBundle.load('assets/branding/logo.png');
        logo = pw.MemoryImage(byteData.buffer.asUint8List());
      } catch (_) {
        logo = null;
      }
    }

    final doc = pw.Document(
      title: '${testMetadata.testTitle} — Assessment Report Card',
      author: 'My Preparation',
    );

    // Pre-render any Devanagari text using HarfBuzz for 100% accurate ligatures & matras
    final candidateNameWidget = hasDevanagari(candidateInfo.fullName)
        ? await _prepareTextWidget(
            text: candidateInfo.fullName,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            maxWidth: 125,
          )
        : null;

    final testTitleWidget = hasDevanagari(testMetadata.testTitle)
        ? await _prepareTextWidget(
            text: testMetadata.testTitle,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            maxWidth: 125,
          )
        : null;

    final runningHeaderWidget = hasDevanagari(testMetadata.testTitle)
        ? await _prepareTextWidget(
            text: '${testMetadata.testTitle} • Student: ${candidateInfo.studentCode}',
            fontSize: 7.5,
            color: const Color(0xFF757575),
            maxWidth: 250,
          )
        : null;

    final questionCards = <pw.Widget>[];
    for (final q in testQuestionsWithResponses) {
      questionCards.add(await _buildQuestionCard(q));
    }

    // 3. MultiPage layout with subtle watermark (opacity 0.06) on every page
    doc.addPage(
      pw.MultiPage(
        // MultiPage has no `buildBackground` parameter; the per-page
        // watermark layer is provided through PageTheme instead.
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          theme: pdfTheme,
          buildBackground: (pw.Context context) {
            final watermark = logo;
            if (watermark == null) return pw.SizedBox();
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Center(
                child: pw.Opacity(
                  opacity: 0.06, // Ultra-subtle: zero interference with text
                  child: pw.Image(watermark, width: 320, height: 320),
                ),
              ),
            );
          },
        ),
        header: (pw.Context context) => _buildPdfHeader(
          context,
          testMetadata,
          candidateInfo,
          logo,
          candidateNameWidget: candidateNameWidget,
          testTitleWidget: testTitleWidget,
          runningHeaderWidget: runningHeaderWidget,
        ),
        footer: (pw.Context context) => _buildPdfFooter(context),
        build: (pw.Context context) => [
          _buildScorecardSummaryCard(testResult),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 1.2, color: PdfColors.grey400),
          pw.SizedBox(height: 10),
          _buildTwoColumnQuestionsSection(questionCards),
          _buildVerdictNote(testQuestionsWithResponses),
        ],
      ),
    );

    return doc.save();
  }

  /// Saves the report PDF bytes to a local document file using path_provider.
  static Future<File> saveToLocalFile(Uint8List bytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  // ── Header Section ──

  static pw.Widget _buildPdfHeader(
    pw.Context context,
    ExamReportTestMetadata testMetadata,
    ExamReportCandidateInfo candidateInfo,
    pw.ImageProvider? logoImage, {
    pw.Widget? candidateNameWidget,
    pw.Widget? testTitleWidget,
    pw.Widget? runningHeaderWidget,
  }) {
    if (context.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 16, height: 16),
                  pw.SizedBox(width: 6),
                ],
                pw.Text(
                  'MY PREPARATION — OFFICIAL ASSESSMENT REPORT',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ],
            ),
            runningHeaderWidget ??
                pw.Text(
                  '${testMetadata.testTitle} • Student: ${candidateInfo.studentCode}',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey600,
                  ),
                ),
          ],
        ),
      );
    }

    // Page 1 Assessment Header
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Top Row: App logo (40x40), title, and generation timestamp
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, width: 40, height: 40)
                  else
                    pw.Container(
                      width: 40,
                      height: 40,
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue900,
                        shape: pw.BoxShape.circle,
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'MP',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MY PREPARATION — OFFICIAL ASSESSMENT REPORT',
                        style: const pw.TextStyle(
                          fontSize: 12.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Standardized Academic Performance Evaluation & Question Analysis',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Generated: ${_formatDate(DateTime.now())}',
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    _formatTime(DateTime.now()),
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),

          // Candidate Details Row
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _detailCell('Student Name', candidateInfo.fullName, candidateNameWidget),
                _detailCell('Student Code', candidateInfo.studentCode),
                _detailCell('Test Title', testMetadata.testTitle, testTitleWidget),
                _detailCell(
                  'Date Attempted',
                  _formatDate(testMetadata.attemptDate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _detailCell(
    String label,
    String value, [
    pw.Widget? customWidget,
  ]) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: PdfColors.grey600,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          customWidget ??
              pw.Text(
                value.isEmpty ? '--' : value,
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                maxLines: 1,
              ),
        ],
      ),
    );
  }

  // ── Scorecard Summary Matrix ──

  static pw.Widget _buildScorecardSummaryCard(ExamReportScorecard testResult) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PERFORMANCE MATRIX',
            style: const pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _metricBox('Total Qs', '${testResult.totalQuestions}'),
              pw.SizedBox(width: 4),
              _metricBox('Attempted', '${testResult.attempted}'),
              pw.SizedBox(width: 4),
              _metricBox(
                'Correct',
                '${testResult.correct}',
                valColor: PdfColors.green700,
                bgColor: PdfColors.green50,
              ),
              pw.SizedBox(width: 4),
              _metricBox(
                'Incorrect',
                '${testResult.incorrect}',
                valColor: PdfColors.red700,
                bgColor: PdfColors.red50,
              ),
              pw.SizedBox(width: 4),
              _metricBox(
                'Skipped',
                '${testResult.skipped}',
                valColor: PdfColors.grey700,
              ),
              pw.SizedBox(width: 4),
              _metricBox(
                'Total Marks',
                testResult.maxMarks != null
                    ? '${_num(testResult.totalMarks)}/${_num(testResult.maxMarks)}'
                    : _num(testResult.totalMarks),
                valColor: PdfColors.blue800,
              ),
              pw.SizedBox(width: 4),
              _metricBox(
                'Percentage',
                '${testResult.percentage.toStringAsFixed(1)}%',
              ),
              pw.SizedBox(width: 4),
              _metricBox(
                'Accuracy %',
                '${testResult.accuracy.toStringAsFixed(1)}%',
                valColor: PdfColors.teal700,
              ),
              pw.SizedBox(width: 4),
              _metricBox('Time Taken', _formatDuration(testResult.timeTaken)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricBox(
    String label,
    String value, {
    PdfColor? valColor,
    PdfColor? bgColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: pw.BoxDecoration(
          color: bgColor ?? PdfColors.grey50,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
        ),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: valColor ?? PdfColors.black,
              ),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 6.5,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // ── Two-Column Questions Section (Left first, then Right) ──

  static pw.Widget _buildTwoColumnQuestionsSection(
    List<pw.Widget> questionCards,
  ) {
    if (questionCards.isEmpty) {
      return pw.Center(
        child: pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Text(
            'No question analysis available.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      );
    }

    // Balanced 2-column distribution: flow down left column first, then right column
    final half = (questionCards.length + 1) ~/ 2;
    final leftList = questionCards.sublist(0, half);
    final rightList = questionCards.sublist(half);

    final rows = <pw.Widget>[];

    for (var i = 0; i < half; i++) {
      final leftCard = leftList[i];
      final rightCard = i < rightList.length ? rightList[i] : null;

      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left Column: 48% width with 1px subtle grey right divider
              pw.Expanded(
                flex: 48,
                child: pw.Container(
                  padding: const pw.EdgeInsets.only(right: 8),
                  margin: const pw.EdgeInsets.only(right: 6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.grey300, width: 1),
                    ),
                  ),
                  child: leftCard,
                ),
              ),
              // Right Column: 48% width
              pw.Expanded(
                flex: 48,
                child: rightCard != null
                    ? pw.Container(
                        padding: const pw.EdgeInsets.only(left: 2),
                        child: rightCard,
                      )
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );

      // Light dashed divider between consecutive questions in the column
      if (i < half - 1) {
        rows.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Divider(
              thickness: 0.5,
              color: PdfColors.grey300,
              borderStyle: pw.BorderStyle.dashed,
            ),
          ),
        );
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// Evaluates one response: an explicit [ExamReportQuestionResponse.isCorrect]
  /// wins, otherwise the answer is compared through normalised option indices.
  /// Returns null when the answer key is unavailable — never a guess.
  static bool? _verdict(ExamReportQuestionResponse item) {
    final given = item.isCorrect;
    if (given != null) return given;
    final userIndex = parseOptionIndex(item.userOption);
    final correctIndex = parseOptionIndex(item.correctOption);
    if (userIndex == null || correctIndex == null) return null;
    return userIndex == correctIndex;
  }

  /// Footnote shown only when an attempted question has no answer key, so a
  /// reader knows a verdict is missing rather than assuming it was wrong.
  static pw.Widget _buildVerdictNote(List<ExamReportQuestionResponse> items) {
    final unkeyed = items.any((q) {
      final raw = q.userOption?.trim();
      if (raw == null || raw.isEmpty) return false;
      return _verdict(q) == null;
    });
    if (!unkeyed) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Answer key is not part of this report — per-question verdicts '
        'appear only where the key is available. Scorecard totals are '
        'server-computed.',
        style: const pw.TextStyle(
          fontSize: 7,
          fontStyle: pw.FontStyle.italic,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  /// Label for an option index: 0 → 'A', 1 → 'B', … (>= 26 falls back to a
  /// 1-based number so a fifth+ option still has a stable name).
  static String optionLetter(int idx) {
    if (idx >= 0 && idx < 26) return String.fromCharCode(65 + idx);
    return '${idx + 1}';
  }

  /// Normalises any stored answer representation to a 0-based option index.
  ///
  /// The same logical answer arrives shaped differently depending on the
  /// layer: `answers.selected_option` is a 0-based int, older payloads used
  /// 1-based ints, and the review/PDF layer spells it as a letter
  /// ('A'..'D'). Comparing those raw values is what made every attempted
  /// question print `[INCORRECT]` while the scorecard counted it correct.
  static int? parseOptionIndex(Object? value) {
    if (value == null) return null;
    // The stored `answers.selected_option` shape: already a 0-based index.
    if (value is num) return value.toInt();
    final raw = value.toString().trim().toUpperCase();
    if (raw.isEmpty) return null;
    switch (raw) {
      case 'A':
        return 0;
      case 'B':
        return 1;
      case 'C':
        return 2;
      case 'D':
        return 3;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) return null;
    // Strings are the ambiguous layer: 1..4 read as a 1-based index, 0 and
    // 5+ as-is.
    return (parsed >= 1 && parsed <= 4) ? parsed - 1 : parsed;
  }

  /// Colour contract: green #16A34A for a correct answer, red #DC2626 for a
  /// wrong one, and a subtle dark green #15803D for the answer key itself.
  static const PdfColor _correctColor = PdfColor.fromInt(0xff16a34a);
  static const PdfColor _incorrectColor = PdfColor.fromInt(0xffdc2626);
  static const PdfColor _answerKeyColor = PdfColor.fromInt(0xff15803d);

  static Future<pw.Widget> _buildQuestionCard(ExamReportQuestionResponse item) async {
    final options = item.options;
    final rawUser = item.userOption?.trim();
    final isAttempted = rawUser != null && rawUser.isNotEmpty;
    final userIndex = parseOptionIndex(item.userOption);
    final correctIndex = parseOptionIndex(item.correctOption);

    final verdict = _verdict(item);

    String label(int? index, String? raw) {
      if (index != null && index >= 0 && index < options.length) {
        return '(${optionLetter(index)}) ${options[index]}';
      }
      final r = raw?.trim();
      return (r == null || r.isEmpty) ? '--' : '($r)';
    }

    pw.TextSpan plain(String text) => pw.TextSpan(
      text: text,
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    );

    // 1. Question Number & Text
    final qNumber = 'Q${item.index + 1}. ';
    final qText = item.questionText;
    final rawQuestionWidget = pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: qNumber,
            style: const pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.TextSpan(
            text: qText,
            style: const pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey900,
            ),
          ),
        ],
      ),
    );

    pw.Widget questionWidget = rawQuestionWidget;
    if (hasDevanagari(qText)) {
      final span = TextSpan(
        children: [
          TextSpan(
            text: qNumber,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontFamily: 'NotoSansDevanagari',
              fontFamilyFallback: _devanagariFontFallbacks,
            ),
          ),
          TextSpan(
            text: qText,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
              fontFamily: 'NotoSansDevanagari',
              fontFamilyFallback: _devanagariFontFallbacks,
            ),
          ),
        ],
      );
      final rendered = await _renderSpanToPng(span, maxWidth: 255);
      if (rendered != null) {
        questionWidget = pw.Stack(
          children: [
            pw.Image(rendered.image, width: rendered.width, height: rendered.height),
            pw.Positioned.fill(
              child: pw.Opacity(opacity: 0, child: rawQuestionWidget),
            ),
          ],
        );
      }
    }

    // 2. Options List
    final optionWidgets = <pw.Widget>[];
    for (var i = 0; i < options.length; i++) {
      final optLetter = '(${optionLetter(i)}) ';
      final optText = options[i];
      final rawOptWidget = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            optLetter,
            style: const pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              optText,
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey800,
              ),
            ),
          ),
        ],
      );

      if (hasDevanagari(optText)) {
        final span = TextSpan(
          children: [
            TextSpan(
              text: optLetter,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Color(0xFF424242),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            TextSpan(
              text: optText,
              style: const TextStyle(
                fontSize: 8,
                color: Color(0xFF424242),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 255);
        if (rendered != null) {
          optionWidgets.add(
            pw.Stack(
              children: [
                pw.Image(rendered.image, width: rendered.width, height: rendered.height),
                pw.Positioned.fill(
                  child: pw.Opacity(opacity: 0, child: rawOptWidget),
                ),
              ],
            ),
          );
        } else {
          optionWidgets.add(rawOptWidget);
        }
      } else {
        optionWidgets.add(rawOptWidget);
      }
    }

    // 3. Candidate Response Analysis
    final hasDevanagariInResponse = options.any(hasDevanagari) ||
        hasDevanagari(rawUser ?? '') ||
        hasDevanagari(item.correctOption ?? '');

    late final pw.Widget response;
    if (!isAttempted) {
      final hasKey =
          correctIndex != null || (item.correctOption?.trim().isNotEmpty ?? false);
      final rawResp = pw.RichText(
        text: pw.TextSpan(
          children: [
            plain('Status: '),
            plain('Not Attempted'),
            if (hasKey) ...[
              plain(' | Correct Answer: '),
              pw.TextSpan(
                text: label(correctIndex, item.correctOption),
                style: const pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _answerKeyColor,
                ),
              ),
            ],
          ],
        ),
      );

      if (hasDevanagariInResponse) {
        final span = TextSpan(
          children: [
            const TextSpan(
              text: 'Status: Not Attempted',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF616161),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            if (hasKey) ...[
              const TextSpan(
                text: ' | Correct Answer: ',
                style: TextStyle(
                  fontSize: 8,
                  color: Color(0xFF616161),
                  fontFamily: 'NotoSansDevanagari',
                  fontFamilyFallback: _devanagariFontFallbacks,
                ),
              ),
              TextSpan(
                text: label(correctIndex, item.correctOption),
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF15803D),
                  fontFamily: 'NotoSansDevanagari',
                  fontFamilyFallback: _devanagariFontFallbacks,
                ),
              ),
            ],
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 255);
        if (rendered != null) {
          response = pw.Stack(
            children: [
              pw.Image(rendered.image, width: rendered.width, height: rendered.height),
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0, child: rawResp),
              ),
            ],
          );
        } else {
          response = rawResp;
        }
      } else {
        response = rawResp;
      }
    } else if (verdict == true) {
      final rawResp = pw.RichText(
        text: pw.TextSpan(
          children: [
            plain('Your Answer: '),
            pw.TextSpan(
              text: '${label(userIndex, rawUser)} [CORRECT]',
              style: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _correctColor,
              ),
            ),
          ],
        ),
      );

      if (hasDevanagariInResponse) {
        final span = TextSpan(
          children: [
            const TextSpan(
              text: 'Your Answer: ',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF616161),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            TextSpan(
              text: '${label(userIndex, rawUser)} [CORRECT]',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Color(0xFF16A34A),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 255);
        if (rendered != null) {
          response = pw.Stack(
            children: [
              pw.Image(rendered.image, width: rendered.width, height: rendered.height),
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0, child: rawResp),
              ),
            ],
          );
        } else {
          response = rawResp;
        }
      } else {
        response = rawResp;
      }
    } else if (verdict == false) {
      final hasKey =
          correctIndex != null || (item.correctOption?.trim().isNotEmpty ?? false);
      final rawResp = pw.RichText(
        text: pw.TextSpan(
          children: [
            plain('Your Answer: '),
            pw.TextSpan(
              text: '${label(userIndex, rawUser)} [INCORRECT]',
              style: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _incorrectColor,
              ),
            ),
            if (hasKey) ...[
              plain('   Correct Answer: '),
              pw.TextSpan(
                text: label(correctIndex, item.correctOption),
                style: const pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _correctColor,
                ),
              ),
            ],
          ],
        ),
      );

      if (hasDevanagariInResponse) {
        final span = TextSpan(
          children: [
            const TextSpan(
              text: 'Your Answer: ',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF616161),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            TextSpan(
              text: '${label(userIndex, rawUser)} [INCORRECT]',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Color(0xFFDC2626),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            if (hasKey) ...[
              const TextSpan(
                text: '   Correct Answer: ',
                style: TextStyle(
                  fontSize: 8,
                  color: Color(0xFF616161),
                  fontFamily: 'NotoSansDevanagari',
                  fontFamilyFallback: _devanagariFontFallbacks,
                ),
              ),
              TextSpan(
                text: label(correctIndex, item.correctOption),
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A),
                  fontFamily: 'NotoSansDevanagari',
                  fontFamilyFallback: _devanagariFontFallbacks,
                ),
              ),
            ],
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 255);
        if (rendered != null) {
          response = pw.Stack(
            children: [
              pw.Image(rendered.image, width: rendered.width, height: rendered.height),
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0, child: rawResp),
              ),
            ],
          );
        } else {
          response = rawResp;
        }
      } else {
        response = rawResp;
      }
    } else {
      final rawResp = pw.RichText(
        text: pw.TextSpan(
          children: [
            plain('Your Answer: '),
            pw.TextSpan(
              text: label(userIndex, rawUser),
              style: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ],
        ),
      );

      if (hasDevanagariInResponse) {
        final span = TextSpan(
          children: [
            const TextSpan(
              text: 'Your Answer: ',
              style: TextStyle(
                fontSize: 8,
                color: Color(0xFF616161),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            TextSpan(
              text: label(userIndex, rawUser),
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 255);
        if (rendered != null) {
          response = pw.Stack(
            children: [
              pw.Image(rendered.image, width: rendered.width, height: rendered.height),
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0, child: rawResp),
              ),
            ],
          );
        } else {
          response = rawResp;
        }
      } else {
        response = rawResp;
      }
    }

    // 4. Solution / Explanation Note
    pw.Widget? explanationWidget;
    if (item.explanation != null && item.explanation!.trim().isNotEmpty) {
      final expText = item.explanation!.trim();
      final rawExpContent = pw.RichText(
        text: pw.TextSpan(
          children: [
            const pw.TextSpan(
              text: 'Explanation: ',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey800,
              ),
            ),
            pw.TextSpan(
              text: expText,
              style: const pw.TextStyle(
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      );

      pw.Widget expInner = rawExpContent;
      if (hasDevanagari(expText)) {
        final span = TextSpan(
          children: [
            const TextSpan(
              text: 'Explanation: ',
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                color: Color(0xFF424242),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
            TextSpan(
              text: expText,
              style: const TextStyle(
                fontSize: 7.5,
                fontStyle: FontStyle.italic,
                color: Color(0xFF616161),
                fontFamily: 'NotoSansDevanagari',
                fontFamilyFallback: _devanagariFontFallbacks,
              ),
            ),
          ],
        );
        final rendered = await _renderSpanToPng(span, maxWidth: 239);
        if (rendered != null) {
          expInner = pw.Stack(
            children: [
              pw.Image(rendered.image, width: rendered.width, height: rendered.height),
              pw.Positioned.fill(
                child: pw.Opacity(opacity: 0, child: rawExpContent),
              ),
            ],
          );
        }
      }

      explanationWidget = pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: const pw.BoxDecoration(
          color: PdfColors.grey50,
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.blue300, width: 2),
          ),
        ),
        child: expInner,
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        questionWidget,
        pw.SizedBox(height: 5),
        if (optionWidgets.isNotEmpty) ...[
          for (final optW in optionWidgets)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2.5),
              child: optW,
            ),
          pw.SizedBox(height: 4),
        ],
        response,
        if (explanationWidget != null) ...[
          pw.SizedBox(height: 4),
          explanationWidget,
        ],
      ],
    );
  }

  // ── Footer Section ──

  static pw.Widget _buildPdfFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by My Preparation App • Server Verified Report',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ── Utility Formatters ──

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  /// `12s` / `42m 10s` — the matrix cell always shows the real duration.
  static String _formatDuration(Duration? d) {
    if (d == null) return '--';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  static String _num(double? n) {
    if (n == null) return '--';
    return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(1);
  }
}

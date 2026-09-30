// Quality checks for the consolidated exam report card PDF:
// Devanagari glyphs actually embedded (no 'dabba' squares), the ultra-subtle
// centred logo watermark on every page, and the left-column-first flow.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/services/pdf/exam_report_pdf_generator.dart';

// ── minimal PDF reader (enough for this document) ────────────────────────

List<int> _inflate(List<int> bytes, int start, int end) {
  var raw = bytes.sublist(start, end);
  while (raw.isNotEmpty && (raw.last == 0x0A || raw.last == 0x0D)) {
    raw = raw.sublist(0, raw.length - 1);
  }
  return const ZLibDecoder().decodeBytes(raw);
}

typedef _Matrix = List<double>; // [a b c d e f]

_Matrix _mul(_Matrix m1, _Matrix m2) => [
  m1[0] * m2[0] + m1[1] * m2[2],
  m1[0] * m2[1] + m1[1] * m2[3],
  m1[2] * m2[0] + m1[3] * m2[2],
  m1[2] * m2[1] + m1[3] * m2[3],
  m1[4] * m2[0] + m1[5] * m2[2] + m2[4],
  m1[4] * m2[1] + m1[5] * m2[3] + m2[5],
];

const _identity = <double>[1, 0, 0, 1, 0, 0];
const _whitespace = {' ', '\n', '\r', '\t'};

class TextRun {
  TextRun(this.page, this.x, this.y, this.fontSize, this.text);
  final int page;
  final double x;
  final double y;
  final double fontSize;
  final String text;
  @override
  String toString() =>
      'p$page (${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}) $fontSize "$text"';
}

List<String> _tokens(String src) {
  final out = <String>[];
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (_whitespace.contains(c)) {
      i++;
      continue;
    }
    if (c == '[' || c == ']') {
      out.add(c);
      i++;
      continue;
    }
    if (c == '<') {
      final end = src.indexOf('>', i);
      if (end < 0) break;
      out.add(src.substring(i, end + 1));
      i = end + 1;
      continue;
    }
    if (c == '(') {
      final start = i;
      var depth = 0;
      while (i < src.length) {
        if (src[i] == r'\') {
          i += 2;
          continue;
        }
        if (src[i] == '(') depth++;
        if (src[i] == ')') {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        i++;
      }
      out.add(src.substring(start, i));
      continue;
    }
    final start = i;
    while (i < src.length && !_whitespace.contains(src[i])) {
      i++;
    }
    out.add(src.substring(start, i));
  }
  return out;
}

List<TextRun> _decodeContent(
  String src,
  int page,
  Map<String, Map<String, String>> unicode,
) {
  final runs = <TextRun>[];
  final stack = <_Matrix>[];
  var ctm = List<double>.from(_identity);
  var tm = List<double>.from(_identity);
  var font = '';
  var size = 0.0;
  final operands = <String>[];

  void show(String raw) {
    final map = unicode[font];
    final buf = StringBuffer();
    if (raw.contains('(')) {
      buf.write(raw.substring(raw.indexOf('(') + 1, raw.lastIndexOf(')')));
    } else {
      final hex = raw.replaceAll(RegExp('[^0-9A-Fa-f]'), '');
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        buf.write(map?[hex.substring(i, i + 4).toUpperCase()] ?? '');
      }
    }
    final text = buf.toString();
    if (text.isEmpty) return;
    final m = _mul(ctm, tm);
    runs.add(TextRun(page, m[4], m[5], size, text));
  }

  for (final t in _tokens(src)) {
    final isOperator =
        !t.startsWith('/') &&
        !RegExp(r'^[-+0-9.]').hasMatch(t) &&
        !t.startsWith('[') &&
        !t.startsWith('<') &&
        !t.startsWith('(') &&
        t != ']' &&
        t != '>';
    if (!isOperator) {
      operands.add(t);
      continue;
    }
    switch (t) {
      case 'q':
        stack.add(List<double>.from(ctm));
      case 'Q':
        if (stack.isNotEmpty) ctm = stack.removeLast();
      case 'cm':
        ctm = _mul(operands.map(double.parse).toList(), ctm);
      case 'BT':
        tm = List<double>.from(_identity);
      case 'Tf':
        font = operands.first.replaceFirst('/', '');
        size = double.tryParse(operands[1]) ?? 0;
      case 'Td':
      case 'TD':
        tm = _mul([
          1,
          0,
          0,
          1,
          double.parse(operands[0]),
          double.parse(operands[1]),
        ], tm);
      case 'Tm':
        tm = operands.map(double.parse).toList();
      case 'Tj':
      case 'TJ':
      case "'":
        show(operands.join());
      default:
        break;
    }
    operands.clear();
  }
  return runs;
}

class Report {
  Report(this.bytes, this.pageRuns, this.pageContents);
  final Uint8List bytes;
  final List<List<TextRun>> pageRuns;
  final List<String> pageContents;

  String get raw => String.fromCharCodes(bytes);

  String get allText => pageRuns
      .expand((r) => r)
      .map((r) => r.text)
      .join()
      .replaceAll(RegExp(r'\s+'), '');
}

String _object(String s, int n) {
  final start = s.indexOf(RegExp('(?<!\\d)$n 0 obj'));
  if (start < 0) return '';
  final end = s.indexOf('endobj', start);
  if (end < 0) return '';
  return s.substring(start, end);
}

Report _read(Uint8List bytes) {
  final s = String.fromCharCodes(bytes);

  // Decoded streams keyed by object number. The dictionary pattern refuses
  // to cross a `>>` so it can never bleed into the next object.
  final streams = <int, String>{};
  final streamRe = RegExp(
    r'(\d+)\s+0\s+obj\s*<<((?:(?!>>)[\s\S])*)>>\s*stream\r?\n',
  );
  for (final m in streamRe.allMatches(s)) {
    if (!m.group(2)!.contains('FlateDecode')) continue;
    final start = m.end;
    final end = s.indexOf('endstream', start);
    if (end < 0) continue;
    try {
      streams[int.parse(m.group(1)!)] = String.fromCharCodes(
        _inflate(bytes, start, end),
      );
    } catch (_) {}
  }

  // Resource name (/F6) → font object → ToUnicode CMap object.
  final unicode = <String, Map<String, String>>{};
  for (final res in RegExp(r'/Font\s*<<(.*?)>>', dotAll: true).allMatches(s)) {
    for (final f in RegExp(
      r'/(F\d+)\s+(\d+)\s+0\s+R',
    ).allMatches(res.group(1)!)) {
      final fontObj = _object(s, int.parse(f.group(2)!));
      final uni = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(fontObj);
      if (uni == null) continue;
      final cmap = streams[int.parse(uni.group(1)!)];
      if (cmap == null) continue;
      unicode[f.group(1)!] = _parseCmap(cmap);
    }
  }

  // Page order via /Kids, then each page's content stream.
  final kids = RegExp(r'/Kids\s*\[(.*?)\]', dotAll: true).firstMatch(s);
  final pageContents = <String>[];
  if (kids != null) {
    for (final k in RegExp(r'(\d+)\s+0\s+R').allMatches(kids.group(1)!)) {
      final pageObj = _object(s, int.parse(k.group(1)!));
      final c = RegExp(r'/Contents\s+(\d+)\s+0\s+R').firstMatch(pageObj);
      if (c == null) continue;
      final content = streams[int.parse(c.group(1)!)];
      if (content != null) pageContents.add(content);
    }
  }

  final pageRuns = [
    for (var i = 0; i < pageContents.length; i++)
      _decodeContent(pageContents[i], i + 1, unicode),
  ];
  return Report(bytes, pageRuns, pageContents);
}

Map<String, String> _parseCmap(String cmap) {
  final map = <String, String>{};

  String decode(String hex) {
    final out = StringBuffer();
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      final cp = int.parse(hex.substring(i, i + 4), radix: 16);
      if (cp != 0) out.write(String.fromCharCode(cp));
    }
    return out.toString();
  }

  for (final b in RegExp(
    r'\d+\s+beginbfchar(.*?)endbfchar',
    dotAll: true,
  ).allMatches(cmap)) {
    for (final m in RegExp(
      r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]+)>',
    ).allMatches(b.group(1)!)) {
      map[m.group(1)!.toUpperCase()] = decode(m.group(2)!);
    }
  }
  for (final b in RegExp(
    r'\d+\s+beginbfrange(.*?)endbfrange',
    dotAll: true,
  ).allMatches(cmap)) {
    for (final m in RegExp(
      r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]+)>',
    ).allMatches(b.group(1)!)) {
      final lo = int.parse(m.group(1)!, radix: 16);
      final hi = int.parse(m.group(2)!, radix: 16);
      final base = int.parse(m.group(3)!, radix: 16);
      for (var c = lo; c <= hi && c - lo < 4096; c++) {
        map[c.toRadixString(16).padLeft(4, '0').toUpperCase()] =
            String.fromCharCode(base + c - lo);
      }
    }
  }
  return map;
}

// ── fixtures ─────────────────────────────────────────────────────────────

const _hindiQuestions = <String>[
  'भारत की राजधानी क्या है?',
  'सूर्य किस दिशा में उगता है?',
  'गंगा नदी किस राज्य से होकर बहती है?',
  'ताजमहल कहाँ स्थित है?',
  'भारतीय संविधान कब लागू हुआ?',
  'प्रसिद्ध नृत्य कथक किस राज्य का है?',
  'हिमालय की सर्वोच्च चोटी कौन सी है?',
  'राष्ट्रगान किसने लिखा?',
  'प्याज का वैज्ञानिक नाम क्या है?',
  'कौन सा ग्रह सबसे बड़ा है?',
  'भारत की सबसे लंबी नदी कौन सी है?',
  'प्रकाश संश्लेषण कहाँ होता है?',
];

List<ExamReportQuestionResponse> _questions() => [
  for (var i = 0; i < _hindiQuestions.length; i++)
    ExamReportQuestionResponse(
      index: i,
      questionText: '${_hindiQuestions[i]} ($i)',
      options: const ['नई दिल्ली', 'मुंबई', 'कोलकाता', 'चेन्नई'],
      userOption: i % 3 == 2 ? null : (i.isEven ? 'A' : 'B'),
      correctOption: 'A',
      isCorrect: i % 3 == 2 ? null : i.isEven,
      explanation: 'समाधान: यह एक साधारण स्पष्टीकरण है। ($i)',
    ),
];

Future<Report> _generate() async {
  final bytes = await ExamReportPdfGenerator.generate(
    candidateInfo: const ExamReportCandidateInfo(
      fullName: 'अमृतांशु आनंद',
      studentCode: 'MP-12345',
    ),
    testMetadata: ExamReportTestMetadata(
      testTitle: 'सामान्य अध्ययन मॉक टेस्ट',
      attemptDate: DateTime(2026, 9, 28),
      duration: const Duration(minutes: 60),
      timeTaken: const Duration(minutes: 42, seconds: 10),
    ),
    testResult: const ExamReportScorecard(
      totalQuestions: 12,
      attempted: 10,
      correct: 7,
      incorrect: 3,
      skipped: 2,
      totalMarks: 14,
      maxMarks: 24,
      percentage: 58.3,
      accuracy: 70.0,
    ),
    testQuestionsWithResponses: _questions(),
  );
  return _read(bytes);
}

TextRun? _marker(List<TextRun> runs, int n) {
  for (final r in runs) {
    if (r.text.startsWith('Q$n.')) return r;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamReportPdfGenerator', () {
    test(
      'bundles Noto Sans Devanagari so Hindi never renders as squares',
      () async {
        final report = await _generate();

        expect(
          report.raw.startsWith('%PDF-'),
          isTrue,
          reason: 'output is not a PDF',
        );
        expect(
          report.raw.contains('NotoSansDevanagari-Regular'),
          isTrue,
          reason: 'Devanagari base font not embedded — Hindi would be squares',
        );
        expect(
          report.raw.contains('NotoSansDevanagari-Bold'),
          isTrue,
          reason: 'Devanagari bold font not embedded',
        );

        for (final q in _hindiQuestions) {
          expect(
            report.allText.contains(q.replaceAll(RegExp(r'\s+'), '')),
            isTrue,
            reason: '"$q" did not round-trip through the PDF text layer',
          );
        }
        expect(report.allText.contains('अमृतांशुआनंद'), isTrue);
        expect(report.allText.contains('सामान्यअध्ययनमॉकटेस्ट'), isTrue);
      },
    );

    test(
      'paints a centred 0.06-opacity logo watermark on every page',
      () async {
        final report = await _generate();

        expect(
          report.raw.contains('/ca 0.06'),
          isTrue,
          reason: 'watermark graphic state must stay at 0.06 opacity',
        );
        expect(report.pageContents.length, greaterThan(1));

        const a4W = 595.27559;
        const a4H = 841.88976;
        const logo = 320.0;
        const expectedX = (a4W - logo) / 2;
        const expectedY = (a4H - logo) / 2;

        for (var p = 0; p < report.pageContents.length; p++) {
          final m = RegExp(
            r'1 0 0 1 ([0-9.]+) ([0-9.]+) cm /\w+ gs q 0 0 320 320 re',
          ).firstMatch(report.pageContents[p]);
          expect(m, isNotNull, reason: 'page ${p + 1} has no watermark layer');
          expect(
            double.parse(m!.group(1)!),
            closeTo(expectedX, 0.5),
            reason: 'page ${p + 1} watermark is not horizontally centred',
          );
          expect(
            double.parse(m.group(2)!),
            closeTo(expectedY, 0.5),
            reason: 'page ${p + 1} watermark is not vertically centred',
          );
        }
      },
    );

    test('fills the left column first, then the right column', () async {
      final report = await _generate();
      final runs = report.pageRuns.expand((r) => r).toList();

      final marks = <int, TextRun>{};
      for (var n = 1; n <= _hindiQuestions.length; n++) {
        final r = _marker(runs, n);
        expect(r, isNotNull, reason: 'question $n marker missing from PDF');
        marks[n] = r!;
      }

      const pageCenter = 595.27559 / 2;
      final split = _hindiQuestions.length ~/ 2;

      for (var n = 1; n <= split; n++) {
        expect(
          marks[n]!.x,
          lessThan(pageCenter),
          reason: 'Q$n should sit in the left column',
        );
      }
      for (var n = split + 1; n <= _hindiQuestions.length; n++) {
        expect(
          marks[n]!.x,
          greaterThan(pageCenter),
          reason: 'Q$n should sit in the right column',
        );
      }

      // Reading order runs top-to-bottom inside each column (y grows up).
      void expectStacked(int from, int to, String column) {
        for (var n = from; n < to; n++) {
          final a = marks[n]!;
          final b = marks[n + 1]!;
          if (a.page != b.page) continue;
          expect(
            a.y,
            greaterThan(b.y),
            reason: 'Q$n must stack above Q${n + 1} in the $column column',
          );
        }
      }

      expectStacked(1, split, 'left');
      expectStacked(split + 1, _hindiQuestions.length, 'right');
    });

    test('carries the scorecard, verdicts and footer', () async {
      final report = await _generate();
      final t = report.allText;

      expect(t.contains('GeneratedbyMyPreparationApp'), isTrue);
      expect(t.contains('Page1of'), isTrue);
      expect(t.contains('PERFORMANCEMATRIX'), isTrue);
      expect(t.contains('OFFICIALASSESSMENTREPORT'), isTrue);
      expect(t.contains('MP-12345'), isTrue);
      expect(t.contains('58.3%'), isTrue);
      expect(t.contains('NotAttempted'), isTrue);
      expect(t.contains('[CORRECT]'), isTrue);
      expect(t.contains('Explanation:'), isTrue);
    });
  });
}

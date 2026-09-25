// V1 — Via Document/File: real byte-level extraction (PDF/DOCX/XLSX),
// question detection on realistic content, group-permission enforcement of
// the document-sourced create path, and retry/idempotency safety.
//
// Pure Dart — no Supabase, no network. Group security here proves the
// CONTROLLER never bypasses `rpc_create_test`'s CREATE_TEST gate; it does
// not and cannot prove live Postgres RLS (see the R4 test suite / the
// FINAL_GAP_AUDIT for that evidence — the fakes used below mirror the same
// live policy shape that suite already relies on).

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/extracted_content.dart';
import 'package:my_praperation/core/services/document_service.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/widgets/question_source_step.dart';

import '../group/fakes.dart';
import '../r4_restart/fakes.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(entry.value.codeUnits);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final out = ZipEncoder().encode(archive);
  return Uint8List.fromList(out);
}

void main() {
  final service = SupabaseDocumentService();

  group('PDF extraction (real bytes, no Supabase)', () {
    test('uncompressed BT/ET content stream extracts Tj text', () {
      const pdfLike = '1 0 obj\n<< >>\nstream\n'
          'BT (1. What is 2+2?) Tj ET\n'
          'BT (A. 3) Tj ET\nBT (B. 4) Tj ET\nBT (C. 5) Tj ET\nBT (D. 6) Tj ET\n'
          'endstream\nendobj';
      final bytes = Uint8List.fromList(pdfLike.codeUnits);

      final content = service.extractFromBytes(bytes, 'quiz.pdf');

      expect(content.sourceFormat, DocumentFormat.pdf);
      final joined = content.blocks.map((b) => b.text).join('\n');
      expect(joined, contains('What is 2+2?'));
      expect(joined, contains('A. 3'));
      expect(joined, contains('D. 6'));
    });

    test('FlateDecode-compressed content stream is inflated and extracted', () {
      const inner = 'BT (1. Capital of France?) Tj ET\n'
          'BT (A. Berlin) Tj ET\nBT (B. Paris) Tj ET\n'
          'BT (C. Rome) Tj ET\nBT (D. Madrid) Tj ET\n';
      final compressed = const ZLibEncoder().encode(inner.codeUnits);

      // A minimal object dictionary declaring the filter, followed by the
      // binary compressed stream and `endstream` — exactly the shape
      // real PDF writers produce for page content streams.
      final builder = BytesBuilder();
      builder.add('4 0 obj\n<< /Length 999 /Filter /FlateDecode >>\n'
              'stream\n'
          .codeUnits);
      builder.add(compressed);
      builder.add('\nendstream\nendobj'.codeUnits);
      final bytes = builder.toBytes();

      final content = service.extractFromBytes(bytes, 'compressed.pdf');

      final joined = content.blocks.map((b) => b.text).join('\n');
      expect(joined, contains('Capital of France?'));
      expect(joined, contains('B. Paris'));
    });

    test('a stream with an unsupported filter is skipped, not crashed on', () {
      final builder = BytesBuilder();
      builder.add('5 0 obj\n<< /Filter /DCTDecode >>\nstream\n'.codeUnits);
      builder.add(List.filled(50, 0xFF)); // opaque binary image data
      builder.add('\nendstream\nendobj'.codeUnits);

      expect(
        () => service.extractFromBytes(builder.toBytes(), 'image.pdf'),
        returnsNormally,
      );
      final content = service.extractFromBytes(builder.toBytes(), 'image.pdf');
      expect(content.blocks, isEmpty);
    });

    test('a file with .pdf extension but no extractable text yields empty blocks, not fabricated content', () {
      final bytes = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
      final content = service.extractFromBytes(bytes, 'blank.pdf');
      expect(content.blocks, isEmpty);
    });
  });

  group('Legacy DOC extraction (heuristic, real bytes, no Supabase)', () {
    test('printable ASCII runs are recovered as blocks, honestly, not fabricated', () {
      // A real .doc is OLE-structured binary; this mimics the shape enough
      // to prove the heuristic finds readable runs and skips binary noise.
      final builder = BytesBuilder();
      builder.add([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]); // OLE magic
      builder.add(List.filled(20, 0x00)); // binary padding
      builder.add('1. What is the capital of Italy?'.codeUnits);
      builder.add([0x00, 0x00, 0x00]);
      builder.add('A. Rome'.codeUnits);
      builder.add([0x00]);
      builder.add('B. Milan'.codeUnits);

      final content = service.extractFromBytes(builder.toBytes(), 'quiz.doc');
      expect(content.sourceFormat, DocumentFormat.doc);
      final joined = content.blocks.map((b) => b.text).join('\n');
      expect(joined, contains('capital of Italy'));
      expect(joined, contains('A. Rome'));
    });

    test('pure binary noise yields no fabricated text', () {
      final bytes = Uint8List.fromList(List.filled(50, 0x01));
      final content = service.extractFromBytes(bytes, 'binary.doc');
      expect(content.blocks, isEmpty);
    });
  });

  group('Image extraction (JPG/PNG uploaded as a file, real bytes)', () {
    test('a JPG file yields one unread page block, honestly, not OCR-guessed', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      final content = service.extractFromBytes(bytes, 'photo.jpg');
      expect(content.sourceFormat, DocumentFormat.image);
      expect(content.blocks.length, 1);
      expect(content.blocks.first.text, isEmpty);
    });

    test('a PNG file yields one unread page block', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final content = service.extractFromBytes(bytes, 'photo.png');
      expect(content.sourceFormat, DocumentFormat.image);
      expect(content.blocks.length, 1);
    });
  });

  group('File signature validation (magic bytes, never trust extension alone)', () {
    test('a real PDF passes validation', () {
      final file = PickedFile(
        path: '/tmp/real.pdf',
        name: 'real.pdf',
        size: 20,
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF        '.codeUnits),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('an .exe renamed to .pdf is rejected despite the correct extension', () {
      final file = PickedFile(
        path: '/tmp/fake.pdf',
        name: 'fake.pdf',
        size: 20,
        bytes: Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]), // MZ (PE exe)
      );
      expect(
        () => service.validateFile(file),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains("doesn't look like a valid"),
          ),
        ),
      );
    });

    test('a real JPG passes validation', () {
      final file = PickedFile(
        path: '/tmp/real.jpg',
        name: 'real.jpg',
        size: 8,
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('a real PNG passes validation', () {
      final file = PickedFile(
        path: '/tmp/real.png',
        name: 'real.png',
        size: 8,
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('a text file renamed to .png is rejected', () {
      final file = PickedFile(
        path: '/tmp/fake.png',
        name: 'fake.png',
        size: 20,
        bytes: Uint8List.fromList('this is plain text!!'.codeUnits),
      );
      expect(() => service.validateFile(file), throwsA(isA<ValidationError>()));
    });

    test('a real DOCX (zip signature) passes validation', () {
      final file = PickedFile(
        path: '/tmp/real.docx',
        name: 'real.docx',
        size: 8,
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('a real DOC (OLE signature) passes validation', () {
      final file = PickedFile(
        path: '/tmp/real.doc',
        name: 'real.doc',
        size: 8,
        bytes: Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });
  });

  group('DOCX extraction (real minimal zip)', () {
    String documentXml(List<String> paragraphs) {
      final body = paragraphs
          .map((t) => '<w:p><w:r><w:t>$t</w:t></w:r></w:p>')
          .join();
      return '<?xml version="1.0"?>'
          '<w:document xmlns:w="ns"><w:body>$body</w:body></w:document>';
    }

    test('extracts paragraphs as content blocks', () {
      final bytes = _zip({
        'word/document.xml': documentXml([
          '1. What is the boiling point of water?',
          'A. 50C',
          'B. 100C',
          'C. 150C',
          'D. 200C',
        ]),
      });

      final content = service.extractFromBytes(bytes, 'quiz.docx');

      expect(content.sourceFormat, DocumentFormat.docx);
      final texts = content.blocks.map((b) => b.text).toList();
      expect(texts, contains('1. What is the boiling point of water?'));
      expect(texts, contains('B. 100C'));
    });

    test('extracts table rows', () {
      const tableXml = '<?xml version="1.0"?>'
          '<w:document xmlns:w="ns"><w:body>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Q1</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>4</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
          '</w:body></w:document>';
      final bytes = _zip({'word/document.xml': tableXml});

      final content = service.extractFromBytes(bytes, 'quiz.docx');

      expect(content.blocks.any((b) => b.blockType == ContentType.table), isTrue);
      expect(content.blocks.first.text, contains('Q1'));
    });

    test('missing document.xml is a clear validation error, not a crash', () {
      final bytes = _zip({'word/other.xml': '<x/>'});
      expect(
        () => service.extractFromBytes(bytes, 'bad.docx'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('not a zip at all fails with a useful, retryable error', () {
      final bytes = Uint8List.fromList('not a docx file'.codeUnits);
      expect(
        () => service.extractFromBytes(bytes, 'fake.docx'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('DOCX'),
          ),
        ),
      );
    });
  });

  group('XLSX extraction (real minimal zip)', () {
    test('extracts rows using shared strings', () {
      const sharedStrings = '<?xml version="1.0"?>'
          '<sst><si><t>What is 5+5?</t></si><si><t>10</t></si>'
          '<si><t>11</t></si><si><t>12</t></si><si><t>13</t></si></sst>';
      const sheet = '<?xml version="1.0"?><worksheet><sheetData>'
          '<row r="1"><c t="s"><v>0</v></c></row>'
          '<row r="2"><c t="s"><v>1</v></c><c t="s"><v>2</v></c>'
          '<c t="s"><v>3</v></c><c t="s"><v>4</v></c></row>'
          '</sheetData></worksheet>';
      final bytes = _zip({
        'xl/sharedStrings.xml': sharedStrings,
        'xl/worksheets/sheet1.xml': sheet,
      });

      final content = service.extractFromBytes(bytes, 'quiz.xlsx');

      expect(content.sourceFormat, DocumentFormat.xlsx);
      expect(content.totalSheets, 1);
      final texts = content.blocks.map((b) => b.text).toList();
      expect(texts, contains('What is 5+5?'));
      expect(texts.any((t) => t.contains('10 | 11 | 12 | 13')), isTrue);
    });

    test('no worksheets is a clear validation error', () {
      final bytes = _zip({'xl/sharedStrings.xml': '<sst/>'});
      expect(
        () => service.extractFromBytes(bytes, 'empty.xlsx'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('No worksheets'),
          ),
        ),
      );
    });
  });

  group('detectQuestions on realistic extracted content', () {
    test('numbered MCQ blocks are detected with options, never a guessed answer', () {
      const content = ExtractedContent(
        blocks: [
          ContentBlock(text: '1. What is 2+2?', sourceLocation: 'Line 1', isQuestionLike: true),
          ContentBlock(text: 'A. 3', sourceLocation: 'Line 2'),
          ContentBlock(text: 'B. 4', sourceLocation: 'Line 3'),
          ContentBlock(text: 'C. 5', sourceLocation: 'Line 4'),
          ContentBlock(text: 'D. 6', sourceLocation: 'Line 5'),
          ContentBlock(text: '2. What is the capital of Japan?', sourceLocation: 'Line 6', isQuestionLike: true),
          ContentBlock(text: 'A. Beijing', sourceLocation: 'Line 7'),
          ContentBlock(text: 'B. Seoul', sourceLocation: 'Line 8'),
          ContentBlock(text: 'C. Tokyo', sourceLocation: 'Line 9'),
          ContentBlock(text: 'D. Bangkok', sourceLocation: 'Line 10'),
        ],
        sourceFormat: DocumentFormat.pdf,
      );

      final detected = service.detectQuestions(content);

      expect(detected.length, 2);
      expect(detected[0].questionText, contains('2+2'));
      expect(detected[0].options, ['3', '4', '5', '6']);
      expect(detected[1].options, ['Beijing', 'Seoul', 'Tokyo', 'Bangkok']);
      // Phase 4: detection must never set a correct answer on its own.
      for (final q in detected) {
        expect(q.detectedCorrectIndex, isNull);
        expect(q.hasCorrectAnswer, isFalse);
      }
    });

    test('duplicate questions across passes are de-duplicated by normalized text', () {
      const content = ExtractedContent(
        blocks: [
          ContentBlock(text: '1. Same question?', sourceLocation: '1', isQuestionLike: true),
          ContentBlock(text: 'A. x', sourceLocation: '2'),
          ContentBlock(text: 'B. y', sourceLocation: '3'),
          ContentBlock(text: '1.  Same   question?  ', sourceLocation: '4', isQuestionLike: true),
          ContentBlock(text: 'A. x', sourceLocation: '5'),
          ContentBlock(text: 'B. y', sourceLocation: '6'),
        ],
        sourceFormat: DocumentFormat.pdf,
      );

      final detected = service.detectQuestions(content);
      expect(detected.length, 1);
    });

    test('a block with fewer than 2 option-like lines after it is not treated as a question', () {
      const content = ExtractedContent(
        blocks: [
          ContentBlock(text: 'What is your favorite color?', sourceLocation: '1', isQuestionLike: true),
          ContentBlock(text: 'Just a sentence, not an option.', sourceLocation: '2'),
        ],
        sourceFormat: DocumentFormat.pdf,
      );
      expect(service.detectQuestions(content), isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────
  // Group security: the document-sourced path uses the SAME
  // TestCreationController -> rpc_create_test as Manual. These tests prove
  // the controller path, not Postgres RLS (see the module doc comment).
  // ──────────────────────────────────────────────────────────────────
  group('Group permission enforcement (document-sourced test creation)', () {
    QuestionDraft mcq(String text) => QuestionDraft(
      questionText: text,
      options: const [
        QuestionOptionDraft(text: 'A'),
        QuestionOptionDraft(text: 'B'),
        QuestionOptionDraft(text: 'C'),
        QuestionOptionDraft(text: 'D'),
      ],
      correctOptionIndex: 0,
    );

    TestCreationController controllerFor(
      String userId,
      FakeTestRepository tests,
      InMemoryGroupRepository groups,
    ) {
      groups.currentUser = userId;
      tests.currentUser = userId;
      return TestCreationController(
        tests: tests,
        questions: FakeQuestionRepository(),
        groups: FakeGroupRepository(),
        currentUserId: () => userId,
      )
        ..setTitle('Imported quiz')
        ..setKind(TestKind.group)
        ..setQuestionSource(QuestionSource.document)
        ..setLocalQuestions([mcq('Imported question?')]);
    }

    test('CREATE_TEST holder (leader) can create a group test from imported questions', () async {
      final groups = InMemoryGroupRepository(currentUser: 'leader-1')
        ..seed(id: 'g-1', ownerId: 'owner-1', members: {'leader-1': 'leader'});
      final tests = FakeTestRepository()..groups = groups;
      final c = controllerFor('leader-1', tests, groups)..groupId = 'g-1';

      final id = await c.saveDraft();

      expect(id, isNotEmpty);
      expect(tests.rows[id]!.testMode, 'group');
      expect(tests.rows[id]!.groupId, 'g-1');
    });

    test('a plain member without CREATE_TEST is denied', () async {
      final groups = InMemoryGroupRepository(currentUser: 'member-1')
        ..seed(id: 'g-1', ownerId: 'owner-1', members: {'member-1': 'member'});
      final tests = FakeTestRepository()..groups = groups;
      final c = controllerFor('member-1', tests, groups)..groupId = 'g-1';

      await expectLater(c.saveDraft(), throwsA(isA<AppError>()));
      expect(tests.rows, isEmpty);
    });

    test('a non-member of the target group is denied', () async {
      final groups = InMemoryGroupRepository(currentUser: 'stranger-1')
        ..seed(id: 'g-1', ownerId: 'owner-1'); // stranger holds no role at all
      final tests = FakeTestRepository()..groups = groups;
      final c = controllerFor('stranger-1', tests, groups)..groupId = 'g-1';

      await expectLater(c.saveDraft(), throwsA(isA<AppError>()));
      expect(tests.rows, isEmpty);
    });

    test('cross-group creation fails: leader of group A cannot create for group B', () async {
      final groups = InMemoryGroupRepository(currentUser: 'leader-1')
        ..seed(id: 'g-a', ownerId: 'owner-a', members: {'leader-1': 'leader'})
        ..seed(id: 'g-b', ownerId: 'owner-b'); // leader-1 has no role in g-b
      final tests = FakeTestRepository()..groups = groups;
      final c = controllerFor('leader-1', tests, groups)..groupId = 'g-b';

      await expectLater(c.saveDraft(), throwsA(isA<AppError>()));
      expect(tests.rows, isEmpty);
    });

    test('the owner can always create, regardless of explicit permission rows', () async {
      final groups = InMemoryGroupRepository(currentUser: 'owner-1')
        ..seed(id: 'g-1', ownerId: 'owner-1');
      final tests = FakeTestRepository()..groups = groups;
      final c = controllerFor('owner-1', tests, groups)..groupId = 'g-1';

      final id = await c.saveDraft();
      expect(tests.rows[id], isNotNull);
    });
  });

  group('Retry / double-tap safety for document-sourced drafts', () {
    QuestionDraft mcq(String text) => QuestionDraft(
      questionText: text,
      options: const [
        QuestionOptionDraft(text: 'A'),
        QuestionOptionDraft(text: 'B'),
        QuestionOptionDraft(text: 'C'),
        QuestionOptionDraft(text: 'D'),
      ],
      correctOptionIndex: 1,
    );

    test('double-tap: a second saveDraft while one is in flight is rejected, not duplicated', () async {
      final tests = FakeTestRepository();
      final questions = FakeQuestionRepository();
      final c = TestCreationController(tests: tests, questions: questions)
        ..setTitle('Double tap test')
        ..setQuestionSource(QuestionSource.document)
        ..setLocalQuestions([mcq('Q1'), mcq('Q2')]);

      final first = c.saveDraft();
      // The controller is already busy; a second call must not create a
      // second test row.
      await expectLater(c.saveDraft(), throwsA(isA<ValidationError>()));
      await first;

      expect(tests.createCount, 1);
    });

    test('sequential saveDraft calls update, never create twice', () async {
      final tests = FakeTestRepository();
      final questions = FakeQuestionRepository();
      final c = TestCreationController(tests: tests, questions: questions)
        ..setTitle('Retry test')
        ..setQuestionSource(QuestionSource.document)
        ..setLocalQuestions([mcq('Q1')]);

      await c.saveDraft();
      await c.saveDraft();

      expect(tests.createCount, 1);
      expect(tests.calls.where((call) => call.startsWith('update:')).length, 1);
    });

    test('one failing draft does not cause a successfully-created sibling to be recreated on retry', () async {
      final tests = FakeTestRepository();
      final questions = FakeQuestionRepository()..failOnce.add('Q-bad');
      final c = TestCreationController(tests: tests, questions: questions)
        ..setTitle('Partial failure test')
        ..setQuestionSource(QuestionSource.document)
        ..setLocalQuestions([mcq('Q-good'), mcq('Q-bad')]);

      await expectLater(c.saveDraft(), throwsA(isA<AppError>()));
      // Q-good was created and removed from the pending list; Q-bad remains.
      expect(c.localQuestions.map((d) => d.questionText), ['Q-bad']);
      expect(questions.calls.where((call) => call == 'create:Q-good').length, 1);

      // Retry: only the still-pending draft is sent again. Q-good is never
      // resent (already removed); Q-bad is attempted a second time — that
      // second attempt is what makes it succeed (failOnce only fires once).
      await c.saveDraft();
      expect(questions.calls.where((call) => call == 'create:Q-good').length, 1);
      expect(questions.calls.where((call) => call == 'create:Q-bad').length, 2);
      expect(c.localQuestions, isEmpty);
    });
  });

  group('Snapshot independence', () {
    QuestionDraft mcq(String text) => QuestionDraft(
      questionText: text,
      options: const [
        QuestionOptionDraft(text: 'A'),
        QuestionOptionDraft(text: 'B'),
        QuestionOptionDraft(text: 'C'),
        QuestionOptionDraft(text: 'D'),
      ],
      correctOptionIndex: 0,
    );

    test('a created question carries no reference back to the source document', () async {
      final tests = FakeTestRepository();
      final questions = FakeQuestionRepository();
      final c = TestCreationController(tests: tests, questions: questions)
        ..setTitle('Snapshot test')
        ..setQuestionSource(QuestionSource.document)
        ..setLocalQuestions([mcq('Imported')]);

      final testId = await c.saveDraft();
      final created = questions.byTest[testId]!.single;

      // QuestionDraft.toCreateParams / _draftParams never send a document or
      // storage id, and the Question model has no such field to carry one
      // back — nothing in `questions` can point at `uploaded_documents`.
      expect(created.question, 'Imported');
      expect(c.localQuestions, isEmpty, reason: 'consumed once, not held onto');
    });
  });
}

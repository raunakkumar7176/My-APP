import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/extracted_content.dart';
import '../../core/services/supabase_service.dart';

/// Handles document file selection, validation, upload to Supabase Storage,
/// and content extraction for PDF, DOCX, and XLSX files.
///
/// SECURITY: All storage operations are scoped to the authenticated user.
/// Files are stored in private buckets with user-scoped paths.
abstract interface class DocumentService {
  /// Pick a document file from the device.
  Future<PickedFile> pickDocument();

  /// Validate the picked file (extension, size, readability).
  void validateFile(PickedFile file);

  /// Upload the file to Supabase Storage and return the document record.
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
  });

  /// Extract content from the uploaded file.
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc);

  /// The pure parsing step of [extractContent], without the storage
  /// download or the `uploaded_documents` status updates. Exposed so the
  /// format-specific parsers (PDF/DOCX/XLSX) are unit-testable with real
  /// byte content and no Supabase client.
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName);

  /// Detect questions from extracted content.
  List<DetectedQuestion> detectQuestions(ExtractedContent content);
}

/// Result of file picking.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.bytes,
  });

  final String path;
  final String name;
  final int size;
  final Uint8List bytes;
}

/// Record returned after upload.
class UploadedDocumentRecord {
  const UploadedDocumentRecord({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.mimeType,
    required this.fileSize,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int fileSize;
}

class SupabaseDocumentService implements DocumentService {
  SupabaseDocumentService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Lazy, like the other repositories' `_client` getters (see
  /// `SupabaseTestRepository`) — so `extractFromBytes`/`detectQuestions`
  /// (pure parsing, no network) can be unit-tested without Supabase ever
  /// being initialized.
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  static const _maxFileSize = 20 * 1024 * 1024; // 20 MB
  static const _allowedExtensions = ['pdf', 'docx', 'xlsx', 'xls'];
  static const _storageBucket = 'test-documents';

  String get _userId {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be logged in.');
    return uid;
  }

  @override
  Future<PickedFile> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      throw const ValidationError(message: 'No file selected.');
    }

    final file = result.files.first;
    if (file.path == null) {
      throw const ValidationError(message: 'Could not read file path.');
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const ValidationError(message: 'File is empty or unreadable.');
    }

    return PickedFile(
      path: file.path!,
      name: file.name,
      size: file.size,
      bytes: bytes,
    );
  }

  @override
  void validateFile(PickedFile file) {
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    if (!_allowedExtensions.contains(ext)) {
      throw ValidationError(
        message: 'Unsupported file format: .$ext. '
            'Supported: ${_allowedExtensions.join(", ")}',
      );
    }

    if (file.size <= 0) {
      throw const ValidationError(message: 'File is empty.');
    }

    if (file.size > _maxFileSize) {
      throw ValidationError(
        message: 'File too large (${_formatSize(file.size)}). '
            'Maximum: ${_formatSize(_maxFileSize)}',
      );
    }
  }

  @override
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
  }) async {
    validateFile(file);

    final uid = _userId;
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$uid/$timestamp-${_sanitizeFileName(file.name)}';

    final contentType = _mimeTypeForExt(ext);

    try {
      await _client.storage.from(_storageBucket).uploadBinary(
        storagePath,
        file.bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: false,
        ),
      );
    } on StorageException catch (e) {
      AppLogger.error('Storage upload failed: ${e.message}');
      throw DataError(message: 'Upload failed: ${e.message}');
    } catch (e, st) {
      AppLogger.error('Storage upload unexpected: $e', stackTrace: st);
      throw const DataError(message: 'Upload failed. Please try again.');
    }

    // Insert metadata row in uploaded_documents table.
    final response = await _client
        .from('uploaded_documents')
        .insert({
          'file_name': file.name,
          'storage_path': storagePath,
          'mime_type': contentType,
          'file_size': file.size,
          'uploaded_by': uid,
          'group_id': groupId,
          'status': 'uploaded',
        })
        .select('id')
        .single();

    return UploadedDocumentRecord(
      id: response['id'] as String,
      fileName: file.name,
      storagePath: storagePath,
      mimeType: contentType,
      fileSize: file.size,
    );
  }

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async {
    // Update status to parsing.
    await _client
        .from('uploaded_documents')
        .update({'status': 'parsing'})
        .eq('id', doc.id);

    try {
      // Download file bytes from storage.
      final bytes = await _client.storage
          .from(_storageBucket)
          .download(doc.storagePath);

      final content = extractFromBytes(bytes, doc.fileName);

      // Update status to parsed.
      await _client
          .from('uploaded_documents')
          .update({'status': 'parsed'})
          .eq('id', doc.id);

      return content;
    } catch (e) {
      // Update status to failed.
      try {
        await _client
            .from('uploaded_documents')
            .update({'status': 'failed'})
            .eq('id', doc.id);
      } catch (_) {
        // Best effort status update.
      }
      rethrow;
    }
  }

  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) {
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'pdf':
        return _extractPdf(bytes, fileName);
      case 'docx':
        return _extractDocx(bytes, fileName);
      case 'xlsx':
      case 'xls':
        return _extractXlsx(bytes, fileName);
      default:
        throw ValidationError(message: 'Unsupported format: .$ext');
    }
  }

  // ── PDF Extraction ──

  ExtractedContent _extractPdf(Uint8List bytes, String fileName) {
    // V1 approach — no external PDF parser: scan the raw byte stream for
    // BT/ET text operators (uncompressed content streams), and separately
    // find every `stream ... endstream` object whose dictionary declares
    // `/FlateDecode`, inflate it with the already-declared `archive` package
    // (cross-platform, no dart:io — most real-world PDFs compress their page
    // content streams this way, so this is what makes typical PDFs actually
    // extract instead of silently returning nothing).
    //
    // What this does NOT do (documented limitation, not silently pretended):
    // true object/xref parsing, so page boundaries are not tracked — blocks
    // are numbered in extraction order, not by page; other filters
    // (LZW/ASCII85/CCITT/DCT images) and encrypted PDFs are skipped, not
    // guessed at.
    final raw = _extractTextFromPdfSegment(bytes);
    final buffer = StringBuffer(raw);
    for (final inflated in _inflatePdfStreams(bytes)) {
      buffer.writeln(_extractTextFromPdfSegment(inflated));
    }
    final blocks = _splitIntoBlocks(buffer.toString(), DocumentFormat.pdf);

    return ExtractedContent(
      blocks: blocks,
      sourceFormat: DocumentFormat.pdf,
    );
  }

  /// Decompresses every `/FlateDecode` object stream found in the raw PDF
  /// bytes. Each stream is decoded independently; a malformed or
  /// unsupported one is skipped (logged), never allowed to abort the whole
  /// file — a partially-extractable PDF still yields whatever it can.
  List<Uint8List> _inflatePdfStreams(Uint8List bytes) {
    final content = String.fromCharCodes(bytes);
    final results = <Uint8List>[];
    final streamPattern = RegExp(r'stream\r?\n', multiLine: true);
    const decoder = ZLibDecoder();

    for (final start in streamPattern.allMatches(content)) {
      // The filter is declared in the object dictionary just before
      // `stream`; a fixed lookback window avoids scanning the whole file.
      final dictStart = (start.start - 2000).clamp(0, content.length);
      final dict = content.substring(dictStart, start.start);
      if (!dict.contains('/FlateDecode')) continue;

      final dataStart = start.end;
      final endIndex = content.indexOf('endstream', dataStart);
      if (endIndex == -1) continue;

      // Trim a trailing EOL PDF writers commonly place before `endstream`.
      var dataEnd = endIndex;
      if (dataEnd > dataStart && content[dataEnd - 1] == '\n') dataEnd--;
      if (dataEnd > dataStart && content[dataEnd - 1] == '\r') dataEnd--;
      if (dataEnd <= dataStart) continue;

      final raw = bytes.sublist(dataStart, dataEnd);
      try {
        results.add(decoder.decodeBytes(raw));
      } catch (e) {
        AppLogger.warning('PDF stream inflate skipped: $e');
      }
    }
    return results;
  }

  /// Extracts `Tj`/`TJ` operator text between `BT`/`ET` markers from one
  /// content-stream segment (works the same whether the bytes came straight
  /// from the file or out of [_inflatePdfStreams]).
  String _extractTextFromPdfSegment(Uint8List bytes) {
    final content = String.fromCharCodes(bytes);
    final buffer = StringBuffer();

    // Match text between BT (begin text) and ET (end text) operators.
    final btEtPattern = RegExp(r'BT[\s\S]*?ET', dotAll: true);
    final matches = btEtPattern.allMatches(content);

    for (final match in matches) {
      final segment = match.group(0) ?? '';
      // Extract text strings from Tj and TJ operators.
      final tjPattern = RegExp(r'\(([^)]*)\)\s*Tj');
      final tjMatches = tjPattern.allMatches(segment);
      for (final tj in tjMatches) {
        final text = tj.group(1) ?? '';
        if (text.trim().isNotEmpty) {
          buffer.writeln(text);
        }
      }

      // TJ arrays: [(text1) (text2) ...] TJ
      final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
      final tjArrayMatches = tjArrayPattern.allMatches(segment);
      for (final tjArray in tjArrayMatches) {
        final inner = tjArray.group(1) ?? '';
        final stringPattern = RegExp(r'\(([^)]*)\)');
        for (final s in stringPattern.allMatches(inner)) {
          final text = s.group(1) ?? '';
          if (text.trim().isNotEmpty) {
            buffer.write(text);
          }
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  // ── DOCX Extraction ──

  ExtractedContent _extractDocx(Uint8List bytes, String fileName) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find document.xml in the archive.
      final docXmlFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw ValidationError(
          message: 'Invalid DOCX file: document.xml not found.',
        ),
      );

      final xmlContent = String.fromCharCodes(docXmlFile.content as List<int>);
      final document = XmlDocument.parse(xmlContent);

      final blocks = <ContentBlock>[];

      // Extract paragraphs from w:p elements.
      final paragraphs = document.findAllElements('w:p');
      var paragraphIndex = 0;

      for (final paragraph in paragraphs) {
        final texts = <String>[];
        // w:r elements contain w:t text nodes.
        for (final run in paragraph.findAllElements('w:r')) {
          for (final textNode in run.findAllElements('w:t')) {
            texts.add(textNode.innerText);
          }
        }

        final text = texts.join('').trim();
        if (text.isNotEmpty) {
          blocks.add(ContentBlock(
            text: text,
            sourceLocation: 'Paragraph ${paragraphIndex + 1}',
            blockType: _classifyBlock(text),
            isQuestionLike: _looksLikeQuestion(text),
          ));
          paragraphIndex++;
        }
      }

      // Extract tables if present.
      final tables = document.findAllElements('w:tbl');
      var tableIndex = 0;
      for (final table in tables) {
        final rows = table.findAllElements('w:tr').toList();
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
          final cells = rows[rowIndex].findAllElements('w:tc');
          final cellTexts = <String>[];
          for (final cell in cells) {
            final cellTextsInner = <String>[];
            for (final p in cell.findAllElements('w:p')) {
              for (final r in p.findAllElements('w:r')) {
                for (final t in r.findAllElements('w:t')) {
                  cellTextsInner.add(t.innerText);
                }
              }
            }
            cellTexts.add(cellTextsInner.join(' ').trim());
          }
          final rowText = cellTexts.where((c) => c.isNotEmpty).join(' | ');
          if (rowText.isNotEmpty) {
            blocks.add(ContentBlock(
              text: rowText,
              sourceLocation: 'Table ${tableIndex + 1}, Row ${rowIndex + 1}',
              blockType: ContentType.table,
              isQuestionLike: _looksLikeQuestion(rowText),
            ));
          }
        }
        tableIndex++;
      }

      return ExtractedContent(
        blocks: blocks,
        sourceFormat: DocumentFormat.docx,
      );
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw const ValidationError(
        message: 'Could not parse DOCX file. It may be corrupted or password-protected.',
      );
    }
  }

  // ── XLSX Extraction ──

  ExtractedContent _extractXlsx(Uint8List bytes, String fileName) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find shared strings if present.
      final sharedStrings = _parseSharedStrings(archive);

      // Find all sheet files (xl/worksheets/sheet1.xml, etc.).
      final sheetFiles = archive.files
          .where((f) => RegExp(r'xl/worksheets/sheet\d+\.xml$').hasMatch(f.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (sheetFiles.isEmpty) {
        throw const ValidationError(
          message: 'No worksheets found in the Excel file.',
        );
      }

      final blocks = <ContentBlock>[];
      var sheetNumber = 0;

      for (final sheetFile in sheetFiles) {
        sheetNumber++;
        final xmlContent = String.fromCharCodes(
          sheetFile.content as List<int>,
        );
        final document = XmlDocument.parse(xmlContent);

        final rows = document.findAllElements('row');
        for (final row in rows) {
          final cells = row.findAllElements('c');
          final cellValues = <String>[];

          for (final cell in cells) {
            final value = cell.findElements('v').firstOrNull;
            final cellText = value?.innerText ?? '';
            final type = cell.getAttribute('t');

            String displayValue;
            if (type == 's' && cellText.isNotEmpty) {
              // Shared string reference.
              final idx = int.tryParse(cellText);
              displayValue = (idx != null && idx < sharedStrings.length)
                  ? sharedStrings[idx]
                  : cellText;
            } else {
              displayValue = cellText;
            }

            if (displayValue.isNotEmpty) {
              cellValues.add(displayValue);
            }
          }

          final rowText = cellValues.join(' | ');
          if (rowText.isNotEmpty) {
            blocks.add(ContentBlock(
              text: rowText,
              sourceLocation: 'Sheet $sheetNumber, Row ${row.getAttribute('r') ?? '?'}',
              blockType: ContentType.row,
              isQuestionLike: _looksLikeQuestion(rowText),
            ));
          }
        }
      }

      return ExtractedContent(
        blocks: blocks,
        sourceFormat: DocumentFormat.xlsx,
        totalSheets: sheetNumber,
      );
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw const ValidationError(
        message: 'Could not parse Excel file. It may be corrupted or password-protected.',
      );
    }
  }

  List<String> _parseSharedStrings(Archive archive) {
    try {
      final ssFile = archive.files.firstWhere(
        (f) => f.name == 'xl/sharedStrings.xml',
        orElse: () => throw StateError('Not found'),
      );
      final xmlContent = String.fromCharCodes(ssFile.content as List<int>);
      final document = XmlDocument.parse(xmlContent);
      final strings = <String>[];
      for (final si in document.findAllElements('si')) {
        final texts = <String>[];
        for (final t in si.findAllElements('t')) {
          texts.add(t.innerText);
        }
        // Handle <r><t>...</t></r> runs within <si>.
        if (texts.isEmpty) {
          for (final r in si.findAllElements('r')) {
            for (final t in r.findAllElements('t')) {
              texts.add(t.innerText);
            }
          }
        }
        strings.add(texts.join(''));
      }
      return strings;
    } catch (_) {
      return const [];
    }
  }

  // ── Question Detection (No AI) ──

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) {
    final questions = <DetectedQuestion>[];
    final allText = content.blocks.map((b) => b.text).join('\n');

    // Strategy 1: Look for numbered questions with ABCD options.
    questions.addAll(_detectNumberedMcq(allText, content.sourceFormat));

    // Strategy 2: Look for question blocks followed by option blocks.
    if (questions.isEmpty) {
      questions.addAll(_detectBlockBasedQuestions(
        content.blocks,
        content.sourceFormat,
      ));
    }

    // Deduplicate by normalized question text.
    final seen = <String>{};
    final unique = <DetectedQuestion>[];
    for (final q in questions) {
      final key = q.questionText.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(q);
      }
    }

    return unique;
  }

  /// Detect numbered questions like:
  /// ```
  /// 1. What is 2+2?
  /// A. 3
  /// B. 4
  /// C. 5
  /// D. 6
  /// ```
  List<DetectedQuestion> _detectNumberedMcq(
    String text,
    DocumentFormat format,
  ) {
    final questions = <DetectedQuestion>[];

    // Match question number + text, followed by option lines.
    final questionPattern = RegExp(
      r'(?:^|\n)\s*(\d+)[.\)]\s*(.+?)(?=\n\s*(?:[A-Da-d][.\)]|\n\n|\Z))',
      dotAll: true,
    );

    final optionPattern = RegExp(
      r'(?:^|\n)\s*([A-Da-d])[.\)]\s*(.+?)(?=\n\s*(?:[A-Da-d][.\)]|\d+[.\)]|\n\n|\Z))',
      dotAll: true,
    );

    final qMatches = questionPattern.allMatches(text).toList();

    for (var i = 0; i < qMatches.length; i++) {
      final qMatch = qMatches[i];
      final qNum = int.tryParse(qMatch.group(1) ?? '');
      final qText = qMatch.group(2)?.trim() ?? '';

      if (qText.isEmpty) continue;

      // Find options between this question and the next.
      final start = qMatch.end;
      final end = (i + 1 < qMatches.length) ? qMatches[i + 1].start : text.length;
      final optionSection = text.substring(start, end);

      final options = <String>[];
      for (final oMatch in optionPattern.allMatches(optionSection)) {
        final optText = oMatch.group(2)?.trim() ?? '';
        if (optText.isNotEmpty) {
          options.add(optText);
        }
      }

      if (qText.isNotEmpty && options.length >= 2) {
        questions.add(DetectedQuestion(
          questionText: qText,
          options: options,
          sourceLocation: 'Question ${qNum ?? questions.length + 1}',
          sourceFormat: format,
          questionNumber: qNum,
        ));
      }
    }

    return questions;
  }

  /// Detect questions from content blocks where question-like blocks
  /// are followed by option-like blocks.
  List<DetectedQuestion> _detectBlockBasedQuestions(
    List<ContentBlock> blocks,
    DocumentFormat format,
  ) {
    final questions = <DetectedQuestion>[];

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (!block.mayContainQuestion) continue;

      final qText = block.text.trim();
      if (qText.length < 10) continue; // Too short to be a question.

      // Look ahead for option blocks.
      final options = <String>[];
      for (var j = i + 1; j < blocks.length && j <= i + 6; j++) {
        final optBlock = blocks[j];
        final optText = optBlock.text.trim();

        // Check if this looks like an option (starts with letter/number or
        // is short enough to be an option).
        if (_looksLikeOption(optText)) {
          options.add(_stripOptionPrefix(optText));
        } else if (options.isNotEmpty) {
          break; // Options section ended.
        }
      }

      if (options.length >= 2) {
        questions.add(DetectedQuestion(
          questionText: qText,
          options: options,
          sourceLocation: block.sourceLocation,
          sourceFormat: format,
        ));
      }
    }

    return questions;
  }

  // ── Helpers ──

  List<ContentBlock> _splitIntoBlocks(String text, DocumentFormat format) {
    final lines = text.split('\n');
    final blocks = <ContentBlock>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      blocks.add(ContentBlock(
        text: line,
        sourceLocation: 'Line ${i + 1}',
        blockType: _classifyBlock(line),
        isQuestionLike: _looksLikeQuestion(line),
      ));
    }

    return blocks;
  }

  ContentType _classifyBlock(String text) {
    if (_looksLikeQuestion(text)) return ContentType.question;
    if (_looksLikeOption(text)) return ContentType.option;
    if (text.length < 80 && text == text.toUpperCase()) return ContentType.header;
    return ContentType.paragraph;
  }

  bool _looksLikeQuestion(String text) {
    final lower = text.toLowerCase();
    return lower.contains('?') ||
        RegExp(r'^\d+[.\)]\s').hasMatch(text.trim()) ||
        lower.startsWith('what') ||
        lower.startsWith('which') ||
        lower.startsWith('who') ||
        lower.startsWith('where') ||
        lower.startsWith('when') ||
        lower.startsWith('why') ||
        lower.startsWith('how') ||
        lower.startsWith('find') ||
        lower.startsWith('calculate') ||
        lower.startsWith('define') ||
        lower.startsWith('explain');
  }

  bool _looksLikeOption(String text) {
    final trimmed = text.trim();
    return RegExp(r'^[A-Da-d][.\)]\s').hasMatch(trimmed) ||
        RegExp(r'^\([A-Da-d]\)\s').hasMatch(trimmed) ||
        RegExp(r'^\d+[.\)]\s').hasMatch(trimmed);
  }

  String _stripOptionPrefix(String text) {
    return text
        .replaceFirst(RegExp(r'^[A-Da-d][.\)]\s*'), '')
        .replaceFirst(RegExp(r'^\([A-Da-d]\)\s*'), '')
        .replaceFirst(RegExp(r'^\d+[.\)]\s*'), '')
        .trim();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\-\.]'), '_');
  }

  String _mimeTypeForExt(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
      case 'xls':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

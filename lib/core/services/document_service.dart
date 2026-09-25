import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/extracted_content.dart';
import '../../core/services/supabase_service.dart';

/// Handles document file selection, validation, upload to Supabase Storage,
/// and content extraction for PDF, DOCX, XLSX, TXT, and image files.
///
/// SECURITY: All storage operations are scoped to the authenticated user.
/// Files are stored in private buckets with user-scoped paths.
abstract interface class DocumentService {
  /// Pick a document file from the device.
  Future<PickedFile> pickDocument();

  /// Pick an image (JPG/JPEG/PNG) from the device gallery.
  Future<PickedFile> pickImage();

  /// Validate the picked file (extension, content signature, size).
  void validateFile(PickedFile file);

  /// Upload the file to Supabase Storage and return the document record.
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  });

  /// Deletes the storage object for [doc], then its metadata row.
  Future<void> deleteDocument(UploadedDocumentRecord doc);

  /// Purges an ephemeral document from storage and database.
  Future<void> purgeEphemeralDocument(UploadedDocumentRecord doc);

  /// Purges stale ephemeral documents older than [maxAgeMinutes].
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120});

  /// Lists the current user's own uploaded-document metadata rows, newest first.
  Future<List<UploadedDocumentRecord>> listMyDocuments();

  /// Finds Storage objects under caller folder without metadata and deletes them.
  Future<int> cleanupOrphanedStorage();

  /// Extract content from the uploaded file.
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc);

  /// The pure parsing step of [extractContent] without storage download.
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName);

  /// Camera pages -> [ExtractedContent] format.
  ExtractedContent extractFromImages(List<Uint8List> pages);

  /// Detect questions from extracted content.
  List<DetectedQuestion> detectQuestions(ExtractedContent content);

  /// Detect questions with confidence evaluation, noise filtering,
  /// and answer key detection.
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  );
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
    this.status = 'uploaded',
    this.isEphemeral = true,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int fileSize;
  final String status;
  final bool isEphemeral;
  final DateTime? createdAt;
}

class SupabaseDocumentService implements DocumentService {
  SupabaseDocumentService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  static const _maxFileSize = 20 * 1024 * 1024; // 20 MB
  static const _allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'xlsx',
    'xls',
    'txt',
    'jpg',
    'jpeg',
    'png',
  ];
  static const _imageExtensions = ['jpg', 'jpeg', 'png'];
  static const _storageBucket = 'test-documents';

  String get _userId {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be logged in.');
    return uid;
  }

  @override
  Future<PickedFile> pickDocument() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );

    if (files.isEmpty) {
      throw const ValidationError(message: 'No file selected.');
    }

    final file = files.first;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ValidationError(message: 'File is empty or unreadable.');
    }

    return PickedFile(
      path: file.path ?? file.name,
      name: file.name,
      size: bytes.length,
      bytes: bytes,
    );
  }

  @override
  Future<PickedFile> pickImage() async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('denied')) {
        throw const AuthError(
          message:
              'Photo library permission is needed to choose an image. '
              'Enable it in your device settings and try again.',
        );
      }
      throw const DataError(
        message: 'Could not open the gallery. Please try again.',
      );
    }

    if (file == null) {
      throw const ValidationError(message: 'No image selected.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ValidationError(message: 'Image is empty or unreadable.');
    }

    var name = file.name;
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!_imageExtensions.contains(ext)) {
      final sniffed = _sniffImageExtension(bytes) ?? 'jpg';
      name =
          '${p.basenameWithoutExtension(name.isEmpty ? 'image' : name)}.$sniffed';
    }

    return PickedFile(
      path: file.path,
      name: name,
      size: bytes.length,
      bytes: bytes,
    );
  }

  @override
  void validateFile(PickedFile file) {
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    if (!_allowedExtensions.contains(ext)) {
      throw ValidationError(
        message:
            'Unsupported file format: .$ext. '
            'Supported: ${_allowedExtensions.join(", ")}',
      );
    }

    if (file.size <= 0) {
      throw const ValidationError(message: 'File is empty.');
    }

    if (file.size > _maxFileSize) {
      throw ValidationError(
        message:
            'File too large (${_formatSize(file.size)}). '
            'Maximum: ${_formatSize(_maxFileSize)}',
      );
    }

    if (!_signatureMatchesExtension(file.bytes, ext)) {
      throw ValidationError(
        message:
            "That file doesn't look like a valid .$ext file. "
            'Its content does not match the expected format — pick the '
            'correct file and try again.',
      );
    }
  }

  bool _signatureMatchesExtension(Uint8List bytes, String ext) {
    if (bytes.length < 4) return false;
    switch (ext) {
      case 'pdf':
        return bytes.length >= 4 &&
            bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46; // %PDF
      case 'docx':
      case 'xlsx':
        return _isZipSignature(bytes);
      case 'doc':
      case 'xls':
        return _isOleSignature(bytes) || _isZipSignature(bytes);
      case 'txt':
        return true;
      case 'jpg':
      case 'jpeg':
        return bytes.length >= 3 &&
            bytes[0] == 0xFF &&
            bytes[1] == 0xD8 &&
            bytes[2] == 0xFF;
      case 'png':
        return bytes.length >= 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47;
      default:
        return true;
    }
  }

  bool _isZipSignature(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);

  bool _isOleSignature(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0;

  String? _sniffImageExtension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return null;
  }

  @override
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  }) async {
    validateFile(file);

    final uid = _userId;
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$uid/$timestamp-${_sanitizeFileName(file.name)}';

    final contentType = _mimeTypeForExt(ext);

    try {
      await _client.storage
          .from(_storageBucket)
          .uploadBinary(
            storagePath,
            file.bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } on StorageException catch (e) {
      AppLogger.error('Storage upload failed: ${e.message}');
      throw DataError(message: 'Upload failed: ${e.message}');
    } catch (e, st) {
      AppLogger.error('Storage upload unexpected: $e', stackTrace: st);
      throw const DataError(message: 'Upload failed. Please try again.');
    }

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
          'is_ephemeral': isEphemeral,
        })
        .select()
        .single();

    return UploadedDocumentRecord(
      id: response['id'] as String,
      fileName: file.name,
      storagePath: storagePath,
      mimeType: contentType,
      fileSize: file.size,
      status: response['status'] as String? ?? 'uploaded',
      isEphemeral: response['is_ephemeral'] as bool? ?? isEphemeral,
      createdAt: response['created_at'] != null
          ? DateTime.tryParse(response['created_at'] as String)
          : null,
    );
  }

  @override
  Future<void> deleteDocument(UploadedDocumentRecord doc) async {
    try {
      await _client.storage.from(_storageBucket).remove([doc.storagePath]);
    } catch (_) {}
    await _client.from('uploaded_documents').delete().eq('id', doc.id);
  }

  @override
  Future<void> purgeEphemeralDocument(UploadedDocumentRecord doc) async {
    try {
      await _client.rpc(
        'rpc_purge_ephemeral_documents',
        params: {'p_document_id': doc.id, 'p_max_age_minutes': 0},
      );
    } catch (_) {
      try {
        await _client.storage.from(_storageBucket).remove([doc.storagePath]);
        await _client.from('uploaded_documents').delete().eq('id', doc.id);
      } catch (_) {}
    }
  }

  @override
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120}) async {
    try {
      final res = await _client.rpc(
        'rpc_purge_ephemeral_documents',
        params: {'p_document_id': null, 'p_max_age_minutes': maxAgeMinutes},
      );
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async {
    final rows = await _client
        .from('uploaded_documents')
        .select()
        .eq('uploaded_by', _userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows as List<dynamic>)
        UploadedDocumentRecord(
          id: row['id'] as String,
          fileName: row['file_name'] as String,
          storagePath: row['storage_path'] as String,
          mimeType: row['mime_type'] as String,
          fileSize: row['file_size'] as int,
          status: row['status'] as String? ?? 'uploaded',
          isEphemeral: row['is_ephemeral'] as bool? ?? true,
          createdAt: row['created_at'] != null
              ? DateTime.tryParse(row['created_at'] as String)
              : null,
        ),
    ];
  }

  @override
  Future<int> cleanupOrphanedStorage() async {
    final uid = _userId;
    final knownPaths = (await listMyDocuments())
        .map((d) => d.storagePath)
        .toSet();

    final objects = await _client.storage.from(_storageBucket).list(path: uid);
    final orphanPaths = [
      for (final obj in objects)
        if (obj.name.isNotEmpty && !knownPaths.contains('$uid/${obj.name}'))
          '$uid/${obj.name}',
    ];

    if (orphanPaths.isEmpty) return 0;
    await _client.storage.from(_storageBucket).remove(orphanPaths);
    return orphanPaths.length;
  }

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async {
    await _client
        .from('uploaded_documents')
        .update({'status': 'parsing'})
        .eq('id', doc.id);

    try {
      final bytes = await _client.storage
          .from(_storageBucket)
          .download(doc.storagePath);

      final content = extractFromBytes(bytes, doc.fileName);

      await _client
          .from('uploaded_documents')
          .update({'status': 'parsed'})
          .eq('id', doc.id);

      return content;
    } catch (e) {
      try {
        await _client
            .from('uploaded_documents')
            .update({'status': 'failed'})
            .eq('id', doc.id);
      } catch (_) {}
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
      case 'doc':
        return _extractLegacyDoc(bytes);
      case 'txt':
        return _extractTxt(bytes);
      case 'jpg':
      case 'jpeg':
      case 'png':
        final imageContent = extractFromImages([bytes]);
        return ExtractedContent(
          blocks: imageContent.blocks,
          sourceFormat: DocumentFormat.image,
          totalPages: imageContent.totalPages,
        );
      default:
        throw ValidationError(message: 'Unsupported format: .$ext');
    }
  }

  ExtractedContent _extractTxt(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final blocks = _splitIntoBlocks(text, DocumentFormat.txt);
    return ExtractedContent(blocks: blocks, sourceFormat: DocumentFormat.txt);
  }

  ExtractedContent _extractLegacyDoc(Uint8List bytes) {
    final buffer = StringBuffer();
    var run = StringBuffer();
    void flush() {
      final text = run.toString().trim();
      if (text.length >= 4) buffer.writeln(text);
      run = StringBuffer();
    }

    for (final byte in bytes) {
      final isPrintable = byte >= 0x20 && byte < 0x7F;
      if (isPrintable) {
        run.writeCharCode(byte);
      } else {
        flush();
      }
    }
    flush();

    final blocks = _splitIntoBlocks(buffer.toString(), DocumentFormat.doc);
    return ExtractedContent(blocks: blocks, sourceFormat: DocumentFormat.doc);
  }

  @override
  ExtractedContent extractFromImages(List<Uint8List> pages) {
    if (pages.isEmpty) {
      throw const ValidationError(message: 'No pages to process.');
    }
    return ExtractedContent(
      blocks: [
        for (var i = 0; i < pages.length; i++)
          ContentBlock(
            text: '',
            sourceLocation: 'Page ${i + 1}',
            blockType: ContentType.unknown,
          ),
      ],
      sourceFormat: DocumentFormat.camera,
      totalPages: pages.length,
    );
  }

  // ── PDF Extraction ──

  ExtractedContent _extractPdf(Uint8List bytes, String fileName) {
    final buffer = StringBuffer();

    final directText = _extractPdfTjStrings(bytes);
    if (directText.isNotEmpty) {
      buffer.writeln(directText);
    }

    final decompressedText = _extractPdfFlateStreams(bytes);
    if (decompressedText.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(decompressedText);
    }

    final raw = buffer.toString().trim();
    if (raw.isEmpty) {
      return const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
        totalPages: 1,
      );
    }

    final blocks = _splitIntoBlocks(raw, DocumentFormat.pdf);
    return ExtractedContent(
      blocks: blocks,
      sourceFormat: DocumentFormat.pdf,
      totalPages: 1,
    );
  }

  String _extractPdfTjStrings(Uint8List bytes) {
    final out = StringBuffer();
    final latin1Text = String.fromCharCodes(bytes);

    final tjPattern = RegExp(r'\(([^)]*)\)\s*Tj');
    for (final m in tjPattern.allMatches(latin1Text)) {
      final s = m.group(1);
      if (s != null && s.trim().isNotEmpty) {
        out.writeln(s);
      }
    }

    final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    for (final m in tjArrayPattern.allMatches(latin1Text)) {
      final inner = m.group(1);
      if (inner == null) continue;
      final piecePattern = RegExp(r'\(([^)]*)\)');
      final linePieces = <String>[];
      for (final piece in piecePattern.allMatches(inner)) {
        final text = piece.group(1);
        if (text != null && text.isNotEmpty) {
          linePieces.add(text);
        }
      }
      if (linePieces.isNotEmpty) {
        out.writeln(linePieces.join(''));
      }
    }

    return out.toString().trim();
  }

  String _extractPdfFlateStreams(Uint8List bytes) {
    final out = StringBuffer();
    final latin1Text = String.fromCharCodes(bytes);

    final objPattern = RegExp(r'<<([^>]*)>>\s*stream\r?\n', dotAll: true);
    final endStreamPattern = RegExp(r'\r?\nendstream');

    for (final dictMatch in objPattern.allMatches(latin1Text)) {
      final dict = dictMatch.group(1) ?? '';
      if (!dict.contains('/FlateDecode')) continue;

      final streamStart = dictMatch.end;
      final endMatch = endStreamPattern.firstMatch(
        latin1Text.substring(streamStart),
      );
      if (endMatch == null) continue;
      final streamEnd = streamStart + endMatch.start;

      if (streamEnd <= streamStart || streamEnd > bytes.length) continue;

      final compressedBytes = bytes.sublist(streamStart, streamEnd);
      try {
        final decompressed = const ZLibDecoder().decodeBytes(compressedBytes);
        final streamText = _extractPdfTjStrings(
          Uint8List.fromList(decompressed),
        );
        if (streamText.isNotEmpty) {
          out.writeln(streamText);
        }
      } catch (_) {
        // Corrupted or unsupported stream chunk.
      }
    }

    return out.toString().trim();
  }

  // ── DOCX Extraction ──

  ExtractedContent _extractDocx(Uint8List bytes, String fileName) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw const ValidationError(
          message: 'Invalid DOCX: missing word/document.xml',
        ),
      );

      final xmlContent = String.fromCharCodes(docFile.content as List<int>);
      final document = XmlDocument.parse(xmlContent);

      final blocks = <ContentBlock>[];

      for (final p in document.findAllElements('w:p')) {
        final textElements = p.findAllElements('w:t');
        final paragraphText = textElements.map((e) => e.innerText).join('');
        if (paragraphText.trim().isNotEmpty) {
          blocks.add(
            ContentBlock(
              text: paragraphText.trim(),
              sourceLocation: 'Paragraph ${blocks.length + 1}',
              blockType: _classifyBlock(paragraphText),
              isQuestionLike: _looksLikeQuestion(paragraphText),
            ),
          );
        }
      }

      for (final table in document.findAllElements('w:tbl')) {
        for (final row in table.findAllElements('w:tr')) {
          final cells = row.findAllElements('w:tc');
          final rowText = cells
              .map(
                (c) =>
                    c.findAllElements('w:t').map((e) => e.innerText).join(''),
              )
              .where((t) => t.trim().isNotEmpty)
              .join(' | ');

          if (rowText.isNotEmpty) {
            blocks.add(
              ContentBlock(
                text: rowText,
                sourceLocation: 'Table row',
                blockType: ContentType.table,
                isQuestionLike: _looksLikeQuestion(rowText),
              ),
            );
          }
        }
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
      final sharedStrings = _parseSharedStrings(archive);

      final sheetFiles =
          archive.files
              .where(
                (f) => RegExp(r'xl/worksheets/sheet\d+\.xml$').hasMatch(f.name),
              )
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
        final xmlContent = String.fromCharCodes(sheetFile.content as List<int>);
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
            blocks.add(
              ContentBlock(
                text: rowText,
                sourceLocation:
                    'Sheet $sheetNumber, Row ${row.getAttribute('r') ?? '?'}',
                blockType: ContentType.row,
                isQuestionLike: _looksLikeQuestion(rowText),
              ),
            );
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

  // ── Question Detection ──

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) =>
      detectQuestionsWithConfidence(content).questions;

  @override
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  ) {
    final rawText = content.blocks.map((b) => b.text).join('\n');
    final rawCharCount = rawText.length;

    // 1. Strip coaching headers, footers, phone numbers, and page numbers
    final cleanResult = DocumentNoiseFilter.clean(rawText);
    final cleanedText = cleanResult.cleanedText;
    final noiseLinesFiltered = cleanResult.strippedCount;

    // 2. Extract answer key section from text/footers if present
    final akResult = AnswerKeyDetector.extractAnswerKeySection(cleanedText);
    final answerKeyMap = akResult.answerKey;
    final textToScan = '${akResult.textWithoutAnswerSection}\n\n';

    final questions = <DetectedQuestion>[];

    // Strategy 1: Look for numbered questions with ABCD options & inline answers
    questions.addAll(
      _detectNumberedMcq(textToScan, content.sourceFormat, answerKeyMap),
    );

    // Strategy 2: Look for question blocks followed by option blocks
    if (questions.isEmpty) {
      final cleanedBlocks = content.blocks
          .where((b) => !DocumentNoiseFilter.isNoiseLine(b.text))
          .toList();
      questions.addAll(
        _detectBlockBasedQuestions(
          cleanedBlocks,
          content.sourceFormat,
          answerKeyMap,
        ),
      );
    }

    // Deduplicate by normalized question text
    final seen = <String>{};
    final unique = <DetectedQuestion>[];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final key = q.questionText
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (!seen.contains(key)) {
        seen.add(key);

        // Fallback sequential answer key matching if not already set
        if (q.detectedCorrectIndex == null && answerKeyMap.isNotEmpty) {
          final sequentialAns =
              answerKeyMap[q.questionNumber ?? (unique.length + 1)];
          if (sequentialAns != null && sequentialAns < q.options.length) {
            unique.add(
              DetectedQuestion(
                questionText: q.questionText,
                options: q.options,
                sourceLocation: q.sourceLocation,
                sourceFormat: q.sourceFormat,
                detectedCorrectIndex: sequentialAns,
                explanation: q.explanation,
                questionNumber: q.questionNumber,
              ),
            );
            continue;
          }
        }
        unique.add(q);
      }
    }

    final confidence = _computeConfidence(unique);
    final answersDetected = unique.where((q) => q.hasCorrectAnswer).length;

    return IngestionDetectionResult(
      questions: unique,
      confidence: confidence,
      answersDetected: answersDetected,
      noiseLinesFiltered: noiseLinesFiltered,
      rawCharacterCount: rawCharCount,
    );
  }

  IngestionConfidence _computeConfidence(List<DetectedQuestion> questions) {
    if (questions.isEmpty) {
      return IngestionConfidence.zero;
    }

    final total = questions.length;
    final validQuestions = questions.where((q) => q.hasValidStructure).toList();
    final validCount = validQuestions.length;
    final withAnswerCount = validQuestions
        .where((q) => q.hasCorrectAnswer)
        .length;

    final structureRatio = validCount / total;
    final answerRatio = validCount > 0 ? (withAnswerCount / validCount) : 0.0;

    final score = double.parse(
      ((structureRatio * 0.8) + (answerRatio * 0.2)).toStringAsFixed(2),
    );

    final isHigh = validCount >= 2 && structureRatio >= 0.7;

    final reason = isHigh
        ? 'Detected $validCount valid MCQs ($withAnswerCount with answers, ${(structureRatio * 100).toInt()}% structural validity)'
        : validCount < 2
        ? 'Only $validCount valid question(s) detected (minimum 2 required for high confidence)'
        : 'Low structural validity (${(structureRatio * 100).toInt()}% valid questions)';

    return IngestionConfidence(
      totalDetected: total,
      validCount: validCount,
      withAnswerCount: withAnswerCount,
      score: score,
      isHighConfidence: isHigh,
      reason: reason,
    );
  }

  List<DetectedQuestion> _detectNumberedMcq(
    String text,
    DocumentFormat format, [
    Map<int, int> answerKeyMap = const {},
  ]) {
    final questions = <DetectedQuestion>[];

    final questionPattern = RegExp(
      r'(?:^|\n)\s*(?:Q\.?\s*)?\(?(\d+)\)?[.\:\)]\s*(.+?)(?=\n\s*(?:(?:[\*•-]\s*)?(?:\([A-Da-d1-4]\)|[A-Da-d1-4][.\)])|\n\n|$))',
      dotAll: true,
    );

    final optionPattern = RegExp(
      r'(?:^|\n)\s*(?:[\*•-]\s*)?(?:\(([A-Da-d1-4])\)|([A-Da-d1-4])[.\)])\s*(.+?)(?=\n\s*(?:(?:[\*•-]\s*)?(?:\([A-Da-d1-4]\)|[A-Da-d1-4][.\)])|(?:Q\.?\s*)?\(?\d+\)?[.\:\)]|\n\s*(?:ans(?:wer)?|correct|उत्तर)|\n\n|$))',
      dotAll: true,
    );

    final qMatches = questionPattern.allMatches(text).toList();

    for (var i = 0; i < qMatches.length; i++) {
      final qMatch = qMatches[i];
      final qNum = int.tryParse(qMatch.group(1) ?? '');
      final qText = qMatch.group(2)?.trim() ?? '';

      if (qText.isEmpty) continue;

      final start = qMatch.end;
      final end = (i + 1 < qMatches.length)
          ? qMatches[i + 1].start + 1
          : text.length;
      final optionSection = text.substring(start, end);

      final inlineAns = AnswerKeyDetector.extractInlineAnswer(optionSection);
      int? correctIndex = inlineAns.correctIndex;
      final cleanedOptionSection = inlineAns.cleanedText;

      final options = <String>[];
      int? markedCorrectIndex;

      final oMatches = optionPattern.allMatches(cleanedOptionSection).toList();
      for (var oIdx = 0; oIdx < oMatches.length; oIdx++) {
        final oMatch = oMatches[oIdx];
        final fullMatchText = oMatch.group(0) ?? '';
        var optText = oMatch.group(3)?.trim() ?? '';

        if (fullMatchText.contains('*') ||
            optText.toLowerCase().contains('[correct]') ||
            optText.toLowerCase().contains('(correct)')) {
          markedCorrectIndex = oIdx;
          optText = optText
              .replaceAll(
                RegExp(r'\[correct\]|\(correct\)', caseSensitive: false),
                '',
              )
              .trim();
        }

        if (optText.isNotEmpty) {
          options.add(optText);
        }
      }

      correctIndex ??= markedCorrectIndex;
      if (correctIndex == null &&
          qNum != null &&
          answerKeyMap.containsKey(qNum)) {
        final akIdx = answerKeyMap[qNum]!;
        if (akIdx < options.length) {
          correctIndex = akIdx;
        }
      }

      if (qText.isNotEmpty && options.length >= 2) {
        questions.add(
          DetectedQuestion(
            questionText: qText,
            options: options,
            sourceLocation: 'Question ${qNum ?? questions.length + 1}',
            sourceFormat: format,
            detectedCorrectIndex: correctIndex,
            questionNumber: qNum,
          ),
        );
      }
    }

    return questions;
  }

  List<DetectedQuestion> _detectBlockBasedQuestions(
    List<ContentBlock> blocks,
    DocumentFormat format, [
    Map<int, int> answerKeyMap = const {},
  ]) {
    final questions = <DetectedQuestion>[];

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (!block.mayContainQuestion) continue;

      var qText = block.text.trim();
      if (qText.length < 10) continue;

      final qInline = AnswerKeyDetector.extractInlineAnswer(qText);
      int? correctIndex = qInline.correctIndex;
      qText = qInline.cleanedText;

      final options = <String>[];
      int? markedCorrectIndex;

      for (var j = i + 1; j < blocks.length && j <= i + 6; j++) {
        final optBlock = blocks[j];
        var optText = optBlock.text.trim();

        final optInline = AnswerKeyDetector.extractInlineAnswer(optText);
        if (optInline.correctIndex != null) {
          correctIndex ??= optInline.correctIndex;
          optText = optInline.cleanedText;
        }

        if (_looksLikeOption(optText)) {
          if (optText.contains('*') ||
              optText.toLowerCase().contains('[correct]') ||
              optText.toLowerCase().contains('(correct)')) {
            markedCorrectIndex = options.length;
            optText = optText
                .replaceAll(
                  RegExp(r'\[correct\]|\(correct\)', caseSensitive: false),
                  '',
                )
                .trim();
          }
          options.add(_stripOptionPrefix(optText));
        } else if (options.isNotEmpty) {
          break;
        }
      }

      correctIndex ??= markedCorrectIndex;
      final qNum = questions.length + 1;
      if (correctIndex == null && answerKeyMap.containsKey(qNum)) {
        final akIdx = answerKeyMap[qNum]!;
        if (akIdx < options.length) {
          correctIndex = akIdx;
        }
      }

      if (options.length >= 2) {
        questions.add(
          DetectedQuestion(
            questionText: qText,
            options: options,
            sourceLocation: block.sourceLocation,
            sourceFormat: format,
            detectedCorrectIndex: correctIndex,
            questionNumber: qNum,
          ),
        );
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

      blocks.add(
        ContentBlock(
          text: line,
          sourceLocation: 'Line ${i + 1}',
          blockType: _classifyBlock(line),
          isQuestionLike: _looksLikeQuestion(line),
        ),
      );
    }

    return blocks;
  }

  ContentType _classifyBlock(String text) {
    if (_looksLikeQuestion(text)) {
      return ContentType.question;
    }
    if (_looksLikeOption(text)) {
      return ContentType.option;
    }
    if (text.length < 80 && text == text.toUpperCase()) {
      return ContentType.header;
    }
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
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'txt':
        return 'text/plain';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
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

/// Pure utility to detect and filter noise lines (headers, footers, phone numbers,
/// URLs, coaching branding, disclaimers) from document text.
class DocumentNoiseFilter {
  static final _pageNumberPattern = RegExp(
    r'^(?:page\s*\d+(?:\s*(?:of|/)\s*\d+)?|\d+\s*(?:of|/)\s*\d+|[-–—]\s*\d+\s*[-–—]|\[\s*\d+\s*\]|page\s*no\.?\s*[:\s]?\s*\d+)$',
    caseSensitive: false,
  );

  static final _phonePattern = RegExp(
    r'^(?:(?:mob(?:ile)?|tel(?:ephone)?|ph(?:one)?|call|contact|whatsapp|helpline)\s*(?:no\.?|number)?\s*[:\s-]?\s*)?(?:\+91[\s-]?)?[6-9]\d{9}$',
    caseSensitive: false,
  );

  static final _urlOrEmailPattern = RegExp(
    r'^(?:https?://\S+|www\.[a-zA-Z0-9-]+\.[a-zA-Z]{2,}\S*|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})$',
    caseSensitive: false,
  );

  static final _coachingHeaderPattern = RegExp(
    r'^(?:allen(?:\s+career\s+institute)?|fiitjee(?:\s+ltd\.?)?|aakash(?:\s+institute)?|resonance|vision\s+ias|drishti\s+ias|byju(?:\x27s)?|unacademy|testbook|career\s+point|narayana|chaitanya|made\s+easy|ace\s+academy)\b.*$',
    caseSensitive: false,
  );

  static final _documentBannerPattern = RegExp(
    r'^(?:all\s+rights?\s+reserved|copyright\s*©?|strictly\s+for\s+internal\s+circulation|do\s+not\s+copy|for\s+admissions?\s+call|downloaded\s+from|visit\s+us\s+at)\b.*$',
    caseSensitive: false,
  );

  /// Checks if a single line is non-content noise.
  static bool isNoiseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (_pageNumberPattern.hasMatch(trimmed)) return true;
    if (_phonePattern.hasMatch(trimmed)) return true;
    if (_urlOrEmailPattern.hasMatch(trimmed)) return true;
    if (_coachingHeaderPattern.hasMatch(trimmed)) return true;
    if (_documentBannerPattern.hasMatch(trimmed)) return true;
    return false;
  }

  /// Filters noise lines from text, returning the cleaned text and the count of stripped lines.
  static ({String cleanedText, int strippedCount}) clean(String text) {
    final lines = text.split('\n');
    var stripped = 0;
    final kept = <String>[];
    for (final line in lines) {
      if (isNoiseLine(line)) {
        stripped++;
      } else {
        kept.add(line);
      }
    }
    return (cleanedText: kept.join('\n'), strippedCount: stripped);
  }
}

/// Pure utility to detect answer keys from document text or footers.
class AnswerKeyDetector {
  /// Matches an Answer Key section header.
  static final _answerSectionHeader = RegExp(
    r'(?:^|\n)\s*(?:[-=*~_#]{2,}\s*)?(?:answer\s*key|answers\s*(?:list|table|sheet)|answer\s*sheet|solutions?|hints\s*&\s*solutions?|उत्तर\s*(?:कुंजी|माला)|answers?)(?:\s*[-=*~_#]{2,})?\s*[:\-]?(?=\s*(?:\n|$))',
    caseSensitive: false,
  );

  /// Matches question-to-answer pairs like "1. A", "1.(B)", "1 - C", "Q1: D", "1 | A".
  static final _answerPairPattern = RegExp(
    r'(?:Q\.?\s*)?(\d+)\s*[\.\:\-\)\s\|]\s*\(?([A-Da-d1-4])\)?',
    caseSensitive: false,
  );

  /// Matches inline answer indicators at the end of a question or option section:
  /// e.g. "Ans: (A)", "Answer: B", "Ans - C", "उत्तर: (B)"
  static final _inlineAnswerPattern = RegExp(
    r'(?:^|\n)\s*(?:ans(?:wer)?|correct\s*(?:option|answer)?|उत्तर)\s*[:\.\-]?\s*[\(\[]?\s*([A-Da-d1-4])\s*[\)\]]?',
    caseSensitive: false,
  );

  /// Checks if [text] contains an answer key section at the bottom or anywhere.
  /// If found, parses the map of {questionNumber: correctOptionIndex} and
  /// returns the parsed map along with the text with the answer key section removed.
  static ({Map<int, int> answerKey, String textWithoutAnswerSection})
  extractAnswerKeySection(String text) {
    final match = _answerSectionHeader.firstMatch(text);
    if (match == null) {
      return (answerKey: const <int, int>{}, textWithoutAnswerSection: text);
    }

    final headerStart = match.start;
    final answerText = text.substring(match.end);
    final textBefore = text.substring(0, headerStart);

    final map = <int, int>{};
    for (final pair in _answerPairPattern.allMatches(answerText)) {
      final qNum = int.tryParse(pair.group(1) ?? '');
      final ansChar = pair.group(2);
      if (qNum != null && ansChar != null) {
        final optIdx = _charToOptionIndex(ansChar);
        if (optIdx != null) {
          map[qNum] = optIdx;
        }
      }
    }

    return (answerKey: map, textWithoutAnswerSection: textBefore);
  }

  /// Extracts inline answer if present at the end of a question/option string.
  /// Returns the option index (0-based) and the text with the inline answer line stripped.
  static ({int? correctIndex, String cleanedText}) extractInlineAnswer(
    String text,
  ) {
    final match = _inlineAnswerPattern.firstMatch(text);
    if (match == null) {
      return (correctIndex: null, cleanedText: text);
    }

    final ansChar = match.group(1);
    final correctIdx = ansChar != null ? _charToOptionIndex(ansChar) : null;
    final cleaned = text.substring(0, match.start).trim();

    return (correctIndex: correctIdx, cleanedText: cleaned);
  }

  /// Converts 'A'/'a'/'1' -> 0, 'B'/'b'/'2' -> 1, 'C'/'c'/'3' -> 2, 'D'/'d'/'4' -> 3.
  static int? _charToOptionIndex(String char) {
    final c = char.trim().toUpperCase();
    switch (c) {
      case 'A':
      case '1':
        return 0;
      case 'B':
      case '2':
        return 1;
      case 'C':
      case '3':
        return 2;
      case 'D':
      case '4':
        return 3;
      default:
        return null;
    }
  }
}

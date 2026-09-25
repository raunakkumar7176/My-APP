import 'dart:typed_data';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/camera_capture_service.dart';
import 'disposable_notifier.dart';

enum CameraCaptureState { idle, capturing, done, error }

/// Multi-page camera capture (Phase 3/4/5): capture one page at a time,
/// thumbnail grid, add/retake/delete/reorder/rotate, a safe page ceiling,
/// and a lightweight per-page readability check with "Retake / Keep
/// Anyway" — never forces a retake, never silently accepts nothing.
///
/// Reused downstream exactly like a picked file: [finish] hands back an
/// ordered list of page bytes that feeds the SAME
/// `DocumentService.extractFromImages` → `detectQuestions` → review
/// pipeline as PDF/DOCX/XLSX (Phase 1/26 — no second detection engine).
class CameraCaptureController extends DisposableNotifier {
  CameraCaptureController({CameraCaptureService? service})
    : _service = service ?? ImagePickerCameraCaptureService();

  final CameraCaptureService _service;

  /// Safe app-side ceiling — bounds memory for one in-flight batch
  /// (Phase 3 "safe system limit", Phase 33 "do not load every page image
  /// into memory simultaneously" — the compressed-JPEG ceiling below keeps
  /// a full batch in the tens of MB, not hundreds).
  static const maxPages = 20;

  final List<CapturedPage> _pages = [];
  CameraCaptureState _state = CameraCaptureState.idle;
  String? _errorMessage;
  int? _pendingQualityWarningIndex;

  List<CapturedPage> get pages => List.unmodifiable(_pages);
  int get pageCount => _pages.length;
  bool get isAtMax => _pages.length >= maxPages;
  CameraCaptureState get state => _state;
  String? get errorMessage => _errorMessage;

  /// Set right after a capture whose quality looked bad; the screen shows
  /// "Retake? / Keep Anyway" for exactly this page until resolved.
  int? get pendingQualityWarningIndex => _pendingQualityWarningIndex;

  bool get isBusy => _state == CameraCaptureState.capturing;

  /// Captures one page. Returns without adding anything if the user
  /// cancelled the camera or the page ceiling is already reached.
  Future<void> captureOne() async {
    if (isBusy) return;
    if (isAtMax) {
      _errorMessage =
          'You\'ve reached the maximum of $maxPages pages for one batch. '
          'Remove a page to add another, or finish with what you have.';
      _state = CameraCaptureState.error;
      notifyListeners();
      return;
    }
    _state = CameraCaptureState.capturing;
    _errorMessage = null;
    notifyListeners();
    try {
      final bytes = await _service.capturePhoto();
      if (bytes == null) {
        // User cancelled — not an error, just back to idle/done.
        _state = _pages.isEmpty ? CameraCaptureState.idle : CameraCaptureState.done;
        notifyListeners();
        return;
      }
      final quality = await _service.assessQuality(bytes);
      _pages.add(CapturedPage(bytes: bytes, quality: quality));
      if (quality != PageQuality.ok) {
        _pendingQualityWarningIndex = _pages.length - 1;
      }
      _state = CameraCaptureState.done;
    } on AppError catch (e) {
      _errorMessage = e.message;
      _state = CameraCaptureState.error;
    } catch (e, st) {
      AppLogger.error('Camera capture failed: $e', stackTrace: st);
      _errorMessage = 'Could not capture that page. Please try again.';
      _state = CameraCaptureState.error;
    }
    notifyListeners();
  }

  /// Resolves the pending quality warning by discarding the page and
  /// re-opening the camera for the same page position.
  Future<void> retakePending() async {
    final i = _pendingQualityWarningIndex;
    if (i == null || i >= _pages.length) return;
    _pages.removeAt(i);
    _pendingQualityWarningIndex = null;
    notifyListeners();
    await captureOne();
  }

  /// Resolves the pending quality warning by keeping the page as-is —
  /// Phase 5: "Do not force users to retake every imperfect page."
  void keepPendingAnyway() {
    _pendingQualityWarningIndex = null;
    notifyListeners();
  }

  void retake(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pages.removeAt(index);
    if (_pendingQualityWarningIndex == index) _pendingQualityWarningIndex = null;
    notifyListeners();
    captureOne();
  }

  void deletePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pages.removeAt(index);
    if (_pendingQualityWarningIndex == index) {
      _pendingQualityWarningIndex = null;
    } else if (_pendingQualityWarningIndex != null && _pendingQualityWarningIndex! > index) {
      _pendingQualityWarningIndex = _pendingQualityWarningIndex! - 1;
    }
    if (_pages.isEmpty) _state = CameraCaptureState.idle;
    notifyListeners();
  }

  void rotatePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pages[index] = _pages[index].rotated();
    notifyListeners();
  }

  void reorderPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length) return;
    if (newIndex < 0 || newIndex >= _pages.length) return;
    final item = _pages.removeAt(oldIndex);
    _pages.insert(newIndex, item);
    if (_pendingQualityWarningIndex == oldIndex) {
      _pendingQualityWarningIndex = newIndex;
    }
    notifyListeners();
  }

  /// Ordered, rotation-applied page bytes ready for extraction/upload.
  /// Rotated pages are re-encoded on a background isolate.
  Future<List<Uint8List>> finish() async {
    final out = <Uint8List>[];
    for (final p in _pages) {
      out.add(await p.finalBytesAsync());
    }
    return out;
  }

  void reset() {
    _pages.clear();
    _state = CameraCaptureState.idle;
    _errorMessage = null;
    _pendingQualityWarningIndex = null;
    notifyListeners();
  }
}

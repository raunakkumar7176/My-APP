import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../errors/app_error.dart';

/// Rotate + re-encode off the UI thread — a 20-page batch otherwise
/// decodes full JPEGs on the main isolate and visibly drops frames.
Uint8List _rotateAndEncode((Uint8List, int) input) {
  final (bytes, turns) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final rotated = img.copyRotate(decoded, angle: 90.0 * turns);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
}

/// Quality heuristic off the UI thread (see [PageQuality] for scope).
PageQuality _assessQuality(Uint8List bytes) {
  // `decodeImage` throws (rather than returning null) on some truncated /
  // malformed inputs once a format sniff partially matches — never let a
  // corrupt photo crash the capture flow.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return PageQuality.unreadableFormat;
  }
  if (decoded == null) return PageQuality.unreadableFormat;

  // Sample a bounded grid of pixels rather than every pixel — this must
  // stay fast for a 20-page batch.
  const samplesPerSide = 24;
  final stepX = (decoded.width / samplesPerSide).clamp(1, decoded.width).floor();
  final stepY = (decoded.height / samplesPerSide).clamp(1, decoded.height).floor();

  var sum = 0.0;
  var sumSq = 0.0;
  var count = 0;
  for (var y = 0; y < decoded.height; y += stepY) {
    for (var x = 0; x < decoded.width; x += stepX) {
      final p = decoded.getPixel(x, y);
      // Perceived luminance (0..255).
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      sum += l;
      sumSq += l * l;
      count++;
    }
  }
  if (count == 0) return PageQuality.ok;
  final mean = sum / count;
  final variance = (sumSq / count) - (mean * mean);

  // Thresholds are deliberately conservative — a false "keep anyway" is
  // far cheaper than blocking a perfectly readable page.
  if (mean < 40) return PageQuality.tooDark;
  if (variance < 25) return PageQuality.blank; // near-uniform: blank/lens-cap
  return PageQuality.ok;
}

/// One captured/edited page, in memory. Bytes are always a decodable image
/// (JPEG/PNG); [rotationQuarterTurns] is applied lazily by [rotated] rather
/// than mutating the stored bytes on every rotate tap.
final class CapturedPage {
  const CapturedPage({
    required this.bytes,
    this.rotationQuarterTurns = 0,
    this.quality = PageQuality.ok,
  });

  final Uint8List bytes;

  /// 0..3 — applied on top of [bytes] when the page is finally used.
  final int rotationQuarterTurns;

  final PageQuality quality;

  CapturedPage rotated() => CapturedPage(
    bytes: bytes,
    rotationQuarterTurns: (rotationQuarterTurns + 1) % 4,
    quality: quality,
  );

  /// Bytes with rotation baked in, ready to hand to extraction/upload.
  /// Runs rotate+encode on a background isolate when a rotation is pending.
  Future<Uint8List> finalBytesAsync() async {
    if (rotationQuarterTurns == 0) return bytes;
    return compute(_rotateAndEncode, (bytes, rotationQuarterTurns));
  }
}

/// A cheap, honest heuristic — not real blur/edge detection (that needs a
/// vision library this app doesn't have). "Too dark" and "blank" are
/// measurable from raw pixels; true blur is not, so it is never claimed.
enum PageQuality { ok, tooDark, blank, unreadableFormat }

/// Camera page capture + a lightweight readability check.
///
/// SECURITY / PERFORMANCE: images are held as compressed JPEG bytes in
/// memory only for the duration of one capture session (never written to
/// permanent storage until the user finishes and the existing
/// [DocumentService] upload path runs); [CameraCaptureController] enforces
/// the page-count and total-memory ceiling — this service does not.
abstract interface class CameraCaptureService {
  /// Opens the device camera for one photo. Returns null if the user
  /// cancelled. Throws [AuthError]-shaped [AppError] on permission denial
  /// where the platform reports it as an exception rather than a null.
  Future<Uint8List?> capturePhoto();

  /// Cheap quality check on already-captured bytes (runs off the UI thread).
  Future<PageQuality> assessQuality(Uint8List bytes);
}

class ImagePickerCameraCaptureService implements CameraCaptureService {
  ImagePickerCameraCaptureService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Compressed on capture so a 20-page batch stays well under memory /
  /// upload limits without visibly hurting OCR-relevant readability.
  static const _maxDimension = 2000.0;
  static const _jpegQuality = 85;

  @override
  Future<Uint8List?> capturePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _jpegQuality,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission') || msg.contains('denied')) {
        throw const AuthError(
          message: 'Camera permission is needed to take photos. '
              'Enable it in your device settings and try again.',
        );
      }
      throw const DataError(
        message: 'Could not open the camera. Please try again.',
      );
    }
  }

  @override
  Future<PageQuality> assessQuality(Uint8List bytes) =>
      compute(_assessQuality, bytes);
}

// Unified Content-to-Test V1 — camera multi-page capture: service quality
// heuristic on real pixels, and the controller's page management
// (add/retake/delete/reorder/rotate/max-limit/empty-batch).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/services/camera_capture_service.dart';
import 'package:my_praperation/features/test/state/camera_capture_controller.dart';

Uint8List _solidJpeg(int r, int g, int b, {int size = 40}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _variedJpeg({int size = 40}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, (x * 20) % 255, (y * 20) % 255, (x + y) % 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

class FakeCameraCaptureService implements CameraCaptureService {
  final List<Uint8List?> queuedPhotos = [];
  final List<PageQuality> queuedQualities = [];
  Object? pickError;
  int captureCalls = 0;

  @override
  Future<Uint8List?> capturePhoto() async {
    captureCalls++;
    if (pickError != null) {
      final e = pickError!;
      pickError = null;
      throw e;
    }
    if (queuedPhotos.isEmpty) return _variedJpeg();
    return queuedPhotos.removeAt(0);
  }

  @override
  Future<PageQuality> assessQuality(Uint8List bytes) async {
    if (queuedQualities.isNotEmpty) return queuedQualities.removeAt(0);
    return PageQuality.ok;
  }
}

void main() {
  group('ImagePickerCameraCaptureService.assessQuality (real pixels)', () {
    final service = ImagePickerCameraCaptureService();

    test('a mostly black photo is too dark', () async {
      expect(await service.assessQuality(_solidJpeg(5, 5, 5)),
          PageQuality.tooDark);
    });

    test('a uniform mid-tone photo (blank/lens-cap) is flagged blank',
        () async {
      expect(await service.assessQuality(_solidJpeg(120, 120, 120)),
          PageQuality.blank);
    });

    test('a photo with real variation is ok', () async {
      expect(await service.assessQuality(_variedJpeg()), PageQuality.ok);
    });

    test('undecodable bytes are unreadableFormat, not a crash', () async {
      expect(
        await service.assessQuality(Uint8List.fromList([1, 2, 3, 4])),
        PageQuality.unreadableFormat,
      );
    });
  });

  group('CameraCaptureController — single/multi-page capture', () {
    late FakeCameraCaptureService service;
    late CameraCaptureController controller;

    setUp(() {
      service = FakeCameraCaptureService();
      controller = CameraCaptureController(service: service);
    });

    tearDown(() => controller.dispose());

    test('starts empty, idle', () {
      expect(controller.pages, isEmpty);
      expect(controller.state, CameraCaptureState.idle);
    });

    test('capturing one page adds it and moves to done', () async {
      await controller.captureOne();
      expect(controller.pageCount, 1);
      expect(controller.state, CameraCaptureState.done);
    });

    test('capturing multiple pages preserves order', () async {
      service.queuedPhotos.addAll([
        _solidJpeg(200, 0, 0),
        _solidJpeg(0, 200, 0),
        _solidJpeg(0, 0, 200),
      ]);
      for (var i = 0; i < 3; i++) {
        await controller.captureOne();
      }
      expect(controller.pageCount, 3);
      expect(controller.pages[0].bytes, isNot(equals(controller.pages[1].bytes)));
    });

    test('user cancelling the camera (null) adds nothing', () async {
      service.queuedPhotos.add(null);
      await controller.captureOne();
      expect(controller.pages, isEmpty);
      expect(controller.state, CameraCaptureState.idle);
    });

    test('camera permission denial surfaces a clear error, not a crash', () async {
      service.pickError = const AuthError(message: 'Camera permission is needed…');
      await controller.captureOne();
      expect(controller.state, CameraCaptureState.error);
      expect(controller.errorMessage, contains('Camera permission'));
    });
  });

  group('CameraCaptureController — page management', () {
    late FakeCameraCaptureService service;
    late CameraCaptureController controller;

    setUp(() async {
      service = FakeCameraCaptureService();
      controller = CameraCaptureController(service: service);
      service.queuedPhotos.addAll([
        _solidJpeg(200, 0, 0),
        _solidJpeg(0, 200, 0),
        _solidJpeg(0, 0, 200),
      ]);
      for (var i = 0; i < 3; i++) {
        await controller.captureOne();
      }
    });

    tearDown(() => controller.dispose());

    test('deletePage removes exactly that page', () {
      final middle = controller.pages[1].bytes;
      controller.deletePage(1);
      expect(controller.pageCount, 2);
      expect(controller.pages.any((p) => p.bytes == middle), isFalse);
    });

    test('deleting every page returns to idle', () {
      controller.deletePage(0);
      controller.deletePage(0);
      controller.deletePage(0);
      expect(controller.pages, isEmpty);
      expect(controller.state, CameraCaptureState.idle);
    });

    test('reorderPage moves a page without dropping others', () {
      final first = controller.pages[0].bytes;
      controller.reorderPage(0, 2);
      expect(controller.pages.last.bytes, first);
      expect(controller.pageCount, 3);
    });

    test('rotatePage cycles 0->1->2->3->0 and changes finalBytes', () async {
      final before = await controller.pages[0].finalBytesAsync();
      controller.rotatePage(0);
      expect(controller.pages[0].rotationQuarterTurns, 1);
      expect(await controller.pages[0].finalBytesAsync(), isNot(equals(before)));
      controller.rotatePage(0);
      controller.rotatePage(0);
      controller.rotatePage(0);
      expect(controller.pages[0].rotationQuarterTurns, 0);
    });

    test('retake discards the page and captures a fresh one at the same slot', () async {
      service.queuedPhotos.add(_solidJpeg(9, 9, 9));
      final before = controller.pages[1].bytes;
      controller.retake(1);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pageCount, 3);
      expect(controller.pages[1].bytes, isNot(equals(before)));
    });

    test('finish returns pages in order with rotation applied', () async {
      controller.rotatePage(1);
      final result = await controller.finish();
      expect(result.length, 3);
      expect(result[1], await controller.pages[1].finalBytesAsync());
    });

    test('reset clears everything back to idle', () {
      controller.reset();
      expect(controller.pages, isEmpty);
      expect(controller.state, CameraCaptureState.idle);
    });
  });

  group('CameraCaptureController — safe maximum', () {
    test('capture stops accepting new pages at maxPages with a clear message', () async {
      final service = FakeCameraCaptureService();
      final controller = CameraCaptureController(service: service);
      for (var i = 0; i < CameraCaptureController.maxPages; i++) {
        await controller.captureOne();
      }
      expect(controller.pageCount, CameraCaptureController.maxPages);
      expect(controller.isAtMax, isTrue);

      await controller.captureOne();
      expect(controller.pageCount, CameraCaptureController.maxPages, reason: 'no page beyond the ceiling');
      expect(controller.state, CameraCaptureState.error);
      expect(controller.errorMessage, contains('maximum'));
      expect(service.captureCalls, CameraCaptureController.maxPages, reason: 'the camera is never even opened once at the ceiling');
      controller.dispose();
    });
  });

  group('CameraCaptureController — quality warning flow', () {
    late FakeCameraCaptureService service;
    late CameraCaptureController controller;

    setUp(() {
      service = FakeCameraCaptureService();
      controller = CameraCaptureController(service: service);
    });

    tearDown(() => controller.dispose());

    test('a low-quality capture sets a pending warning; keeping it clears the warning without removing the page', () async {
      service.queuedQualities.add(PageQuality.tooDark);
      await controller.captureOne();
      expect(controller.pendingQualityWarningIndex, 0);

      controller.keepPendingAnyway();
      expect(controller.pendingQualityWarningIndex, isNull);
      expect(controller.pageCount, 1);
    });

    test('retaking a flagged page removes it and captures a replacement', () async {
      service.queuedQualities.add(PageQuality.blank);
      await controller.captureOne();
      expect(controller.pendingQualityWarningIndex, 0);

      service.queuedPhotos.add(_variedJpeg());
      await controller.retakePending();
      expect(controller.pendingQualityWarningIndex, isNull);
      expect(controller.pageCount, 1);
    });

    test('a good-quality capture never sets a pending warning', () async {
      await controller.captureOne();
      expect(controller.pendingQualityWarningIndex, isNull);
    });
  });
}

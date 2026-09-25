// Unified Content-to-Test V1 — widget tests for the camera capture screen:
// thumbnail grid, add/retake/delete/rotate, the quality "Retake / Keep
// Anyway" dialog, and returning ordered pages via GoRouter pop.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:my_praperation/core/services/camera_capture_service.dart';
import 'package:my_praperation/features/test/screens/camera_capture_screen.dart';
import 'package:my_praperation/features/test/state/camera_capture_controller.dart';

/// A real, decodable 8x8 JPEG (the tile renders it with `Image.memory`, which
/// needs valid image bytes, unlike the pure-Dart controller/service tests).
Uint8List _fakePhoto([int shade = 128]) {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  return Uint8List.fromList(img.encodeJpg(image));
}

class _FakeCameraCaptureService implements CameraCaptureService {
  final List<Uint8List?> queuedPhotos = [];
  final List<PageQuality> queuedQualities = [];

  @override
  Future<Uint8List?> capturePhoto() async {
    if (queuedPhotos.isEmpty) return _fakePhoto();
    return queuedPhotos.removeAt(0);
  }

  @override
  Future<PageQuality> assessQuality(Uint8List bytes) async {
    if (queuedQualities.isNotEmpty) return queuedQualities.removeAt(0);
    return PageQuality.ok;
  }
}

void main() {
  Widget host(CameraCaptureController controller, {VoidCallback? onPopped}) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, _) => CameraCaptureScreen(controller: controller),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('opens straight into the first capture and shows one page', (tester) async {
    final service = _FakeCameraCaptureService();
    final controller = CameraCaptureController(service: service);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    expect(find.text('1 page added'), findsOneWidget);
    expect(find.byKey(const Key('camera_page_0')), findsOneWidget);
  });

  testWidgets('Add Page increases the count and shows a new thumbnail', (tester) async {
    final service = _FakeCameraCaptureService();
    final controller = CameraCaptureController(service: service);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('camera_add_page')));
    await tester.pumpAndSettle();

    expect(find.text('2 pages added'), findsOneWidget);
    expect(find.byKey(const Key('camera_page_1')), findsOneWidget);
  });

  testWidgets('a low-quality capture shows Retake/Keep Anyway and Keep Anyway keeps the page', (tester) async {
    final service = _FakeCameraCaptureService()..queuedQualities.add(PageQuality.tooDark);
    final controller = CameraCaptureController(service: service);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera_quality_dialog')), findsOneWidget);
    expect(find.text('This page looks very dark.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('camera_quality_keep')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera_quality_dialog')), findsNothing);
    expect(find.text('1 page added'), findsOneWidget);
  });

  testWidgets('Retake on the quality dialog re-captures the same page', (tester) async {
    final service = _FakeCameraCaptureService()
      ..queuedQualities.add(PageQuality.blank)
      ..queuedPhotos.add(_fakePhoto(200));
    final controller = CameraCaptureController(service: service);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('camera_quality_retake')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera_quality_dialog')), findsNothing);
    expect(find.text('1 page added'), findsOneWidget);
  });

  testWidgets('deleting the only page returns to the empty state', (tester) async {
    final service = _FakeCameraCaptureService();
    final controller = CameraCaptureController(service: service);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    final deleteButton = find.byKey(const Key('camera_delete_0'));
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('No pages yet'), findsOneWidget);
    expect(find.byKey(const Key('camera_done')), findsOneWidget);
    final doneButton = tester.widget<FilledButton>(find.byKey(const Key('camera_done')));
    expect(doneButton.onPressed, isNull, reason: 'cannot finish with zero pages');
  });

  testWidgets('Done returns the ordered page bytes to the caller', (tester) async {
    final service = _FakeCameraCaptureService()
      ..queuedPhotos.addAll([
        _fakePhoto(50),
        _fakePhoto(150),
      ]);
    final controller = CameraCaptureController(service: service);
    List<Uint8List>? result;

    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => ElevatedButton(
            onPressed: () async {
              result = await context.push<List<Uint8List>>('/camera');
            },
            child: const Text('open'),
          ),
        ),
        GoRoute(
          path: '/camera',
          builder: (_, _) => CameraCaptureScreen(controller: controller),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('camera_add_page')));
    await tester.pumpAndSettle();
    expect(find.text('2 pages added'), findsOneWidget);

    await tester.tap(find.byKey(const Key('camera_done')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 2);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_praperation/core/services/settings/library_mode_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryModeController.instance.init();
  });

  tearDown(() async {
    await LibraryModeController.instance.stopFocusSession();
  });

  group('LibraryModeController', () {
    test('initial state is false when not configured', () {
      expect(LibraryModeController.instance.isLibraryMode, isFalse);
      expect(LibraryModeController.instance.remainingTime, isNull);
    });

    test('toggleLibraryMode switches state and notifies listeners', () async {
      final controller = LibraryModeController.instance;
      var notified = false;
      controller.addListener(() => notified = true);

      await controller.toggleLibraryMode();
      expect(controller.isLibraryMode, isTrue);
      expect(notified, isTrue);

      await controller.toggleLibraryMode();
      expect(controller.isLibraryMode, isFalse);
    });

    test('startFocusSession enables library mode and sets countdown timer', () async {
      final controller = LibraryModeController.instance;
      await controller.startFocusSession(const Duration(minutes: 45));

      expect(controller.isLibraryMode, isTrue);
      expect(controller.remainingTime, isNotNull);
      expect(controller.remainingTime!.inMinutes, greaterThanOrEqualTo(44));
      expect(controller.formattedRemainingTime, contains('m'));

      await controller.stopFocusSession();
      expect(controller.isLibraryMode, isFalse);
      expect(controller.remainingTime, isNull);
    });

    test('auto-routine triggers and restores library mode if enabled', () async {
      final controller = LibraryModeController.instance;
      await controller.setLibraryMode(false);
      await controller.setAutoRoutineEnabled(true);

      // Slot becomes active
      await controller.handleRoutineSlotChange(isStudySlotActive: true);
      expect(controller.isLibraryMode, isTrue);

      // Slot ends
      await controller.handleRoutineSlotChange(isStudySlotActive: false);
      expect(controller.isLibraryMode, isFalse);
    });
  });
}

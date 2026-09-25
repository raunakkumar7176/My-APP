// Push — Settings screen. Widget tests using a fake repository (existing
// convention for this app's tests) and a fake PushPermissionGateway so no
// Firebase/permission_handler call ever happens in a test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/services/push_notification_service.dart';
import 'package:my_praperation/features/notifications/data/notification_settings.dart';
import 'package:my_praperation/features/notifications/data/notification_settings_repository.dart';
import 'package:my_praperation/features/notifications/screens/notification_settings_screen.dart';
import 'package:my_praperation/features/notifications/state/notification_settings_controller.dart';

class _FakeSettingsRepository implements NotificationSettingsRepository {
  NotificationSettings current = const NotificationSettings(userId: 'u1');
  Object? getError;
  Object? updateError;

  @override
  Future<NotificationSettings> get() async {
    if (getError != null) throw getError!;
    return current;
  }

  @override
  Future<NotificationSettings> update(NotificationSettings settings) async {
    if (updateError != null) throw updateError!;
    current = settings;
    return settings;
  }
}

class _FakePushGateway implements PushPermissionGateway {
  SystemPermissionStatus statusToReturn = SystemPermissionStatus.denied;
  SystemPermissionStatus? requestResult;
  bool openSettingsCalled = false;
  bool registerCalled = false;
  final List<String> calls = [];

  @override
  Future<SystemPermissionStatus> checkPermissionStatus() async {
    calls.add('checkPermissionStatus');
    return statusToReturn;
  }

  @override
  Future<SystemPermissionStatus> requestPermissionWithRationale(BuildContext context) async {
    calls.add('requestPermissionWithRationale');
    return requestResult ?? statusToReturn;
  }

  @override
  Future<void> openAndroidNotificationSettings() async {
    calls.add('openAndroidNotificationSettings');
    openSettingsCalled = true;
  }

  @override
  Future<void> registerCurrentDevice() async {
    calls.add('registerCurrentDevice');
    registerCalled = true;
  }
}

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  group('Push permission status display', () {
    testWidgets('granted: shows enabled status, no Open Settings button', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway()..statusToReturn = SystemPermissionStatus.granted;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Notifications enabled'), findsOneWidget);
      expect(find.byKey(const Key('open_android_settings_button')), findsNothing);
    });

    testWidgets('denied: shows permission-required status', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway()..statusToReturn = SystemPermissionStatus.denied;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Permission required'), findsOneWidget);
    });

    testWidgets('permanently denied: shows the Open Settings button, toggle disabled', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway()..statusToReturn = SystemPermissionStatus.permanentlyDenied;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Notifications disabled in Android Settings'), findsOneWidget);
      expect(find.byKey(const Key('open_android_settings_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open_android_settings_button')));
      expect(gateway.openSettingsCalled, isTrue);

      final toggle = tester.widget<SwitchListTile>(find.byKey(const Key('push_enabled_toggle')));
      expect(toggle.onChanged, isNull);
    });

    testWidgets('the app never shows push as ON when the OS permission is not granted', (tester) async {
      // Settings row itself claims push_enabled=true, but the OS says
      // denied — Phase 14's core rule: never lie about this.
      final repo = _FakeSettingsRepository()
        ..current = const NotificationSettings(userId: 'u1', pushEnabled: true);
      final gateway = _FakePushGateway()..statusToReturn = SystemPermissionStatus.denied;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(find.byKey(const Key('push_enabled_toggle')));
      expect(toggle.value, isFalse);
    });
  });

  group('Enabling push', () {
    testWidgets('toggling on requests permission, then registers the device and saves push_enabled=true', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway()
        ..statusToReturn = SystemPermissionStatus.denied
        ..requestResult = SystemPermissionStatus.granted;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('push_enabled_toggle')));
      await tester.pumpAndSettle();

      expect(gateway.calls, contains('requestPermissionWithRationale'));
      expect(gateway.registerCalled, isTrue);
      expect(repo.current.pushEnabled, isTrue);
    });

    testWidgets('a denied permission request leaves push_enabled false, does not register a device', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway()
        ..statusToReturn = SystemPermissionStatus.denied
        ..requestResult = SystemPermissionStatus.denied;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('push_enabled_toggle')));
      await tester.pumpAndSettle();

      expect(gateway.registerCalled, isFalse);
      expect(repo.current.pushEnabled, isFalse);
    });
  });

  group('Disabling push', () {
    testWidgets('toggling off (when already granted) just saves push_enabled=false, no permission prompt', (tester) async {
      final repo = _FakeSettingsRepository()
        ..current = const NotificationSettings(userId: 'u1', pushEnabled: true);
      final gateway = _FakePushGateway()..statusToReturn = SystemPermissionStatus.granted;
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('push_enabled_toggle')));
      await tester.pumpAndSettle();

      expect(gateway.calls, isNot(contains('requestPermissionWithRationale')));
      expect(repo.current.pushEnabled, isFalse);
    });
  });

  group('Existing behavior preserved', () {
    testWidgets('master toggle off hides categories and the push section, does not crash', (tester) async {
      final repo = _FakeSettingsRepository()
        ..current = const NotificationSettings(userId: 'u1', notificationsEnabled: false);
      final gateway = _FakePushGateway();
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('push_enabled_toggle')), findsNothing);
      expect(find.byKey(const Key('toggle_group_messages')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category toggles still work exactly as before', (tester) async {
      final repo = _FakeSettingsRepository();
      final gateway = _FakePushGateway();
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle_group_messages')));
      await tester.pumpAndSettle();

      expect(repo.current.groupMessages, isFalse);
    });

    testWidgets('a settings load failure shows the error state, not a crash', (tester) async {
      final repo = _FakeSettingsRepository()
        ..getError = const DataError(message: 'network down');
      final gateway = _FakePushGateway();
      await tester.pumpWidget(host(NotificationSettingsScreen(
        controller: NotificationSettingsController(repository: repo),
        pushGateway: gateway,
      )));
      await tester.pumpAndSettle();

      expect(find.text('network down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

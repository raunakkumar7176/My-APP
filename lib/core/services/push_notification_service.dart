import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_router.dart';
import '../../features/notifications/state/notification_deep_link_handler.dart';
import '../logging/app_logger.dart';
import '../models/app_notification.dart';
import 'auth_service.dart';
import 'device_token_service.dart';

/// One Android notification channel per notification "family" (Phase 9) —
/// never one generic channel for everything, so the user can control each
/// category's importance/sound independently from Android Settings.
/// MUST be kept in sync with `androidChannelForCategory` in
/// `My-Prepration/src/lib/push/fcm.ts` (server side sets the same channel
/// id on the FCM payload so a background/terminated-delivered system
/// notification lands in the right channel too).
enum PushChannel {
  testExam('test_exam', 'Test & Exam', 'Live tests, invitations, and start reminders', Importance.high),
  testResult('test_result', 'Test Results', 'Results, reports, and leaderboard updates', Importance.high),
  group('group', 'Group Activity', 'Group chat, announcements, and membership', Importance.defaultImportance),
  routineReminder('routine_reminder', 'Study Reminders', 'Routine and streak reminders', Importance.defaultImportance),
  general('general', 'General', 'Other notifications', Importance.defaultImportance),
  importantSystem('important_system', 'Important', 'Critical account and system alerts', Importance.max);

  const PushChannel(this.id, this.title, this.description, this.importance);
  final String id;
  final String title;
  final String description;
  final Importance importance;
}

/// Maps a live `notif_category` (see [NotificationCategory]) to the Android
/// channel it should ring on. Explicit per-category, not a prefix guess —
/// see the matching comment in `fcm.ts` for why.
PushChannel channelForCategory(String category) {
  const map = <String, PushChannel>{
    'GROUP_MESSAGE': PushChannel.group,
    'GROUP_ANNOUNCEMENT': PushChannel.group,
    'GROUP_JOIN': PushChannel.group,
    'GROUP_TEST_ASSIGNED': PushChannel.group,
    'GROUP_TEST_REMINDER': PushChannel.group,
    'GROUP_JOIN_REQUEST': PushChannel.group,
    'JOIN_ACCEPTED': PushChannel.group,
    'JOIN_REJECTED': PushChannel.group,
    'ROLE_CHANGED': PushChannel.group,
    'MEMBER_REMOVED': PushChannel.group,
    'TEST_REMINDER': PushChannel.testExam,
    'TEST_LIVE': PushChannel.testExam,
    'TEST_INVITATION': PushChannel.testExam,
    'TEST_SCHEDULED': PushChannel.testExam,
    'TEST_STARTING_SOON': PushChannel.testExam,
    'TEST_STARTED': PushChannel.testExam,
    'TEST_ENDED': PushChannel.testExam,
    'TEST_COMPLETED': PushChannel.testResult,
    'RESULTS_AVAILABLE': PushChannel.testResult,
    'LEADERBOARD_UPDATED': PushChannel.testResult,
    'REPORT_READY': PushChannel.testResult,
    'ROUTINE_REMINDER': PushChannel.routineReminder,
    'ROUTINE_DUE': PushChannel.routineReminder,
    'ROUTINE_MISSED': PushChannel.routineReminder,
    'ROUTINE_COMPLETED': PushChannel.routineReminder,
    'STREAK_MILESTONE': PushChannel.routineReminder,
    'SYSTEM_NOTIFICATION': PushChannel.importantSystem,
    'CONTENT_REVIEW_RESULT': PushChannel.general,
  };
  return map[category.toUpperCase()] ?? PushChannel.general;
}

/// The Android system permission state, normalized to what the Settings UI
/// (Phase 14) needs to show — distinct from `notification_settings.
/// push_enabled` (the app-level preference), never conflated with it.
enum SystemPermissionStatus { granted, denied, permanentlyDenied, notRequestedYet }

/// Top-level, `@pragma('vm:entry-point')` background handler — required by
/// firebase_messaging to run in a separate background isolate with NO
/// BuildContext and no access to any running app state. Does not (and must
/// not) touch the UI: Android's own FCM/notification-tray handling already
/// displays the system notification for a "notification message" while the
/// app is backgrounded/terminated (Phase 8) — this only exists so the
/// plugin has a registered handler at all; showing anything here would be
/// the exact duplicate-notification bug Phase 7 warns against.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — see doc comment above.
}

/// Orchestrates the whole mobile push pipeline: Firebase init, Android
/// notification channels, permission request (with rationale + "don't
/// annoy repeatedly" + permanently-denied handling), FCM token lifecycle,
/// foreground display, and tap → deep link (reusing the existing
/// [NotificationDeepLinkHandler] so system-push taps resolve exactly the
/// same destinations the in-app notification list already does).
///
/// The Settings screen (Phase 14) depends only on this narrower interface,
/// not the concrete [PushNotificationService], so it can be faked in
/// widget tests without touching Firebase/permission_handler.
abstract interface class PushPermissionGateway {
  Future<SystemPermissionStatus> checkPermissionStatus();
  Future<SystemPermissionStatus> requestPermissionWithRationale(BuildContext context);
  Future<void> openAndroidNotificationSettings();
  Future<void> registerCurrentDevice();
}

class PushNotificationService implements PushPermissionGateway {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _prefsAskedKey = 'push_permission_asked_at';

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  DeviceTokenService _tokenService = SupabaseDeviceTokenService();
  bool _initialized = false;
  Future<void>? _initFuture;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  @visibleForTesting
  void setTokenServiceForTesting(DeviceTokenService service) => _tokenService = service;

  /// The group whose chat is currently on screen, if any — set by
  /// `GroupHubController` on open/dispose. Used only to skip a redundant
  /// foreground toast for a `GROUP_MESSAGE` push about the group the user
  /// is already looking at (realtime already updated that screen; the
  /// server-side dedupe/exclude rules in `fn_notify_group` are unrelated
  /// and untouched — this is purely a client-side "don't repeat what's
  /// already visible" guard).
  String? activeGroupId;

  /// Call once at app startup, before requesting permission or registering
  /// a token. Sets up Firebase, local-notification channels, and message
  /// listeners. Safe to call on a platform/build where Firebase isn't
  /// configured yet (e.g. no `google-services.json`) — logs and no-ops
  /// rather than crashing the app. Does not block the first frame: the
  /// returned future completes whenever init actually finishes.
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      AppLogger.error('Firebase.initializeApp failed — push notifications disabled: $e', stackTrace: st);
      return; // No Firebase config yet: the rest of the app must keep working.
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _initLocalNotifications();
    await _createChannels();

    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _persistToken(token);
    });

    _initialized = true;
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateToPath(payload);
        }
      },
    );
  }

  Future<void> _createChannels() async {
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    await Future.wait([
      for (final ch in PushChannel.values)
        androidPlugin.createNotificationChannel(
          AndroidNotificationChannel(
            ch.id,
            ch.title,
            description: ch.description,
            importance: ch.importance,
            // Sound/vibration follow the channel's importance and the
            // user's own Android channel settings (Phase 10) — never forced
            // here; leaving these unset uses the platform default for the
            // channel's importance level, which the user can still override
            // per-channel from Android Settings at any time.
          ),
        ),
    ]);
  }

  // ── Foreground display (Phase 7) ──

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return; // data-only message: nothing to show
    final category = message.data['category'] as String? ?? '';
    if (category == 'GROUP_MESSAGE' &&
        activeGroupId != null &&
        message.data['group_id'] == activeGroupId) {
      // The user is already viewing this group's chat — realtime already
      // rendered the message there; a toast on top would just be noise.
      return;
    }
    final channel = channelForCategory(category);

    _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.title,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
        ),
      ),
      payload: _resolvePathFromData(message.data),
    );
  }

  // ── Tap → deep link (Phase 11) ──

  void _handleNotificationTap(RemoteMessage message) {
    _navigateToPath(_resolvePathFromData(message.data));
  }

  String _resolvePathFromData(Map<String, dynamic> data) {
    final notification = AppNotification.fromJson({
      'id': data['notification_id'] ?? '',
      'user_id': AuthService.currentUser?.id ?? '',
      'category': data['category'] ?? '',
      'title': '',
      'body': '',
      'data': data,
      'created_at': DateTime.now().toIso8601String(),
    });
    return NotificationDeepLinkHandler.resolvePath(notification);
  }

  void _navigateToPath(String path) {
    try {
      AppRouter.router.push(path);
    } catch (e, st) {
      AppLogger.error('Push tap navigation failed: $path', stackTrace: st);
    }
  }

  /// Cold-start deep link (Phase 11: "if the app was completely closed,
  /// deep link must still work"). Call once, after the router is mounted.
  Future<void> handleColdStartDeepLink() async {
    await _initFuture; // push init runs after the first frame — wait for it
    if (!_initialized) return;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleNotificationTap(initial);
    } catch (e) {
      AppLogger.warning('getInitialMessage failed: $e');
    }
  }

  // ── Permission (Phase 3) ──

  @override
  Future<SystemPermissionStatus> checkPermissionStatus() async {
    if (!Platform.isAndroid) return SystemPermissionStatus.notRequestedYet;
    final status = await Permission.notification.status;
    return switch (status) {
      PermissionStatus.granted => SystemPermissionStatus.granted,
      PermissionStatus.permanentlyDenied => SystemPermissionStatus.permanentlyDenied,
      PermissionStatus.denied => SystemPermissionStatus.denied,
      _ => SystemPermissionStatus.notRequestedYet,
    };
  }

  /// Whether the "why notifications are useful" rationale has already been
  /// shown once — used to avoid re-prompting a user who dismissed it,
  /// satisfying "must not repeatedly annoy the user" without ever hiding
  /// the option to turn push on later from Settings.
  Future<bool> hasAskedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefsAskedKey);
  }

  Future<void> _markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAskedKey, DateTime.now().toIso8601String());
  }

  /// Shows a short rationale dialog, then requests the OS permission
  /// (Android 13+ POST_NOTIFICATIONS; a no-op grant on older Android,
  /// which never gated notifications behind a runtime permission). Safe to
  /// call multiple times — only actually prompts the OS once per the
  /// platform's own one-shot-unless-permanently-denied rule.
  @override
  Future<SystemPermissionStatus> requestPermissionWithRationale(BuildContext context) async {
    await _markAsked();

    if (context.mounted) {
      final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.notifications_active_outlined, size: 40),
              title: const Text('Stay updated'),
              content: const Text(
                'Turn on notifications to get alerted when a test starts, '
                'your result is ready, or there\'s new activity in your groups.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed) return checkPermissionStatus();
    }

    final result = await Permission.notification.request();
    return switch (result) {
      PermissionStatus.granted => SystemPermissionStatus.granted,
      PermissionStatus.permanentlyDenied => SystemPermissionStatus.permanentlyDenied,
      _ => SystemPermissionStatus.denied,
    };
  }

  @override
  Future<void> openAndroidNotificationSettings() async {
    await openAppSettings();
  }

  // ── Token lifecycle (Phase 5/16) ──

  /// Call after login (and whenever the app resumes with push enabled):
  /// gets the current FCM token (if permission is already granted — never
  /// requests permission itself, so this never surprises the user with a
  /// system dialog outside an explicit onboarding/settings moment) and
  /// persists it.
  @override
  Future<void> registerCurrentDevice() async {
    if (!_initialized) return;
    if (!Platform.isAndroid) return;
    final status = await checkPermissionStatus();
    if (status != SystemPermissionStatus.granted) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _persistToken(token);
    } catch (e, st) {
      AppLogger.error('FCM token registration failed: $e', stackTrace: st);
    }
  }

  Future<void> _persistToken(String token) async {
    try {
      await _tokenService.registerToken(fcmToken: token, appVersion: null);
    } catch (e) {
      AppLogger.warning('Device token persist failed: $e');
    }
  }

  /// Call on logout: deactivates only THIS device's token (never every
  /// device the user is signed into — Phase 16).
  Future<void> deactivateCurrentDevice() async {
    if (!_initialized || !Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _tokenService.deactivateToken(token);
    } catch (e) {
      AppLogger.warning('Device token deactivate-on-logout failed: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}

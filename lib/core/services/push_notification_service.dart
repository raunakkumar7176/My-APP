import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

import '../../app/app_router.dart';
import '../../features/notifications/state/notification_deep_link_handler.dart';
import '../logging/app_logger.dart';
import '../models/app_notification.dart';
import 'auth_service.dart';
import 'device_identity.dart';
import 'device_token_service.dart';
import 'single_device_enforcer.dart';

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
  routineAlarm('routine_alarm', 'Study Session Alarms', 'Exact-time alarms for routine sessions', Importance.max),
  general('general', 'General', 'Other notifications', Importance.defaultImportance),
  importantSystem('important_system', 'Important', 'Critical account and system alerts', Importance.max),
  // Distinct-tone channels (carved out of the broader channels above so
  // each of these specific moments gets its own custom sound — Android
  // ties a sound to the CHANNEL, not the individual notification, so a
  // shared sound for all of "test_exam" would mean every one of those
  // categories rings the same way).
  testStart('test_start', 'Live Test & Challenge Alerts', 'A live test or challenge is starting now', Importance.max),
  testScheduled('test_scheduled', 'Test Scheduled', 'A new test has been scheduled', Importance.high),
  routineStart('routine_start', 'Study Slot Starting', 'A routine study slot is starting now', Importance.high),
  groupChat('group_chat', 'Group Chat Messages', 'New messages in your study groups', Importance.defaultImportance),
  groupAnnouncement('group_announcement', 'Group Announcements', 'Owner/manager notices in your study groups', Importance.high);

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
    'GROUP_MESSAGE': PushChannel.groupChat,
    'GROUP_ANNOUNCEMENT': PushChannel.groupAnnouncement,
    'GROUP_JOIN': PushChannel.group,
    'GROUP_TEST_ASSIGNED': PushChannel.group,
    'GROUP_TEST_REMINDER': PushChannel.group,
    'GROUP_JOIN_REQUEST': PushChannel.group,
    'JOIN_ACCEPTED': PushChannel.group,
    'JOIN_REJECTED': PushChannel.group,
    'ROLE_CHANGED': PushChannel.group,
    'MEMBER_REMOVED': PushChannel.group,
    'TEST_REMINDER': PushChannel.testExam,
    'TEST_LIVE': PushChannel.testStart,
    'TEST_INVITATION': PushChannel.testStart,
    'TEST_SCHEDULED': PushChannel.testScheduled,
    'TEST_STARTING_SOON': PushChannel.testStart,
    'TEST_STARTED': PushChannel.testStart,
    'TEST_ENDED': PushChannel.testExam,
    'TEST_COMPLETED': PushChannel.testResult,
    'RESULTS_AVAILABLE': PushChannel.testResult,
    'LEADERBOARD_UPDATED': PushChannel.testResult,
    'REPORT_READY': PushChannel.testResult,
    'ROUTINE_REMINDER': PushChannel.routineReminder,
    'ROUTINE_DUE': PushChannel.routineStart,
    'ROUTINE_MISSED': PushChannel.routineReminder,
    'ROUTINE_COMPLETED': PushChannel.routineReminder,
    'STREAK_MILESTONE': PushChannel.routineReminder,
    'SYSTEM_NOTIFICATION': PushChannel.importantSystem,
    'CONTENT_REVIEW_RESULT': PushChannel.general,
    'STREAK_AT_RISK': PushChannel.routineReminder,
    'LEVEL_UP': PushChannel.general,
    'NEW_FOLLOWER': PushChannel.general,
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
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final deviceId = await DeviceIdentity.current();
      _persistToken(token, deviceId: deviceId);
    });

    _initialized = true;
  }

  Future<void> _initLocalNotifications() async {
    tz.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (details) {
        if (details.actionId == _snoozeActionId) {
          _handleSnooze(details);
          return;
        }
        // Ringing alarms are `ongoing: true` (not swipe-dismissible, so a
        // student can't accidentally clear one without acting on it) —
        // which means tapping "Start Session" or the notification body
        // itself does NOT auto-clear it the way a normal notification
        // would. Explicitly cancel it here so the alarm actually stops
        // once the student has acted on it.
        if (details.id != null) {
          unawaited(_local.cancel(details.id!));
        }
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateToPath(payload);
        }
      },
    );
  }

  static const _snoozeActionId = 'routine_alarm_snooze';

  void _handleSnooze(NotificationResponse details) {
    final payload = details.payload;
    if (payload == null || payload.isEmpty) return;
    unawaited(
      scheduleExactNotification(
        id: details.id ?? payload.hashCode,
        title: 'Snoozed session',
        body: 'Tap to resume your study session.',
        scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
        payload: payload,
      ),
    );
  }

  /// The device's own system alarm ringtone (`Settings.System.
  /// DEFAULT_ALARM_ALERT_URI`) — every Android phone already has one
  /// configured, so this plays a genuine, properly-long alarm tone without
  /// this app needing to bundle its own audio asset (none exists in this
  /// project). Paired with [AudioAttributesUsage.alarm] so it routes
  /// through the phone's Alarm volume, not Notification/Media volume, and
  /// behaves like a real alarm (rings even in most silent/DND
  /// configurations) rather than a one-shot notification chime.
  static const _alarmSound = UriAndroidNotificationSound('content://settings/system/alarm_alert');

  /// Custom tones bundled at `android/app/src/main/res/raw/<name>.mp3`
  /// (resource name passed WITHOUT the extension). Any channel not listed
  /// here keeps the platform default sound for its importance level,
  /// exactly as before this map existed.
  static const Map<PushChannel, String> _customSounds = {
    PushChannel.testStart: 'test_start',
    PushChannel.testScheduled: 'test_scheduled',
    PushChannel.routineStart: 'routine_start',
    PushChannel.groupChat: 'chat_message',
    PushChannel.groupAnnouncement: 'announcement',
  };

  static const _prefsLibraryModeKey = 'push_library_mode';

  /// "Library Mode" — one toggle that silences every tone-carrying channel
  /// (vibrate only), for a student who doesn't want a loud chime going off
  /// in a quiet room. Deliberately does NOT touch [PushChannel.routineAlarm]:
  /// that channel exists specifically to ring through silent/DND (the
  /// device's own alarm sound, [AudioAttributesUsage.alarm]) so a study
  /// session alarm is never silently missed — muting it here would defeat
  /// the entire reason it's wired differently from every other channel.
  Future<bool> get libraryModeEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsLibraryModeKey) ?? false;
  }

  Future<void> setLibraryMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLibraryModeKey, enabled);
    // Android only applies sound/vibration changes to a channel that is
    // (re)created with them — so every affected channel must be deleted
    // and recreated, not merely re-registered with new settings.
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    for (final ch in PushChannel.values) {
      if (ch == PushChannel.routineAlarm) continue;
      await androidPlugin.deleteNotificationChannel(ch.id);
    }
    await _createChannels();
  }

  static const silentLibraryChannelId = 'channel_library_silent';

  Future<void> _createChannels() async {
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    final libraryMode = await libraryModeEnabled;

    // Register dedicated silent library channel:
    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        silentLibraryChannelId,
        'Library Mode Alerts',
        description: 'Gentle vibration alerts while in Library Mode',
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
        vibrationPattern: Int64List.fromList(const [0, 150, 100, 150]),
      ),
    );

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
            // per-channel from Android Settings at any time. The one
            // exception is `routineAlarm`: it must actually ring like an
            // alarm, not chime like a notification.
            playSound: ch == PushChannel.routineAlarm || !libraryMode,
            sound: ch == PushChannel.routineAlarm
                ? _alarmSound
                : (_customSounds[ch] != null
                      ? RawResourceAndroidNotificationSound(_customSounds[ch]!)
                      : null),
            audioAttributesUsage: ch == PushChannel.routineAlarm
                ? AudioAttributesUsage.alarm
                : AudioAttributesUsage.notification,
            enableVibration: true,
            vibrationPattern: ch == PushChannel.routineAlarm
                ? Int64List.fromList(const [0, 1000, 500, 1000, 500, 1000, 500, 1000])
                : null,
          ),
        ),
    ]);
  }

  // ── Foreground display (Phase 7) ──

  void _handleForegroundMessage(RemoteMessage message) async {
    final category = message.data['category'] as String? ?? '';
    if (category == 'FORCE_LOGOUT') {
      unawaited(SingleDeviceEnforcer.handleForceLogoutPush(message.data));
      return; // Never shown as a normal toast — the sign-out flow owns the UI.
    }
    final notification = message.notification;
    if (notification == null) return; // data-only message: nothing to show
    if (category == 'GROUP_MESSAGE' &&
        activeGroupId != null &&
        message.data['group_id'] == activeGroupId) {
      // The user is already viewing this group's chat — realtime already
      // rendered the message there; a toast on top would just be noise.
      return;
    }
    final isLibrary = await libraryModeEnabled;
    final channel = channelForCategory(category);

    final androidDetails = isLibrary
        ? AndroidNotificationDetails(
            silentLibraryChannelId,
            'Library Mode Alerts',
            channelDescription: 'Gentle vibration alerts while in Library Mode',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(const [0, 150, 100, 150]),
          )
        : AndroidNotificationDetails(
            channel.id,
            channel.title,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
          );

    _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: androidDetails),
      payload: _resolvePathFromData(message.data),
    );
  }

  /// Dispatches a local notification, automatically routing through the silent
  /// library channel with gentle vibration if Library Mode is currently active.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String category = '',
    String? payload,
  }) async {
    final isLibrary = await libraryModeEnabled;
    final channel = channelForCategory(category);

    final androidDetails = isLibrary
        ? AndroidNotificationDetails(
            silentLibraryChannelId,
            'Library Mode Alerts',
            channelDescription: 'Gentle vibration alerts while in Library Mode',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(const [0, 150, 100, 150]),
          )
        : AndroidNotificationDetails(
            channel.id,
            channel.title,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
          );

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  // ── Academic routine alarms (exact-time local notifications) ──
  //
  // Deliberately built on the SAME `_local` plugin instance and the SAME
  // `onDidReceiveNotificationResponse` handler already wired above, instead
  // of a second `FlutterLocalNotificationsPlugin()` in a standalone alarm
  // service — a second instance would either double-register the tap
  // callback or silently not receive taps at all, depending on platform.
  // `AcademicAlarmService` calls these; it owns the "which routines need an
  // alarm in the next N days" logic, this owns "how to actually alarm".

  /// Schedules one exact-time local notification with a full-screen intent
  /// (Android) and a "Start Session" / "Snooze 5m" action pair. [payload] is
  /// the deep-link path opened on tap (or after a snooze), exactly like a
  /// push notification's payload.
  /// Returns true once the OS has actually accepted the schedule, false on
  /// any failure (not initialized, permission missing, plugin error) — a
  /// caller that wants to tell the user "reminder set" must check this
  /// rather than assume success just because nothing threw.
  Future<bool> scheduleExactNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String payload,
    /// e.g. `DateTimeComponents.time` to repeat daily at the same
    /// hour/minute instead of firing once. Null = one-shot (default).
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    if (!_initialized && _initFuture == null) {
      // Local notifications are set up as part of full initialize(); a
      // caller that schedules before the app has called initialize() gets a
      // clear no-op rather than a plugin-not-ready exception.
      AppLogger.warning('scheduleExactNotification called before PushNotificationService.initialize()');
      return false;
    }
    try {
      await _local.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            PushChannel.routineAlarm.id,
            PushChannel.routineAlarm.title,
            channelDescription: PushChannel.routineAlarm.description,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            // Rings like a real alarm (device's own alarm tone, Alarm
            // volume stream) rather than chiming once like a notification
            // — see `_alarmSound`/_createChannels. Stays on screen and
            // keeps vibrating until the student taps Start Session or
            // Snooze, instead of being swipe-dismissible like an ordinary
            // notification.
            playSound: true,
            sound: _alarmSound,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(const [0, 1000, 500, 1000, 500, 1000, 500, 1000]),
            ongoing: true,
            autoCancel: false,
            actions: const [
              AndroidNotificationAction('start_session', 'Start Session', showsUserInterface: true),
              AndroidNotificationAction(_snoozeActionId, 'Snooze 5m'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
      return true;
    } catch (e, st) {
      AppLogger.error('scheduleExactNotification failed for id=$id: $e', stackTrace: st);
      return false;
    }
  }

  Future<void> cancelScheduledNotification(int id) => _local.cancel(id);

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
    // Mark "asked" only once we've actually gone through with asking —
    // either the user answered the rationale dialog, or we're about to fire
    // the real OS prompt. Marking this BEFORE either of those (as this used
    // to) permanently poisons hasAskedBefore() the instant this function is
    // entered — if the widget context happened to be unmounted or the
    // dialog was interrupted, the real POST_NOTIFICATIONS prompt might
    // never have fired at all, yet the app would never ask again.
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
      if (!proceed) {
        await _markAsked();
        return checkPermissionStatus();
      }
    }

    final result = await Permission.notification.request();
    await _markAsked();
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
    if (!Platform.isAndroid) return;
    // main.dart kicks off initialize() in the background, deferred past the
    // first frame, so it very often hasn't finished by the time AppShell
    // calls this on cold start. Bailing out here (as this used to) silently
    // abandons FCM token registration for the entire app session — nothing
    // ever retries it — which is exactly why push never worked even with
    // permission granted. initialize() is idempotent and returns
    // immediately once already done, so awaiting it here is always safe.
    await initialize();
    if (!_initialized) {
      AppLogger.warning('registerCurrentDevice: skipped — push service failed to initialize');
      return;
    }
    final status = await checkPermissionStatus();
    AppLogger.info('registerCurrentDevice: permission status = $status');
    if (status != SystemPermissionStatus.granted) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      AppLogger.info('registerCurrentDevice: FCM token = ${token == null ? 'null' : '${token.substring(0, 12)}…'}');
      if (token != null) {
        final deviceId = await DeviceIdentity.current();
        await _persistToken(token, deviceId: deviceId);
      }
    } catch (e, st) {
      AppLogger.error('FCM token registration failed: $e', stackTrace: st);
    }
  }

  /// One retry after a short delay: right after a cold start the device's
  /// network stack is sometimes not fully up yet (DNS resolution fails for
  /// a couple of seconds even though the radio reports connected) — a
  /// one-shot attempt right then can permanently miss registering the
  /// token for the whole app session, which is exactly what device
  /// evidence showed. A single retry covers that window without adding
  /// unbounded retry complexity for a genuinely offline device.
  Future<void> _persistToken(String token, {String? deviceId, bool isRetry = false}) async {
    try {
      await _tokenService.registerToken(fcmToken: token, deviceId: deviceId, appVersion: null);
      AppLogger.info('registerCurrentDevice: token persisted to server successfully');
    } catch (e) {
      if (!isRetry) {
        AppLogger.warning('Device token persist failed, retrying once in 5s: $e');
        await Future.delayed(const Duration(seconds: 5));
        await _persistToken(token, deviceId: deviceId, isRetry: true);
        return;
      }
      AppLogger.warning('Device token persist failed (after retry): $e');
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

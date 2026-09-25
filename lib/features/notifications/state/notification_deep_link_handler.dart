import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';

/// Handles navigation from notification taps. Validates the deep link
/// path before navigation and falls back to the notification center
/// for unrecognized or unauthorized destinations.
///
/// IMPORTANT: A notification payload is NOT authorization. Every destination
/// screen performs its own auth checks (RLS, RPC, membership, etc.).
class NotificationDeepLinkHandler {
  const NotificationDeepLinkHandler._();

  /// Navigate to the correct screen based on notification data.
  ///
  /// Priority order:
  /// 1. `data->>'deep_link'` (server-generated, authoritative)
  /// 2. Fallback based on `type` / `category`
  /// 3. Notification center
  static void handleTap(BuildContext context, AppNotification notification) {
    _navigateToPath(context, resolvePath(notification));
  }

  /// The context-free half of [handleTap]'s logic: validated deep_link, or
  /// a type/category-derived fallback, or the notification center. Exposed
  /// separately so a system push tap — which can happen before any
  /// [BuildContext] exists yet (cold start) — can resolve the destination
  /// path first and navigate via [AppRouter.router] directly once the
  /// router itself is ready, without needing to thread a context through.
  static String resolvePath(AppNotification notification) {
    final deepLink = notification.deepLink;
    if (deepLink != null && deepLink.isNotEmpty) {
      if (_isValidDeepLink(deepLink)) {
        return deepLink;
      }
      AppLogger.warning(
        'Invalid deep_link in notification ${notification.id}: $deepLink',
      );
    }

    final fallback = _fallbackRoute(notification);
    if (fallback != null) return fallback;

    return '/notifications';
  }

  /// Validate the deep link path. Must start with a known prefix and
  /// contain only expected path segments. Rejects URLs, query strings,
  /// fragments, and unknown prefixes.
  static bool _isValidDeepLink(String path) {
    if (path.isEmpty) return false;
    // Must start with /
    if (!path.startsWith('/')) return false;
    // No query strings or fragments
    if (path.contains('?') || path.contains('#')) return false;
    // Must be a known app route prefix
    const validPrefixes = [
      '/groups',
      '/tests',
      '/attempts',
      '/routine',
      '/notifications',
      '/settings',
      '/profile',
      '/subjects',
      '/question-bank',
    ];
    return validPrefixes.any((prefix) => path.startsWith(prefix));
  }

  /// Navigate to a path using go_router. Catches errors gracefully.
  static void _navigateToPath(BuildContext context, String path) {
    try {
      context.push(path);
    } catch (e) {
      AppLogger.error('Deep link navigation failed: $path', error: e);
      // Fallback to home if navigation fails.
      try {
        context.go('/home');
      } catch (_) {
        // Last resort — do nothing.
      }
    }
  }

  /// Derive a fallback route from notification type/category when no
  /// explicit deep_link is present.
  static String? _fallbackRoute(AppNotification notification) {
    final groupId = notification.groupId;
    final testId = notification.testId;
    final routineId = notification.routineId;

    // Test-related
    if (testId != null) {
      if (notification.category == 'TEST_COMPLETED' ||
          notification.category == 'RESULTS_AVAILABLE') {
        return '/tests/$testId';
      }
      if (groupId != null) {
        return '/groups/$groupId/tests';
      }
      return '/tests/$testId';
    }

    // Routine-related
    if (routineId != null) {
      return '/routine/$routineId';
    }

    // Group-scoped notifications
    if (groupId != null) {
      switch (notification.type) {
        case 'group_message':
        case 'group_announcement':
        case 'group_join':
          return '/groups/$groupId';
        case 'group_test':
          return '/groups/$groupId/tests';
        default:
          return '/groups/$groupId/notifications';
      }
    }

    // Category-based fallback
    switch (notification.parsedCategory) {
      case NotificationCategory.testReminder:
      case NotificationCategory.testLive:
      case NotificationCategory.testInvitation:
        return '/tests';
      case NotificationCategory.routineReminder:
      case NotificationCategory.routineDue:
      case NotificationCategory.streakMilestone:
        return '/routine';
      case NotificationCategory.reportReady:
      case NotificationCategory.resultsAvailable:
        if (testId != null) return '/tests/$testId';
        return '/tests';
      case NotificationCategory.leaderboardUpdated:
        if (testId != null) return '/tests/$testId/leaderboard';
        return '/tests';
      case NotificationCategory.groupJoinRequest:
      case NotificationCategory.joinAccepted:
      case NotificationCategory.joinRejected:
      case NotificationCategory.roleChanged:
      case NotificationCategory.memberRemoved:
        if (groupId != null) return '/groups/$groupId';
        return '/notifications';
      default:
        return null;
    }
  }
}

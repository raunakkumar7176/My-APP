import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'push_notification_service.dart';

/// Thin façade over the app's real permission flows. Notification
/// permission is NOT duplicated here — [PushNotificationService] already
/// implements the exact "educational rationale, then the native OS
/// dialog" flow this class's notification methods delegate to (it also
/// owns the FCM/local-notification plugin those permissions gate, so a
/// second, separate permission flow would risk asking twice or
/// disagreeing about whether permission was ever granted). Camera/gallery
/// permission genuinely didn't exist anywhere in the app before this —
/// `image_picker` triggers the OS's own picker-scoped prompt on its own,
/// but a caller that wants to know the answer UP FRONT (e.g. to show a
/// clear in-app message instead of a bare OS denial) needs this.
abstract final class PermissionService {
  /// Shows the existing educational dialog, then requests OS notification
  /// permission if the user proceeds. See
  /// [PushNotificationService.requestPermissionWithRationale] for the
  /// exact rationale copy and re-prompt-avoidance logic.
  static Future<SystemPermissionStatus> requestNotificationPermission(
    BuildContext context,
  ) {
    return PushNotificationService.instance.requestPermissionWithRationale(context);
  }

  /// True only when notification permission is currently granted — for a
  /// Settings screen banner ("notifications are off"), not for deciding
  /// whether to ask (asking is always routed through
  /// [requestNotificationPermission], which has its own rationale/re-prompt
  /// rules).
  static Future<bool> hasNotificationPermission() async {
    final status = await PushNotificationService.instance.checkPermissionStatus();
    return status == SystemPermissionStatus.granted;
  }

  /// Requests camera + photo-library access together, for the feedback
  /// screenshot picker and profile avatar upload. Returns true only if
  /// BOTH are granted (a caller that only needs one should check
  /// [Permission.camera]/[Permission.photos] directly instead).
  static Future<bool> requestCameraAndGalleryPermission() async {
    final results = await [Permission.camera, Permission.photos].request();
    return results.values.every((status) => status.isGranted);
  }

  static Future<bool> hasCameraPermission() async => Permission.camera.status.then((s) => s.isGranted);

  static Future<bool> hasGalleryPermission() async => Permission.photos.status.then((s) => s.isGranted);
}

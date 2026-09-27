import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/profile_service.dart';
import '../../../core/services/supabase_service.dart';

const _maxDimension = 1280;
const _jpegQuality = 70;

/// Decode/resize/encode off the UI thread. Returns null when the bytes
/// cannot be decoded as an image.
Uint8List? _compressScreenshot(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = (decoded.width > _maxDimension || decoded.height > _maxDimension)
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _maxDimension : null,
          height: decoded.height > decoded.width ? _maxDimension : null,
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
}

/// Real device/app diagnostic info gathered at feedback time — never
/// fabricated placeholders. Fields fall back to null when a plugin call
/// fails (e.g. unsupported platform), rather than a fake string.
final class DeviceDiagnostics {
  const DeviceDiagnostics({
    this.platform,
    this.osVersion,
    this.deviceBrand,
    this.deviceModel,
    this.appVersion,
  });

  final String? platform;
  final String? osVersion;
  final String? deviceBrand;
  final String? deviceModel;
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'os_version': osVersion,
        'device_brand': deviceBrand,
        'device_model': deviceModel,
        'app_version': appVersion,
      };

  static Future<DeviceDiagnostics> gather() async {
    String? platform;
    String? osVersion;
    String? deviceBrand;
    String? deviceModel;
    String? appVersion;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      AppLogger.warning('DeviceDiagnostics: package info failed: $e');
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        platform = 'Web';
        osVersion = info.userAgent;
        deviceBrand = info.browserName.name;
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        platform = 'Android';
        osVersion = info.version.release;
        deviceBrand = info.brand;
        deviceModel = info.model;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        platform = 'iOS';
        osVersion = info.systemVersion;
        deviceBrand = 'Apple';
        deviceModel = info.utsname.machine;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        platform = 'Windows';
        osVersion = info.displayVersion;
        deviceModel = info.productName;
      }
    } catch (e) {
      AppLogger.warning('DeviceDiagnostics: device info failed: $e');
    }

    return DeviceDiagnostics(
      platform: platform,
      osVersion: osVersion,
      deviceBrand: deviceBrand,
      deviceModel: deviceModel,
      appVersion: appVersion,
    );
  }
}

/// Handles the two feedback paths: a plain `mailto:` handoff to the user's
/// own email app, and an in-app submission (with optional compressed
/// screenshot) into `public.app_feedbacks` (migration 0067).
abstract final class FeedbackService {
  static const supportEmail = 'help.mypreparation@gmail.com';
  static const _bucket = 'feedback-attachments';
  static const _maxScreenshotBytes = 1024 * 1024; // 1 MB (matches the bucket)

  static SupabaseClient get _client => SupabaseService.client;

  static String get _studentCode => ProfileService.currentProfile?.studentCode ?? 'Unknown';

  /// Opens the device's email app pre-filled with diagnostic context. Never
  /// silently fails: throws [DataError] if no email app can handle the
  /// `mailto:` link.
  static Future<void> launchSupportEmail({String? subject, String? initialBody}) async {
    final diagnostics = await DeviceDiagnostics.gather();
    final body = StringBuffer()
      ..writeln(initialBody ?? 'Hi Support Team,')
      ..writeln()
      ..writeln('[Write your feedback/issue here...]')
      ..writeln()
      ..writeln('--- Diagnostic Info (Do not delete) ---')
      ..writeln('Student Code: $_studentCode')
      ..writeln('Device: ${diagnostics.deviceBrand ?? '--'} ${diagnostics.deviceModel ?? ''}'.trim())
      ..writeln('OS: ${diagnostics.platform ?? '--'} ${diagnostics.osVersion ?? ''}'.trim())
      ..writeln('App Version: ${diagnostics.appVersion ?? '--'}');

    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {
        'subject': subject ?? '[Feedback/Support] - Student: $_studentCode',
        'body': body.toString(),
      },
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const DataError(
        message: 'No email app is available on this device. Please email us directly.',
      );
    }
  }

  static Future<Uint8List?> pickScreenshot({required bool fromCamera}) async {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 95, // real compression happens at submit time
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Submits an in-app feedback row, compressing+uploading [screenshotBytes]
  /// first when present. Throws [ValidationError]/[DataError] on failure —
  /// never silently drops the screenshot on a compression/upload error.
  static Future<void> submitInAppFeedback({
    required String feedbackType,
    required int rating,
    required String message,
    Uint8List? screenshotBytes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to send feedback.');
    }
    if (message.trim().length < 10) {
      throw const ValidationError(message: 'Please write at least 10 characters.');
    }

    String? screenshotUrl;
    if (screenshotBytes != null && screenshotBytes.isNotEmpty) {
      final compressed = await compute(_compressScreenshot, screenshotBytes);
      if (compressed == null) {
        throw const ValidationError(
          message: 'Could not read that screenshot. Please try a different image.',
        );
      }
      if (compressed.length > _maxScreenshotBytes) {
        throw const ValidationError(
          message: 'The screenshot is still too large after compression. Try a smaller image.',
        );
      }
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      try {
        await _client.storage.from(_bucket).uploadBinary(
              path,
              compressed,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
            );
        screenshotUrl = _client.storage.from(_bucket).getPublicUrl(path);
      } on StorageException catch (e) {
        AppLogger.error('Feedback screenshot upload failed: ${e.message}');
        throw const DataError(message: 'Could not upload the screenshot. Please try again.');
      }
    }

    final diagnostics = await DeviceDiagnostics.gather();

    try {
      await _client.from('app_feedbacks').insert({
        'user_id': userId,
        'student_code': ProfileService.currentProfile?.studentCode,
        'feedback_type': feedbackType,
        'rating': rating,
        'message': message.trim(),
        'screenshot_url': screenshotUrl,
        'device_info': diagnostics.toJson(),
      });
    } on PostgrestException catch (e) {
      AppLogger.error('Feedback insert failed: ${e.message}');
      throw const DataError(message: 'Could not submit your feedback. Please try again.');
    }
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:io';

const bool kIsWebPlatform = bool.fromEnvironment('dart.library.html');

abstract final class PlatformUtils {
  static bool get isAndroid => !kIsWebPlatform && Platform.isAndroid;
  static bool get isIOS => !kIsWebPlatform && Platform.isIOS;
  static bool get isWeb => kIsWebPlatform;
  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop =>
      !kIsWebPlatform &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}

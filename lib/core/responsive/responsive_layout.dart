import 'package:flutter/material.dart';

import 'breakpoints.dart';

enum ScreenType { mobile, tablet, desktop }

final class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    required this.mobile,
    this.tablet,
    this.desktop,
    super.key,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (Breakpoints.isDesktop(width)) return ScreenType.desktop;
    if (Breakpoints.isTablet(width)) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  static bool isMobile(BuildContext context) =>
      getScreenType(context) == ScreenType.mobile;

  static bool isTablet(BuildContext context) =>
      getScreenType(context) == ScreenType.tablet;

  static bool isDesktop(BuildContext context) =>
      getScreenType(context) == ScreenType.desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (Breakpoints.isDesktop(constraints.maxWidth)) {
          return desktop ?? tablet ?? mobile;
        }
        if (Breakpoints.isTablet(constraints.maxWidth)) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}

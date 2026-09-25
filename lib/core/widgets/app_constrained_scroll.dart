import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/app_spacing.dart';

/// Responsive scrollable container that enforces maximum content width on tablets
/// and desktop while providing safe edge-to-edge layout on mobile phones.
class AppConstrainedScroll extends StatelessWidget {
  const AppConstrainedScroll({
    super.key,
    required this.child,
    this.maxWidth = AppDimensions.maxContentWidth,
    this.padding = AppSpacing.screenPadding,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.controller,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      physics: physics,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          key: const Key('app_constrained_scroll_box'),
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Form-optimized responsive container for auth, creation, and profile screens.
///
/// Limits width to [AppDimensions.maxFormWidth] to prevent text fields from
/// stretching unreadably on tablets and wide desktop screens.
class AppFormPage extends StatelessWidget {
  const AppFormPage({
    super.key,
    required this.child,
    this.maxWidth = AppDimensions.maxFormWidth,
    this.padding = AppSpacing.screenPadding,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.controller,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      physics: physics,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          key: const Key('app_form_page_box'),
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

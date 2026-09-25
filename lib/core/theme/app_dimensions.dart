/// Design system layout dimensions and accessibility constraints.
abstract final class AppDimensions {
  /// Accessible minimum touch target dimension (WCAG 2.1 Level AA requirement).
  static const double minTouchTarget = 48.0;

  /// Standard button heights.
  static const double buttonHeightSm = 36.0;
  static const double buttonHeightMd = 44.0;
  static const double buttonHeightLg = 48.0;

  /// Top app bar standard height.
  static const double appBarHeight = 56.0;

  /// Bottom navigation bar height.
  static const double bottomNavHeight = 64.0;

  /// Maximum readable content width on tablets and desktop screens.
  static const double maxContentWidth = 720.0;

  /// Maximum form width on tablets and desktop screens to prevent stretched fields.
  static const double maxFormWidth = 540.0;

  /// Standard card elevation.
  static const double cardElevation = 0.0;
  static const double cardElevatedElevation = 1.5;

  /// Standard divider and border width.
  static const double borderWidth = 1.0;
  static const double activeBorderWidth = 1.5;
}

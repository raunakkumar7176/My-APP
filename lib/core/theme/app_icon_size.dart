/// Design system icon size scale for "My Preparation".
///
/// Follows a strict semantic hierarchy:
/// - [inline]: 16.0 (embedded in body text, trailing metadata, small chips)
/// - [button]: 18.0 (inside action buttons, list item icons)
/// - [section]: 20.0 (section headers, app bar actions, card leading icons)
/// - [empty]: 48.0 (empty state illustrations, error state headers)
/// - [hero]: 64.0 (splash, success modals, large status callouts)
abstract final class AppIconSize {
  static const double inline = 16.0;
  static const double button = 18.0;
  static const double section = 20.0;
  static const double empty = 48.0;
  static const double hero = 64.0;
}

import 'package:flutter/widgets.dart';

/// Design system radius scale for "My Preparation".
///
/// Follows a strict geometric scale:
/// - [sm]: 6.0 (tags, small badges, inline chips)
/// - [md]: 8.0 (buttons, text inputs, list items)
/// - [lg]: 12.0 (cards, dialogs, modals, bottom sheets)
/// - [pill]: 999.0 (capsule badges, circular avatars, status pills)
abstract final class AppRadius {
  static const double sm = 6.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double pill = 999.0;

  // Radius objects
  static const Radius smRadius = Radius.circular(sm);
  static const Radius mdRadius = Radius.circular(md);
  static const Radius lgRadius = Radius.circular(lg);
  static const Radius pillRadius = Radius.circular(pill);

  // BorderRadius objects
  static const BorderRadius smBorder = BorderRadius.all(smRadius);
  static const BorderRadius mdBorder = BorderRadius.all(mdRadius);
  static const BorderRadius lgBorder = BorderRadius.all(lgRadius);
  static const BorderRadius pillBorder = BorderRadius.all(pillRadius);

  // Top-only borders (for bottom sheets / panels)
  static const BorderRadius topLgBorder = BorderRadius.vertical(top: lgRadius);
  static const BorderRadius topMdBorder = BorderRadius.vertical(top: mdRadius);
}

import 'package:flutter/material.dart';

/// Group logo with the initial as fallback. Any broken, expired or
/// unreachable `logo_url` degrades to the initial instead of an error tile,
/// so a stale storage object never breaks the list or the hub.
///
/// The initial-letter fallback sits on a gradient background instead of a
/// flat color — picked deterministically from [name] so the same group
/// always gets the same gradient, the way most modern chat apps do.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    required this.name,
    this.logoUrl,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? logoUrl;
  final double radius;

  String get _initial {
    final t = name.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  /// A small set of premium-feeling gradient pairs — picked by a stable
  /// hash of the group name, not randomly, so a given group's avatar never
  /// changes color between rebuilds/sessions.
  static const List<List<Color>> _gradients = [
    [Color(0xFF2563EB), Color(0xFF7C3AED)], // blue → violet
    [Color(0xFF0EA5E9), Color(0xFF2563EB)], // sky → blue
    [Color(0xFFDB2777), Color(0xFFF59E0B)], // pink → amber
    [Color(0xFF16A34A), Color(0xFF0EA5E9)], // green → sky
    [Color(0xFFF59E0B), Color(0xFFDB2777)], // amber → pink
    [Color(0xFF7C3AED), Color(0xFFDB2777)], // violet → pink
  ];

  List<Color> get _gradient {
    final key = name.trim();
    if (key.isEmpty) return _gradients[0];
    return _gradients[key.hashCode.abs() % _gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    final initial = Container(
      key: const Key('group_avatar_initial'),
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
    if (url == null || url.isEmpty) return initial;
    return ClipOval(
      key: const Key('group_avatar_logo'),
      child: Image.network(
        url,
        width: radius * 2,
        height: radius * 2,
        cacheWidth: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => initial,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : initial,
      ),
    );
  }
}

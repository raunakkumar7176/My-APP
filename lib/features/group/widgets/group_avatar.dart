import 'package:flutter/material.dart';

/// Group logo with the initial as fallback. Any broken, expired or
/// unreachable `logo_url` degrades to the initial instead of an error tile,
/// so a stale storage object never breaks the list or the hub.
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

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    final initial = CircleAvatar(
      key: const Key('group_avatar_initial'),
      radius: radius,
      child: Text(_initial, style: TextStyle(fontSize: radius * 0.8)),
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

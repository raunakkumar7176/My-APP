import 'package:flutter/material.dart';

/// Supported social and portfolio platforms with brand metadata and URL normalization.
enum SocialPlatform {
  linkedin(
    key: 'linkedin',
    displayName: 'LinkedIn',
    color: Color(0xFF0A66C2),
    icon: Icons.link_rounded,
    prefix: 'https://linkedin.com/in/',
    hint: 'username or profile URL',
  ),
  youtube(
    key: 'youtube',
    displayName: 'YouTube',
    color: Color(0xFFFF0000),
    icon: Icons.play_arrow_rounded,
    prefix: 'https://youtube.com/@',
    hint: '@handle or channel URL',
  ),
  x(
    key: 'x',
    displayName: 'X (Twitter)',
    color: Color(0xFF000000),
    icon: Icons.alternate_email_rounded,
    prefix: 'https://x.com/',
    hint: '@handle or profile URL',
  ),
  telegram(
    key: 'telegram',
    displayName: 'Telegram',
    color: Color(0xFF229ED9),
    icon: Icons.send_rounded,
    prefix: 'https://t.me/',
    hint: '@username or channel link',
  ),
  instagram(
    key: 'instagram',
    displayName: 'Instagram',
    color: Color(0xFFE4405F),
    icon: Icons.camera_alt_outlined,
    prefix: 'https://instagram.com/',
    hint: 'username or profile URL',
  ),
  github(
    key: 'github',
    displayName: 'GitHub',
    color: Color(0xFF24292E),
    icon: Icons.code_rounded,
    prefix: 'https://github.com/',
    hint: 'username or repository URL',
  ),
  website(
    key: 'website',
    displayName: 'Official Website',
    color: Color(0xFF6366F1),
    icon: Icons.language_rounded,
    prefix: 'https://',
    hint: 'https://yourwebsite.com',
  );

  const SocialPlatform({
    required this.key,
    required this.displayName,
    required this.color,
    required this.icon,
    required this.prefix,
    required this.hint,
  });

  final String key;
  final String displayName;
  final Color color;
  final IconData icon;
  final String prefix;
  final String hint;

  /// Looks up platform from string key (case-insensitive, alias aware).
  static SocialPlatform? fromKey(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'twitter') return SocialPlatform.x;
    for (final p in SocialPlatform.values) {
      if (p.key == lower) return p;
    }
    return null;
  }

  /// Normalizes a username or partial URL into a valid full HTTPS URL.
  static String normalizeUrl(SocialPlatform platform, String rawInput) {
    var text = rawInput.trim();
    if (text.isEmpty) return '';

    if (text.startsWith('http://') || text.startsWith('https://')) {
      return text;
    }

    if (text.startsWith('@')) {
      text = text.substring(1);
    }

    if (platform == SocialPlatform.website) {
      return 'https://$text';
    }

    return '${platform.prefix}$text';
  }
}

import 'package:flutter/material.dart';

/// Large circular profile photo with a camera-icon edit badge. Any broken,
/// expired, or unreachable [avatarUrl] degrades to the initials instead of
/// an error tile — same graceful-fallback rule as [GroupAvatar] elsewhere
/// in the app.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.initials,
    this.avatarUrl,
    this.radius = 56,
    this.onTap,
    this.onEditTap,
    this.busy = false,
    super.key,
  });

  final String initials;
  final String? avatarUrl;
  final double radius;

  /// "Tap to view" — opens the full-screen viewer.
  final VoidCallback? onTap;

  /// Tapping the camera badge — opens the choose-photo action sheet. Null
  /// hides the badge entirely (view-only contexts).
  final VoidCallback? onEditTap;

  /// Shows a progress ring over the photo while an upload/delete is
  /// in-flight, instead of leaving the badge tappable mid-operation.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = avatarUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    final circle = CircleAvatar(
      key: Key(hasPhoto ? 'profile_avatar_photo' : 'profile_avatar_initials'),
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                cacheWidth:
                    (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _InitialsText(initials: initials, radius: radius),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : _InitialsText(initials: initials, radius: radius),
              ),
            )
          : _InitialsText(initials: initials, radius: radius),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: onTap != null,
          label: hasPhoto ? 'Profile photo. Tap to view.' : 'Default profile avatar.',
          child: InkWell(
            key: const Key('profile_avatar_tap_target'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: circle,
          ),
        ),
        if (busy)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            ),
          ),
        if (onEditTap != null)
          Positioned(
            right: -4,
            bottom: -4,
            child: Material(
              color: theme.colorScheme.primary,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                key: const Key('profile_avatar_edit_badge'),
                customBorder: const CircleBorder(),
                onTap: busy ? null : onEditTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.camera_alt, size: 18, color: theme.colorScheme.onPrimary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InitialsText extends StatelessWidget {
  const _InitialsText({required this.initials, required this.radius});

  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Text(
      initials,
      style: TextStyle(
        fontSize: radius * 0.65,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

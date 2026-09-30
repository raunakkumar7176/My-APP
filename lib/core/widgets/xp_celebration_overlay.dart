import 'package:flutter/material.dart';

import '../services/profile_service.dart';

/// A brief floating "+N XP Earned! ⚡" toast, shown on the root overlay so it
/// survives the route transition that usually follows (e.g. submit ->
/// result screen). No Lottie dependency: a [TweenAnimationBuilder] drives a
/// scale/fade pop-in, holds, then fades out, then removes itself.
///
/// Purely a visual echo of an amount the server already awarded — it never
/// awards points itself. Callers pass the real `points_awarded` from the
/// triggering RPC's response; a 0 or null amount shows nothing.
class XpCelebrationOverlay {
  XpCelebrationOverlay._();

  /// Shows the toast for [points] XP (a no-op if [points] is null or <= 0),
  /// and — since the award has already landed server-side by the time the
  /// caller has this number — refreshes the cached profile's `total_points`
  /// so the AppBar XP pill updates instantly without a full profile reload.
  static void show(
    BuildContext context, {
    required int? points,
    String? label,
    int? newTotalPoints,
  }) {
    if (points == null || points <= 0) return;
    final current = ProfileService.currentProfile?.totalPoints;
    if (newTotalPoints != null) {
      ProfileService.updatePointsLocally(totalPoints: newTotalPoints);
    } else if (current != null) {
      ProfileService.updatePointsLocally(totalPoints: current + points);
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _XpToast(
        points: points,
        label: label,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _XpToast extends StatefulWidget {
  const _XpToast({required this.points, required this.onDone, this.label});

  final int points;
  final String? label;
  final VoidCallback onDone;

  @override
  State<_XpToast> createState() => _XpToastState();
}

class _XpToastState extends State<_XpToast> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _visible = false);
      Future.delayed(const Duration(milliseconds: 300), widget.onDone);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 72,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              builder: (ctx, scale, child) => Transform.scale(scale: scale, child: child),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(24),
                color: theme.colorScheme.primary,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    '+${widget.points} XP Earned! ⚡ ${widget.label ?? ''}'.trim(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

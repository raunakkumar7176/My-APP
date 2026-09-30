import 'package:flutter/material.dart';

import '../services/network_status_service.dart';

/// Wraps the whole app (mounted via `MaterialApp.router`'s `builder`) and
/// shows a global "no internet" treatment whenever
/// [NetworkStatusService.instance] goes offline — a full, motivating
/// overlay on ordinary screens, or a small non-intrusive top banner while
/// a test is actively in progress (`NetworkStatusService.isInActiveTest`),
/// since losing connectivity mid-test must never cover the screen or look
/// like the attempt itself has failed.
class NetworkAwareOverlay extends StatefulWidget {
  const NetworkAwareOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<NetworkAwareOverlay> createState() => _NetworkAwareOverlayState();
}

class _NetworkAwareOverlayState extends State<NetworkAwareOverlay> {
  @override
  void initState() {
    super.initState();
    NetworkStatusService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    NetworkStatusService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = NetworkStatusService.instance;
    final offline = !service.isOnline;
    final inTest = service.isInActiveTest;

    return Stack(
      children: [
        widget.child,
        if (offline && inTest)
          const Positioned(top: 0, left: 0, right: 0, child: _ReconnectingBanner()),
        AnimatedOpacity(
          opacity: (offline && !inTest) ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: IgnorePointer(
            ignoring: !(offline && !inTest),
            child: (offline && !inTest) ? const _NoInternetCard() : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Full-screen motivating "no internet" card for ordinary (non-test)
/// screens — never a real `showDialog`, since that would have its own
/// navigator/back-button semantics to fight with; this is purely visual,
/// on top of everything, and disappears on its own the instant
/// connectivity returns.
class _NoInternetCard extends StatefulWidget {
  const _NoInternetCard();

  @override
  State<_NoInternetCard> createState() => _NoInternetCardState();
}

class _NoInternetCardState extends State<_NoInternetCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween(begin: 0.92, end: 1.08).animate(
    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.scrim.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_off_rounded, size: 44, color: Color(0xFFF59E0B)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Internet Gayab Ho Gaya! 📡',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              const SizedBox(height: 10),
              Text(
                'Lagta hai network ne chhota sa break le liya hai. Kripya apna internet '
                'chalu karein aur apne lakshya ki taraf aage badhein! Aapki padhai hum '
                'rukne nahi denge.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => NetworkStatusService.instance.recheck(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reconnect Karein'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact top banner shown instead of the full card while a test is
/// actively in progress — reassures without covering the question/timer.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Internet disconnected. Aapke jawab safe hain. Reconnecting...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

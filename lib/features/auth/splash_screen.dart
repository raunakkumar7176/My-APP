import 'package:flutter/material.dart';

import 'widgets/app_logo.dart';
import 'widgets/neumorphic.dart';

/// Shown while the session is being restored. One short fade+scale of the
/// logo (implicit animations only; nothing repaints continuously except the
/// small progress indicator).
final class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Neu.base,
      body: Center(
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: _shown ? 1 : 0.85,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Neu.raised),
                  child: Padding(padding: EdgeInsets.all(10), child: AppLogo(size: 96)),
                ),
                SizedBox(height: 28),
                Text(
                  'My Preparation',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Neu.ink),
                ),
                SizedBox(height: 28),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Neu.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

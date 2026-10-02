import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../core/services/auth_service.dart';
import 'widgets/app_logo.dart';
import 'widgets/neumorphic.dart';

/// Premium academic splash / launch screen shown on app cold start.
/// Features a smooth entrance sequence for the logo, dynamic breathing glow aura,
/// academic app title, tagline, and prominent "from SHARDA GROUP" footer branding.
final class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _indicatorFade;
  late final Animation<Offset> _footerSlide;
  late final Animation<double> _footerFade;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // Primary entrance animation (logo, typography, footer)
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Continuous subtle breathing pulse for the logo badge
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.30, 0.75, curve: Curves.easeOutCubic),
          ),
        );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.30, 0.70, curve: Curves.easeOut),
      ),
    );

    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.30), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
          ),
        );

    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.45, 0.80, curve: Curves.easeOut),
      ),
    );

    _indicatorFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.60, 0.95, curve: Curves.easeOut),
      ),
    );

    _footerSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.65, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
      ),
    );

    _entryController.forward().then((_) {
      if (mounted) {
        _pulseController.repeat(reverse: true);
      }
    });

    _scheduleNavigation();
  }

  void _scheduleNavigation() {
    _navigationTimer = Timer(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;

      if (AuthService.currentStatus == AuthStatus.unknown) {
        try {
          await AuthService.authStatusStream
              .firstWhere((s) => s != AuthStatus.unknown)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      if (!mounted) return;

      AppRouter.splashCompleted = true;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        if (AuthService.currentStatus == AuthStatus.authenticated) {
          context.go('/home');
        } else {
          context.go('/login');
        }
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Neu.base,
      body: Stack(
        children: [
          // Soft ambient radial highlight in center
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [Colors.white.withValues(alpha: 0.65), Neu.base],
                ),
              ),
            ),
          ),

          // Central Hero: Logo, App Name, Tagline & Loading Pill
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with Neumorphic elevation & breathing pulse
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final pulse = _pulseController.value;
                      return Transform.scale(
                        scale: 1.0 + (pulse * 0.03),
                        child: FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Neu.base,
                                boxShadow: [
                                  ...Neu.raised,
                                  BoxShadow(
                                    color: const Color(
                                      0xFF2457D6,
                                    ).withValues(alpha: 0.08 + (pulse * 0.08)),
                                    blurRadius: 28 + (pulse * 12),
                                    spreadRadius: 2 + (pulse * 4),
                                  ),
                                ],
                              ),
                              child: const AppLogo(size: 104),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // App Title
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: const Text(
                        'My Preparation',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Neu.ink,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Academic Tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: SlideTransition(
                      position: _taglineSlide,
                      child: const Text(
                        'PREPARE  •  PRACTICE  •  PERFORM',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                          color: Neu.muted,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Sleek Linear Progress Capsule
                  FadeTransition(
                    opacity: _indicatorFade,
                    child: SizedBox(
                      width: 130,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 3.5,
                          backgroundColor: Color(0xFFDDE3ED),
                          color: Color(0xFF2457D6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Footer Branding: "from SHARDA GROUP"
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 30),
              child: FadeTransition(
                opacity: _footerFade,
                child: SlideTransition(
                  position: _footerSlide,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'FROM',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.2,
                          color: Neu.hint,
                        ),
                      ),
                      SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.school_rounded,
                            size: 18,
                            color: Color(0xFF2457D6),
                          ),
                          SizedBox(width: 8),
                          const Text(
                            'SHARDA GROUP',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.8,
                              color: Neu.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

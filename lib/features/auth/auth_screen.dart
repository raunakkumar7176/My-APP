import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import 'widgets/app_logo.dart';
import 'widgets/neumorphic.dart';

/// Login (front) / Sign up (back) on one neumorphic card that flips in 3D.
///
/// Performance: only the card's transform is animated (an [AnimatedBuilder]
/// around a [Transform]); the two faces are ordinary widgets that are not
/// rebuilt per frame, and the hidden face is not painted at all. No blur or
/// backdrop filters are used anywhere on this screen.
class AuthScreen extends StatefulWidget {
  const AuthScreen({this.startWithSignup = false, super.key});

  final bool startWithSignup;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    value: widget.startWithSignup ? 1 : 0,
  );
  late final Animation<double> _angle = CurvedAnimation(
    parent: _flip,
    curve: const Cubic(0.4, 0.1, 0.2, 1),
  );

  void _toggle() {
    if (_flip.isAnimating) return;
    if (_flip.value < 0.5) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      body: Stack(
        children: [
          const Positioned.fill(child: RepaintBoundary(child: _Backdrop())),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: AnimatedBuilder(
                    animation: _angle,
                    builder: (context, _) {
                      final t = _angle.value; // 0 = login, 1 = signup
                      final showBack = t > 0.5;
                      // Perspective + Y rotation; the back face is pre-rotated
                      // by π so its content reads correctly once visible.
                      final matrix = Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(t * math.pi + (showBack ? math.pi : 0));
                      return Transform(
                        alignment: Alignment.center,
                        transform: matrix,
                        child: showBack ? _signup : _login,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  late final Widget _login = _LoginFace(onFlip: _toggle);
  late final Widget _signup = _SignupFace(onFlip: _toggle);
}

/// Soft colour blobs painted once (no blur filter — radial gradients are
/// cheap and look the same at this size).
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6EEF7), Color(0xFFF0F4F9), Color(0xFFE8EEF5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -120, left: -120, child: _Glow(size: 450, color: Color(0x73B8C9E0))),
          Positioned(bottom: -100, right: -100, child: _Glow(size: 380, color: Color(0x73C9D8EB))),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Shared card chrome for both faces.
class _Face extends StatelessWidget {
  const _Face({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Neu.base,
        borderRadius: BorderRadius.circular(28),
        boxShadow: Neu.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 34, 32, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Neu.raisedSmall),
                child: Padding(padding: EdgeInsets.all(6), child: AppLogo(size: 62)),
              ),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600, color: Neu.ink)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Neu.muted)),
            const SizedBox(height: 26),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.text, required this.icon, required this.onTap, required this.tooltip});
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Neu.muted),
            ),
          ),
          const SizedBox(width: 10),
          NeuCircleButton(
            onPressed: onTap,
            tooltip: tooltip,
            child: Icon(icon, size: 20, color: Neu.accent),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message, {this.success = false});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          color: success ? const Color(0xFF2E9E5B) : const Color(0xFFD64545),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Please enter your email';
  final ok = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value.trim());
  return ok ? null : 'Please enter a valid email address';
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Please enter your password';
  if (value.length < 6) return 'Password must be at least 6 characters';
  return null;
}

// ─────────────────────────── LOGIN (front) ───────────────────────────

class _LoginFace extends StatefulWidget {
  const _LoginFace({required this.onFlip});
  final VoidCallback onFlip;

  @override
  State<_LoginFace> createState() => _LoginFaceState();
}

class _LoginFaceState extends State<_LoginFace> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Navigation happens via the router's auth redirect on success.
      await AuthService.signIn(email: _email.text.trim(), password: _password.text);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('AppError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Face(
      title: 'Welcome',
      subtitle: 'Login to continue your journey',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NeuField(
                  controller: _email,
                  hint: 'Email Address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: _validateEmail,
                ),
                const SizedBox(height: 14),
                NeuField(
                  controller: _password,
                  hint: 'Password',
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: _validatePassword,
                  onSubmitted: (_) => _submit(),
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20, color: Neu.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_error != null) _ErrorText(_error!),
        NeuButton(label: 'LOGIN', loading: _loading, onPressed: _submit),
        _SwitchRow(
          text: "Don't have an account?",
          icon: Icons.add,
          tooltip: 'Create account',
          onTap: widget.onFlip,
        ),
      ],
    );
  }
}

// ─────────────────────────── SIGN UP (back) ───────────────────────────

class _SignupFace extends StatefulWidget {
  const _SignupFace({required this.onFlip});
  final VoidCallback onFlip;

  @override
  State<_SignupFace> createState() => _SignupFaceState();
}

class _SignupFaceState extends State<_SignupFace> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _password.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await AuthService.signUp(email: _email.text.trim(), password: _password.text);
      if (mounted) {
        setState(() => _success = 'Account created! Please check your email to verify.');
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('AppError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Face(
      title: 'Create Account',
      subtitle: 'Start your journey with us',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NeuField(
                  controller: _email,
                  hint: 'Email Address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: _validateEmail,
                ),
                const SizedBox(height: 14),
                NeuField(
                  controller: _password,
                  hint: 'Password',
                  obscure: _obscure,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _validatePassword,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20, color: Neu.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                const SizedBox(height: 14),
                NeuField(
                  controller: _confirm,
                  hint: 'Confirm Password',
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  validator: _validateConfirm,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_error != null) _ErrorText(_error!),
        if (_success != null) _ErrorText(_success!, success: true),
        NeuButton(label: 'CREATE ACCOUNT', loading: _loading, onPressed: _submit),
        _SwitchRow(
          text: 'Already have an account?',
          icon: Icons.arrow_back,
          tooltip: 'Back to login',
          onTap: widget.onFlip,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Neumorphic ("embossed") building blocks for the auth screens.
///
/// Performance notes: all decorations are `const` and use plain
/// [BoxShadow]s — no blur filters, no backdrop filters, no gradients that
/// repaint per frame. Widgets are stateless so the flip animation only
/// transforms an already-rasterised subtree.
abstract final class Neu {
  static const Color base = Color(0xFFEEF2F7);
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentDark = Color(0xFF1D4ED8);
  static const Color ink = Color(0xFF1A1A2E);
  static const Color muted = Color(0xFF6B7A8F);
  static const Color hint = Color(0xFF9AA8BC);
  static const Color shadowDark = Color(0x739BAAC3); // rgba(155,170,195,.45)
  static const Color shadowLight = Color(0xF2FFFFFF);

  /// Soft outline so cards, fields and buttons read as distinct surfaces
  /// instead of dissolving into the background on bright screens.
  static const Color outline = Color(0xFFD3DBE6);
  static const Color outlineStrong = Color(0xFFBFC9D6);
  static const Color fieldFill = Color(0xFFE6EBF2);

  static const List<BoxShadow> raised = [
    BoxShadow(color: shadowDark, offset: Offset(7, 7), blurRadius: 14),
    BoxShadow(color: shadowLight, offset: Offset(-7, -7), blurRadius: 14),
  ];

  static const List<BoxShadow> raisedSmall = [
    BoxShadow(color: shadowDark, offset: Offset(5, 5), blurRadius: 10),
    BoxShadow(color: shadowLight, offset: Offset(-5, -5), blurRadius: 10),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(color: shadowDark, offset: Offset(14, 14), blurRadius: 28),
    BoxShadow(color: shadowLight, offset: Offset(-14, -14), blurRadius: 28),
  ];
}

/// Inset ("pressed-in") text field. Uses the standard [TextFormField] so
/// validation, autofill and IME behaviour stay untouched.
class NeuField extends StatelessWidget {
  const NeuField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.suffix,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14, color: Neu.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Neu.hint, fontSize: 14),
        filled: true,
        fillColor: Neu.fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        suffixIcon: suffix,
        enabledBorder: _border(Neu.outlineStrong),
        focusedBorder: _border(Neu.accent.withValues(alpha: 0.6)),
        errorBorder: _border(const Color(0xFFE05A5A)),
        focusedErrorBorder: _border(const Color(0xFFE05A5A)),
        errorStyle: const TextStyle(fontSize: 11),
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: 1.4),
      );
}

/// Raised pill button that sinks in while pressed.
class NeuButton extends StatefulWidget {
  const NeuButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 52,
        decoration: BoxDecoration(
          color: Neu.base,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _down ? Neu.outlineStrong : Neu.outline, width: 1.2),
          boxShadow: _down ? const [] : Neu.raised,
        ),
        alignment: Alignment.center,
        child: widget.loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Neu.accent),
              )
            : Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: enabled ? Neu.accent : Neu.hint,
                ),
              ),
      ),
    );
  }
}

/// Small raised circular button (the "+" / "←" flip trigger).
class NeuCircleButton extends StatelessWidget {
  const NeuCircleButton({
    required this.child,
    required this.onPressed,
    this.size = 38,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Neu.base,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(width: size, height: size, child: Center(child: child)),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Neu.outline, width: 1.2)),
        boxShadow: Neu.raisedSmall,
      ),
      child: tooltip == null ? button : Tooltip(message: tooltip!, child: button),
    );
  }
}

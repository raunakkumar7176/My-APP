import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';

/// Full-width primary action button with the app's signature blue-violet
/// gradient and a light press-scale (the "button press 200-300ms smooth"
/// touch from the premium redesign). Disabled (onPressed: null) fades to a
/// flat, muted fill instead of the gradient — never shows an interactive
/// gradient that then does nothing when tapped.
class GradientButton extends StatefulWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdBorder,
            gradient: enabled ? AppColors.primaryGradient : null,
            color: enabled
                ? null
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 18,
                  color: enabled
                      ? Colors.white
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: enabled
                      ? Colors.white
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

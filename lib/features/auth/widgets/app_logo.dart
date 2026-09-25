import 'package:flutter/material.dart';

/// The app logo: a black circle with a white "P" whose bowl carries a rising
/// arrow over three step bars.
///
/// Uses `assets/branding/logo.png` when it exists; otherwise draws a vector
/// version of the same mark, so the app never depends on the asset being
/// present. Wrapped in a [RepaintBoundary]: the mark is static and must not
/// be re-rasterised while the surrounding card animates.
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 64, super.key});

  final double size;

  static const assetPath = 'assets/branding/logo.png';

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          // Keep decode size tied to the display size (memory + speed).
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) =>
              const CustomPaint(painter: _PLogoPainter()),
        ),
      ),
    );
  }
}

/// Vector fallback drawn in a 100×100 design space.
class _PLogoPainter extends CustomPainter {
  const _PLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.scale(s, s);

    final black = Paint()..color = const Color(0xFF1C1C1C);
    final white = Paint()..color = Colors.white;

    // Circle badge.
    canvas.drawCircle(const Offset(50, 50), 50, black);

    // "P" — stem plus bowl (bowl as a thick stroked arc).
    final stem = RRect.fromRectAndRadius(
      const Rect.fromLTWH(42, 22, 9, 52),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(stem, white);
    final bowl = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawArc(
      const Rect.fromLTWH(38, 26, 40, 30),
      -1.5708,
      3.1416,
      false,
      bowl,
    );

    // Rising arrow from the lower left into the bowl.
    final arrowShaft = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(const Offset(34, 62), const Offset(58, 38), arrowShaft);
    final head = Path()
      ..moveTo(52, 34)
      ..lineTo(66, 32)
      ..lineTo(64, 46)
      ..close();
    canvas.drawPath(head, white);

    // Three step bars, bottom-left.
    canvas.drawRect(const Rect.fromLTWH(20, 66, 20, 7), white);
    canvas.drawRect(const Rect.fromLTWH(27, 56, 13, 7), white);
    canvas.drawRect(const Rect.fromLTWH(34, 46, 6, 7), white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

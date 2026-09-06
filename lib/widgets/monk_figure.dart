import 'dart:math';

import 'package:flutter/material.dart';

/// 盲僧立绘占位：几何切面的僧人剪影（打坐姿态）。
/// v0.1 用 CustomPainter 占位，接美术后替换为正式立绘资源。
class MonkFigure extends StatelessWidget {
  const MonkFigure({super.key, this.size = 180, this.dim = false});

  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MonkPainter(dim: dim)),
    );
  }
}

class _MonkPainter extends CustomPainter {
  _MonkPainter({this.dim = false});

  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rng = Random(11);

    final robeDark = Paint()..color = const Color(0xFF2C2A26);
    final robeLight = Paint()..color = const Color(0xFF3B3830);
    final skin = Paint()..color = const Color(0xFF8A7A62);
    final bead = Paint()..color = const Color(0xFFD8B36A);
    final facetLight = Paint()..color = const Color(0xFF4A4638);

    if (dim) {
      for (final p in [robeDark, robeLight, skin, bead, facetLight]) {
        p.color = p.color.withValues(alpha: 0.25);
      }
    }

    final center = Offset(w / 2, h * 0.62);

    // 袍身：宽三角 + 若干切面。
    final robe = Path()
      ..moveTo(center.dx, h * 0.28)
      ..quadraticBezierTo(w * 0.15, h * 0.75, w * 0.12, h * 0.9)
      ..lineTo(w * 0.88, h * 0.9)
      ..quadraticBezierTo(w * 0.85, h * 0.75, center.dx, h * 0.28)
      ..close();
    canvas.drawPath(robe, robeDark);

    // 切面高光（Low-Poly 感）。
    for (var i = 0; i < 6; i++) {
      final x0 = w * (0.2 + rng.nextDouble() * 0.5);
      final y0 = h * (0.5 + rng.nextDouble() * 0.32);
      final tri = Path()
        ..moveTo(x0, y0)
        ..lineTo(x0 + w * 0.08, y0 - h * 0.06)
        ..lineTo(x0 + w * 0.1, y0 + h * 0.05)
        ..close();
      canvas.drawPath(tri, rng.nextBool() ? robeLight : facetLight);
    }

    // 头部。
    canvas.drawCircle(Offset(center.dx, h * 0.24), w * 0.13, skin);
    // 斗笠沿。
    final hat = Path()
      ..moveTo(center.dx, h * 0.07)
      ..lineTo(w * 0.3, h * 0.2)
      ..lineTo(w * 0.7, h * 0.2)
      ..close();
    canvas.drawPath(hat, robeLight);

    // 佛珠。
    for (var i = 0; i < 7; i++) {
      final t = i / 6;
      final x = center.dx - w * 0.07 + w * 0.14 * t;
      final y = h * 0.42 + sin(t * pi) * h * 0.06;
      canvas.drawCircle(Offset(x, y), w * 0.018, bead);
    }
  }

  @override
  bool shouldRepaint(_MonkPainter oldDelegate) => oldDelegate.dim != dim;
}

import 'dart:math';

import 'package:flutter/material.dart';

/// Low-Poly 风格的按钮方块（僧页四按钮：签·成·禅·友）。
///
/// 用 CustomPainter 直接画几何切面，不切图、分辨率无损。
class LowPolyButton extends StatelessWidget {
  const LowPolyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.size = 64,
    this.seed = 7,
  });

  final String label;
  final VoidCallback onTap;
  final double size;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _LowPolySquarePainter(seed),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFE8DFC8),
                fontSize: 20,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LowPolySquarePainter extends CustomPainter {
  _LowPolySquarePainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final n = 3;
    final grid = List.generate(
      n,
      (row) => List.generate(n, (col) {
        final jitter = size.width * 0.12;
        return Offset(
          col * size.width / (n - 1) +
              (col == 0 || col == n - 1 ? 0 : (rng.nextDouble() - 0.5) * jitter),
          row * size.height / (n - 1) +
              (row == 0 || row == n - 1 ? 0 : (rng.nextDouble() - 0.5) * jitter),
        );
      }),
    );

    final base = Paint()..color = const Color(0xFF2A2620);
    final facet = Paint()..color = const Color(0xFF3A342A);
    final edge = Paint()
      ..color = const Color(0x33D8B36A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 把 3×3 网格剖成三角面，交替两种明度，形成 Low-Poly 切面感。
    for (var row = 0; row < n - 1; row++) {
      for (var col = 0; col < n - 1; col++) {
        final a = grid[row][col];
        final b = grid[row][col + 1];
        final c = grid[row + 1][col];
        final d = grid[row + 1][col + 1];
        final flip = rng.nextBool();
        final t1 = flip ? [a, b, c] : [a, b, d];
        final t2 = flip ? [b, d, c] : [a, d, c];
        canvas.drawPath(Path()..addPolygon(t1, true), base);
        canvas.drawPath(Path()..addPolygon(t2, true), facet);
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      edge,
    );
  }

  @override
  bool shouldRepaint(_LowPolySquarePainter oldDelegate) => oldDelegate.seed != seed;
}

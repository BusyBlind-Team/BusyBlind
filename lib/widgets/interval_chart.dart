import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 间隔序列曲线（木鱼频率曲线 / 呼吸同步率共用组件）。
class IntervalChart extends StatelessWidget {
  const IntervalChart({
    super.key,
    required this.valuesMs,
    this.targetMs,
    this.height = 120,
  });

  /// 各间隔（毫秒）。
  final List<double> valuesMs;

  /// 目标间隔（如木鱼 1000ms），画参考线。
  final double? targetMs;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (valuesMs.isEmpty) {
      return SizedBox(height: height, child: const SizedBox.shrink());
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _IntervalChartPainter(valuesMs, targetMs),
      ),
    );
  }
}

class _IntervalChartPainter extends CustomPainter {
  _IntervalChartPainter(this.values, this.target);

  final List<double> values;
  final double? target;

  @override
  void paint(Canvas canvas, Size size) {
    double lo = values.reduce(min);
    double hi = values.reduce(max);
    if (target != null) {
      lo = min(lo, target!);
      hi = max(hi, target!);
    }
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;
    final pad = span * 0.15;
    lo -= pad;
    hi += pad;
    final range = hi - lo;

    double y(double v) => size.height - (v - lo) / range * size.height;
    double x(int i) =>
        size.width * i / (values.length - 1).clamp(1, 1 << 30);

    if (target != null) {
      final p = Paint()
        ..color = AppTheme.goldDim
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, y(target!)), Offset(size.width, y(target!)), p);
    }

    // 分段上色：快于目标为"心急"（暖红），慢于目标为"走神"（冷青），其余暖金。
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    Color colorFor(double v) {
      if (target == null) return AppTheme.gold;
      if (v < target! * 0.95) return const Color(0xFFC97B6B);
      if (v > target! * 1.05) return const Color(0xFF7BA3A8);
      return AppTheme.gold;
    }

    for (var i = 1; i < values.length; i++) {
      final a = Offset(x(i - 1), y(values[i - 1]));
      final b = Offset(x(i), y(values[i]));
      canvas.drawLine(a, b, line..color = colorFor(values[i]));
    }
  }

  @override
  bool shouldRepaint(_IntervalChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.target != target;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PracticeSceneKind {
  sitQuiet,
  woodenFish,
  countRain,
  tideBreath,
  fishPetals,
  crossRiver,
}

/// 六种修行共享的低刺激场景壳：生成式氛围底图 + 可测试的原生动态前景。
class PracticeScene extends StatefulWidget {
  const PracticeScene({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.progress = 0,
    this.active = false,
    this.count = 0,
    this.accent = 0,
    this.showText = true,
  });

  final PracticeSceneKind kind;
  final String title;
  final String subtitle;
  final double progress;
  final bool active;
  final int count;
  final double accent;

  /// 关闭后场景只含底图与确定性画笔（无文本）。
  /// 视觉快照（golden）必须传 false：文本的字形栅格化依宿主字体而定，
  /// 会让基准图跨平台失效。文案由功能测试用 finder 断言。
  final bool showText;

  @override
  State<PracticeScene> createState() => _PracticeSceneState();
}

class _PracticeSceneState extends State<PracticeScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reduce =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    if (reduce == _reduceMotion && (_motion.isAnimating || reduce)) return;
    _reduceMotion = reduce;
    if (reduce) {
      _motion
        ..stop()
        ..value = 0.35;
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('practice-scene-${widget.kind.name}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _assetFor(widget.kind),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF071014)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x11000000),
                  Color(0xAA000000),
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => CustomPaint(
              painter: _ScenePainter(
                kind: widget.kind,
                motion: _motion.value,
                progress: widget.progress.clamp(0, 1),
                active: widget.active,
                count: widget.count,
                accent: widget.accent.clamp(0, 1),
              ),
            ),
          ),
          if (!widget.showText)
            const SizedBox.shrink()
          else
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              child: Column(
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xDDE8DFC8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 5,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x6603080A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x33D8B36A)),
                    ),
                    child: Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xB3E8DFC8),
                        fontSize: 13,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _assetFor(PracticeSceneKind kind) => switch (kind) {
  PracticeSceneKind.sitQuiet => 'assets/images/practices/sit_quiet.webp',
  PracticeSceneKind.woodenFish => 'assets/images/practices/wooden_fish.webp',
  PracticeSceneKind.countRain => 'assets/images/practices/count_rain.webp',
  PracticeSceneKind.tideBreath => 'assets/images/practices/tide_breath.webp',
  PracticeSceneKind.fishPetals => 'assets/images/practices/fish_petals.webp',
  PracticeSceneKind.crossRiver => 'assets/images/practices/cross_river.webp',
};

class _ScenePainter extends CustomPainter {
  const _ScenePainter({
    required this.kind,
    required this.motion,
    required this.progress,
    required this.active,
    required this.count,
    required this.accent,
  });

  final PracticeSceneKind kind;
  final double motion;
  final double progress;
  final bool active;
  final int count;
  final double accent;

  static const gold = Color(0xFFD8B36A);
  static const jade = Color(0xFF6E9B8B);

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case PracticeSceneKind.sitQuiet:
        _paintSit(canvas, size);
      case PracticeSceneKind.woodenFish:
        _paintWoodenFish(canvas, size);
      case PracticeSceneKind.countRain:
        _paintRain(canvas, size);
      case PracticeSceneKind.tideBreath:
        _paintTide(canvas, size);
      case PracticeSceneKind.fishPetals:
        _paintFishing(canvas, size);
      case PracticeSceneKind.crossRiver:
        _paintCrossing(canvas, size);
    }
  }

  void _paintSit(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.57);
    final breath = 0.5 + 0.5 * math.sin(motion * math.pi * 2);
    for (var i = 3; i >= 0; i--) {
      canvas.drawCircle(
        c,
        s.shortestSide * (0.15 + i * 0.055 + breath * 0.015),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = gold.withValues(alpha: 0.05 + (3 - i) * 0.035),
      );
    }
    final shadow = Paint()..color = const Color(0xDD08090A);
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(0, s.height * 0.08),
        width: s.width * 0.42,
        height: s.height * 0.16,
      ),
      shadow,
    );
    canvas.drawCircle(c - Offset(0, s.height * 0.09), s.width * 0.07, shadow);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: s.width * 0.16),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = gold.withValues(alpha: 0.75),
    );
  }

  void _paintWoodenFish(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.58);
    final pulse = active ? 1.08 : 1.0;
    final fishRect = Rect.fromCenter(
      center: c,
      width: s.width * 0.46 * pulse,
      height: s.width * 0.31 * pulse,
    );
    canvas.drawOval(fishRect, Paint()..color = const Color(0xE86A442B));
    canvas.drawArc(
      fishRect.deflate(s.width * 0.035),
      math.pi * 0.12,
      math.pi * 1.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFB47B43),
    );
    canvas.drawLine(
      c + Offset(s.width * 0.08, -s.height * 0.13),
      c + Offset(s.width * 0.24, -s.height * (active ? 0.01 : 0.16)),
      Paint()
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC59A68),
    );
    for (var i = 0; i < 3; i++) {
      final radius = s.width * (0.27 + i * 0.08 + accent * 0.03);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        -math.pi * 0.72,
        math.pi * 0.44,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = gold.withValues(alpha: active ? 0.32 - i * 0.07 : 0.08),
      );
    }
  }

  void _paintRain(Canvas canvas, Size s) {
    final rain = Paint()
      ..color = const Color(0x446FA8B3)
      ..strokeWidth = 1;
    for (var i = 0; i < 30; i++) {
      final x = ((i * 47 + motion * 180) % (s.width + 40)) - 20;
      final y = ((i * 83 + motion * s.height) % s.height);
      canvas.drawLine(Offset(x, y), Offset(x - 7, y + 24), rain);
    }
    final rippleCount = math.min(5, 1 + count % 5);
    for (var i = 0; i < rippleCount; i++) {
      final r = s.width * (0.08 + i * 0.055 + motion * 0.02);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s.width / 2, s.height * 0.68),
          width: r * 2,
          height: r * 0.48,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2.5 : 1.2
          ..color = (active ? gold : jade).withValues(alpha: 0.34 - i * 0.05),
      );
    }
  }

  void _paintTide(Canvas canvas, Size s) {
    final phase = motion * math.pi * 2;
    for (var layer = 0; layer < 3; layer++) {
      final path = Path()..moveTo(0, s.height * (0.65 + layer * 0.045));
      for (var x = 0.0; x <= s.width; x += 8) {
        final y =
            s.height * (0.65 + layer * 0.045) +
            math.sin(x / s.width * math.pi * 2 + phase + layer) *
                (8 + layer * 3);
        path.lineTo(x, y);
      }
      path
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = jade.withValues(alpha: 0.16 + layer * 0.06),
      );
    }
    final c = Offset(s.width / 2, s.height * 0.46);
    final radius = s.width * (active ? 0.19 : 0.15) * (0.96 + motion * 0.08);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = (active ? gold : jade).withValues(alpha: 0.7),
    );
  }

  void _paintFishing(Canvas canvas, Size s) {
    final tip = Offset(s.width * 0.18, s.height * 0.36);
    final float = Offset(
      s.width * 0.55,
      s.height * (0.64 + math.sin(motion * math.pi * 2) * 0.006),
    );
    canvas.drawLine(
      Offset(-10, s.height * 0.3),
      tip,
      Paint()
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8A7657),
    );
    final line = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(s.width * 0.48, s.height * 0.42, float.dx, float.dy);
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x88E8DFC8),
    );
    canvas.drawCircle(
      float,
      active ? 8 : 6,
      Paint()..color = active ? gold : const Color(0xFFB35C45),
    );
    if (accent > 0) {
      for (var i = 0; i < 5; i++) {
        final a = i * math.pi * 2 / 5 + motion;
        final p = float + Offset(math.cos(a), math.sin(a)) * (22 + accent * 16);
        canvas.drawCircle(
          p,
          3 + accent * 2,
          Paint()..color = gold.withValues(alpha: 0.65),
        );
      }
    }
  }

  void _paintCrossing(Canvas canvas, Size s) {
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final w = s.width * (0.34 - t * 0.22);
      final center = Offset(
        s.width / 2 + math.sin(i * 1.7) * s.width * 0.08,
        s.height * (0.78 - t * 0.4),
      );
      final reached = i <= count % 9;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: w * 0.34),
          const Radius.circular(10),
        ),
        Paint()
          ..color = reached ? const Color(0xAA8B7654) : const Color(0x882A3435),
      );
      if (i == count % 9) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: w * (active ? 1.25 : 1.05),
            height: w * 0.48,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = gold.withValues(alpha: 0.65),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.count != count ||
      oldDelegate.accent != accent ||
      oldDelegate.kind != kind;
}

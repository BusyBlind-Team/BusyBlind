import 'package:flutter/material.dart';

import '../domain/petals.dart';
import '../theme.dart';

/// 花瓣图标（图鉴 / 结算页共用）。
class PetalIcon extends StatelessWidget {
  const PetalIcon({super.key, required this.species, this.size = 28, this.dim = false});

  final PetalSpecies species;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PetalPainter(species.color, dim: dim)),
    );
  }
}

class _PetalPainter extends CustomPainter {
  _PetalPainter(this.color, {this.dim = false});

  final Color color;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = dim ? color.withValues(alpha: 0.18) : color;
    final fill = Paint()..color = c;
    final w = size.width;
    final h = size.height;
    final petal = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..quadraticBezierTo(w * 0.95, h * 0.35, w * 0.5, h * 0.95)
      ..quadraticBezierTo(w * 0.05, h * 0.35, w * 0.5, h * 0.08)
      ..close();
    canvas.drawPath(petal, fill);
    final vein = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(w * 0.5, h * 0.15), Offset(w * 0.5, h * 0.88), vein);
  }

  @override
  bool shouldRepaint(_PetalPainter oldDelegate) => oldDelegate.color != color;
}

/// 花瓣行（图鉴条目）。
class PetalRow extends StatelessWidget {
  const PetalRow({
    super.key,
    required this.species,
    required this.count,
    required this.flowerOwned,
    required this.onFuse,
  });

  final PetalSpecies species;
  final int count;
  final bool flowerOwned;
  final VoidCallback onFuse;

  @override
  Widget build(BuildContext context) {
    final canFuse = count >= kPetalsPerFlower && !flowerOwned;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          PetalIcon(species: species, dim: count == 0),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${species.name}花 petal × $count${flowerOwned ? '  · 已合成一朵' : ''}',
              style: TextStyle(
                color: count == 0 ? AppTheme.inkFaint : AppTheme.ink,
                fontSize: 14,
              ),
            ),
          ),
          if (canFuse)
            TextButton(
              onPressed: onFuse,
              child: Text(
                '合成（$kPetalsPerFlower 朵）',
                style: const TextStyle(color: AppTheme.gold, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

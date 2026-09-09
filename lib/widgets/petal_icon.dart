import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/petals.dart';
import '../theme.dart';

/// 单片花瓣（钓花结算徽记等通用）。
class PetalGlyph extends StatelessWidget {
  const PetalGlyph({super.key, this.color = kGenericPetalColor, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PetalPainter(color)),
    );
  }
}

/// 一朵花：按该花档位的瓣数画环形花瓣（图鉴 / 结算共用）。
class FlowerIcon extends StatelessWidget {
  const FlowerIcon({super.key, required this.species, this.size = 28, this.dim = false});

  final FlowerSpecies species;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FlowerPainter(species.color, petals: species.petals, dim: dim),
      ),
    );
  }
}

class _PetalPainter extends CustomPainter {
  _PetalPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color;
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

class _FlowerPainter extends CustomPainter {
  _FlowerPainter(this.color, {required this.petals, this.dim = false});

  final Color color;
  final int petals;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = dim ? color.withValues(alpha: 0.18) : color;
    final fill = Paint()..color = c;
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.30;
    for (var i = 0; i < petals; i++) {
      final angle = 2 * math.pi * i / petals - math.pi / 2;
      final px = cx + math.cos(angle) * r;
      final py = cy + math.sin(angle) * r;
      canvas.drawCircle(Offset(px, py), w * 0.21, fill);
    }
    canvas.drawCircle(
      Offset(cx, cy),
      w * 0.13,
      Paint()..color = dim ? c : const Color(0xFFD8B36A),
    );
  }

  @override
  bool shouldRepaint(_FlowerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.petals != petals || oldDelegate.dim != dim;
}

/// 图鉴合成条目：一档花 + 投入瓣数 + 抽取按钮。
class CraftRow extends StatelessWidget {
  const CraftRow({
    super.key,
    required this.tierPetalCount,
    required this.petalCount,
    required this.onCraft,
  });

  final int tierPetalCount;
  final int petalCount;
  final VoidCallback onCraft;

  @override
  Widget build(BuildContext context) {
    final pool = kFlowerSpecies
        .where((s) => s.petals == tierPetalCount)
        .toList(growable: false);
    final names = pool.map((s) => s.displayName).join(' / ');
    final canCraft = petalCount >= tierPetalCount;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < pool.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            FlowerIcon(species: pool[i], size: 22),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$tierPetalCount 瓣合成一朵：$names',
              style: const TextStyle(color: AppTheme.ink, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: canCraft ? onCraft : null,
            child: Text(
              '投入 $tierPetalCount 瓣',
              style: TextStyle(
                color: canCraft ? AppTheme.gold : AppTheme.inkFaint,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图鉴收藏条目：一朵花 + 档位/稀有度 + 是否已收入。
class FlowerRow extends StatelessWidget {
  const FlowerRow({super.key, required this.species, required this.owned});

  final FlowerSpecies species;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          FlowerIcon(species: species, dim: !owned),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${species.displayName} · ${species.petals} 瓣 · ${species.rarityLabel}',
              style: TextStyle(
                color: owned ? AppTheme.ink : AppTheme.inkFaint,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            owned ? '已收入' : '未遇',
            style: TextStyle(
              color: owned ? AppTheme.gold : AppTheme.inkFaint,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

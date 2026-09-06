import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/petals.dart';
import '../../domain/sign_slips.dart';
import '../../theme.dart';

/// 签（每日仅限一次）：得一张写在树叶上的签文。
///
/// 奖励口径（设计方案待对齐 #4）：按建议 b 执行——发一张签文收藏 +
/// 一片随机花瓣（凑图鉴），不发修为，保持"修为只来自真实专注"的纯净。
class SignPage extends ConsumerStatefulWidget {
  const SignPage({super.key});

  @override
  ConsumerState<SignPage> createState() => _SignPageState();
}

class _SignPageState extends ConsumerState<SignPage> {
  SignSlip? _todaySlip;
  PetalSpecies? _rewardPetal;
  bool _drawing = false;

  void _draw() {
    if (_drawing || ref.read(storeProvider).signedToday) return;
    setState(() => _drawing = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      final store = ref.read(storeProvider);
      final slip = kSignSlips[Random().nextInt(kSignSlips.length)];
      final petal = kPetalSpecies[Random().nextInt(kPetalSpecies.length)];
      store.recordSign(slipId: slip.id, text: slip.text, fortune: slip.fortune);
      store.addPetal(petal.id);
      if (mounted) {
        setState(() {
          _drawing = false;
          _todaySlip = slip;
          _rewardPetal = petal;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final signed = store.signedToday;
    final lastSlip = store.slips.isEmpty ? null : store.slips.last;

    return Scaffold(
      appBar: AppBar(title: const Text('签')),
      body: Center(
        child: _drawing
            ? const CircularProgressIndicator(color: AppTheme.gold)
            : !signed && _todaySlip == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '每日一签',
                        style: TextStyle(color: AppTheme.ink, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '今日还未抽签。签文与一片花瓣会收进你的收藏。',
                        style: TextStyle(color: AppTheme.inkDim, fontSize: 13),
                      ),
                      const SizedBox(height: 28),
                      OutlinedButton(
                        onPressed: _draw,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gold,
                          side: const BorderSide(color: AppTheme.goldDim),
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        ),
                        child: const Text('抽签'),
                      ),
                    ],
                  )
                : _LeafSlip(
                    text: _todaySlip?.text ?? (lastSlip?['text'] as String? ?? ''),
                    fortune: _todaySlip?.fortune ?? (lastSlip?['fortune'] as String? ?? ''),
                    rewardPetal: _rewardPetal,
                  ),
      ),
    );
  }
}

class _LeafSlip extends StatelessWidget {
  const _LeafSlip({required this.text, required this.fortune, this.rewardPetal});

  final String text;
  final String fortune;
  final PetalSpecies? rewardPetal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            height: 190,
            child: CustomPaint(
              painter: _LeafPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 44, 30, 30),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF2C2A20),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fortune,
            style: const TextStyle(color: AppTheme.gold, fontSize: 16, letterSpacing: 4),
          ),
          if (rewardPetal != null) ...[
            const SizedBox(height: 12),
            Text(
              '附赠花瓣：${rewardPetal!.name}',
              style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leaf = Paint()..color = const Color(0xFFC9CFA8);
    final vein = Paint()
      ..color = const Color(0x55333A22)
      ..strokeWidth = 1.2;

    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..quadraticBezierTo(w * 1.02, h * 0.45, w * 0.5, h)
      ..quadraticBezierTo(-w * 0.02, h * 0.45, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, leaf);
    canvas.drawLine(const Offset(0, 0).translate(w * 0.5, 0), Offset(w * 0.5, h), vein);
    for (var i = 1; i <= 5; i++) {
      final y = h * i / 6;
      canvas.drawLine(Offset(w * 0.5, y), Offset(w * 0.2, y - h * 0.05), vein);
      canvas.drawLine(Offset(w * 0.5, y), Offset(w * 0.8, y - h * 0.05), vein);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

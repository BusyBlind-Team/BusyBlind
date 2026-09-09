import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../data/app_store.dart';
import '../../domain/sign_slips.dart';
import '../../theme.dart';

/// 签（每日仅限一次）：+10 修为，得一张写在树叶上的签文。
///
/// 奖励口径（待对齐清单 #4 拍板）：抽签还是 +10 修为，并获得树叶签文
/// 收藏——原"改发花瓣"的建议不再执行。
/// 展示（改进列表）：菩提叶从上方飘落，落到中间后签文渐渐显现，
/// 文字排版不超出叶面。
class SignPage extends ConsumerStatefulWidget {
  const SignPage({super.key});

  @override
  ConsumerState<SignPage> createState() => _SignPageState();
}

class _SignPageState extends ConsumerState<SignPage> {
  SignSlip? _todaySlip;
  bool _drawing = false;
  bool _animateIn = false;

  void _draw() {
    if (_drawing || ref.read(storeProvider).signedToday) return;
    setState(() => _drawing = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final store = ref.read(storeProvider);
      final slip = kSignSlips[Random().nextInt(kSignSlips.length)];
      store.recordSign(slipId: slip.id, text: slip.text, fortune: slip.fortune);
      setState(() {
        _drawing = false;
        _todaySlip = slip;
        _animateIn = true;
      });
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
                        '今日还未抽签。抽签得十点修为，'
                        '一张写在树叶上的签文会收进你的收藏。',
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
                    key: ValueKey(_todaySlip?.id ?? lastSlip?['id']),
                    text: _todaySlip?.text ?? (lastSlip?['text'] as String? ?? ''),
                    fortune: _todaySlip?.fortune ?? (lastSlip?['fortune'] as String? ?? ''),
                    fallIn: _animateIn,
                  ),
      ),
    );
  }
}

/// 菩提叶签文：叶子落下 → 停在中间 → 签文渐渐显现。
class _LeafSlip extends StatefulWidget {
  const _LeafSlip({
    super.key,
    required this.text,
    required this.fortune,
    required this.fallIn,
  });

  final String text;
  final String fortune;

  /// 抽签后为 true：播放叶子飘落 + 文字渐显；查看旧签则直接呈现。
  final bool fallIn;

  @override
  State<_LeafSlip> createState() => _LeafSlipState();
}

class _LeafSlipState extends State<_LeafSlip> with SingleTickerProviderStateMixin {
  late final AnimationController _fall;

  @override
  void initState() {
    super.initState();
    _fall = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.fallIn) {
      _fall.forward();
    } else {
      _fall.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _LeafSlip old) {
    super.didUpdateWidget(old);
    if (!old.fallIn && widget.fallIn) {
      _fall.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fall,
      builder: (context, _) {
        final t = Curves.easeIn.transform(_fall.value);
        // 叶子从屏幕上方飘落到中间，带一点旋转。
        final drop = (1 - t) * -420.0;
        final angle = (1 - t) * -0.35;
        // 叶子就位后（前 60%），签文开始渐渐显现。
        final textT = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
        return Opacity(
          opacity: (t * 3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, drop),
            child: Transform.rotate(
              angle: angle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    height: 226,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/菩提叶.png',
                          width: 300,
                          height: 226,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFFC9CFA8)),
                        ),
                        // 签文排在叶面中央区域，不越出叶缘。
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 52),
                          child: Opacity(
                            opacity: textT,
                            child: Text(
                              widget.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF2C2A20),
                                fontSize: 13.5,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: textT,
                    child: Text(
                      widget.fortune,
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 16,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: textT,
                    child: Text(
                      '修为 +${AppStore.kSignMerit}',
                      style: const TextStyle(color: AppTheme.gold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }
}

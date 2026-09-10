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
/// 展示（Bug 描述 #4）：菩提叶从上方飘落，落到中间后弹出弹窗展示签文
/// 与签等（文字不再叠在叶片上）；每次进入本页都重播落叶并再次弹窗，
/// 不记忆"弹窗已关闭"的状态。
class SignPage extends ConsumerStatefulWidget {
  const SignPage({super.key});

  @override
  ConsumerState<SignPage> createState() => _SignPageState();
}

class _SignPageState extends ConsumerState<SignPage> {
  SignSlip? _todaySlip;
  bool _drawing = false;

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
      });
    });
  }

  /// 叶子落定后弹出签文弹窗。
  void _showSlipDialog(String text, String fortune) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: Text(
          fortune,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.gold,
            fontSize: 20,
            letterSpacing: 6,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.ink, fontSize: 15, height: 1.8),
            ),
            const SizedBox(height: 16),
            const Text(
              '修为 +${AppStore.kSignMerit}',
              style: TextStyle(color: AppTheme.goldDim, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭', style: TextStyle(color: AppTheme.gold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final signed = store.signedToday;
    final lastSlip = store.slips.isEmpty ? null : store.slips.last;
    final text = _todaySlip?.text ?? (lastSlip?['text'] as String? ?? '');
    final fortune = _todaySlip?.fortune ?? (lastSlip?['fortune'] as String? ?? '');

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
                    onLanded: () => _showSlipDialog(text, fortune),
                  ),
      ),
    );
  }
}

/// 菩提叶签文：叶子从上方飘落到中间（叶片上不叠任何文字，Bug 描述 #4）。
/// 落定后回调 [onLanded]，由页面弹出签文弹窗。
class _LeafSlip extends StatefulWidget {
  const _LeafSlip({super.key, required this.onLanded});

  final VoidCallback onLanded;

  @override
  State<_LeafSlip> createState() => _LeafSlipState();
}

class _LeafSlipState extends State<_LeafSlip> with SingleTickerProviderStateMixin {
  late final AnimationController _fall;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _fall = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _fall.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fall,
      builder: (context, _) {
        if (_fall.isCompleted && !_notified) {
          _notified = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLanded();
          });
        }
        final t = Curves.easeIn.transform(_fall.value);
        // 叶子从屏幕上方飘落到中间，带一点旋转。
        final drop = (1 - t) * -420.0;
        final angle = (1 - t) * -0.35;
        return Opacity(
          opacity: (t * 3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, drop),
            child: Transform.rotate(
              angle: angle,
              child: Image.asset(
                'assets/images/bodhi_leaf.png',
                width: 300,
                height: 300,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFC9CFA8)),
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

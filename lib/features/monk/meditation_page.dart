import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../core/practice/practice_manifest.dart';
import '../../core/practice/practice_result.dart';
import '../../core/practice/practice_types.dart';
import '../../data/app_store.dart';
import '../../di.dart';
import '../../domain/achievements.dart';
import '../../widgets/monk_figure.dart';

/// 打坐（"禅"按钮进入）。
///
/// 主界面的常驻基础态——不在修行列表里，不是修行插件，没有结算页，
/// 退出即回主界面。反挂机三重判定（设计方案 6.4）：
/// 1. 进入后台立即暂停计时（本页生命周期观察）；
/// 2. 每 5 分钟一声极轻的磬，30 秒内轻触任意处确认在场，超时则暂停计时（不惩罚）；
/// 3. 陀螺仪检测持续大幅位移暂停计时（v0.1 未接入传感器，见 TODO）。
class MeditationPage extends ConsumerStatefulWidget {
  const MeditationPage({super.key});

  @override
  ConsumerState<MeditationPage> createState() => _MeditationPageState();
}

class _MeditationPageState extends ConsumerState<MeditationPage> {
  static const int _chimeIntervalSec = 300;
  static const int _confirmWindowSec = 30;
  static const int _exitHoldMs = 2000;

  Timer? _ticker;
  int _elapsedSec = 0;
  int _nextChimeSec = _chimeIntervalSec;
  bool _awaitingConfirm = false;
  bool _confirmExpired = false;
  Timer? _exitTimer;
  double _exitProgress = 0;
  bool _exiting = false;

  bool get _accumulating => !_confirmExpired && !_exiting;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!_accumulating) return;
    _elapsedSec++;
    final store = ref.read(storeProvider);

    // 每满 60 秒 +1 修为（单日上限 60 点，AppStore 内截断）。
    if (_elapsedSec % 60 == 0) {
      store.addMeditationMerit(1);
    }

    // 每 5 分钟：极轻的磬 + 30 秒在场确认窗口。
    if (_elapsedSec >= _nextChimeSec && !_awaitingConfirm) {
      _awaitingConfirm = true;
      _nextChimeSec += _chimeIntervalSec;
      ref.read(soundBankProvider).play(SoundCatalog.chimeSoftKey, gain: 0.35);
      Future.delayed(
        const Duration(seconds: _confirmWindowSec),
        () {
          if (mounted && _awaitingConfirm) {
            setState(() => _confirmExpired = true);
          }
        },
      );
    }
    setState(() {});
  }

  void _onTapAnywhere() {
    if (_awaitingConfirm || _confirmExpired) {
      // 确认在场（或确认窗口已过后的恢复），不惩罚。
      setState(() {
        _awaitingConfirm = false;
        _confirmExpired = false;
      });
    }
  }

  void _onHoldStart() {
    _exitTimer?.cancel();
    setState(() => _exitProgress = 0);
    const steps = 20;
    _exitTimer = Timer.periodic(
      const Duration(milliseconds: _exitHoldMs ~/ steps),
      (t) {
        setState(() => _exitProgress = (t.tick) / steps);
        if (t.tick >= steps) {
          t.cancel();
          _exit();
        }
      },
    );
  }

  void _onHoldEnd() {
    _exitTimer?.cancel();
    if (mounted) setState(() => _exitProgress = 0);
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    _ticker?.cancel();
    final store = ref.read(storeProvider);
    final minutes = _elapsedSec ~/ 60;

    // 打坐虽非修行插件，结算口径保持一致：写记录 + 判成就。
    store.addSession(
      practiceId: 'meditation',
      merit: 0, // 修为已逐分钟入账，不重复结算。
      completed: true,
      durationMs: _elapsedSec * 1000,
      metrics: {'minutes': minutes, 'seconds': _elapsedSec},
    );
    store.unlockAchievements(
      kAchievements
          .where(
            (a) => a.test(
              AchievementEval(
                store: store,
                lastResult: PracticeResult(
                  effectiveDuration: Duration(seconds: _elapsedSec),
                  quality: 1,
                  merit: 0,
                  metrics: {'minutes': minutes},
                ),
                lastManifest: const PracticeManifest(
                  id: 'meditation',
                  name: '打坐',
                  subtitle: '',
                  tags: [],
                  eyeMode: EyeMode.eyesClosed,
                  typicalLength: Duration(minutes: 1),
                  meritBase: 0,
                  iconKey: 'meditation',
                ),
              ),
            ),
          )
          .map((a) => a.id),
    );
    await ref.read(soundBankProvider).play(SoundCatalog.chimeDoubleKey);
    if (mounted) Navigator.of(context).maybePop();
  }

  String get _clockText {
    final m = _elapsedSec ~/ 60;
    final s = _elapsedSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final capped = store.meditationEarnedToday() >= AppStore.kDailyMeditationCap;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTapAnywhere,
        onLongPressStart: (_) => _onHoldStart(),
        onLongPressEnd: (_) => _onHoldEnd(),
        onLongPressCancel: _onHoldEnd,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Spacer(flex: 3),
              const MonkFigure(dim: true),
              const Spacer(flex: 4),
              Text(
                _confirmExpired
                    ? '轻触任意处继续'
                    : _awaitingConfirm
                        ? '——你在吗？轻触任意处——'
                        : '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0x55E8DFC8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                _clockText,
                style: TextStyle(
                  color: capped ? const Color(0x33E8DFC8) : const Color(0x44E8DFC8),
                  fontSize: 14,
                ),
              ),
              if (capped)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '今日打坐修为已满 ${AppStore.kDailyMeditationCap}',
                    style: TextStyle(color: Color(0x33E8DFC8), fontSize: 11),
                  ),
                ),
              const SizedBox(height: 20),
              _exitProgress > 0
                  ? Text(
                      '再按住一会儿… ${(_exitProgress * 100).toInt()}%',
                      style: const TextStyle(color: Color(0x55E8DFC8), fontSize: 11),
                    )
                  : const Text(
                      '长按 2 秒退出',
                      style: TextStyle(color: Color(0x2EE8DFC8), fontSize: 11),
                    ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

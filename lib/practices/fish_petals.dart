import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../domain/petals.dart';

/// 钓花（耐心 · 收集）——听觉化改造版（设计方案 7.4）。
///
/// 玩法循环：长按甩杆 → 聚瓣期（触竿概率随本次甩杆时长上升：
/// 前 2 秒为 0，10 秒约 20% → 60 秒约 60%）→ 触竿响"叮"（花瓣，65%）
/// 或"咚"（杂物，35%）→ "叮"后 1.5 秒内松手收杆；"咚"后松手为空竿
/// → 松手后 2 秒休竿期。
/// 反挂机：连续 90 秒无有效输入自动进入结算。
/// 花瓣经 extraRewards 返还宿主入库；核心判定全走听觉，
/// 画面只是睁眼奖励层。
/// 钓竿状态机：idle → casting（按住）→ hooked（已触发叮/咚）→ 休竿 → casting…
enum _RodState { idle, casting, hooked, resting }

class FishPetalsSession extends PracticeSession {
  static const int _noBiteBeforeUs = 2000000; // 前 2 秒概率为 0
  static const int _restUs = 2000000; // 休竿期
  static const int _catchWindowUs = 1500000; // "叮"后收杆窗口
  static const int _antiIdleUs = 90000000; // 90 秒无输入自动结算
  static const double _petalChance = 0.65;

  late PracticeContext _ctx;
  final Random _rng = Random();

  _RodState _state = _RodState.idle;
  int _castStartUs = 0;
  int _hookAtUs = 0;
  bool _hookIsPetal = false;
  int _restEndUs = 0;
  int? _lastInputUs;
  Timer? _pollTimer;

  // 统计。
  int _petalsCaught = 0;
  int _miscatch = 0; // "咚"后收杆次数（空竿）
  int _missed = 0; // "叮"后超时未收
  int _casts = 0;
  final List<int> _waitTimesUs = [];
  final List<Reward> _caught = [];

  bool _finished = false;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'fish_petals',
    name: '钓花',
    subtitle: '叮则收手，咚则空竿',
    tags: [TrainingTag.patience, TrainingTag.collect],
    eyeMode: EyeMode.openThenClosed,
    typicalLength: Duration(minutes: 4),
    meritBase: 8,
    iconKey: 'fish_petals',
    allowManualEnd: true,
    rulesText:
        '长按屏幕甩竿，闭眼等。\n刚甩竿会惊散花瓣——前两秒不会有人上钩；\n甩得越久，花瓣越愿意靠近。\n'
        '"叮"是花瓣碰竿，1.5 秒内松手收杆；"咚"只是杂物，收了也是空竿。',
  );

  /// 触竿概率曲线：随本次甩杆时长上升（10s≈20% → 60s≈60%，每秒概率）。
  static double biteRatePerSecond(int heldUs) {
    if (heldUs < _noBiteBeforeUs) return 0;
    final s = heldUs / 1000000;
    const p10 = 0.20;
    const p60 = 0.60;
    if (s <= 10) {
      return p10 * (s - 2) / 8;
    }
    return (p10 + (p60 - p10) * (s - 10) / 50).clamp(p10, p60);
  }

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    _lastInputUs = 0;
  }

  @override
  void start() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  void _poll() {
    if (_finished || !_ctx.scheduler.isRunning) return;
    final now = _ctx.scheduler.nowUs();

    // 反挂机：连续 90 秒无有效输入。
    final last = _lastInputUs ?? 0;
    if (now - last >= _antiIdleUs) {
      _ctx.requestFinish(FinishReason.antiIdle);
      return;
    }

    switch (_state) {
      case _RodState.casting:
        final heldUs = now - _castStartUs;
        final rate = biteRatePerSecond(heldUs);
        // 100ms 轮询，事件概率 = 每秒概率 × 0.1。
        if (_rng.nextDouble() < rate * 0.1) {
          _hook(now);
        }
      case _RodState.hooked:
        // "叮"后超时未收手：花瓣随波而去。
        if (_hookIsPetal && now - _hookAtUs > _catchWindowUs) {
          _missed++;
          _state = _RodState.resting;
          _restEndUs = now + _restUs;
        }
      case _RodState.idle:
      case _RodState.resting:
        break;
    }
  }

  void _hook(int now) {
    _hookAtUs = now;
    _hookIsPetal = _rng.nextDouble() < _petalChance;
    _ctx.sounds.play(_hookIsPetal ? 'fish_ding' : 'fish_dong', gain: 0.9);
    _ctx.recorder.log('hook', {'petal': _hookIsPetal, 'waitMs': (now - _castStartUs) ~/ 1000});
    _state = _RodState.hooked;
  }

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    _lastInputUs = e.sessionUs;
    final now = e.sessionUs;

    switch (e.phase) {
      case PointerPhase.down:
        if (_state == _RodState.idle || (_state == _RodState.resting && now >= _restEndUs)) {
          // 甩杆。
          _state = _RodState.casting;
          _castStartUs = now;
          _casts++;
          _ctx.sounds.play('swish', gain: 0.6);
          _ctx.recorder.log('cast', {'at': now});
        }
      case PointerPhase.up:
      case PointerPhase.cancel:
        if (_state == _RodState.hooked) {
          final heldUs = _hookAtUs - _castStartUs;
          if (_hookIsPetal && now - _hookAtUs <= _catchWindowUs) {
            // 收杆成功：花瓣入库。
            final species = kPetalSpecies[_rng.nextInt(kPetalSpecies.length)];
            _petalsCaught++;
            _waitTimesUs.add(heldUs);
            _caught.add(
              Reward(kind: RewardKind.petal, id: species.id, label: '${species.name}花瓣'),
            );
            _ctx.sounds.play('wind_chime', gain: 0.5);
            _ctx.recorder.log('catch', {'species': species.id});
          } else if (!_hookIsPetal) {
            _miscatch++;
            _waitTimesUs.add(heldUs);
          }
          _state = _RodState.resting;
          _restEndUs = now + _restUs;
        } else if (_state == _RodState.casting) {
          // 没等到触竿就收手：空竿。
          _state = _RodState.resting;
          _restEndUs = now + _restUs;
        }
    }
  }

  @override
  void onInterrupt(InterruptReason r) {}

  @override
  void onResume() {}

  @override
  Future<PracticeResult> finish(FinishReason r) async {
    _pollTimer?.cancel();
    if (_finished) return _buildResult(r);
    _finished = true;
    return _buildResult(r);
  }

  PracticeResult _buildResult(FinishReason r) {
    final elapsedUs = _ctx.scheduler.nowUs().clamp(0, 1 << 30);
    final minutes = elapsedUs / 60000000;
    final avgWaitUs = _waitTimesUs.isEmpty
        ? 0
        : _waitTimesUs.fold<int>(0, (a, b) => a + b) ~/ _waitTimesUs.length;
    // quality 由平均等待时长与误收率构成，防"速钓刷次数"。
    final waitScore = (avgWaitUs / 20000000).clamp(0.2, 1.0);
    final miscatchRate = (_casts == 0) ? 0.0 : _miscatch / _casts;
    final quality = (waitScore * 0.7 + (1 - miscatchRate) * 0.3).clamp(0.1, 1.0);
    final merit = _petalsCaught == 0 && minutes < 0.5 ? 0 : (minutes * 2 * quality).round();

    return PracticeResult(
      effectiveDuration: Duration(microseconds: elapsedUs),
      quality: quality,
      merit: merit,
      completed: r == FinishReason.completed || r == FinishReason.userEnded,
      metrics: {
        'casts': _casts,
        'petalsCaught': _petalsCaught,
        'miscatch': _miscatch,
        'missed': _missed,
        'avgWaitSec': avgWaitUs / 1000000,
        'antiIdle': r == FinishReason.antiIdle,
      },
      extraRewards: _caught,
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    return const Center(
      child: Text(
        '长 按 甩 竿 · 闭 眼 等',
        style: TextStyle(color: Color(0x33E8DFC8), fontSize: 15, letterSpacing: 6),
      ),
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final idle = m['antiIdle'] as bool? ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          idle ? '水面静了太久，先回去吧。' : '收竿。花瓣已收进图鉴。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 16),
        _Row(label: '甩竿', value: '${m['casts']} 次'),
        _Row(label: '钓起花瓣', value: '${m['petalsCaught']} 片'),
        _Row(label: '"咚"空竿', value: '${m['miscatch']} 次'),
        _Row(label: '"叮"未接住', value: '${m['missed']} 次'),
        _Row(label: '平均等待', value: '${(m['avgWaitSec'] as num? ?? 0).toStringAsFixed(1)} 秒'),
        if (_caught.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (final reward in _caught)
                PetalBadge(label: reward.label, color: petalById(reward.id).color),
            ],
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13)),
          Text(value, style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 14)),
        ],
      ),
    );
  }
}

class PetalBadge extends StatelessWidget {
  const PetalBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

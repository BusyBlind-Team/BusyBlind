import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 数雨（专注 · 听觉计数 + 白噪声）——待对齐清单 #2 / #8 拍板版。
///
/// 统共 3 分钟。没有钟声，只有雨：每 3–10 秒落下一滴（区间内均匀随机）。
/// 过程中不实时计数（不再轻点/长按），用户只管在心里默数；
/// 听完之后由玩法弹出报数页询问"你数到了几滴"，报数与实际对账。
///
/// 修为（待对齐清单 #5）：完成一次 = 10 − 数数误差（误差为绝对滴数，
/// 下限 0）；未听完就退出不发修为。
class CountRainSession extends PracticeSession {
  static const int _lengthUs = 180000000; // 3 分钟
  static const int _rainMinUs = 3000000; // 3–10 秒一滴
  static const int _rainMaxUs = 10000000;
  static const int _askTimeoutUs = 180000000; // 报数页兜底：3 分钟无人确认自动收口

  late PracticeContext _ctx;
  final Random _rng = Random();

  // 实际雨滴（会话时间轴 µs）。
  final List<int> _rainTimesUs = [];

  bool _askingReport = false;
  int? _reportedCount;
  bool _finished = false;

  // ---- 测试钩子 ----
  @visibleForTesting
  List<int> get rainTimesUs => _rainTimesUs;
  @visibleForTesting
  bool get askingReport => _askingReport;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'count_rain',
    name: '数雨',
    subtitle: '静听三分钟能记住几滴',
    tags: [TrainingTag.focus, TrainingTag.noise],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(minutes: 3),
    meritBase: 10,
    iconKey: 'count_rain',
    rulesText: '只有雨，没有钟。雨滴大约三到十秒落下一滴。\n'
        '全程不用动手，只管在心里默数。\n三分钟后雨停，会问你这个数。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    _generateRain();
  }

  /// 生成 3–10 秒均匀间隔的雨滴序列。最小间隔 3 秒天然防扎堆，
  /// 无需旧版的反作弊约束重试。
  void _generateRain() {
    var t = 0;
    while (true) {
      t += _rainMinUs + _rng.nextInt(_rainMaxUs - _rainMinUs + 1);
      if (t >= _lengthUs) break;
      _rainTimesUs.add(t);
    }
  }

  @override
  void start() {
    // 背景白噪声（鸟鸣虫鸣，约 -24dB）。
    _ctx.sounds.startLoop(SoundCatalog.forestLoopKey, gain: 0.08);
    for (final t in _rainTimesUs) {
      _ctx.scheduler.scheduleSound(t, 'rain_drop', gain: 0.9);
    }
    _ctx.scheduler.scheduleCallback(_lengthUs, _enterReportPhase);
  }

  /// 3 分钟到：雨停，转入报数阶段（不再计时收口，等用户报数）。
  void _enterReportPhase() {
    if (_finished || _askingReport) return;
    _askingReport = true;
    // 声音语言：磬一声 = 这一局听完了，请睁眼报数。
    _ctx.sounds.play(SoundCatalog.chimeSoftKey, gain: 0.5);
    _ctx.sounds.stopLoop(SoundCatalog.forestLoopKey);
    // 兜底：报数页若长时间无人确认（用户走开），自动收口不发修为。
    // scheduleCallback 用会话时间轴绝对时刻：听雨 3 分钟 + 报数等待 3 分钟。
    _ctx.scheduler.scheduleCallback(_lengthUs + _askTimeoutUs, () {
      if (!_finished) _ctx.requestFinish(FinishReason.userEnded);
    });
    notifyVisualChanged();
  }

  /// 报数页确认回调（UI 层调用）。
  void submitReport(int count) {
    if (_finished || !_askingReport) return;
    _reportedCount = count;
    _ctx.requestFinish(FinishReason.completed);
  }

  @override
  void onInput(InputEvent e) {
    // 待对齐清单 #8：过程中不计数，一切输入只留痕，不参与判定。
    if (e.phase == PointerPhase.down) {
      _ctx.recorder.log('input:ignored', {'at': e.sessionUs});
    }
  }

  @override
  void onInterrupt(InterruptReason r) {}

  @override
  void onResume() {}

  @override
  Future<PracticeResult> finish(FinishReason r) async {
    if (_finished) return _buildResult(r);
    _finished = true;
    await _ctx.sounds.stopLoop(SoundCatalog.forestLoopKey);
    return _buildResult(r);
  }

  PracticeResult _buildResult(FinishReason r) {
    final actualRain = _rainTimesUs.length;
    final completed = r == FinishReason.completed && _reportedCount != null;
    final report = _reportedCount ?? 0;
    // 数数误差 = |报数 − 实际|（绝对滴数）；修为 = 10 − 误差，下限 0。
    final error = (report - actualRain).abs();
    final errorRate = actualRain == 0
        ? 0.0
        : (error / actualRain).clamp(0.0, 1.0);
    final merit = completed ? max(0, 10 - error) : 0;
    final quality = completed ? (1 - errorRate).clamp(0.0, 1.0) : 0.0;

    return PracticeResult(
      effectiveDuration: Duration(
        microseconds: _ctx.scheduler.nowUs().clamp(0, _lengthUs),
      ),
      quality: quality,
      merit: merit,
      completed: completed,
      metrics: {
        'userReport': completed ? report : null,
        'actualRain': actualRain,
        'error': error,
        'errorRate': errorRate,
        'excellent': completed && errorRate <= 0.10,
        'actualRainTimesUs': _rainTimesUs,
      },
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    if (_askingReport) {
      return _ReportCountView(onSubmit: submitReport);
    }
    return PracticeScene(
      kind: PracticeSceneKind.countRain,
      title: '数 雨',
      subtitle: '在心里默数 · 不用动手',
      active: true,
      progress: (_ctx.scheduler.nowUs() / _lengthUs).clamp(0.0, 1.0),
      count: 0,
      accent: 0,
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final report = m['userReport'] as int?;
    final actual = m['actualRain'] as int? ?? 0;
    final error = m['error'] as int? ?? 0;
    final excellent = m['excellent'] as bool? ?? false;
    final verdict = !r.completed && report == null
        ? '雨还没听完，先回去了。'
        : error == 0
        ? '一滴不差——你的心一直在雨里。'
        : excellent
        ? '只差 $error 滴，很静了。'
        : '对答案：数漏的雨，都是走神的一瞬。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          verdict,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 20),
        if (report != null) ...[
          _Row(label: '你的报数', value: '$report 滴'),
          _Row(label: '实际落下', value: '$actual 滴'),
          _Row(label: '数数误差', value: '$error 滴'),
        ] else ...[
          _Row(label: '实际落下', value: '$actual 滴'),
        ],
      ],
    );
  }
}

/// 报数页：听完之后才出现的"你数到了几滴？"询问（待对齐清单 #8）。
class _ReportCountView extends StatefulWidget {
  const _ReportCountView({required this.onSubmit});

  final void Function(int) onSubmit;

  @override
  State<_ReportCountView> createState() => _ReportCountViewState();
}

class _ReportCountViewState extends State<_ReportCountView> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '雨 停 了',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFE8DFC8),
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '你听见了多少滴雨？',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0x88E8DFC8), fontSize: 14),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepButton(
                icon: '−',
                onTap: () => setState(() => _count = max(0, _count - 1)),
              ),
              GestureDetector(
                onLongPress: () => setState(() => _count = 0),
                child: SizedBox(
                  width: 96,
                  child: Text(
                    '$_count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 44),
                  ),
                ),
              ),
              _StepButton(
                icon: '+',
                onTap: () => setState(() => _count = min(999, _count + 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '长按数字可清零',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0x44E8DFC8), fontSize: 12),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () => widget.onSubmit(_count),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE8DFC8),
              side: const BorderSide(color: Color(0x55E8DFC8)),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            ),
            child: const Text('就这个数'),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE8DFC8),
        side: const BorderSide(color: Color(0x33E8DFC8)),
        minimumSize: const Size(56, 56),
        padding: EdgeInsets.zero,
      ),
      child: Text(icon, style: const TextStyle(fontSize: 24)),
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
          Text(
            label,
            style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

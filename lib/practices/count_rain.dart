import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';

/// 数雨（专注 · 双通道计数 + 白噪声）。
///
/// 5 分钟。背景鸟鸣虫鸣；雨滴均值 13s（±4s）一滴，钟声均值 30s（±8s）一声。
/// 轻点 = 记一滴雨；长按 ≥300ms = 记一声钟。所有输入与实际事件都打音频
/// 时间戳进 SessionRecorder，结算对账。
/// 反作弊：任意两事件最小间隔 800ms；同一滚动 60 秒窗口内 ≤3 个事件。
class CountRainSession extends PracticeSession {
  static const int _lengthUs = 300000000; // 5 分钟
  static const int _rainMeanUs = 13000000;
  static const int _rainJitterUs = 4000000;
  static const int _bellMeanUs = 30000000;
  static const int _bellJitterUs = 8000000;
  static const int _minEventGapUs = 800000;
  static const int _longPressThresholdUs = 300000;
  static const int _inputDebounceUs = 200000;

  // 防连爆窗口：任意 10 秒内 ≤3 个事件。
  // 注：设计方案原文为"同一分钟内不超过 3 个事件"，但雨滴均值 13s/滴
  // （约 4.6 滴/分钟）与该约束矛盾，按意图（防事件扎堆）改为 10 秒窗口。
  static const int _maxEventsInBurst = 3;
  static const int _burstWindowUs = 10000000;

  late PracticeContext _ctx;
  final Random _rng = Random();

  // 实际事件（会话时间轴 µs）。
  final List<int> _rainTimesUs = [];
  final List<int> _bellTimesUs = [];

  // 用户输入（会话时间轴 µs）。
  final List<int> _userRainUs = [];
  final List<int> _userBellUs = [];
  int? _downUs;
  int? _lastRainInputUs;
  int? _lastBellInputUs;
  bool _finished = false;

  // ---- 测试钩子 ----
  @visibleForTesting List<int> get rainTimesUs => _rainTimesUs;
  @visibleForTesting List<int> get bellTimesUs => _bellTimesUs;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'count_rain',
    name: '数雨',
    subtitle: '轻点记雨，长按记钟',
    tags: [TrainingTag.focus, TrainingTag.noise],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(minutes: 5),
    meritBase: 15,
    iconKey: 'count_rain',
    rulesText:
        '鸟鸣虫鸣里，雨滴偶尔落下，钟声偶尔响起。\n轻点一次＝记一滴雨；按住不松（约半秒）＝记一声钟。\n五分钟后对答案。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    _generateEvents();
  }

  /// 生成满足反作弊约束的事件序列（重试法）。
  void _generateEvents() {
    for (var attempt = 0; attempt < 50; attempt++) {
      final rains = _jitteredSeries(_rainMeanUs, _rainJitterUs);
      final bells = _jitteredSeries(_bellMeanUs, _bellJitterUs);
      final merged = <(int, String)>[
        for (final t in rains) (t, 'rain'),
        for (final t in bells) (t, 'bell'),
      ]..sort((a, b) => a.$1.compareTo(b.$1));

      // 约束 1：任意两事件最小间隔 800ms。
      var ok = true;
      for (var i = 1; i < merged.length; i++) {
        if (merged[i].$1 - merged[i - 1].$1 < _minEventGapUs) {
          ok = false;
          break;
        }
      }
      // 约束 2：任意 10 秒窗口内 ≤3 个事件（防扎堆）。
      if (ok) {
        for (var i = 0; i + _maxEventsInBurst < merged.length; i++) {
          if (merged[i + _maxEventsInBurst].$1 - merged[i].$1 < _burstWindowUs) {
            ok = false;
            break;
          }
        }
      }
      if (ok) {
        _rainTimesUs
          ..clear()
          ..addAll(rains.where((t) => t < _lengthUs));
        _bellTimesUs
          ..clear()
          ..addAll(bells.where((t) => t < _lengthUs));
        return;
      }
    }
    // 兜底：直接用均值（必然满足约束）。
    for (var t = _rainMeanUs; t < _lengthUs; t += _rainMeanUs) {
      _rainTimesUs.add(t);
    }
    for (var t = _bellMeanUs; t < _lengthUs; t += _bellMeanUs) {
      _bellTimesUs.add(t);
    }
  }

  List<int> _jitteredSeries(int meanUs, int jitterUs) {
    final out = <int>[];
    var t = 0;
    while (t < _lengthUs) {
      t += meanUs + ((_rng.nextDouble() * 2 - 1) * jitterUs).round();
      if (t > 0) out.add(t);
    }
    return out;
  }

  @override
  void start() {
    // 背景白噪声（鸟鸣虫鸣，约 -24dB）。
    _ctx.sounds.startLoop(SoundCatalog.forestLoopKey, gain: 0.08);
    for (final t in _rainTimesUs) {
      _ctx.scheduler.scheduleSound(t, 'rain_drop', gain: 0.9);
    }
    for (final t in _bellTimesUs) {
      _ctx.scheduler.scheduleSound(t, 'bell_low', gain: 0.7);
    }
    _ctx.scheduler.scheduleCallback(_lengthUs, () {
      _ctx.requestFinish(FinishReason.completed);
    });
  }

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    switch (e.phase) {
      case PointerPhase.down:
        _downUs = e.sessionUs;
      case PointerPhase.up:
        final down = _downUs;
        _downUs = null;
        if (down == null) return;
        final heldUs = e.sessionUs - down;
        if (heldUs >= _longPressThresholdUs) {
          _recordBell(down);
        } else {
          _recordRain(down);
        }
      case PointerPhase.cancel:
        _downUs = null;
    }
  }

  void _recordRain(int atUs) {
    if (_lastRainInputUs != null && atUs - _lastRainInputUs! < _inputDebounceUs) {
      return;
    }
    _lastRainInputUs = atUs;
    _userRainUs.add(atUs);
    _ctx.recorder.log('input:rain', {'at': atUs});
  }

  void _recordBell(int atUs) {
    if (_lastBellInputUs != null && atUs - _lastBellInputUs! < _inputDebounceUs) {
      return;
    }
    _lastBellInputUs = atUs;
    _userBellUs.add(atUs);
    _ctx.recorder.log('input:bell', {'at': atUs});
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
    final actualBell = _bellTimesUs.length;
    final rainErr = actualRain == 0 ? 0.0 : (_userRainUs.length - actualRain).abs() / actualRain;
    final bellErr = actualBell == 0 ? 0.0 : (_userBellUs.length - actualBell).abs() / actualBell;
    final avgErr = (rainErr + bellErr) / 2;
    final completed = r == FinishReason.completed;
    final quality = (1 - avgErr).clamp(0.0, 1.0);
    final merit = completed ? max(5, (15 * (1 - avgErr)).round()) : 5;

    return PracticeResult(
      effectiveDuration: Duration(
        microseconds: _ctx.scheduler.nowUs().clamp(0, _lengthUs),
      ),
      quality: quality,
      merit: merit,
      completed: completed,
      metrics: {
        'userRain': _userRainUs.length,
        'userBell': _userBellUs.length,
        'actualRain': actualRain,
        'actualBell': actualBell,
        'rainError': rainErr,
        'bellError': bellErr,
        'avgError': avgErr,
        'excellent': avgErr <= 0.10,
        'userRainTimesUs': _userRainUs,
        'userBellTimesUs': _userBellUs,
        'actualRainTimesUs': _rainTimesUs,
        'actualBellTimesUs': _bellTimesUs,
      },
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    return Center(
      child: Text(
        '闭眼 · 听雨',
        style: const TextStyle(color: Color(0x33E8DFC8), fontSize: 15, letterSpacing: 8),
      ),
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final excellent = m['excellent'] as bool? ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          excellent ? '误差不到一成——心很静。' : '对答案：数漏的雨，都是走神的一瞬。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 20),
        _Row(label: '你数到的雨滴', value: '${m['userRain']} 滴'),
        _Row(label: '实际雨滴', value: '${m['actualRain']} 滴'),
        _Row(label: '雨滴误差', value: '${((m['rainError'] as num) * 100).toStringAsFixed(0)}%'),
        const SizedBox(height: 8),
        _Row(label: '你数到的钟声', value: '${m['userBell']} 声'),
        _Row(label: '实际钟声', value: '${m['actualBell']} 声'),
        _Row(label: '钟声误差', value: '${((m['bellError'] as num) * 100).toStringAsFixed(0)}%'),
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

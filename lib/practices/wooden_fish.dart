import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/interval_chart.dart';

/// 木鱼（专注 · 节奏保持）。
///
/// - 108 下，目标间隔 1000ms（佛家百八之数；磬声节点基于 36 的倍数）。
/// - 无外部节拍音——节拍必须来自用户内心。
/// - 过程反馈仅两处：每 36 下极轻磬；偏差累积超阈值时木鱼音色变闷。
/// - 结算：心急/走神判定 + 间隔曲线 + 稳定性标准差。
/// - 修为：12 × quality，quality 由稳定性而非总时长决定。
class WoodenFishSession extends PracticeSession {
  static const int _totalStrikes = 108;
  static const int _targetIntervalUs = 1000000;
  static const int _chimeEvery = 36;
  static const int _muffleThresholdUs = 1200000;
  static const int _unmuffleThresholdUs = 600000;

  late PracticeContext _ctx;

  int _strikes = 0;
  int? _lastStrikeUs;
  final List<int> _intervalsUs = [];
  int _cumDeviationUs = 0;
  bool _muffled = false;
  bool _finished = false;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'wooden_fish',
    name: '木鱼',
    subtitle: '一百零八声，快慢由心',
    tags: [TrainingTag.focus, TrainingTag.rhythm],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(seconds: 108),
    meritBase: 12,
    iconKey: 'wooden_fish',
    rulesText: '没有节拍器。闭上眼，在心里守住一秒一击的节奏，敲满一百零八声。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
  }

  @override
  void start() {}

  @override
  void onInput(InputEvent e) {
    if (e.phase != PointerPhase.down || _finished) return;
    final now = e.sessionUs;
    _ctx.recorder.log('input:strike', {'at': now});

    if (_lastStrikeUs != null) {
      final interval = now - _lastStrikeUs!;
      if (interval > 0) {
        _intervalsUs.add(interval);
        _cumDeviationUs += interval - _targetIntervalUs;
      }
    }

    _lastStrikeUs = now;
    _strikes++;

    // 音色反馈：偏差累积超阈值 → 音色微微变闷；回到阈值内 → 恢复。
    if (!_muffled && _cumDeviationUs.abs() > _muffleThresholdUs) {
      _muffled = true;
    } else if (_muffled && _cumDeviationUs.abs() < _unmuffleThresholdUs) {
      _muffled = false;
    }
    _ctx.sounds.play(_muffled ? 'muyu_muffled' : SoundCatalog.muyuKey);

    // 每三分之一：极轻的磬远远应一声。
    if (_strikes % _chimeEvery == 0 && _strikes < _totalStrikes) {
      _ctx.sounds.play(SoundCatalog.chimeSoftKey, gain: 0.4);
    }

    if (_strikes >= _totalStrikes) {
      _ctx.requestFinish(FinishReason.completed);
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
    return _buildResult(r);
  }

  PracticeResult _buildResult(FinishReason r) {
    final totalUs = _intervalsUs.fold<int>(0, (a, b) => a + b);
    final meanUs =
        _intervalsUs.isEmpty ? 0.0 : totalUs / _intervalsUs.length;
    final stdUs = _intervalsUs.isEmpty
        ? 0.0
        : _std(_intervalsUs.map((e) => e.toDouble()).toList());
    // quality 由稳定性决定：标准差 ≤80ms 满质量，≥480ms 降到底。
    final quality = (1.0 - (stdUs - 80000) / 400000).clamp(0.05, 1.0);
    final completed = r == FinishReason.completed;
    final merit = completed ? (12 * quality).round() : (6 * quality).round();

    var rush = 0;
    var drift = 0;
    for (final v in _intervalsUs) {
      if (v < _targetIntervalUs - 150000) {
        rush++;
      } else if (v > _targetIntervalUs + 150000) {
        drift++;
      }
    }

    return PracticeResult(
      effectiveDuration: Duration(microseconds: totalUs),
      quality: quality,
      merit: merit,
      completed: completed,
      metrics: {
        'strikes': _strikes,
        'intervalMeanUs': meanUs.round(),
        'intervalStdUs': stdUs.round(),
        'totalMs': totalUs ~/ 1000,
        'rushCount': rush,
        'driftCount': drift,
        'intervalsMs': _intervalsUs.map((e) => e ~/ 1000).toList(),
      },
    );
  }

  static double _std(List<double> xs) {
    if (xs.length < 2) return 0;
    final mean = xs.fold<double>(0, (a, b) => a + b) / xs.length;
    final variance =
        xs.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) / xs.length;
    return sqrt(variance);
  }

  @override
  Widget buildVisual(BuildContext c) {
    return Center(
      child: Text(
        _strikes == 0 ? '第 一 声 由 你 敲 响' : '$_strikes / $_totalStrikes',
        style: const TextStyle(color: Color(0x33E8DFC8), fontSize: 16, letterSpacing: 4),
      ),
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final intervals =
        ((m['intervalsMs'] as List?) ?? const []).cast<int>().map((e) => e.toDouble()).toList();
    final totalMs = m['totalMs'] as int? ?? 0;
    final diffSec = (totalMs - _totalStrikes * 1000) / 1000.0;
    final verdict = !r.completed
        ? '中途收手'
        : diffSec < -2
            ? '心急了——整体偏快 ${diffSec.abs().toStringAsFixed(1)} 秒'
            : diffSec > 2
                ? '走神了——整体偏慢 ${diffSec.toStringAsFixed(1)} 秒'
                : '节奏守得很稳';
    final stdMs = ((m['intervalStdUs'] as num?) ?? 0) / 1000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(verdict, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15)),
        const SizedBox(height: 16),
        const Text('间隔曲线（虚线为目标 1 秒）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0x66E8DFC8), fontSize: 12)),
        const SizedBox(height: 8),
        IntervalChart(valuesMs: intervals, targetMs: _targetIntervalUs / 1000),
        const SizedBox(height: 16),
        _Row(label: '敲响', value: '${m['strikes']} / $_totalStrikes 声'),
        _Row(label: '总用时', value: '${(totalMs / 1000).toStringAsFixed(1)} 秒'),
        _Row(label: '稳定性（间隔标准差）', value: '${stdMs.toStringAsFixed(0)} ms'),
        _Row(label: '心急段', value: '${m['rushCount']} 次'),
        _Row(label: '走神段', value: '${m['driftCount']} 次'),
        _Row(label: '完成质量', value: '${(r.quality * 100).toStringAsFixed(0)} 分'),
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

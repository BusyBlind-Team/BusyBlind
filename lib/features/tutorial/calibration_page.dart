import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../theme.dart';

/// AudioClock 手动校准：跟着节拍轻点 16 次，取偏差中位数写入 L_user。
///
/// 此后所有时机判定都会贴着用户的耳朵来算（教程第三段，用户无感知）。
class CalibrationPage extends ConsumerStatefulWidget {
  const CalibrationPage({super.key});

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage> {
  static const int _totalTaps = 16;
  static const int _periodUs = 800000;

  final List<int> _beatUs = [];
  final List<int> _offsetsUs = [];
  StreamSubscription<int>? _beatSubscription;
  bool _running = false;
  int? _medianUs;
  int _runId = 0;

  void _stopBeats() {
    _runId++;
    final subscription = _beatSubscription;
    _beatSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _start() {
    _stopBeats();
    _beatUs.clear();
    _offsetsUs.clear();
    _medianUs = null;
    final clock = ref.read(clockProvider);
    final sounds = ref.read(soundBankProvider);
    final runId = _runId;
    setState(() => _running = true);
    _beatSubscription = clock.beats(_periodUs).listen((beatAt) {
      if (!_running || runId != _runId) return;
      _beatUs.add(beatAt);
      sounds.play(SoundCatalog.tickKey, gain: 0.8);
      if (mounted) setState(() {});
    });
  }

  void _onTap() {
    if (!_running) return;
    final clock = ref.read(clockProvider);
    final tapUs = clock.nowUs();
    if (_beatUs.isEmpty) return;

    // 取最近的节拍，计算偏差 = 用户落后节拍多少。
    int best = _beatUs.last;
    for (final b in _beatUs) {
      if ((b - tapUs).abs() < (best - tapUs).abs()) best = b;
    }
    final window = _periodUs ~/ 2;
    final offset = tapUs - best;
    if (offset.abs() <= window) {
      _offsetsUs.add(offset);
    }
    if (_offsetsUs.length >= _totalTaps) {
      final sorted = [..._offsetsUs]..sort();
      final median = sorted[sorted.length ~/ 2];
      final clock = ref.read(clockProvider);
      final store = ref.read(storeProvider);
      clock.userOffsetUs = median;
      store.lUserUs = median;
      _stopBeats();
      setState(() {
        _running = false;
        _medianUs = median;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _stopBeats();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taps = _offsetsUs.length;
    return Scaffold(
      appBar: AppBar(title: const Text('时机校准')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _running ? _onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _running ? '跟着节拍轻点 16 次\n（$taps / $_totalTaps）' : '校准你的耳朵与手指',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.ink, fontSize: 20, height: 1.6),
              ),
              const SizedBox(height: 16),
              Text(
                _running
                    ? '每次 tick 落下的瞬间点屏幕任意处。'
                    : _medianUs == null
                        ? '会播放一段节拍，请跟着点。校准结果只在本机生效。'
                        : '校准完成：偏差中位数 ${_medianUs! / 1000} ms\n（正数 = 你习惯性慢半拍）',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 40),
              if (!_running)
                OutlinedButton(
                  onPressed: _start,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.gold,
                    side: const BorderSide(color: AppTheme.goldDim),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_medianUs == null ? '开始校准' : '重新校准'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

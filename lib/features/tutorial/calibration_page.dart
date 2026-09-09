import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../theme.dart';

/// AudioClock 手动校准（改进列表）：判定线横向移动，移到中间定线的
/// 瞬间会发声，此刻按下屏幕；共 5 下，取偏差中位数写入 L_user。
///
/// 此后所有时机判定都会贴着用户的耳朵来算（教程第三段，用户无感知）。
/// 离开页面必须取消节拍订阅，否则 tick 会一直响（本次一并修复）。
class CalibrationPage extends ConsumerStatefulWidget {
  const CalibrationPage({super.key});

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage>
    with SingleTickerProviderStateMixin {
  static const int _totalTaps = 5;
  static const int _periodUs = 1200000;

  final List<int> _beatUs = [];
  final List<int> _offsetsUs = [];
  StreamSubscription<int>? _beatSubscription;
  late final AnimationController _sweep;
  bool _running = false;
  int? _medianUs;

  @override
  void initState() {
    super.initState();
    // 一格周期：动线从中心飞回左缘（前 25%），再从左缘扫回中心（后 75%），
    // 扫到中心的时刻正好是下一次节拍。
    _sweep = AnimationController(vsync: this, duration: const Duration(microseconds: _periodUs));
  }

  @override
  void dispose() {
    _beatSubscription?.cancel();
    _beatSubscription = null;
    _sweep.dispose();
    super.dispose();
  }

  void _stopBeats() {
    _beatSubscription?.cancel();
    _beatSubscription = null;
    _sweep.stop();
  }

  void _start() {
    _stopBeats();
    _beatUs.clear();
    _offsetsUs.clear();
    _medianUs = null;
    final clock = ref.read(clockProvider);
    final sounds = ref.read(soundBankProvider);
    setState(() => _running = true);
    _beatSubscription = clock.beats(_periodUs).listen((beatAt) {
      _beatUs.add(beatAt);
      sounds.play(SoundCatalog.tickKey, gain: 0.8);
      if (mounted) {
        setState(() {});
        _sweep.forward(from: 0);
      }
    });
  }

  void _onTap() {
    if (!_running) return;
    if (_beatUs.isEmpty) return;
    final clock = ref.read(clockProvider);
    final tapUs = clock.nowUs();

    // 取最近的节拍（判定线扫到中心的时刻），偏差 = 用户落后多少。
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
                _running ? '判定线移到中间定线时会有声音\n此刻点下屏幕（$taps / $_totalTaps）' : '校准你的耳朵与手指',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.ink, fontSize: 20, height: 1.6),
              ),
              const SizedBox(height: 16),
              Text(
                _running
                    ? '动线扫到中间、听见"哒"的瞬间，点屏幕任意处。'
                    : _medianUs == null
                        ? '一条动线会横向移动，它扫到中间定线时会发声。'
                            '在那声瞬间点下屏幕，共 5 下。校准结果只在本机生效。'
                        : '校准完成：偏差中位数 ${_medianUs! / 1000} ms\n（正数 = 你习惯性慢半拍）',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 40),
              // 判定线轨道。
              SizedBox(
                height: 36,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) => CustomPaint(
                    painter: _CalibrationTrackPainter(
                      position: _running ? _linePosition(_sweep.value) : 0,
                      running: _running,
                    ),
                  ),
                ),
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

  /// 扫描值 → 轨道位置（0 = 左缘，1 = 中心，2 = 右缘再折返的进度）。
  double _linePosition(double t) {
    if (t <= 0.25) {
      // 从中心飞回左缘。
      return 1 - (t / 0.25);
    }
    // 从左缘扫回中心。
    return (t - 0.25) / 0.75;
  }
}

class _CalibrationTrackPainter extends CustomPainter {
  const _CalibrationTrackPainter({required this.position, required this.running});

  final double position;
  final bool running;

  /// 动线扫动区：左缘 12% → 屏幕中线（位置 0 = 左缘，1 = 定线）。
  static const double _trackStart = 0.12;
  static const double _trackEnd = 0.50;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x0 = size.width * _trackStart;
    final x1 = size.width * _trackEnd;
    final track = Paint()
      ..color = const Color(0x22E8DFC8)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), track);

    // 中间定线（动线扫到这里的瞬间发声）。
    final center = Paint()
      ..color = AppTheme.gold
      ..strokeWidth = 2.4;
    canvas.drawLine(Offset(x1, y - 14), Offset(x1, y + 14), center);

    // 动线：位置与发声时刻对齐——值 1 即定线（复审 P2-4）。
    if (running) {
      final x = x0 + position * (x1 - x0);
      final line = Paint()
        ..color = const Color(0xFFE8DFC8)
        ..strokeWidth = 3;
      canvas.drawLine(Offset(x, y - 18), Offset(x, y + 18), line);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = const Color(0xFFE8DFC8));
    }
  }

  @override
  bool shouldRepaint(covariant _CalibrationTrackPainter old) =>
      old.position != position || old.running != running;
}

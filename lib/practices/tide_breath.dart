import 'dart:async';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 呼吸法（改进列表：难度选择移到开始界面，含憋气段）。
///
/// 每段 = (时长, 屏幕应当按住吗, 音量包络)。间隔即憋气：
/// 憋气段请保持按住；间隔时依然播放潮涌的声音，也算在潮涌判定里。
class BreathSegment {
  const BreathSegment(this.lengthUs, this.pressExpected, this.envelope);

  final int lengthUs;
  final bool pressExpected;
  final BreathEnvelope envelope;
}

enum BreathEnvelope { up, holdHigh, down, holdLow }

/// 三种呼吸法：
/// - 4-6：4 秒潮涌（吸），6 秒潮落（呼），无间隔。
/// - 盒式：4 涌 - 4 间隔 - 4 落 - 4 间隔。
/// - 4-7-8：4 涌 - 7 间隔 - 8 落。
const List<List<BreathSegment>> kBreathMethods = [
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(6000000, false, BreathEnvelope.down),
  ],
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(4000000, true, BreathEnvelope.holdHigh),
    BreathSegment(4000000, false, BreathEnvelope.down),
    BreathSegment(4000000, true, BreathEnvelope.holdLow),
  ],
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(7000000, true, BreathEnvelope.holdHigh),
    BreathSegment(8000000, false, BreathEnvelope.down),
  ],
];

const List<String> kBreathMethodLabels = ['4-6 呼吸', '盒式呼吸', '4-7-8 呼吸'];

/// 听潮（呼吸 · 助眠）。
///
/// 吸气/憋气段按住屏幕，呼气段松开；相位吻合时潮声里叠入一层极轻的风铃。
/// 呼吸法在开始界面选择（4-6 / 盒式 / 4-7-8）。
/// 按压特效（改进列表）：屏幕中间圆圈随按住逐渐增大，松手时留下
/// 原大小虚影快速虚化，圆圈快速缩小到原始大小。
/// 助眠模式：结束不弹结算页（note='sleep_mode'，宿主处理次日补发）。
///
/// 修为公式为拟定值（设计方案待对齐 #5）：分钟数 × 2 × 同步率。
class TideBreathSession extends PracticeSession {
  late PracticeContext _ctx;

  List<BreathSegment> _segments = kBreathMethods[0];
  int _segIndex = 0;
  int _phaseStartUs = 0;

  // 输入状态。
  bool _pressed = false;
  int? _pressStartUs;

  // 同步统计：与相位期望吻合的累计时长。
  int _matchedUs = 0;
  int? _lastMatchCheckUs;
  bool _chimedThisPhase = false;
  final List<int> _phaseBoundariesUs = [];
  final List<double> _phaseSyncRates = [];

  bool _finished = false;

  int _breathMethod = 0;

  @override
  List<String> get startChoices => kBreathMethodLabels;

  @override
  int get startChoice => _breathMethod;

  @override
  set startChoice(int index) => _breathMethod = index.clamp(0, 2);

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'tide_breath',
    name: '听潮',
    subtitle: '潮涨时吸气，潮落时呼气',
    tags: [TrainingTag.breath, TrainingTag.sleep],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(minutes: 5),
    meritBase: 10,
    iconKey: 'tide_breath',
    allowManualEnd: true,
    rulesText: '潮涨渐强时，按住屏幕吸气；潮落渐弱时，松开屏幕呼气。憋气段请保持按住。\n咬合的瞬间，会有一层风铃。',
    introTags: '呼吸·助眠·白噪声',
    intro: '潮涌，潮落，这是自然的呼吸。让气息和自然同步，能带来安稳的睡眠。在这放松的五分钟内，循着潮声呼吸吧。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
  }

  bool get _shouldPress => _segments[_segIndex].pressExpected;

  @override
  void start() {
    _segments = kBreathMethods[_breathMethod.clamp(0, kBreathMethods.length - 1)];
    _segIndex = 0;
    _ctx.sounds.startLoop(SoundCatalog.tideLoopKey, gain: 0.05);
    _phaseStartUs = _ctx.scheduler.nowUs();
    _lastMatchCheckUs = _phaseStartUs;
    _schedulePhaseEnd();
    // 音量包络与吻合累计交给低频轮询（120ms 足够平滑）。
    _rampTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _rampVolume(),
    );
    _matchTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollMatch(),
    );
  }

  Timer? _rampTimer;
  Timer? _matchTimer;

  double _envelopeVolume(BreathEnvelope envelope, double x) => switch (envelope) {
    BreathEnvelope.up => 0.05 + (0.5 - 0.05) * x,
    BreathEnvelope.holdHigh => 0.5,
    BreathEnvelope.down => 0.5 - (0.5 - 0.05) * x,
    BreathEnvelope.holdLow => 0.05 + 0.06 * x, // 蓄势微升，引出下一段潮涌
  };

  void _rampVolume() {
    if (!_ctx.scheduler.isRunning) return;
    final seg = _segments[_segIndex];
    final t = _ctx.scheduler.nowUs() - _phaseStartUs;
    final x = (t / seg.lengthUs).clamp(0.0, 1.0);
    _ctx.sounds.setLoopGain(
      SoundCatalog.tideLoopKey,
      _envelopeVolume(seg.envelope, x),
    );
  }

  void _schedulePhaseEnd() {
    final len = _segments[_segIndex].lengthUs;
    _ctx.scheduler.scheduleCallback(
      _ctx.scheduler.nowUs() + len,
      _advancePhase,
    );
  }

  void _advancePhase() {
    if (_finished) return;
    final now = _ctx.scheduler.nowUs();
    _phaseBoundariesUs.add(now);

    // 本相位同步率快照。
    final len = _segments[_segIndex].lengthUs;
    if (len > 0 && _phaseSyncRates.length < 400) {
      _phaseSyncRates.add((_matchedUs / len).clamp(0.0, 1.0));
    }
    _matchedUs = 0;

    _segIndex = (_segIndex + 1) % _segments.length;
    _chimedThisPhase = false;
    _phaseStartUs = now;
    notifyVisualChanged();
    _schedulePhaseEnd();
  }

  bool get _phaseMatchesInput => _pressed == _shouldPress;

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    switch (e.phase) {
      case PointerPhase.down:
        _pressed = true;
        _pressStartUs = e.sessionUs;
      case PointerPhase.move:
        break; // 按住挪动不改变按住状态。
      case PointerPhase.up:
      case PointerPhase.cancel:
        _pressed = false;
        _pressStartUs = null;
    }
    _ctx.recorder.log('input:breath', {
      'pressed': _pressed,
      'expectPress': _shouldPress,
    });
    notifyVisualChanged();
  }

  /// 相位吻合累计与风铃反馈，交给低频轮询（200ms，精度足够）。
  void _pollMatch() {
    if (_finished || !_ctx.scheduler.isRunning) return;
    final now = _ctx.scheduler.nowUs();
    if (_phaseMatchesInput) {
      final delta = now - (_lastMatchCheckUs ?? now);
      _matchedUs += delta;
      // 吻合持续 ≥300ms 且本相位还没响过风铃 → 叠入极轻风铃。
      if (!_chimedThisPhase && _matchedUs >= 300000 && _pressStartUs != null) {
        _chimedThisPhase = true;
        _ctx.sounds.play(SoundCatalog.windChimeKey, gain: 0.35);
      }
    }
    _lastMatchCheckUs = now;
  }

  @override
  void onInterrupt(InterruptReason r) {}

  @override
  void onResume() {}

  @override
  Future<PracticeResult> finish(FinishReason r) async {
    _rampTimer?.cancel();
    _matchTimer?.cancel();
    if (_finished) return _buildResult(r);
    _finished = true;

    final sleepMode = _ctx.boolParam('sleepMode');
    if (sleepMode) {
      // 助眠模式：音频渐弱至静音（约 4 秒），宿主按 note 跳过结算页。
      for (var i = 10; i >= 0; i--) {
        await _ctx.sounds.setLoopGain(SoundCatalog.tideLoopKey, 0.05 * i / 10);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    await _ctx.sounds.stopLoop(SoundCatalog.tideLoopKey);
    return _buildResult(r);
  }

  PracticeResult _buildResult(FinishReason r) {
    final now = _ctx.scheduler.nowUs();
    final elapsedUs = now.clamp(1, 1 << 40);
    final avgSync = _phaseSyncRates.isEmpty
        ? 0.0
        : _phaseSyncRates.reduce((a, b) => a + b) / _phaseSyncRates.length;
    final quality = avgSync.clamp(0.0, 1.0);
    final minutes = elapsedUs / 60000000;
    final merit = (minutes * 2 * quality).round();
    final sleepMode = _ctx.boolParam('sleepMode');

    return PracticeResult(
      effectiveDuration: Duration(microseconds: elapsedUs),
      quality: quality,
      merit: merit,
      completed: r == FinishReason.completed || r == FinishReason.userEnded,
      note: sleepMode ? 'sleep_mode' : null,
      metrics: {
        'avgSync': avgSync,
        'phaseCount': _phaseBoundariesUs.length,
        'phaseSyncRates': _phaseSyncRates
            .map((e) => (e * 100).round())
            .toList(),
        'sleepMode': sleepMode,
        'breathMethod': _breathMethod,
      },
    );
  }

  String get _phaseLabel {
    final envelope = _segments[_segIndex].envelope;
    return switch (envelope) {
      BreathEnvelope.up => '潮 涨 · 吸',
      BreathEnvelope.holdHigh || BreathEnvelope.holdLow => '憋 气 · 按',
      BreathEnvelope.down => '潮 落 · 呼',
    };
  }

  String get _phaseHint =>
      _segments[_segIndex].pressExpected ? '按住屏幕' : '松开屏幕';

  /// 当前按住时长占比（0..1，圆圈增大用；8 秒按满）。
  double get _holdProgress {
    if (!_pressed || _pressStartUs == null) return 0;
    final held = _ctx.scheduler.nowUs() - _pressStartUs!;
    return (held / 8000000).clamp(0.0, 1.0);
  }

  @override
  Widget buildVisual(BuildContext c) {
    return Stack(
      children: [
        Positioned.fill(
          child: PracticeScene(
            kind: PracticeSceneKind.tideBreath,
            title: _phaseLabel,
            subtitle: _phaseHint,
            active: _pressed,
            count: _phaseBoundariesUs.length,
            accent: _phaseMatchesInput ? 1 : 0.25,
          ),
        ),
        // 按压圆圈特效（改进列表）：按住渐大，松手留虚影快速虚化。
        Positioned.fill(
          child: IgnorePointer(
            child: _BreathCircleOverlay(
              pressed: _pressed,
              holdProgress: _holdProgress,
              matched: _phaseMatchesInput,
              revision: visualRevision.value,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _rampTimer?.cancel();
    _matchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final sync = ((r.metrics['avgSync'] as num? ?? 0) * 100).toStringAsFixed(0);
    final method = (r.metrics['breathMethod'] as int? ?? 0)
        .clamp(0, kBreathMethodLabels.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          r.quality >= 0.7 ? '呼吸与潮汐咬合得很好。' : '潮水不催人，下次慢慢来。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 16),
        Text(
          '呼吸法：${kBreathMethodLabels[method]}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0x66E8DFC8), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          '平均同步率 $sync %',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 14),
        ),
      ],
    );
  }
}

/// 按压圆圈特效：按住时圆圈逐渐增大；松手时在原大小留一个虚影，
/// 虚影快速虚化（淡出 + 外扩），圆圈快速缩小到原始大小（改进列表）。
class _BreathCircleOverlay extends StatefulWidget {
  const _BreathCircleOverlay({
    required this.pressed,
    required this.holdProgress,
    required this.matched,
    required this.revision,
  });

  final bool pressed;
  final double holdProgress;
  final bool matched;

  /// 会话视觉修订号：松手等关键事件借它触发一次 rebuild。
  final int revision;

  @override
  State<_BreathCircleOverlay> createState() => _BreathCircleOverlayState();
}

class _BreathCircleOverlayState extends State<_BreathCircleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frame;
  static const double _baseRadius = 46;
  static const double _maxRadius = 170;

  double _radius = _baseRadius;
  final List<({double radius, double opacity})> _ghosts = [];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _frame = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..repeat();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0005, 0.1);
    _last = elapsed;
    if (widget.pressed) {
      // 按住：向目标半径（随按住时长增大）靠拢。
      final target =
          _baseRadius + (_maxRadius - _baseRadius) * widget.holdProgress;
      _radius += (target - _radius) * (dt * 6).clamp(0.0, 1.0);
    } else if (_radius > _baseRadius) {
      // 松手：快速缩回原大。
      _radius -= 340 * dt;
      if (_radius < _baseRadius) _radius = _baseRadius;
    }
    // 虚影快速虚化：淡出 + 外扩。
    for (var i = 0; i < _ghosts.length; i++) {
      final g = _ghosts[i];
      _ghosts[i] = (
        radius: g.radius + 60 * dt,
        opacity: (g.opacity - 2.6 * dt).clamp(0.0, 1.0),
      );
    }
    _ghosts.removeWhere((g) => g.opacity <= 0);
  }

  @override
  void didUpdateWidget(covariant _BreathCircleOverlay old) {
    super.didUpdateWidget(old);
    // 松手瞬间：留下原大小的虚影。
    if (old.pressed && !widget.pressed && _radius > _baseRadius + 4) {
      _ghosts.add((radius: _radius, opacity: 0.4));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _frame,
      builder: (context, _) {
        _tick(elapsedOfController());
        return CustomPaint(
          painter: _BreathCirclePainter(
            radius: _radius,
            ghosts: _ghosts,
            matched: widget.matched,
          ),
        );
      },
    );
  }

  Duration elapsedOfController() => _frame.lastElapsedDuration ?? _last;

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }
}

class _BreathCirclePainter extends CustomPainter {
  _BreathCirclePainter({
    required this.radius,
    required this.ghosts,
    required this.matched,
  });

  final double radius;
  final List<({double radius, double opacity})> ghosts;
  final bool matched;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    for (final g in ghosts) {
      canvas.drawCircle(
        c,
        g.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.lerp(
            const Color(0x00E8DFC8),
            const Color(0x66E8DFC8),
            g.opacity,
          )!,
      );
    }
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = matched ? 2.4 : 1.4
        ..color = matched ? const Color(0x88D8B36A) : const Color(0x44E8DFC8),
    );
    canvas.drawCircle(c, radius * 0.92, Paint()..color = const Color(0x0DE8DFC8));
  }

  @override
  bool shouldRepaint(covariant _BreathCirclePainter old) => true;
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 呼吸段：时长 + 屏幕是否应当按住 + 音量包络。
///
/// 新-改进说明文档 §3：按住 = 吸气（及憋气），松开 = 呼气（及憋气）。
class BreathSegment {
  const BreathSegment(this.lengthUs, this.pressExpected, this.envelope);

  final int lengthUs;
  final bool pressExpected;
  final BreathEnvelope envelope;
}

enum BreathEnvelope { up, holdHigh, down, holdLow }

/// 三种呼吸法时间轴（新-改进说明文档 §3.1 表 1）：
///
/// - 4-6：按住 4 秒（吸气）→ 松开 6 秒（呼气），周期 10 秒。
/// - 盒式：按住 8 秒（4 吸气 + 4 憋气）→ 松开 8 秒（4 呼气 + 4 憋气），
///   周期 16 秒。憋气在"松开段"里，故最后一段 pressExpected 为 false。
/// - 4-7-8：按住 11 秒（4 吸气 + 7 憋气）→ 松开 8 秒（呼气），周期 19 秒。
const List<List<BreathSegment>> kBreathMethods = [
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(6000000, false, BreathEnvelope.down),
  ],
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(4000000, true, BreathEnvelope.holdHigh),
    BreathSegment(4000000, false, BreathEnvelope.down),
    BreathSegment(4000000, false, BreathEnvelope.holdLow),
  ],
  [
    BreathSegment(4000000, true, BreathEnvelope.up),
    BreathSegment(7000000, true, BreathEnvelope.holdHigh),
    BreathSegment(8000000, false, BreathEnvelope.down),
  ],
];

const List<String> kBreathMethodLabels = ['4-6 呼吸', '盒式呼吸', '4-7-8 呼吸'];

/// 开始界面展开的呼吸法详情（新-改进说明文档 §6.2 表 2）。
const List<({String rhythm, String note})> kBreathMethodDetails = [
  (rhythm: '4 秒吸气，6 秒呼气', note: '难度低，容易上手'),
  (rhythm: '4 秒吸气，4 秒憋气，4 秒呼气，4 秒憋气', note: '难度较低，呼吸节奏稳定'),
  (rhythm: '4 秒吸气，7 秒憋气，8 秒呼气', note: '有一定难度，但放松效果很好'),
];

/// 听潮（呼吸 · 助眠）。
///
/// 新-改进说明文档 §2–§4：
/// - 背景音改为潮水（长音轨，随机起点 + 循环 + 渐入渐出），不再播五首 BGM；
/// - 进入后先单独播 3 秒潮水，随后循环所选呼吸法的指引音乐，
///   指引开始后才进入长按/松开的时间轴判定；
/// - 圆圈只有**一个**：按住从 0 匀速扩大，到"吸气→憋气"交界处停住等松手，
///   松手后以同一速度匀速缩小直到消失（全程单一速度，无分段跳变）。
///
/// §7：删除助眠模式；新增"解放双手模式"（自动按时间轴呼吸，但不积攒修为）。
class TideBreathSession extends PracticeSession {
  late PracticeContext _ctx;

  /// 进入后先单独播 3 秒潮水（§2.3）。
  static const int _introUs = 3000000;

  /// 单局总时长 5 分钟（§3.2）。
  static const int _totalUs = 5 * 60 * 1000000;

  /// 圆圈扩到最大的时长 = 吸气时长（三种呼吸法都是 4 秒，§4.2）。
  static const int _growUs = 4000000;

  static const double _tideGain = 0.35;
  static const double _guideGain = 0.45;

  List<BreathSegment> _segments = kBreathMethods[0];
  int _segIndex = 0;

  /// 呼吸时间轴起点 = 指引音乐开始播放的时刻（= 开始 + 3 秒）。
  int _begunUs = 0;
  bool _breathing = false;

  // 输入状态。
  bool _pressed = false;

  // 同步统计：与相位期望吻合的累计时长。
  int _matchedUs = 0;
  int? _lastMatchCheckUs;
  bool _chimedThisPhase = false;
  final List<int> _phaseBoundariesUs = [];
  final List<double> _phaseSyncRates = [];

  bool _finished = false;
  bool _fadingOut = false;

  int _breathMethod = 0;

  /// 解放双手模式：自动完成呼吸，但不积攒修为（§7.2）。
  bool get _handsFree => _ctx.boolParam('handsFree');

  @override
  List<String> get startChoices => kBreathMethodLabels;

  /// §6：开始界面点击呼吸法后展开的节奏与难度。
  @override
  List<StartChoiceDetail> get startChoiceDetails => [
    for (final d in kBreathMethodDetails)
      StartChoiceDetail(rhythm: d.rhythm, note: d.note),
  ];

  @override
  int get startChoice => _breathMethod;

  @override
  set startChoice(int index) => _breathMethod = index.clamp(0, 2);

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'tide_breath',
    // §2/§13：音频由会话自理（潮水 + 呼吸指引），不提供 BGM 选择。
    allowsBgmChoice: false,
    ambience: AmbiencePolicy.sessionOwned,
    name: '听潮',
    subtitle: '潮涨时吸气，潮落时呼气',
    tags: [TrainingTag.breath, TrainingTag.sleep],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(minutes: 5),
    meritBase: 10,
    iconKey: 'tide_breath',
    allowManualEnd: true,
    usesAmbientLoop: false,
    rulesText: '潮涨渐强时，按住屏幕吸气；潮落渐弱时，松开屏幕呼气。憋气段保持按住。\n跟随音乐的引导，与潮水一同呼吸。',
    introTags: '呼吸·潮水·5分钟',
    intro: '潮涌，潮落，这是自然的呼吸。跟随音乐的引导，与潮水一同呼吸，如此重复五分钟，不必睁眼。',
  );

  /// 指引音乐 key（下标与 kBreathMethods 对齐）。
  String get _guideKey => SoundCatalog.breathGuideKeys[
      _breathMethod.clamp(0, SoundCatalog.breathGuideKeys.length - 1)
  ];

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
  }

  bool get _shouldPress => _breathing && _segments[_segIndex].pressExpected;

  /// 圆圈此时是否处于"扩大"阶段（§4.2）。
  ///
  /// 手动模式看用户的按住；解放双手模式由时间轴自己决定。
  bool get _growActive =>
      _breathing && (_handsFree ? _shouldPress : _pressed);

  /// 圆圈半径变化速度：最大半径 / 吸气时长。扩大与缩小共用这一个参数，
  /// 保证加减速完全一致、平滑连续（§4.2(5)）。
  static const double circleSpeed = _BreathCircleOverlay.maxRadius /
      (_growUs / 1000000);

  Timer? _rampTimer;
  Timer? _matchTimer;

  @override
  void start() {
    _segments = kBreathMethods[_breathMethod.clamp(0, kBreathMethods.length - 1)];
    _segIndex = 0;
    final now = _ctx.scheduler.nowUs();
    // 引子结束 = **发起**指引播放的时刻；判定起点不在这里定，
    // 而要等起播真正返回（见 _beginBreathing）。
    _begunUs = now + _introUs;
    _breathing = false;
    _lastMatchCheckUs = now;

    // 潮水背景：随机起点 + 循环（§14.4），音量从 0 渐入（§14.5）。
    _ctx.sounds.startLoop(
      SoundCatalog.ambTideKey,
      gain: 0,
      startAt: _randomStart(),
    );
    _tideLevel = 0;
    // 3 秒后进入呼吸时间轴并起播指引音乐。
    _ctx.scheduler.scheduleCallback(_begunUs, _beginBreathing);
    // 5 分钟到点自动收口（§3.2）。
    _ctx.scheduler.scheduleCallback(_totalUs, () {
      if (!_finished) _ctx.requestFinish(FinishReason.completed);
    });

    _rampTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _rampGains(),
    );
    _matchTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollMatch(),
    );
  }

  double _tideLevel = 0;
  double _guideLevel = 0;

  final Random _rng = Random();

  /// 潮水总长 611 秒：随机起点（§14.4），留出余量避免开场即接近末尾。
  Duration _randomStart() => Duration(seconds: _rng.nextInt(480));

  /// 引子结束：**先发起指引播放并等它真的开始**，再从那一点起算判定。
  ///
  /// #2（复审）：不能把"发起播放"和"开始判定"放在同一时刻——播放随后
  /// 还要经历加载与输出延迟，判定会一直领先声音（整体把回调整体延后
  /// 并不能补偿这部分）。这里 await 起播，并把判定起点定在
  /// "起播返回 + 输出延迟"，两块延迟都被算进去。
  Future<void> _beginBreathing() async {
    if (_finished) return;
    // 指引音乐在潮水之上开始循环（§2.3(2)）；await 覆盖异步加载。
    await _ctx.sounds.startLoop(_guideKey, gain: 0, startAt: Duration.zero);
    if (_finished) return;
    final startUs = _ctx.scheduler.nowUs() + _ctx.clock.outputLatencyUs;
    _begunUs = startUs;
    _breathing = true;
    // #4：前三秒是"先单独播潮水"，不参与同步统计，也不能提前响风铃。
    _matchedUs = 0;
    _lastMatchCheckUs = startUs;
    _chimedThisPhase = false;
    _segIndex = 0;
    _phaseEndUs = startUs + _segments[_segIndex].lengthUs;
    _schedulePhaseEnd();
    notifyVisualChanged();
  }

  /// 淡入/淡出（§14.5）：潮水起手渐入，指引在 3 秒后渐入，收口时一并渐出。
  void _rampGains() {
    if (!_ctx.scheduler.isRunning) return;
    const step = 0.12 / 1.5; // 约 1.5 秒渐入
    if (_fadingOut) {
      _tideLevel = (_tideLevel - 0.12 / 2.0).clamp(0.0, 1.0);
      _guideLevel = (_guideLevel - 0.12 / 2.0).clamp(0.0, 1.0);
    } else {
      _tideLevel = (_tideLevel + step).clamp(0.0, 1.0);
      if (_breathing) _guideLevel = (_guideLevel + step).clamp(0.0, 1.0);
    }
    _ctx.sounds.setLoopGain(SoundCatalog.ambTideKey, _tideGain * _tideLevel);
    if (_breathing) {
      _ctx.sounds.setLoopGain(_guideKey, _guideGain * _guideLevel);
    }
  }

  /// 本段在会话时间轴上的绝对结束时刻（自 [_begunUs] 累加）。
  ///
  /// #1：不用 nowUs() + len 逐段排期——那样每段的回调延迟都会累积，
  /// 一段一段把判定节奏推后，整局下来与音轨明显错位。
  int _phaseEndUs = 0;

  void _schedulePhaseEnd() {
    _ctx.scheduler.scheduleCallback(_phaseEndUs, _advancePhase);
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
    // 下一段截止 = 本段截止 + 下一段时长，始终锚在时间轴上。
    _phaseEndUs += _segments[_segIndex].lengthUs;
    notifyVisualChanged();
    _schedulePhaseEnd();
  }

  /// 只有进入正式呼吸后才谈得上吻合（#4：开场三秒不计入）。
  bool get _phaseMatchesInput =>
      _breathing && (_handsFree ? true : _pressed == _shouldPress);

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    switch (e.phase) {
      case PointerPhase.down:
        _pressed = true;
      case PointerPhase.move:
        break; // 按住挪动不改变按住状态。
      case PointerPhase.up:
      case PointerPhase.cancel:
        _pressed = false;
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
    // #4：正式呼吸开始前不累计吻合时长（否则首段吸气白拿同步率）。
    if (!_breathing) return;
    final now = _ctx.scheduler.nowUs();
    if (_phaseMatchesInput) {
      final delta = now - (_lastMatchCheckUs ?? now);
      _matchedUs += delta;
      // 吻合持续 ≥300ms 且本相位还没响过风铃 → 叠入极轻风铃。
      if (!_chimedThisPhase && _matchedUs >= 300000 && (_pressed || _handsFree)) {
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

    // 收口：两条音轨一并渐弱（§14.5）。
    final result = _buildResult(r);
    _fadingOut = true;
    for (var i = 0; i < 8; i++) {
      _tideLevel = (_tideLevel - 0.125).clamp(0.0, 1.0);
      _guideLevel = (_guideLevel - 0.125).clamp(0.0, 1.0);
      await _ctx.sounds.setLoopGain(
        SoundCatalog.ambTideKey,
        _tideGain * _tideLevel,
      );
      if (_breathing) {
        await _ctx.sounds.setLoopGain(_guideKey, _guideGain * _guideLevel);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _ctx.sounds.stopLoop(SoundCatalog.ambTideKey);
    if (_breathing) await _ctx.sounds.stopLoop(_guideKey);
    return result;
  }

  PracticeResult _buildResult(FinishReason r) {
    final now = _ctx.scheduler.nowUs();
    final elapsedUs = now.clamp(1, 1 << 40);
    final avgSync = _phaseSyncRates.isEmpty
        ? 0.0
        : _phaseSyncRates.reduce((a, b) => a + b) / _phaseSyncRates.length;
    final quality = avgSync.clamp(0.0, 1.0);
    final minutes = elapsedUs / 60000000;
    // 解放双手模式：专心呼吸但无法积攒修为（§7.2）。
    final merit = _handsFree ? 0 : (minutes * 2 * quality).round();

    return PracticeResult(
      effectiveDuration: Duration(microseconds: elapsedUs),
      quality: quality,
      merit: merit,
      completed: r == FinishReason.completed || r == FinishReason.userEnded,
      metrics: {
        'avgSync': avgSync,
        'phaseCount': _phaseBoundariesUs.length,
        'phaseSyncRates': _phaseSyncRates
            .map((e) => (e * 100).round())
            .toList(),
        'handsFree': _handsFree,
        'breathMethod': _breathMethod,
      },
    );
  }

  String get _phaseLabel {
    if (!_breathing) return '潮 水 · 静';
    final envelope = _segments[_segIndex].envelope;
    return switch (envelope) {
      BreathEnvelope.up => '潮 涨 · 吸',
      BreathEnvelope.holdHigh || BreathEnvelope.holdLow => '憋 气 · 按',
      BreathEnvelope.down => '潮 落 · 呼',
    };
  }

  String get _phaseHint {
    if (!_breathing) return '听潮水 · 稍候';
    if (_handsFree) return '解放双手 · 跟随圆圈';
    return _segments[_segIndex].pressExpected ? '按住屏幕' : '松开屏幕';
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
            active: _growActive,
            count: _phaseBoundariesUs.length,
            accent: _phaseMatchesInput ? 1 : 0.25,
          ),
        ),
        // 单圆圈动画（§4）：按住从 0 匀速扩大 → 交界处停住 → 松手等速缩小。
        Positioned.fill(
          child: IgnorePointer(
            child: _BreathCircleOverlay(
              growActive: _growActive,
              matched: _phaseMatchesInput,
            ),
          ),
        ),
      ],
    );
  }

  @visibleForTesting
  int get debugPhaseCount => _phaseBoundariesUs.length;

  /// 圆圈此刻是否在放大（§4.2/§7.2 的观察点）。
  @visibleForTesting
  bool get debugGrowActive => _growActive;

  /// 呼吸时间轴起点（#1 排期锚点）与下一段截止时刻。
  @visibleForTesting
  int get debugBegunUs => _begunUs;
  @visibleForTesting
  int get debugPhaseEndUs => _phaseEndUs;

  /// 本相位已累计的吻合时长（#4：开场三秒必须为 0）。
  @visibleForTesting
  int get debugMatchedUs => _matchedUs;
  @visibleForTesting
  bool get debugBreathing => _breathing;
  @visibleForTesting
  int get debugSegIndex => _segIndex;

  @visibleForTesting
  PracticeResult debugResultForTest() =>
      _buildResult(FinishReason.userEnded);

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
    final handsFree = r.metrics['handsFree'] == true;
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
          handsFree ? '解放双手模式 · 本局不计修为' : '平均同步率 $sync %',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 14),
        ),
      ],
    );
  }
}

/// 单圆圈动画（新-改进说明文档 §4）。
///
/// 只有一个圆圈：半径从 0 起，[growActive] 时以固定速度匀速扩大并在最大
/// 半径处停住；否则以**同一速度**匀速缩小到 0（消失）。扩大与缩小共用
/// [TideBreathSession.circleSpeed]，因此不会出现分段跳变。
class _BreathCircleOverlay extends StatefulWidget {
  const _BreathCircleOverlay({required this.growActive, required this.matched});

  final bool growActive;
  final bool matched;

  static const double maxRadius = 170;

  @override
  State<_BreathCircleOverlay> createState() => _BreathCircleOverlayState();
}

class _BreathCircleOverlayState extends State<_BreathCircleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frame;
  double _radius = 0;
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
    if (widget.growActive) {
      _radius = (_radius + TideBreathSession.circleSpeed * dt)
          .clamp(0.0, _BreathCircleOverlay.maxRadius);
    } else {
      _radius = (_radius - TideBreathSession.circleSpeed * dt).clamp(0.0, _BreathCircleOverlay.maxRadius);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return CustomPaint(
        painter: _BreathCirclePainter(
          radius: widget.growActive ? _BreathCircleOverlay.maxRadius : 0,
          matched: widget.matched,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _frame,
      builder: (context, _) {
        _tick(_frame.lastElapsedDuration ?? _last);
        return CustomPaint(
          painter: _BreathCirclePainter(
            radius: _radius,
            matched: widget.matched,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }
}

class _BreathCirclePainter extends CustomPainter {
  _BreathCirclePainter({required this.radius, required this.matched});

  final double radius;
  final bool matched;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0.5) return;
    // 只保留一个圆圈（§4.1：删除原有两个同心圆环）。
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = matched ? 2.6 : 1.8
        ..color = matched ? const Color(0x88D8B36A) : const Color(0x55E8DFC8),
    );
  }

  @override
  bool shouldRepaint(covariant _BreathCirclePainter old) => true;
}

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
    usesAmbientLoop: true,
    // §14.3：叠加随机一种鸟叫/虫鸣（单局固定）。
    ambience: AmbiencePolicy.birdsOrInsects,
    rulesText: '只有雨，没有钟。雨滴大约三到十秒落下一滴。\n'
        '全程不用动手，只管在心里默数。\n三分钟后雨停，会问你这个数。',
    introTags: '专注·白噪声',
    intro: '天大约刚刚放晴。坐在屋檐下，还可以静听雨滴落下的滴答声。'
        '什么都不要做，在心里默数有多少滴雨滴落下吧。三分钟后，告诉师傅你的答案。',
  );

  late String _ambientKey = SoundCatalog.forestLoopKey;
  double _ambientVolume = 0.35;

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    // 环境循环音（默认鸟鸣虫鸣）可被所选背景音乐对应替换（首页"乐"设置）。
    _ambientKey = ctx.stringParam('ambientKey', SoundCatalog.forestLoopKey);
    _ambientVolume = ctx.doubleParam('ambientVolume', 0.35);
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

  int _dropPulse = 0; // 雨滴视觉脉冲：每落一滴 +1（改进列表：雨滴渐显渐隐动画）

  @override
  void start() {
    // 背景音：默认鸟鸣虫鸣用约 -24dB 的环境音量；被所选 BGM 曲目替换时
    // 就是用户在听的背景音乐，按其设置的音量播（复审 R1）。
    _ctx.sounds.startLoop(
      _ambientKey,
      gain: _ambientKey == SoundCatalog.forestLoopKey
          ? 0.25 * _ambientVolume
          : _ambientVolume,
    );
    const dropSounds = ['rain_drop_1', 'rain_drop_2', 'rain_drop_3'];
    for (final t in _rainTimesUs) {
      // 每滴雨从三段音色里随机选一个（新改进意见）。
      _ctx.scheduler.scheduleSound(
        t,
        dropSounds[_rng.nextInt(dropSounds.length)],
        gain: 0.9,
      );
      // 同一刻触发视觉脉冲（雨滴渐显至半透明再渐隐）。
      _ctx.scheduler.scheduleCallback(t, () {
        _dropPulse++;
        notifyVisualChanged();
      });
    }
    _ctx.scheduler.scheduleCallback(_lengthUs, _enterReportPhase);
  }

  /// 3 分钟到：雨停，转入报数阶段（不再计时收口，等用户报数）。
  void _enterReportPhase() {
    if (_finished || _askingReport) return;
    _askingReport = true;
    // 声音语言：磬一声 = 这一局听完了，请睁眼报数。
    // （Bug 描述 #3：极轻的磬已删除，报数页本身就是提示。）
    unawaited(_ctx.sounds.stopLoop(_ambientKey));
    // 兜底：报数页若长时间无人确认（用户走开），自动收口不发修为。
    // scheduleCallback 用会话时间轴绝对时刻：听雨 3 分钟 + 报数等待 3 分钟。
    _ctx.scheduler.scheduleCallback(_lengthUs + _askTimeoutUs, () {
      if (!_finished) _ctx.requestFinish(FinishReason.userEnded);
    });
    notifyVisualChanged();
  }

  /// 报数页确认回调（UI 层调用）。防重复提交：只接受第一次。
  void submitReport(int count) {
    if (_finished || !_askingReport || _reportedCount != null) return;
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
    try {
      await _ctx.sounds.stopLoop(_ambientKey);
    } on Exception {
      // 已停止则忽略。
    }
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
    return Stack(
      children: [
        Positioned.fill(
          child: PracticeScene(
            kind: PracticeSceneKind.countRain,
            title: '数 雨',
            subtitle: '在心里默数 · 不用动手',
            active: true,
            progress: (_ctx.scheduler.nowUs() / _lengthUs).clamp(0.0, 1.0),
            count: 0,
            accent: 0,
          ),
        ),
        // 雨滴落下动画：屏幕中间渐显至半透明再渐隐（改进列表）。
        Positioned.fill(
          child: IgnorePointer(child: _RainDropFlash(pulse: _dropPulse)),
        ),
      ],
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final report = m['userReport'] as int?;
    final actual = m['actualRain'] as int? ?? 0;
    final error = m['error'] as int? ?? 0;
    final verdict = !r.completed && report == null
        ? '雨还没听完，先回去了。'
        : error == 0
        ? '分毫不差。'
        : error <= 3
        ? '失之毫厘。'
        : '心猿意马。';
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
        if (report != null && error > 0) ...[
          const SizedBox(height: 10),
          Text(
            '真正落下了 $actual 滴雨。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// 报数页：听完之后才出现的"你数到了几滴？"询问（待对齐清单 #8）。
/// 加减支持长按连发（改进列表）：点按 ±1，按住不放快速连加/连减。
class _ReportCountView extends StatefulWidget {
  const _ReportCountView({required this.onSubmit});

  final void Function(int) onSubmit;

  @override
  State<_ReportCountView> createState() => _ReportCountViewState();
}

class _ReportCountViewState extends State<_ReportCountView> {
  int _count = 0;
  bool _submitted = false;

  void _submit() {
    if (_submitted) return;
    setState(() => _submitted = true);
    widget.onSubmit(_count);
  }

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
              _RepeatButton(
                icon: '−',
                onTick: () => setState(() => _count = max(0, _count - 1)),
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
              _RepeatButton(
                icon: '+',
                onTick: () => setState(() => _count = min(999, _count + 1)),
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
            onPressed: _submitted ? null : _submit,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE8DFC8),
              side: const BorderSide(color: Color(0x55E8DFC8)),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            ),
            child: Text(_submitted ? '已报数' : '就这个数'),
          ),
        ],
      ),
    );
  }
}

/// 点按一次 ±1；按住不放先延迟 400ms，然后每 60ms 连发（长按连发）。
class _RepeatButton extends StatefulWidget {
  const _RepeatButton({required this.icon, required this.onTick});

  final String icon;
  final VoidCallback onTick;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _delay;
  Timer? _repeat;

  void _start() {
    widget.onTick();
    _delay = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 60), (_) {
        widget.onTick();
      });
    });
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x33E8DFC8)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          widget.icon,
          style: const TextStyle(fontSize: 24, color: Color(0xFFE8DFC8)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

/// 雨滴落下动画：每次脉冲触发"渐显至半透明 → 渐隐"。
class _RainDropFlash extends StatefulWidget {
  const _RainDropFlash({required this.pulse});

  final int pulse;

  @override
  State<_RainDropFlash> createState() => _RainDropFlashState();
}

class _RainDropFlashState extends State<_RainDropFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didUpdateWidget(covariant _RainDropFlash old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!_controller.isAnimating) return const SizedBox.shrink();
        final t = _controller.value;
        // 前 40% 渐显到 0.5 透明度，之后渐隐。
        final opacity = t < 0.4 ? (t / 0.4) * 0.5 : 0.5 * (1 - (t - 0.4) / 0.6);
        // 雨滴出现涟漪（Bug 描述 #6）：雨滴图层的下方，一个半透明圆形
        // 缓缓扩大、边扩大边虚化，最后完全消失。
        final rippleT = (t / 0.8).clamp(0.0, 1.0);
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (rippleT < 1)
                CustomPaint(
                  size: const Size(220, 220),
                  painter: _RipplePainter(progress: rippleT),
                ),
              Opacity(
                opacity: opacity,
                child: Image.asset(
                  'assets/images/raindrop.png',
                  width: 64,
                  height: 64,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// 雨滴出现涟漪：半径随时间扩大，透明度与描边同步衰减（边扩大边虚化）。
class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final radius = 14 + (maxR - 14) * Curves.easeOut.transform(progress);
    final alpha = (1 - progress) * 0.4;
    // 柔和的水痕：一圈渐淡的填充 + 一圈更淡的描边。
    canvas.drawCircle(
      c,
      radius,
      Paint()..color = const Color(0xFF6FA8B3).withValues(alpha: alpha * 0.35),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * (1 - progress)
        ..color = const Color(0xFF6FA8B3).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 听潮的三档呼吸节奏标签（修行列表选择用）。
const List<String> kBreathTierLabels = ['入门 4-6', '标准 4-7', '深度 4-8'];

/// 听潮（呼吸 · 助眠）。
///
/// 潮汐节奏引导呼吸：涨潮音渐强 4 秒（吸气时按住屏幕），落潮音渐弱
/// （6/7/8 秒，呼气时松开）。相位吻合时潮声里叠入一层极轻的风铃。
/// 三档节奏：入门 4-6 / 标准 4-7 / 深度 4-8。
/// 助眠模式：结束不弹结算页（note='sleep_mode'，宿主处理次日补发）。
///
/// 修为公式为拟定值（设计方案待对齐 #5）：分钟数 × 2 × quality。
class TideBreathSession extends PracticeSession {
  static const int _inhaleUs = 4000000;

  late PracticeContext _ctx;

  int _exhaleUs = 6000000;
  bool _inhaling = true;
  int _phaseStartUs = 0;

  // 输入状态。
  bool _pressed = false;
  int? _pressStartUs;

  // 同步统计：与潮汐相位吻合的累计时长。
  int _matchedUs = 0;
  int? _lastMatchCheckUs;
  bool _chimedThisPhase = false;
  final List<int> _phaseBoundariesUs = [];
  final List<double> _phaseSyncRates = [];

  bool _finished = false;

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
    rulesText: '潮涨渐强时，按住屏幕吸气（4 秒）；\n潮落渐弱时，松开屏幕呼气。\n咬合的瞬间，会有一层风铃。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    final tier = ctx.intParam('tier', 0).clamp(0, 2);
    _exhaleUs = (6000000 + tier * 1000000);
  }

  @override
  void start() {
    _ctx.sounds.startLoop(SoundCatalog.tideLoopKey, gain: 0.05);
    _phaseStartUs = _ctx.scheduler.nowUs();
    _lastMatchCheckUs = _phaseStartUs;
    _scheduleNextPhase();
    // 音量包络：涨潮渐强 / 落潮渐弱（缓慢变化，走普通定时器即可）。
    _volumeTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _rampVolume(),
    );
    // 相位吻合累计与风铃反馈：200ms 轮询，精度足够。
    _matchTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollMatch(),
    );
  }

  Timer? _volumeTimer;
  Timer? _matchTimer;

  void _rampVolume() {
    if (!_ctx.scheduler.isRunning) return;
    final t = _ctx.scheduler.nowUs() - _phaseStartUs;
    final len = _inhaling ? _inhaleUs : _exhaleUs;
    final x = (t / len).clamp(0.0, 1.0);
    // 涨潮 0.05 → 0.5；落潮 0.5 → 0.05（用平滑的 sin 曲线）。
    final v = 0.05 + (0.5 - 0.05) * (_inhaling ? x : 1 - x);
    _ctx.sounds.setLoopGain(SoundCatalog.tideLoopKey, v);
  }

  void _scheduleNextPhase() {
    // 本方法总在相位切换的当下调用，所以下一个边界就是 now + len。
    final len = _inhaling ? _inhaleUs : _exhaleUs;
    _ctx.scheduler.scheduleCallback(_ctx.scheduler.nowUs() + len, _flipPhase);
  }

  void _flipPhase() {
    if (_finished) return;
    final now = _ctx.scheduler.nowUs();
    _phaseBoundariesUs.add(now);

    // 本相位同步率快照。
    final len = _inhaling ? _inhaleUs : _exhaleUs;
    if (len > 0 && _phaseSyncRates.length < 200) {
      _phaseSyncRates.add((_matchedUs / len).clamp(0.0, 1.0));
    }
    _matchedUs = 0;

    _inhaling = !_inhaling;
    _chimedThisPhase = false;
    _phaseStartUs = now;
    notifyVisualChanged();
    _scheduleNextPhase();
  }

  bool get _phaseMatchesInput => _inhaling == _pressed;

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
      'inhaling': _inhaling,
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
    _volumeTimer?.cancel();
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
      },
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    return PracticeScene(
      kind: PracticeSceneKind.tideBreath,
      title: _inhaling ? '潮 涨 · 吸' : '潮 落 · 呼',
      subtitle: _inhaling ? '按住屏幕 · 缓缓吸气' : '松开屏幕 · 慢慢呼气',
      active: _pressed,
      count: _phaseBoundariesUs.length,
      accent: _phaseMatchesInput ? 1 : 0.25,
    );
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    _matchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final sync = ((r.metrics['avgSync'] as num? ?? 0) * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          r.quality >= 0.7 ? '呼吸与潮汐咬合得很好。' : '潮水不催人，下次慢慢来。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 16),
        const Text(
          '各相位同步率（%）',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0x66E8DFC8), fontSize: 12),
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

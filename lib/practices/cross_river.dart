import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 过河（专注 · 节奏复现）——编号音色版（Bug 描述 #8）。
///
/// 每轮：系统播"引导音 a → 间隔 T → b"，用户随后按下屏幕（响起跟随音 c）
/// 并在自认为 T 之后松开（响起跟随音 d）。按下→松手的间隔复现引导的 T。
/// 6 轮一循环的固定序列（1..12 再折返），见 [_rounds]。
/// 判定：以两段音"开始播放的一刻"为锚（引导按调度时刻、跟随按按下/
/// 松手时刻——都是发声起点而非播完时刻）；因音频存在播放延迟，
/// 窗口在 max(T×15%, 180ms) 基础上放宽 [_latencyGraceUs]。
/// 窗口 1.5 倍内 = 踩滑（不死，难度不递进）；超出 = 失败结束。
/// 修为：每轮得分 = 100 × (1 − 偏移率)，结束后修为 = 总分 / 100。
class CrossRiverSession extends PracticeSession {
  static const int _minTUs = 600000;
  static const int _maxTUs = 2000000;
  static const int _guideLeadUs = 500000; // 引导音之前留白
  static const int _missGuardUs = 6000000; // 引导结束仍不起手 → 失败
  static const int _latencyGraceUs = 250000; // 音频播放延迟补偿（Bug 描述 #8）

  /// 6 轮一循环的编号音序列：(引导a, 引导b, 跟随c, 跟随d)。
  /// 1→12 递增三轮，12 处折返递减三轮，第 6 轮后回到第 1 轮。
  static const List<(int, int, int, int)> _rounds = [
    (1, 2, 3, 4),
    (5, 6, 7, 8),
    (9, 10, 11, 12),
    (12, 11, 10, 9),
    (8, 7, 6, 5),
    (4, 3, 2, 1),
  ];

  late PracticeContext _ctx;
  final Random _rng;

  CrossRiverSession({Random? rng}) : _rng = rng ?? Random();

  int _jumpNo = 0; // 已上石阶数（成功+踩滑）
  int _difficultySteps = 0; // 仅精确踏稳的轮次推进难度（踩滑不递进）。
  int _lastExpandedAt = 0;
  int _loUs = _minTUs;
  int _hiUs = _maxTUs;

  (int, int, int, int) _roundSounds = _rounds.first;
  int _tUs = 0; // 本轮引导间隔（跟随需复现的目标）
  int _guideEndUs = 0; // 引导音 b 的调度时刻（此刻起接受起手）
  int _jumpId = 0; // 守门回调按轮次 id 失效

  // 本轮输入。
  bool _pressed = false;
  int? _pressSessionUs; // 按下时刻 = 跟随音 c 的发声起点
  final List<int> _releaseDeviationsUs = [];
  double _scoreTotal = 0; // 每轮 100×(1−偏移率) 累计

  bool _finished = false;
  String _hudText = '听引导音 · 复现间隔';

  // ---- 测试钩子 ----
  @visibleForTesting
  int get jumpNo => _jumpNo;
  @visibleForTesting
  int get tUs => _tUs;
  @visibleForTesting
  int get guideEndUs => _guideEndUs;
  @visibleForTesting
  (int, int, int, int) get roundSounds => _roundSounds;
  @visibleForTesting
  bool get finished => _finished;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'cross_river',
    name: '过河',
    subtitle: '在心里复现那个间隔',
    tags: [TrainingTag.focus, TrainingTag.rhythm],
    eyeMode: EyeMode.openThenClosed,
    typicalLength: Duration(minutes: 3),
    meritBase: 20,
    iconKey: 'cross_river',
    rulesText:
        '师傅先敲出一段引导音，间隔是他的一步。\n随后由你跟随：按下时响起第一个音，'
        '自认为到了间隔就松开，第二个音随之响起。\n12 个音色六轮一循环，周而复始。\n'
        '踩滑不会落水，但难度不再递进；差得远，就掉进河里了。',
    introTags: '趣味·节奏',
    intro: '闭上眼也能玩的跳一跳。跟随师傅的脚步声，在河上的木桩间跳跃吧。想想那冰冷的河水，果然还是得认真起来了。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
  }

  @override
  void start() {
    _nextJump();
  }

  void _nextJump() {
    _jumpNo++;
    _jumpId++;
    // 每 5 次踏稳：T 范围扩大。踩滑仍能继续，但不应让下一轮更难。
    if (_difficultySteps > 0 &&
        _difficultySteps % 5 == 0 &&
        _lastExpandedAt != _difficultySteps) {
      _loUs = (_loUs * 0.85).round();
      _hiUs = min((_hiUs * 1.15).round(), 4000000);
      _lastExpandedAt = _difficultySteps;
    }
    _roundSounds = _rounds[(_jumpNo - 1) % _rounds.length];
    _tUs = _loUs + _rng.nextInt(_hiUs - _loUs);

    final (guideA, guideB, _, _) = _roundSounds;
    final t0 = _ctx.scheduler.nowUs() + _guideLeadUs;
    _ctx.scheduler.scheduleSound(t0, SoundCatalog.riverSoundKey(guideA), gain: 0.9);
    _ctx.scheduler.scheduleSound(
      t0 + _tUs,
      SoundCatalog.riverSoundKey(guideB),
      gain: 0.9,
    );

    _guideEndUs = t0 + _tUs;
    _pressed = false;

    _hudText = '第 $_jumpNo 步 · 第 ${(_jumpNo - 1) % _rounds.length + 1} 轮';
    notifyVisualChanged();
    // 守门：本轮到点仍未完成（一直不起手，或起手后迟迟不松手）判失败。
    // 完成本轮会推进 _jumpId，陈旧守门自动失效。
    final guard = _guideEndUs + _missGuardUs;
    final id = _jumpId;
    _ctx.scheduler.scheduleCallback(guard, () {
      if (id == _jumpId) _fail();
    });
  }

  /// 判定窗口：基础窗口 + 音频播放延迟补偿（Bug 描述 #8：放宽，不过轻易判负）。
  int _windowFor(int tUs) =>
      max((tUs * 0.15).round(), 180000) + _latencyGraceUs;

  void _judgeRelease(int releaseUs) {
    // 判定锚 = 两段跟随音"开始播放的一刻"：c 在按下瞬间起播，d 在松手
    // 瞬间起播（Bug 描述 #8）。按下与松手共享同一份设备输出延迟，
    // 相减后互相抵消，偏差即 |复现间隔 − 引导间隔|。
    final dev = releaseUs - (_pressSessionUs ?? releaseUs) - _tUs;
    _releaseDeviationsUs.add(dev);
    // 每轮得分 = 100 × (1 − 偏移率)，偏移率上限 1。
    final devRate = (dev.abs() / _tUs).clamp(0.0, 1.0);
    _scoreTotal += 100 * (1 - devRate);
    final w = _windowFor(_tUs);

    if (dev.abs() <= w) {
      _onStepped(slip: false);
    } else if (dev.abs() <= w * 1.5) {
      _onStepped(slip: true);
    } else {
      _fail();
    }
  }

  void _onStepped({required bool slip}) {
    if (!slip) _difficultySteps++;
    _nextJump();
  }

  void _fail() {
    if (_finished) return;
    _hudText = '一念偏了 · 落入水中';
    notifyVisualChanged();
    _ctx.requestFinish(FinishReason.completed);
  }

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    switch (e.phase) {
      case PointerPhase.down:
        // 引导未播完不起手（起手过早只留痕，不触发跟随音）。
        if (_ctx.scheduler.nowUs() < _guideEndUs) {
          _ctx.recorder.log('input:earlyPress', {'at': e.sessionUs});
          return;
        }
        _pressed = true;
        _pressSessionUs = e.sessionUs;
        notifyVisualChanged();
        // 跟随音 c：按下瞬间起播（发声起点即计时的一个锚点）。
        _ctx.sounds.play(
          SoundCatalog.riverSoundKey(_roundSounds.$3),
          gain: 0.9,
        );
        _ctx.recorder.log('input:press', {'at': e.sessionUs});
      case PointerPhase.move:
        break; // 按住挪动不参与判定。
      case PointerPhase.up:
      case PointerPhase.cancel:
        if (_pressed) {
          _pressed = false;
          notifyVisualChanged();
          _ctx.recorder.log('input:release', {'at': e.sessionUs});
          // 跟随音 d：松手瞬间起播，判定同时收口。
          _ctx.sounds.play(
            SoundCatalog.riverSoundKey(_roundSounds.$4),
            gain: 0.9,
          );
          _judgeRelease(e.sessionUs);
        }
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
    final jumps = max(_jumpNo - 1, 0); // 最后一轮落水不计
    // 修为 = 总分 / 100（四舍五入，下限 0）。
    final merit = max(_scoreTotal / 100, 0).round();
    final avgDevUs = _releaseDeviationsUs.isEmpty
        ? 0
        : _releaseDeviationsUs.fold<int>(0, (a, b) => a + b.abs()) ~/
              _releaseDeviationsUs.length;
    return PracticeResult(
      effectiveDuration: Duration(
        microseconds: _ctx.scheduler.nowUs().clamp(0, 1 << 30),
      ),
      quality: (jumps / 20).clamp(0.0, 1.0),
      merit: merit,
      completed: true,
      metrics: {
        'jumps': jumps,
        'score': _scoreTotal.round(),
        'avgDeviationUs': avgDevUs,
        'deviationsMs': _releaseDeviationsUs.map((e) => e ~/ 1000).toList(),
      },
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    return PracticeScene(
      kind: PracticeSceneKind.crossRiver,
      title: '过 河',
      subtitle: _pressed ? '心中复现 · 到时松手' : _hudText,
      active: _pressed,
      count: _jumpNo,
      accent: _pressed ? 1 : 0.45,
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final jumps = r.metrics['jumps'] as int? ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          jumps == 0 ? '河水很凉。' : '踩着 $jumps 块石阶过了河。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 20),
        // 走过的石阶。
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < min(jumps, 60); i++)
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33D8B36A),
                  border: Border.all(color: const Color(0x66D8B36A)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '平均偏差 ${(r.metrics['avgDeviationUs'] as num? ?? 0) / 1000} ms',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '过河总分 ${r.metrics['score'] ?? 0}（满分 = 步数 × 100）',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13),
        ),
      ],
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 过河（专注 · 节奏复现）。
///
/// 每一跳：先播"叮——咚"，间隔 T 随机取 0.6–2.0 秒；用户长按屏幕，
/// 在自认为 T 之后松开。起手口径：按下时刻不作硬判定（以"咚"为计时
/// 锚点），硬判定只有"松手时刻 − 咚时刻 ≈ T"。
/// 判定窗口 max(T×15%, 180ms)；窗口 1.5 倍内 = 踩滑（不死，难度不递进）；
/// 超出 = 失败结束。每 5 跳扩大 T 范围并引入"叮-咚-咚"变奏（复现第二段间隔）。
/// 修为（待对齐清单 #5）：每跳一次得分 = 100 × (1 − 偏移率)，偏移率 =
/// |松手偏差| / T；结束后修为 = 总分 / 100（四舍五入）。判定一律用音频
/// 时间戳，不用墙钟。
class CrossRiverSession extends PracticeSession {
  static const int _minTUs = 600000;
  static const int _maxTUs = 2000000;
  static const int _pressLeadUs = 500000; // 叮之前留白
  static const int _missGuardUs = 6000000; // 长按无松手 → 失败

  late PracticeContext _ctx;
  final Random _rng;

  CrossRiverSession({Random? rng}) : _rng = rng ?? Random();

  int _jumpNo = 0; // 已上石阶数（成功+踩滑）
  int _difficultySteps = 0; // 仅精确踏稳的石阶推进难度。
  int _lastExpandedAt = 0;
  int _loUs = _minTUs;
  int _hiUs = _maxTUs;
  bool _variation = false; // 本跳是否为 叮-咚-咚
  int _t1Us = 0;
  int _t2Us = 0;
  int _dongAnchorUs = 0; // 咚的调度时刻（会话时间轴）
  bool _awaitingSecondSegment = false;
  int _jumpId = 0; // 守门回调按跳跃 id 失效，防陈旧守门影响后续跳跃

  // 本跳输入轨迹。
  bool _pressed = false;
  final List<int> _releaseDeviationsUs = [];
  double _scoreTotal = 0; // 待对齐清单 #5：每跳 100×(1−偏移率) 累计

  bool _finished = false;
  String _hudText = '听 叮 咚 · 复 现 间 隔';

  // ---- 测试钩子 ----
  @visibleForTesting
  int get jumpNo => _jumpNo;
  @visibleForTesting
  int get t1Us => _t1Us;
  @visibleForTesting
  int get t2Us => _t2Us;
  @visibleForTesting
  int get dongAnchorUs => _dongAnchorUs;
  @visibleForTesting
  bool get variation => _variation;
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
        '每一步会响起"叮——咚"。用长按把这个间隔在心里复现出来：\n听到叮预备，咚响起时按下，自认为到了间隔就松开。\n'
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
    // 每 5 次踏稳：T 范围扩大。踩滑仍能继续，但不应让下一跳更难。
    if (_difficultySteps > 0 &&
        _difficultySteps % 5 == 0 &&
        _lastExpandedAt != _difficultySteps) {
      _loUs = (_loUs * 0.85).round();
      _hiUs = min((_hiUs * 1.15).round(), 4000000);
      _lastExpandedAt = _difficultySteps;
    }
    _variation = _difficultySteps >= 10 && _rng.nextBool();
    _t1Us = _loUs + _rng.nextInt(_hiUs - _loUs);
    _t2Us = _loUs + _rng.nextInt(_hiUs - _loUs);

    final t0 = _ctx.scheduler.nowUs() + _pressLeadUs;
    _ctx.scheduler.scheduleSound(t0, SoundCatalog.heDingKey, gain: 0.9);
    _ctx.scheduler.scheduleSound(t0 + _t1Us, SoundCatalog.heDongKey, gain: 0.9);
    if (_variation) {
      _ctx.scheduler.scheduleSound(
        t0 + _t1Us + _t2Us,
        SoundCatalog.heDongKey,
        gain: 0.8,
      );
    }

    // 咚的实际调度时刻为计时锚点（判定只对齐它）。
    _dongAnchorUs = t0 + _t1Us;
    _awaitingSecondSegment = false;
    _pressed = false;

    _hudText = '第 $_jumpNo 步${_variation ? ' · 叮-咚-咚' : ''}';
    notifyVisualChanged();
    // 守门：若本跳迟迟未完成，按失败收口（只对本跳生效）。
    final guard = t0 + _t1Us + (_variation ? _t2Us : 0) + _missGuardUs;
    final id = _jumpId;
    _ctx.scheduler.scheduleCallback(guard, () {
      if (id == _jumpId) _onMiss();
    });
  }

  void _onMiss() {
    if (_finished) return;
    // 按着不放（或变奏第二段迟迟不起手）超时：判为失败。
    if (_pressed || _awaitingSecondSegment) {
      _fail();
    }
  }

  int _windowFor(int segmentTUs) => max((segmentTUs * 0.15).round(), 180000);

  void _judgeRelease(int releaseUs) {
    final t = _awaitingSecondSegment ? _t2Us : _t1Us;
    final anchor = _awaitingSecondSegment
        ? _dongAnchorUs + _t1Us
        : _dongAnchorUs;
    final dev = releaseUs - anchor - t;
    _releaseDeviationsUs.add(dev);
    // 待对齐清单 #5：本跳得分 = 100 × (1 − 偏移率)，偏移率上限 1（落水那跳得 0 分起）。
    final devRate = (dev.abs() / t).clamp(0.0, 1.0);
    _scoreTotal += 100 * (1 - devRate);
    final w = _windowFor(t);

    if (dev.abs() <= w) {
      _onStepped(slip: false);
    } else if (dev.abs() <= w * 1.5) {
      _onStepped(slip: true);
    } else {
      _fail();
    }
  }

  void _onStepped({required bool slip}) {
    if (_variation && !_awaitingSecondSegment) {
      // 变奏第一段通过：等待第二段复现。
      _awaitingSecondSegment = true;
      _hudText = '第 $_jumpNo 步 · 还有第二段';
      notifyVisualChanged();
      return;
    }
    if (!slip) _difficultySteps++;
    _nextJump();
  }

  void _fail() {
    if (_finished) return;
    _hudText = '一念偏了 · 落入水中';
    notifyVisualChanged();
    _ctx.sounds.play(SoundCatalog.heDongKey, gain: 0.5);
    _ctx.requestFinish(FinishReason.completed);
  }

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    switch (e.phase) {
      case PointerPhase.down:
        _pressed = true;
        notifyVisualChanged();
        // 起手早晚不作硬判定，只计入曲线。
        _ctx.recorder.log('input:press', {
          'at': e.sessionUs,
          'leadMs': (e.sessionUs - _dongAnchorUs) ~/ 1000,
        });
      case PointerPhase.move:
        break; // 按住挪动不参与判定。
      case PointerPhase.up:
      case PointerPhase.cancel:
        if (_pressed) {
          _pressed = false;
          notifyVisualChanged();
          _ctx.recorder.log('input:release', {'at': e.sessionUs});
          // 等咚响过才判定（咚没响就松手 = 起手过早，计入曲线但不硬判）。
          if (e.sessionUs >= _dongAnchorUs) {
            _judgeRelease(e.sessionUs);
          } else {
            _releaseDeviationsUs.add(e.sessionUs - _dongAnchorUs - _t1Us);
            _fail();
          }
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
    final jumps = max(_jumpNo - 1, 0); // 最后一跳落水不计
    // 待对齐清单 #5：修为 = 总分 / 100（四舍五入，下限 0）。
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
      accent: _awaitingSecondSegment ? 1 : 0.45,
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

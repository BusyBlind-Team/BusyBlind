import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../widgets/practice_scene.dart';

/// 静坐（一分钟）——框架验收用例，同时是教程的 60 秒试玩。
///
/// 验收标准：新增这个修行没有改动宿主与其他任何部分；
/// 它只依赖 PracticeContext 注入的四件套。
class SitQuietSession extends PracticeSession {
  static const int _lengthUs = 60000000;

  late PracticeContext _ctx;
  bool _started = false;
  bool _finished = false;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'sit_quiet',
    name: '静坐',
    subtitle: '一分钟，什么都不做',
    tags: [TrainingTag.focus],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(seconds: 60),
    meritBase: 1,
    iconKey: 'sit_quiet',
    rulesText: '磬响后闭眼静坐。什么都不用做，一分钟后再听到磬声即可睁眼。',
  );

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
  }

  @override
  void start() {
    _started = true;
    notifyVisualChanged();
    _scheduleVisualTick();
    // 一分钟后：磬两声 = 结束。
    _ctx.scheduler.scheduleCallback(_lengthUs, () {
      _ctx.requestFinish(FinishReason.completed);
    });
  }

  void _scheduleVisualTick() {
    final next = (_ctx.scheduler.nowUs() + 1000000).clamp(0, _lengthUs);
    if (next >= _lengthUs) return;
    _ctx.scheduler.scheduleCallback(next, () {
      if (_finished) return;
      notifyVisualChanged();
      _scheduleVisualTick();
    });
  }

  @override
  void onInput(InputEvent e) {}

  @override
  void onInterrupt(InterruptReason r) {
    // 宿主已暂停调度器，静坐计时自动冻结，无需额外处理。
  }

  @override
  void onResume() {}

  @override
  Future<PracticeResult> finish(FinishReason r) async {
    if (_finished) {
      return _result(r);
    }
    _finished = true;
    return _result(r);
  }

  PracticeResult _result(FinishReason r) {
    final t = _ctx.scheduler.nowUs().clamp(0, _lengthUs);
    final completedFull = t >= _lengthUs && r == FinishReason.completed;
    return PracticeResult(
      effectiveDuration: Duration(microseconds: t),
      quality: t >= _lengthUs ? 1.0 : t / _lengthUs,
      // 修为只来自真实完成（设计方案原则 5）：没坐满一分钟不发修为。
      merit: completedFull ? 1 : 0,
      metrics: {'seconds': t ~/ 1000000},
      completed: r == FinishReason.completed,
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    final progress = _started ? _ctx.scheduler.nowUs() / _lengthUs : 0.0;
    return PracticeScene(
      kind: PracticeSceneKind.sitQuiet,
      title: '静 坐',
      subtitle: '闭眼 · 随呼吸安住此刻',
      progress: progress,
      active: _started,
    );
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    return const Center(
      child: Text(
        '一炷香的时间，你已经坐完了。',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0x99E8DFC8), fontSize: 15),
      ),
    );
  }
}

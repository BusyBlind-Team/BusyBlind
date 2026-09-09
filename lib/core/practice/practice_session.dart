import 'package:flutter/widgets.dart';

import '../audio/audio_clock.dart';
import '../audio/event_scheduler.dart';
import '../audio/input_capture.dart';
import '../audio/session_recorder.dart';
import '../audio/sound_bank.dart';
import 'practice_manifest.dart';
import 'practice_result.dart';
import 'practice_types.dart';

/// 注入给修行插件的运行环境。
///
/// 插件不许自己 new 这些东西——AudioClock、SoundBank、Scheduler、Recorder
/// 全部由宿主注入，保证全 app 只有一根时间轴、一个音效库。
class PracticeContext {
  const PracticeContext({
    required this.clock,
    required this.scheduler,
    required this.sounds,
    required this.recorder,
    required this.input,
    this.params = const {},
    required this.requestFinish,
  });

  final AudioClock clock;
  final EventScheduler scheduler;
  final SoundBank sounds;
  final SessionRecorder recorder;
  final InputCapture input;

  /// 玩法参数（如听潮的节奏档位、助眠模式开关），来自修行列表的选择。
  final Map<String, Object?> params;

  /// 玩法请求结束（敲满 108 声、计时到点、挂机超时等）。
  /// 宿主负责统一收口：结算 → 发修为 → 判成就 → 写库 → 结算页。
  final void Function(FinishReason reason) requestFinish;

  int intParam(String key, int fallback) =>
      params[key] is int ? params[key]! as int : fallback;
  bool boolParam(String key, [bool fallback = false]) =>
      params[key] is bool ? params[key]! as bool : fallback;
  double doubleParam(String key, double fallback) =>
      params[key] is num ? (params[key]! as num).toDouble() : fallback;
  String stringParam(String key, String fallback) =>
      params[key] is String ? params[key]! as String : fallback;
}

/// 运行时逻辑：每个修行实现这一份契约。
///
/// 验收标准：新增一个修行 = 一个本接口的实现 + 一条注册 + 一组音效，
/// 不改动宿主与其他修行的任何一行。
abstract class PracticeSession {
  /// 玩法状态变化时递增；宿主只据此重建视觉层，不介入玩法状态机。
  final ValueNotifier<int> visualRevision = ValueNotifier<int>(0);

  @protected
  void notifyVisualChanged() {
    visualRevision.value++;
  }

  PracticeManifest get manifest;

  /// 开始界面的可选项（如听潮的呼吸法）。空 = 无选项。
  /// 用户在开始界面点选后宿主会写回 [startChoice]，start() 时即可读取。
  List<String> get startChoices => const [];

  int get startChoice => 0;

  set startChoice(int index) {}

  /// 预载音频、标定等准备工作（宿主在进入会话页前调用一次）。
  Future<void> prepare(PracticeContext ctx);

  /// 开始（宿主在此之前已完成：scheduler.begin + 磬一声）。
  void start();

  /// 全屏统一输入（按下/抬起都送进来，手势判定由玩法自己做）。
  void onInput(InputEvent e);

  /// 来电/通知/退后台：宿主已暂停调度器，玩法在此暂停自己的状态机。
  void onInterrupt(InterruptReason r);

  /// 从中断恢复。
  void onResume();

  /// 结束并产出结算。宿主保证此后不再调用其他方法。
  Future<PracticeResult> finish(FinishReason r);

  /// 睁眼时看到的画面（闭眼时它照样在跑，只是用户不看）。
  Widget buildVisual(BuildContext c);

  /// 结算页（助眠模式等特殊结局可由 note 控制，宿主跳过）。
  Widget buildSummary(BuildContext c, PracticeResult r);

  /// 释放视觉通知器；调度器必须先于会话释放，避免迟到回调。
  @mustCallSuper
  void dispose() {
    visualRevision.dispose();
  }
}

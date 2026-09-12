import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/achievements.dart';
import 'practice_art.dart';
import '../../theme.dart';
import '../audio/bgm_player.dart';
import '../audio/event_scheduler.dart';
import '../audio/input_capture.dart';
import '../audio/session_recorder.dart';
import '../audio/sound_bank.dart';
import '../audio/sound_catalog.dart';
import 'practice_manifest.dart';
import 'practice_registry.dart';
import 'practice_result.dart';
import 'practice_session.dart';
import 'practice_tutorials.dart';
import 'practice_types.dart';

/// 修行宿主：生命周期调度、中断恢复、结算收口。
///
/// 玩法只实现 PracticeSession 契约；修为入账、成就判定、花瓣入库、
/// 助眠补发全部在这里单点完成——反作弊与经济调平只有一处代码。
class PracticeHostPage extends ConsumerStatefulWidget {
  const PracticeHostPage({
    super.key,
    required this.factory,
    this.params = const {},
  });

  final PracticeSessionFactory factory;
  final Map<String, Object?> params;

  @override
  ConsumerState<PracticeHostPage> createState() => _PracticeHostPageState();
}

class _PracticeHostPageState extends ConsumerState<PracticeHostPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final PracticeSession _session;
  EventScheduler? _scheduler;
  PracticeContext? _ctx;

  bool _prepared = false;
  bool _running = false;
  bool _finishing = false;
  PracticeResult? _result;
  List<String> _freshAchievements = const [];

  // 首次教程（改进列表）：每个修行第一次打开，开始界面之前强制浮窗教程。
  bool _tutorialDone = false;

  // 修行 BGM（改进列表）：随机一首 + 顶部小字唱片机。
  final BgmPlayer _bgm = BgmPlayer();
  String _bgmName = '';
  String _bgmTrackName = '';
  late final AnimationController _bgmSpin;

  // §13：本局 BGM 选择（开始界面可选），初值取全局设置。
  int _bgmChoice = SoundCatalog.bgmTrackRandom;

  /// 会话参数（可变）：BGM 相关项在 _begin() 按最终选择写入。
  Map<String, Object?>? _params;
  SoundBank? _sounds;

  /// #2：环境音"已请求停止"标记，用于兜住尚未完成的异步起播。
  bool _ambienceStopped = false;

  /// 环境音操作统一入口：优先用 prepare 时记下的 SoundBank。
  SoundBank get _bank => _sounds ?? ref.read(soundBankProvider);

  // §14：本局叠加或替代的环境音（河流/溪流/鸟叫/虫鸣），带渐入渐出。
  String? _ambienceKey;
  double _ambienceLevel = 0;
  double _ambienceTarget = 0;
  Timer? _ambienceRamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bgmSpin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _session = widget.factory();
    _tutorialDone = ref
        .read(storeProvider)
        .isTutorialSeen(_session.manifest.id);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final clock = ref.read(clockProvider);
    final sounds = ref.read(soundBankProvider);
    final input = ref.read(inputCaptureProvider);
    late final EventScheduler scheduler;
    final recorder = SessionRecorder(() => scheduler.nowUs());
    scheduler = EventScheduler(clock, sounds, recorder: recorder);

    // 背景音乐设置（首页"乐"入口）：选了曲目则本局固定一首，BGM 与
    // 两个循环环境音（数雨/听潮）对应替换为同一首；选"无"则不播 BGM、
    // 环境音回退各自的默认音效。
    final store = ref.read(storeProvider);
    // §13：本局用开始界面选的那一项（默认随机），全局"乐"设置作为初值。
    _bgmChoice = store.bgmTrackIndex;
    final policy = _session.manifest.ambience;
    // §14.3：数雨在鸟叫/虫鸣里随机取一个，单局固定不切换。
    _ambienceKey = switch (policy) {
      AmbiencePolicy.riverOnly => SoundCatalog.ambRiverKey,
      AmbiencePolicy.stream => SoundCatalog.ambStreamKey,
      AmbiencePolicy.birdsOrInsects =>
        Random().nextBool()
            ? SoundCatalog.ambBirdsKey
            : SoundCatalog.ambInsectsKey,
      AmbiencePolicy.sessionOwned => SoundCatalog.ambTideKey,
      AmbiencePolicy.none => null,
    };
    // #3：BGM 播放参数**不在这里**生成——开始界面上还能改选，早生成会让
    // 改选失效。这里只建可变 map，真正的取值在 _begin() 里做。
    final params = <String, Object?>{...widget.params};
    _params = params;
    _sounds = sounds;

    final ctx = PracticeContext(
      clock: clock,
      scheduler: scheduler,
      sounds: sounds,
      recorder: recorder,
      input: input,
      params: params,
      requestFinish: _requestFinish,
    );
    _scheduler = scheduler;
    _ctx = ctx;
    await _session.prepare(ctx);
    if (mounted) {
      setState(() => _prepared = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgmSpin.dispose();
    // #2：结算后立刻返回时，渐出定时器会被取消，必须在这里兜底停掉音轨，
    // 否则河流/溪流会跟着回到首页继续响。
    _stopAmbienceNow();
    unawaited(_bgm.stop());
    _scheduler?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_result != null || !_running && _scheduler == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _scheduler?.pause();
        ref.read(soundBankProvider).pauseAll();
        unawaited(_bgm.pause());
        _session.onInterrupt(InterruptReason.appBackgrounded);
      case AppLifecycleState.resumed:
        _scheduler?.resume();
        ref.read(soundBankProvider).resumeAll();
        unawaited(_bgm.resume());
        _session.onResume();
      default:
        break;
    }
  }

  void _begin() {
    if (!_prepared || _running || _finishing || _result != null) return;
    final scheduler = _scheduler!;
    scheduler.begin();
    // #3：此刻才按最终选择生成 BGM 参数；数雨等会话在 start() 里读取。
    _applyBgmParams();
    _session.start();
    // 声音语言：磬一声 = 开始 / 请闭眼。
    ref.read(soundBankProvider).play(SoundCatalog.chimeKey);
    // 修行 BGM：本局解析好的那首（"无"设置下不启动），放完隔一秒循环。
    // 只跳过音乐启动，绝不影响开始流程（复审 P1：此前 return 吞掉了
    // _running 置位，选"无"会卡在开始界面）。
    // 听潮/数雨的会话内环境循环在选曲时就是这首曲子（音量包络的载体），
    // 这里不再另起 BgmPlayer，避免两个声道同播同一首（复审 R1）；
    // 但曲名与唱片动画照常展示——音乐确实在放，只是由环境循环承载
    //（二轮审查 P2：指示器不能只认 _bgm.start）。
    final policy = _session.manifest.ambience;
    final bgmAsset = _ctx?.params['bgmAsset'] as String?;
    if (policy == AmbiencePolicy.sessionOwned) {
      // 听潮：潮水与呼吸指引都由会话自己起播（§2）。
    } else {
      if (bgmAsset != null && !_session.manifest.usesAmbientLoop) {
        _bgm
            .start(
              asset: bgmAsset,
              volume: (_ctx?.params['bgmVolume'] as num?)?.toDouble() ?? 0.35,
            )
            .then((_) {
              if (mounted && _running) {
                setState(() => _bgmName = _bgm.trackName);
                _bgmSpin.repeat();
              }
            });
      } else if (bgmAsset != null) {
        if (mounted) {
          setState(() => _bgmName = _bgmTrackName);
        }
        _bgmSpin.repeat();
      }
      // §14：过河只播河流；钓花叠溪流；数雨叠鸟叫/虫鸣。§14.5 渐入。
      unawaited(_startAmbience());
    }
    setState(() => _running = true);
  }

  /// #3：按"点开始那一刻"的最终选择生成 BGM 播放参数。
  void _applyBgmParams() {
    final params = _params;
    if (params == null) return;
    params.remove('bgmAsset');
    params.remove('bgmVolume');
    params.remove('ambientKey');
    params.remove('ambientVolume');
    final policy = _session.manifest.ambience;
    // §14.1/§2：过河只播河流、听潮自带潮水，都不播五首 BGM。
    final playBgm =
        policy != AmbiencePolicy.riverOnly &&
        policy != AmbiencePolicy.sessionOwned;
    final resolved = SoundCatalog.resolveTrack(_bgmChoice);
    _bgmTrackName = playBgm ? (resolved?.name ?? '') : '';
    if (playBgm && resolved != null) {
      params['bgmAsset'] = SoundCatalog.catalog[resolved.key];
      params['bgmVolume'] = ref.read(storeProvider).bgmVolume;
      params['ambientKey'] = resolved.key;
      params['ambientVolume'] = ref.read(storeProvider).bgmVolume;
    }
  }

  /// 起播本局环境音并渐入（§14.5）。过河的河流随机起点（§14.1）。
  Future<void> _startAmbience() async {
    final key = _ambienceKey;
    if (key == null) return;
    final sounds = _bank;
    _ambienceStopped = false;
    await sounds.startLoop(
      key,
      gain: 0,
      startAt: key == SoundCatalog.ambRiverKey
          ? Duration(seconds: Random().nextInt(300))
          : null,
    );
    // 起播是异步的，若期间已经请求停止，补一次停止，避免音轨在起播完成后
    // 继续留在前台。更重要的是，渐入只能从真正就绪后开始，否则慢加载时
    // 所有音量更新都会落空，播放器会永远以 0 音量启动。
    if (_ambienceStopped) {
      await sounds.stopLoop(key);
      return;
    }
    _ambienceLevel = 0;
    _ambienceTarget = 1;
    _ambienceRamp ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _rampAmbience(),
    );
  }

  void _rampAmbience() {
    final key = _ambienceKey;
    if (key == null || _ambienceLevel == _ambienceTarget) return;
    final step = _ambienceTarget > _ambienceLevel ? 0.1 : -0.1;
    _ambienceLevel = (_ambienceLevel + step).clamp(0.0, 1.0);
    unawaited(_bank.setLoopGain(key, 0.35 * _ambienceLevel));
    if (_ambienceLevel == 0 && _ambienceTarget == 0) {
      _ambienceRamp?.cancel();
      _ambienceRamp = null;
      _ambienceStopped = true;
      unawaited(_bank.stopLoop(key));
    }
  }

  /// 立即停止环境音（#2：销毁兜底，不等渐出）。
  void _stopAmbienceNow() {
    _ambienceStopped = true;
    _ambienceRamp?.cancel();
    _ambienceRamp = null;
    final key = _ambienceKey;
    if (key == null) return;
    unawaited(_bank.stopLoop(key));
  }

  /// 收口时环境音渐出（§14.5）。
  void _fadeOutAmbience() {
    if (_ambienceKey == null) return;
    _ambienceTarget = 0;
    if (_ambienceLevel == 0) {
      _ambienceStopped = true;
      unawaited(_bank.stopLoop(_ambienceKey!));
      return;
    }
    _ambienceRamp ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _rampAmbience(),
    );
  }

  void _requestFinish(FinishReason reason) {
    if (!_running || _finishing) return;
    _finish(reason);
  }

  /// 统一输入分发：原始 down/up 先进 SessionRecorder（对账的原始时间线），
  /// 再交给玩法做语义判定。move 只服务视觉层（如钓花浮标），不进时间线。
  void _dispatchInput(PointerEvent e, PointerPhase phase) {
    final ctx = _ctx;
    if (ctx == null || !_running || _finishing) return;
    final event = ctx.input.capture(e, ctx.scheduler.toSessionUs);
    if (phase != PointerPhase.move) {
      ctx.recorder.log('input:${phase.name}', {'sessionUs': event.sessionUs});
    }
    _session.onInput(event);
  }

  Future<void> _finish(FinishReason reason) async {
    if (_finishing || !_running) return;
    _finishing = true;
    setState(() => _running = false);
    _scheduler?.cancelAll();
    unawaited(_bgm.stop());
    _fadeOutAmbience();
    if (mounted) {
      setState(() => _bgmName = '');
      _bgmSpin.stop();
    }

    final sounds = ref.read(soundBankProvider);
    final store = ref.read(storeProvider);

    // 结算收口（单点）：修为 clamp → 成就 → 花瓣 → 写库。
    // 整段用兜底保护：玩法 finish 抛异常也不能把用户卡死在黑屏
    // （改进列表反馈的"提交答案后卡死、没法退出"）。
    PracticeResult result;
    try {
      result = await _session.finish(reason);
    } catch (e) {
      debugPrint('practice finish failed: $e');
      result = PracticeResult(
        effectiveDuration: Duration.zero,
        quality: 0,
        merit: 0,
        completed: false,
        metrics: const {},
        note: 'settle_error',
      );
    }

    final maxMerit = _session.manifest.meritBase * 3;
    final merit = result.merit.clamp(0, maxMerit);

    try {
      // 会话历史入库是公共结算步骤（复审 R2）：成就口径读的是
      // store.sessions，漏入库会让潮涌潮落/水之呼吸永不解锁，
      // 统计与报告也会漏计这一次。
      store.addSession(
        practiceId: _session.manifest.id,
        merit: merit,
        completed: result.completed,
        durationMs: result.effectiveDuration.inMilliseconds,
        metrics: result.metrics,
      );
      for (final reward in result.extraRewards) {
        switch (reward.kind) {
          case RewardKind.petal:
            // 花瓣在上钩那一刻就定了花种（新要求 #1）：reward.id = 花种 id。
            store.addPetal(reward.id);
          case RewardKind.slip:
            break;
        }
      }
      store.addMerit(merit);
      // 成就评估对所有模式一致（历史口径靠上面刚入库的会话，复审 R2）。
      final freshIds = evaluateAchievements(
        store,
        lastResult: result,
        lastManifest: _session.manifest,
      );
      final freshTitles = [
        for (final id in freshIds)
          kAchievements.firstWhere((a) => a.id == id).title,
      ];

      // 声音语言：磬两声 = 结束 / 可以睁眼。
      // （Bug 描述 #3：极轻的磬已删除，新成就只以结算页徽记提示。）
      await sounds.play(SoundCatalog.chimeDoubleKey);
      if (mounted) {
        setState(() {
          _result = result;
          _freshAchievements = freshTitles;
        });
      }
    } catch (e) {
      // 入账环节异常：仍要给结算页，绝不能卡死。
      debugPrint('practice settle failed: $e');
      if (mounted) {
        setState(() {
          _result = result;
          _freshAchievements = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _session.manifest;
    final ctx = _ctx;

    Widget child;
    if (!_prepared || ctx == null) {
      child = const _BlackScaffold(child: SizedBox.shrink());
    } else if (_result != null) {
      child = _BlackScaffold(
        child: _SummaryView(
          session: _session,
          result: _result!,
          merit: _result!.merit.clamp(0, manifest.meritBase * 3),
          achievementTitles: _freshAchievements,
        ),
      );
    } else if (_finishing) {
      // 结算中（音频淡出）：只给一个安静的加载指示，不给任何可点入口。
      child = const _BlackScaffold(
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE8DFC8)),
        ),
      );
    } else if (!_running) {
      // 首次教程只对有脚本脚目的修行生效（静坐试玩等直接进开始界面）。
      final tutorial = kPracticeTutorials[manifest.id];
      child = _BlackScaffold(
        child: !_tutorialDone && tutorial != null
            ? _TutorialOverlay(
                tutorial: tutorial,
                sounds: ref.read(soundBankProvider),
                onDone: () {
                  ref.read(storeProvider).markTutorialSeen(manifest.id);
                  setState(() => _tutorialDone = true);
                },
              )
            : _StartOverlay(
                manifest: manifest,
                session: _session,
                bgmChoice: _bgmChoice,
                onBgmChoice: (v) => setState(() => _bgmChoice = v),
                onStart: _begin,
                onExit: () => Navigator.of(context).maybePop(),
              ),
      );
    } else {
      child = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _dispatchInput(e, PointerPhase.down),
        onPointerMove: (e) => _dispatchInput(e, PointerPhase.move),
        onPointerUp: (e) => _dispatchInput(e, PointerPhase.up),
        onPointerCancel: (e) => _dispatchInput(e, PointerPhase.cancel),
        child: _BlackScaffold(
          child: AnimatedBuilder(
            animation: _session.visualRevision,
            builder: (context, _) => _session.buildVisual(context),
          ),
        ),
      );
    }

    // 所有修行在修行过程界面都有退出入口（改进列表）。
    final showEndChip = _running && _result == null && !_finishing;
    // Bug#8（第二轮）：这里兜一层正常文本样式。
    //
    // 修行页顶部的「退出」「♪ 曲名」是 Stack 覆盖层里的裸 Text，没有
    // Material/Scaffold 祖先，会继承 WidgetsApp 的 _errorTextStyle
    //（纯黄双下划线）——传进来的 TextStyle 只设了颜色字号、没写 decoration，
    // 下划线就漏出来了。app 根的 MaterialApp.builder 已做全局兜底，这里再
    // 保一层：修行页不依赖宿主根组件提供合理的默认样式。
    return DefaultTextStyle(
      style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(decoration: TextDecoration.none),
      child: PopScope<Object?>(
        // 运行中拦截系统返回：按"用户结束"走正常结算收口，不丢结果。
        canPop: !_running || _finishing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _running && !_finishing) {
            _finish(FinishReason.cancelled);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: child),
            if (showEndChip)
              Positioned(
                top: 48,
                right: 20,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => _finish(FinishReason.userEnded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x22FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '退出',
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 修行 BGM 指示：上方小字曲名 + 旋转唱片机（改进列表）。
            if (_bgmName.isNotEmpty)
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _bgmSpin,
                      builder: (context, _) {
                        final paused = _bgmSpin.isAnimating ? 1.0 : 0.0;
                        return Opacity(
                          opacity: 0.55,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomPaint(
                                size: const Size(14, 14),
                                painter: _DiscPainter(
                                  angle: _bgmSpin.value * 2 * 3.14159265,
                                  visible: paused,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '♪ $_bgmName',
                                style: const TextStyle(
                                  color: Color(0x88E8DFC8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 简化唱片机：圆形"唱片"缓慢旋转（BGM 指示动画）。
class _DiscPainter extends CustomPainter {
  _DiscPainter({required this.angle, required this.visible});

  final double angle;
  final double visible;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0x66E8DFC8));
    canvas.drawCircle(
      Offset.zero,
      r * 0.35,
      Paint()..color = const Color(0x33050505),
    );
    canvas.drawLine(
      Offset(-r, 0),
      Offset(r, 0),
      Paint()
        ..color = const Color(0x55050505)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.angle != angle;
}

/// 首次教程浮窗（改进列表）：半透明浮窗逐段显示文案，
/// 浮窗下方"点击屏幕继续"，最后一段点击后进入开始界面。
class _TutorialOverlay extends StatefulWidget {
  const _TutorialOverlay({
    required this.tutorial,
    required this.sounds,
    required this.onDone,
  });

  final PracticeTutorial? tutorial;
  final SoundBank sounds;
  final VoidCallback onDone;

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay> {
  int _page = 0;
  bool _ambientStarted = false;

  PracticeTutorial? get _tutorial => widget.tutorial;

  @override
  void initState() {
    super.initState();
    _showCurrent();
  }

  Future<void> _showCurrent() async {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    // 持续环境声（听潮：教程期间持续播放潮水声音）。
    final loop = tutorial.ambientLoopKey;
    if (loop != null && !_ambientStarted) {
      _ambientStarted = true;
      await widget.sounds.startLoop(loop, gain: 0.18);
    }
    final sound = tutorial.pages[_page].soundKey;
    if (sound != null) {
      await widget.sounds.play(sound, gain: tutorial.pages[_page].soundGain);
    }
  }

  @override
  void dispose() {
    final loop = _tutorial?.ambientLoopKey;
    if (loop != null && _ambientStarted) {
      unawaited(widget.sounds.stopLoop(loop));
    }
    super.dispose();
  }

  void _advance() {
    final tutorial = _tutorial;
    if (tutorial == null || _page >= tutorial.pages.length - 1) {
      widget.onDone();
      return;
    }
    setState(() => _page++);
    _showCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final tutorial = _tutorial;
    final text = tutorial == null ? '' : tutorial.pages[_page].text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: Container(
        color: const Color(0xAA050505),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0x66201E1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33E8DFC8)),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xE6E8DFC8),
                  fontSize: 17,
                  height: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tutorial == null || _page >= tutorial.pages.length - 1
                  ? '点击屏幕，进入修行'
                  : '点击屏幕继续 (${_page + 1}/${tutorial.pages.length})',
              style: const TextStyle(color: Color(0x55E8DFC8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlackScaffold extends StatelessWidget {
  const _BlackScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ChoiceChip 等 Material 组件要求 Material 祖先；透明 Material 不改变纯黑视觉。
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(color: const Color(0xFF050505), child: child),
    );
  }
}

class _StartOverlay extends StatefulWidget {
  const _StartOverlay({
    required this.manifest,
    required this.session,
    required this.bgmChoice,
    required this.onBgmChoice,
    required this.onStart,
    required this.onExit,
  });

  final PracticeManifest manifest;
  final PracticeSession session;

  /// §13：本局 BGM 选择。
  final int bgmChoice;
  final ValueChanged<int> onBgmChoice;
  final VoidCallback onStart;
  final VoidCallback onExit;

  @override
  State<_StartOverlay> createState() => _StartOverlayState();
}

class _StartOverlayState extends State<_StartOverlay> {
  /// §13：当前选择的显示名。
  String get _bgmChoiceLabel {
    final c = widget.bgmChoice;
    if (c == SoundCatalog.bgmTrackNone) return '不要背景音乐';
    if (c >= 0 && c < SoundCatalog.bgmTracks.length) {
      return SoundCatalog.bgmTracks[c].name;
    }
    return '随机背景音乐';
  }

  /// §13：点击后弹出五首 BGM + 不要 + 随机。
  Future<void> _pickBgm(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF12100C),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < SoundCatalog.bgmTracks.length; i++)
                ListTile(
                  dense: true,
                  title: Text(
                    SoundCatalog.bgmTracks[i].name,
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                  trailing: widget.bgmChoice == i
                      ? const Icon(Icons.check, color: AppTheme.gold, size: 18)
                      : null,
                  onTap: () => Navigator.of(context).pop(i),
                ),
              ListTile(
                dense: true,
                title: const Text(
                  '随机背景音乐',
                  style: TextStyle(color: AppTheme.ink),
                ),
                trailing: widget.bgmChoice == SoundCatalog.bgmTrackRandom
                    ? const Icon(Icons.check, color: AppTheme.gold, size: 18)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(SoundCatalog.bgmTrackRandom),
              ),
              ListTile(
                dense: true,
                title: const Text(
                  '不要背景音乐',
                  style: TextStyle(color: AppTheme.ink),
                ),
                trailing: widget.bgmChoice == SoundCatalog.bgmTrackNone
                    ? const Icon(Icons.check, color: AppTheme.gold, size: 18)
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(SoundCatalog.bgmTrackNone),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) widget.onBgmChoice(picked);
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.session.startChoices;
    final details = widget.session.startChoiceDetails;
    final art = practiceArtFor(widget.session.manifest.iconKey);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 修行插画横幅（Bug 描述 #2）：从介绍详情移到准备开始界面。
            // Bug#1（第二轮）：原先是 height:132 + BoxFit.cover，把 600×600
            // 的方图压成横条、上下裁掉大半（过河连僧人头部都看不见）。
            // 改为 1:1 容器撑满可用宽度：源图本身就是 1:1，cover 不会裁到主体。
            if (art != null) ...[
              // Bug#1（第二轮）：原先是 height:132 + BoxFit.cover，把 600×600
              // 的方图压成横条、上下裁掉大半（过河连僧人头部都看不见）。
              // 现在固定 1:1 完整显示，不上下裁切。
              //
              // 但屏幕高度有限：无脑"宽度撑满"会让整页溢出（实测溢 430px），
              // 所以边长取「可用宽度」与「屏高 42%」的较小值——高屏上就是
              // 撑满宽度，矮屏上自动退让，始终维持 1:1 且不裁主体。
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxSide = MediaQuery.sizeOf(context).height * 0.42;
                  final side = constraints.maxWidth < maxSide
                      ? constraints.maxWidth
                      : maxSide;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: Image.asset(
                        art,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(height: 0),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
            ],
            Text(
              widget.manifest.name,
              style: const TextStyle(
                color: Color(0xFFE8DFC8),
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '请闭上双眼',
              style: TextStyle(color: Color(0x88E8DFC8), fontSize: 14),
            ),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < choices.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: ChoiceChip(
                        label: Text(choices[i]),
                        selected: widget.session.startChoice == i,
                        onSelected: (_) =>
                            setState(() => widget.session.startChoice = i),
                        labelStyle: TextStyle(
                          color: widget.session.startChoice == i
                              ? AppTheme.bg
                              : AppTheme.inkDim,
                          fontSize: 12,
                        ),
                        selectedColor: AppTheme.gold,
                        backgroundColor: const Color(0x14E8DFC8),
                      ),
                    ),
                ],
              ),
              // §6：点击某种呼吸法后，展开它的节奏与难度详情。
              if (details.length == choices.length) ...[
                const SizedBox(height: 14),
                _StartChoiceDetailCard(
                  detail:
                      details[widget.session.startChoice.clamp(
                        0,
                        details.length - 1,
                      )],
                ),
              ],
            ],
            // §13：BGM 手动选择入口（听潮/过河不提供）。
            if (widget.manifest.allowsBgmChoice) ...[
              const SizedBox(height: 18),
              _BgmChoiceRow(
                label: _bgmChoiceLabel,
                onTap: () => _pickBgm(context),
              ),
            ],
            const SizedBox(height: 44),
            OutlinedButton(
              onPressed: widget.onStart,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE8DFC8),
                side: const BorderSide(color: Color(0x55E8DFC8)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 44,
                  vertical: 14,
                ),
              ),
              child: const Text('开始'),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: widget.onExit,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0x66E8DFC8),
              ),
              child: const Text('退出'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({
    required this.session,
    required this.result,
    required this.merit,
    this.achievementTitles = const [],
  });

  final PracticeSession session;
  final PracticeResult result;
  final int merit;
  final List<String> achievementTitles;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              result.completed ? '修行结束' : '修行中断',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE8DFC8),
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '修为 +$merit',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD8B36A), fontSize: 18),
            ),
            if (achievementTitles.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final title in achievementTitles)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1AD8B36A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.military_tech,
                        color: Color(0xFFD8B36A),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '解锁成就 · $title',
                        style: const TextStyle(
                          color: Color(0xFFD8B36A),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 24),
            session.buildSummary(context, result),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: const Color(0xFF0B0B10),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('回去'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 花瓣/成就等结算公共小组件，供各修行 buildSummary 复用。
class SummaryChip extends StatelessWidget {
  const SummaryChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0x99E8DFC8), fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// §6：开始界面展开的呼吸法详情（节奏 + 难度）。
class _StartChoiceDetailCard extends StatelessWidget {
  const _StartChoiceDetailCard({required this.detail});

  final StartChoiceDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x0FE8DFC8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.rhythm,
            style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            detail.note,
            style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// §13：开始界面的"BGM 选择"入口。
class _BgmChoiceRow extends StatelessWidget {
  const _BgmChoiceRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Color(0x88E8DFC8), size: 16),
            const SizedBox(width: 8),
            Text(
              '背景音乐：$label',
              style: const TextStyle(color: Color(0xAAE8DFC8), fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, color: Color(0x66E8DFC8), size: 16),
          ],
        ),
      ),
    );
  }
}

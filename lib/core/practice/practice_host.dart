import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/achievements.dart';
import '../../theme.dart';
import '../audio/event_scheduler.dart';
import '../audio/session_recorder.dart';
import '../audio/sound_catalog.dart';
import 'practice_manifest.dart';
import 'practice_registry.dart';
import 'practice_result.dart';
import 'practice_session.dart';
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
    with WidgetsBindingObserver {
  late final PracticeSession _session;
  EventScheduler? _scheduler;
  PracticeContext? _ctx;

  bool _prepared = false;
  bool _running = false;
  bool _finishing = false;
  PracticeResult? _result;
  List<String> _freshAchievements = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.factory();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final clock = ref.read(clockProvider);
    final sounds = ref.read(soundBankProvider);
    final input = ref.read(inputCaptureProvider);
    late final EventScheduler scheduler;
    final recorder = SessionRecorder(() => scheduler.nowUs());
    scheduler = EventScheduler(clock, sounds, recorder: recorder);
    final ctx = PracticeContext(
      clock: clock,
      scheduler: scheduler,
      sounds: sounds,
      recorder: recorder,
      input: input,
      params: widget.params,
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
    _scheduler?.dispose();
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
        _session.onInterrupt(InterruptReason.appBackgrounded);
      case AppLifecycleState.resumed:
        _scheduler?.resume();
        ref.read(soundBankProvider).resumeAll();
        _session.onResume();
      default:
        break;
    }
  }

  void _begin() {
    if (!_prepared || _running) return;
    final scheduler = _scheduler!;
    scheduler.begin();
    _session.start();
    // 声音语言：磬一声 = 开始 / 请闭眼。
    ref.read(soundBankProvider).play(SoundCatalog.chimeKey);
    setState(() => _running = true);
  }

  void _requestFinish(FinishReason reason) {
    if (!_running || _finishing) return;
    _finish(reason);
  }

  Future<void> _finish(FinishReason reason) async {
    if (_finishing || !_running) return;
    _finishing = true;
    setState(() => _running = false);
    _scheduler?.cancelAll();

    final sounds = ref.read(soundBankProvider);
    final store = ref.read(storeProvider);
    final result = await _session.finish(reason);

    // 结算收口（单点）：修为 clamp → 成就 → 花瓣 → 写库。
    final maxMerit = _session.manifest.meritBase * 3;
    final merit = result.merit.clamp(0, maxMerit);

    if (result.note == 'sleep_mode') {
      // 助眠模式：不弹结算页，修为次日打开时补发（设计方案 7.3）。
      store.queuePendingMerit(merit);
      await sounds.stopLoop(SoundCatalog.tideLoopKey);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }

    store.addMerit(merit);
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
          store.addPetal(reward.id);
        case RewardKind.slip:
          break;
      }
    }
    final freshIds = store.unlockAchievements(
      kAchievements
          .where(
            (a) => a.test(
              AchievementEval(store: store, lastResult: result, lastManifest: _session.manifest),
            ),
          )
          .map((a) => a.id),
    );
    final freshTitles = [
      for (final id in freshIds)
        kAchievements.firstWhere((a) => a.id == id).title,
    ];

    // 声音语言：磬两声 = 结束 / 可以睁眼。
    await sounds.play(SoundCatalog.chimeDoubleKey);
    for (final _ in freshTitles) {
      await sounds.play(SoundCatalog.chimeSoftKey);
    }

    if (mounted) {
      setState(() {
        _result = result;
        _freshAchievements = freshTitles;
      });
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
    } else if (!_running) {
      child = _BlackScaffold(
        child: _StartOverlay(
          manifest: manifest,
          onStart: _begin,
        ),
      );
    } else {
      child = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _session
            .onInput(ctx.input.capture(e, ctx.scheduler.nowUs)),
        onPointerUp: (e) => _session
            .onInput(ctx.input.capture(e, ctx.scheduler.nowUs)),
        onPointerCancel: (e) => _session
            .onInput(ctx.input.capture(e, ctx.scheduler.nowUs)),
        child: _BlackScaffold(child: _session.buildVisual(context)),
      );
    }

    final showEndChip = manifest.allowManualEnd && _running && _result == null;
    return PopScope<Object?>(
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x22FFFFFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '结束',
                      style: TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlackScaffold extends StatelessWidget {
  const _BlackScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: const Color(0xFF050505), child: child);
  }
}

class _StartOverlay extends StatelessWidget {
  const _StartOverlay({required this.manifest, required this.onStart});

  final PracticeManifest manifest;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final rules = manifest.rulesText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              manifest.name,
              style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              manifest.subtitle,
              style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 14),
            ),
            if (rules != null) ...[
              const SizedBox(height: 28),
              Text(
                rules,
                style: const TextStyle(color: Color(0xB3E8DFC8), fontSize: 15, height: 1.7),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 44),
            OutlinedButton(
              onPressed: onStart,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE8DFC8),
                side: const BorderSide(color: Color(0x55E8DFC8)),
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              ),
              child: const Text('开始（磬响后请闭眼）'),
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
              style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 24, fontWeight: FontWeight.w600),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x1AD8B36A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.military_tech, color: Color(0xFFD8B36A), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '解锁成就 · $title',
                        style: const TextStyle(color: Color(0xFFD8B36A), fontSize: 14),
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
          Text(label, style: const TextStyle(color: Color(0x99E8DFC8), fontSize: 14)),
          Text(value, style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15)),
        ],
      ),
    );
  }
}

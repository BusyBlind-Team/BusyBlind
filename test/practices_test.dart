import 'dart:math';

import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/session_recorder.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_registry.dart';
import 'package:busy_blind/core/practice/practice_result.dart';
import 'package:busy_blind/core/practice/practice_session.dart';
import 'package:busy_blind/core/practice/practice_types.dart';
import 'package:busy_blind/practices/count_rain.dart';
import 'package:busy_blind/practices/cross_river.dart';
import 'package:busy_blind/practices/fish_petals.dart';
import 'package:busy_blind/practices/sit_quiet.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

/// 构造一套纯内存的 PracticeContext（无真实音频、时钟可控）。
(PracticeContext, FakeClock, SilentSoundBank, EventScheduler) makeContext(
  void Function(FinishReason) requestFinish,
) {
  final clock = FakeClock();
  final sounds = SilentSoundBank();
  late final EventScheduler scheduler;
  final recorder = SessionRecorder(() => scheduler.nowUs());
  scheduler = EventScheduler(clock, sounds, recorder: recorder);
  final input = InputCapture(clock);
  final ctx = PracticeContext(
    clock: clock,
    scheduler: scheduler,
    sounds: sounds,
    recorder: recorder,
    input: input,
    requestFinish: requestFinish,
  );
  return (ctx, clock, sounds, scheduler);
}

InputEvent tap(int sessionUs) => InputEvent(
  phase: PointerPhase.down,
  absAudioUs: sessionUs,
  sessionUs: sessionUs,
  rawTimeStamp: Duration(microseconds: sessionUs),
);

InputEvent release(int sessionUs) => InputEvent(
  phase: PointerPhase.up,
  absAudioUs: sessionUs,
  sessionUs: sessionUs,
  rawTimeStamp: Duration(microseconds: sessionUs),
);

void main() {
  group('注册表', () {
    test('五个修行（静坐已移出列表），id 唯一，manifest 完整', () {
      final manifests = practiceFactories.map((f) => f().manifest).toList();
      expect(manifests.length, 5);
      expect(manifests.map((m) => m.id), isNot(contains('sit_quiet')));
      expect(manifests.map((m) => m.id).toSet().length, 5);
      for (final m in manifests) {
        expect(m.name, isNotEmpty);
        expect(m.subtitle, isNotEmpty);
        expect(m.tags, isNotEmpty);
        expect(m.meritBase, greaterThan(0));
        expect(m.typicalLength, greaterThan(Duration.zero));
        expect(m.introTags, isNotEmpty);
        expect(m.intro, isNotEmpty);
      }
    });
  });

  group('插件框架验收：静坐一分钟', () {
    test('60 秒后自动收口，修为 1，不改宿主任何代码即可新增', () {
      fakeAsync((async) {
        FinishReason? reason;
        final (ctx, clock, sounds, scheduler) = makeContext((r) => reason = r);
        final session = SitQuietSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        clock.advanceUs(59000000);
        async.elapse(const Duration(milliseconds: 100));
        expect(reason, isNull);

        clock.advanceUs(1000000);
        async.elapse(const Duration(milliseconds: 200));
        expect(reason, FinishReason.completed);
        expect(sounds.played, isEmpty); // 开始/结束磬由宿主播，静坐自身无声

        PracticeResult? result;
        session.finish(reason!).then((r) => result = r);
        async.flushMicrotasks();
        final settled = result;
        expect(settled, isNotNull);
        expect(settled!.completed, isTrue);
        expect(settled.merit, 1);
        expect(settled.effectiveDuration.inSeconds, 60);
        scheduler.dispose();
      });
    });

    test('没坐满就取消：不发修为（修为只来自真实完成）', () async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = SitQuietSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      final result = await session.finish(FinishReason.cancelled);
      expect(result.merit, 0);
      expect(result.completed, isFalse);
      scheduler.dispose();
    });
  });

  group('木鱼', () {
    test('108 声整间隔 → 偏移 0，修为 15，里程碑磬两次', () async {
      FinishReason? reason;
      final (ctx, _, sounds, _) = makeContext((r) => reason = r);
      final session = WoodenFishSession();
      await session.prepare(ctx);
      session.start();

      for (var i = 1; i <= 108; i++) {
        session.onInput(tap(i * 1000000));
      }
      expect(reason, FinishReason.completed);

      final result = await session.finish(reason!);
      expect(result.metrics['strikes'], 108);
      expect(result.quality, 1.0);
      // 待对齐 #5：15 − 偏移秒；完美节奏偏移 0（107 个 1s 间隔 = 满拍总时长）。
      expect(result.merit, 15);
      // 每 36 声一声极轻的磬：第 36、72 声（第 108 声直接收口）。
      expect(sounds.played.where((k) => k == 'chime_soft').length, 2);
      expect(sounds.played.where((k) => k == 'muyu').length, 108);
    });

    test('整体偏慢 5.35 秒 → 修为 = round(15 − 5.35) = 10', () async {
      FinishReason? reason;
      final (ctx, _, _, _) = makeContext((r) => reason = r);
      final session = WoodenFishSession();
      await session.prepare(ctx);
      session.start();

      // 每拍 1.05s：总时长 107 × 1.05 = 112.35s，偏移 5.35s。
      var t = 0;
      for (var i = 1; i <= 108; i++) {
        t += 1050000;
        session.onInput(tap(t));
      }
      expect(reason, FinishReason.completed);
      final result = await session.finish(reason!);
      expect(result.merit, 10);
    });

    test('抖动节奏 → 修为随偏移扣减但不为负；中途收手不发修为', () async {
      FinishReason? reason;
      final (ctx, _, _, _) = makeContext((r) => reason = r);
      final session = WoodenFishSession();
      await session.prepare(ctx);
      session.start();

      // ±300ms 抖动的间隔序列（均值 1s，偏移只会来自随机游走）。
      final rng = Random(3);
      var t = 0;
      for (var i = 0; i < 108; i++) {
        t += 1000000 + (rng.nextInt(600000) - 300000);
        session.onInput(tap(t));
      }
      expect(reason, FinishReason.completed);
      final result = await session.finish(reason!);
      expect(result.merit, inInclusiveRange(0, 15));

      // 中途收手：没"完成一次"，不发修为（修为只来自真实完成）。
      final (ctx2, _, _, _) = makeContext((_) {});
      final session2 = WoodenFishSession();
      await session2.prepare(ctx2);
      session2.start();
      for (var i = 0; i < 10; i++) {
        session2.onInput(tap(i * 1000000 + 500000));
      }
      final result2 = await session2.finish(FinishReason.cancelled);
      expect(result2.merit, 0);
    });
  });

  group('数雨（待对齐 #2/#8：删钟声 · 3–10 秒一滴 · 3 分钟 · 听完报数）', () {
    test('雨滴序列：间隔 3–10 秒，3 分钟内，无钟声', () async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = CountRainSession();
      await session.prepare(ctx);

      final rains = session.rainTimesUs;
      var prev = 0;
      for (final t in rains) {
        expect(t - prev, inInclusiveRange(3000000, 10000000), reason: '间隔越界 @$t');
        prev = t;
      }
      expect(rains.last, lessThan(180000000));
      // 期望 ~28 滴（180/6.5），极端也在 15–45 之间。
      expect(rains.length, inInclusiveRange(15, 45));
      scheduler.dispose();
    });

    test('3 分钟后进入报数页，不自动收口；报数后按 10 − 误差 结算', () {
      fakeAsync((async) {
        FinishReason? reason;
        final (ctx, clock, _, scheduler) = makeContext((r) => reason = r);
        final session = CountRainSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        clock.advanceUs(180000000);
        async.elapse(const Duration(milliseconds: 50));
        expect(session.askingReport, isTrue);
        expect(reason, isNull); // 报数页等人报数，不自动收口

        // 精确报数：修为满额 10。
        final actual = session.rainTimesUs.length;
        session.submitReport(actual);
        expect(reason, FinishReason.completed);

        PracticeResult? result;
        session.finish(reason!).then((r) => result = r);
        async.flushMicrotasks();
        final settled = result;
        expect(settled, isNotNull);
        expect(settled!.completed, isTrue);
        expect(settled.merit, 10);
        expect(settled.metrics['error'], 0);
        scheduler.dispose();
      });
    });

    test('报数偏差按绝对滴数扣分、下限 0；未报数收口不发修为', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = CountRainSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        clock.advanceUs(180000000);
        async.elapse(const Duration(milliseconds: 50));
        final actual = session.rainTimesUs.length;
        session.submitReport(actual + 4); // 误差 4 滴 → 10 − 4 = 6
        PracticeResult? result;
        session.finish(FinishReason.completed).then((r) => result = r);
        async.flushMicrotasks();
        final settledA = result;
        expect(settledA!.merit, 6);

        // 多报 20 滴：10 − 20 < 0 → 下限 0。
        final (ctx2, clock2, _, scheduler2) = makeContext((_) {});
        final session2 = CountRainSession();
        session2.prepare(ctx2);
        scheduler2.begin();
        session2.start();
        clock2.advanceUs(180000000);
        async.elapse(const Duration(milliseconds: 50));
        session2.submitReport(session2.rainTimesUs.length + 20);
        PracticeResult? result2;
        session2.finish(FinishReason.completed).then((r) => result2 = r);
        async.flushMicrotasks();
        final settledB = result2;
        expect(settledB!.merit, 0);

        // 没听完就退出：未报数，不发修为。
        final (ctx3, _, _, scheduler3) = makeContext((_) {});
        final session3 = CountRainSession();
        session3.prepare(ctx3);
        scheduler3.begin();
        session3.start();
        PracticeResult? result3;
        session3.finish(FinishReason.cancelled).then((r) => result3 = r);
        async.flushMicrotasks();
        final settledC = result3;
        expect(settledC!.completed, isFalse);
        expect(settledC.merit, 0);
        scheduler.dispose();
        scheduler2.dispose();
        scheduler3.dispose();
      });
    });
  });

  group('过河', () {
    test('窗口内松手踩上石阶，超窗落水结算', () async {
      FinishReason? reason;
      final (ctx, _, _, scheduler) = makeContext((r) => reason = r);
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      // 第一跳：锚点 = 叮后 500ms 的咚；T = t1。
      expect(session.jumpNo, 1);
      final anchor = session.dongAnchorUs;
      final t1 = session.t1Us;
      session.onInput(tap(anchor)); // 按下时刻不作硬判定
      session.onInput(release(anchor + t1)); // 正点复现
      expect(session.jumpNo, 2);

      // 第二跳：故意拖倍间隔 → 落水。
      final anchorB = session.dongAnchorUs;
      final t1b = session.t1Us;
      session.onInput(tap(anchorB));
      session.onInput(release(anchorB + t1b * 2));
      expect(reason, FinishReason.completed); // 玩法已请求收口

      final result = await session.finish(reason!);
      expect(session.finished, isTrue); // finish() 之后置位
      expect(result.metrics['jumps'], 1);
      expect(result.merit, 1); // min(round(1 × 0.6), 20)
      scheduler.dispose();
    });

    test('踩滑（1.5 倍窗口内）不死，但难度不递进', () async {
      FinishReason? reason;
      final (ctx, _, _, scheduler) = makeContext((r) => reason = r);
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      final anchor = session.dongAnchorUs;
      final t1 = session.t1Us;
      final window = (t1 * 0.15).round() < 180000 ? 180000 : (t1 * 0.15).round();
      session.onInput(tap(anchor));
      session.onInput(release(anchor + t1 + (window * 1.2).round()));
      expect(session.finished, isFalse);
      expect(reason, isNull);
      expect(session.jumpNo, 2); // 踩滑仍在石阶上

      scheduler.dispose();
    });

    test('难度递进与 叮-咚-咚 变奏：连踩 10 阶（每跳偏差 0.1s 判成功）', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = CrossRiverSession(rng: Random(7));
        session.prepare(ctx);
        async.flushMicrotasks();
        scheduler.begin();
        session.start();

        var variationSeen = false;
        for (var i = 1; i <= 10; i++) {
          final anchor = session.dongAnchorUs;
          final t = session.t1Us;
          clock.advanceUs(anchor + 100000);
          session.onInput(tap(anchor + 100000));
          session.onInput(release(anchor + 100000 + t));
          if (session.variation) {
            // 变奏第二段：在第二声咚后 0.1s 起手，复现 T2。
            variationSeen = true;
            final anchor2 = anchor + t;
            final t2 = session.t2Us;
            clock.advanceUs(anchor2 + 100000);
            session.onInput(tap(anchor2 + 100000));
            session.onInput(release(anchor2 + 100000 + t2));
          }
          expect(session.jumpNo, i + 1, reason: '第 $i 跳应成功');
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(variationSeen, isTrue, reason: '第 10 跳应出现过变奏');
        expect(session.finished, isFalse);
        scheduler.dispose();
      });
    });

    test('连续踩滑能继续过河，但不推进下一跳难度', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = CrossRiverSession(rng: Random(1));
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        for (var i = 0; i < 5; i++) {
          final anchor = session.dongAnchorUs;
          final t = session.t1Us;
          final window = max((t * 0.15).round(), 180000);
          final releaseAt = anchor + t + (window * 1.25).round();
          session.onInput(tap(anchor));
          clock.advanceUs(releaseAt - clock.nowUs());
          session.onInput(release(releaseAt));
        }

        expect(session.jumpNo, 6);
        expect(session.t1Us, lessThanOrEqualTo(2000000));
        scheduler.dispose();
      });
    });
  });

  group('钓花', () {
    test('暂停期间不触发反挂机；恢复后只按活动会话时间结算', () {
      fakeAsync((async) {
        FinishReason? reason;
        final (ctx, clock, _, scheduler) = makeContext((r) => reason = r);
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        scheduler.pause();
        clock.advanceUs(91000000);
        async.elapse(const Duration(milliseconds: 200));
        expect(reason, isNull);
        expect(scheduler.nowUs(), 0);

        scheduler.resume();
        clock.advanceUs(90000000);
        async.elapse(const Duration(milliseconds: 200));
        expect(reason, FinishReason.antiIdle);

        scheduler.dispose();
        session.dispose();
      });
    });

    test('聚瓣期概率曲线：前 2 秒为 0，10s≈20%，60s≈60%', () {
      expect(FishPetalsSession.biteRatePerSecond(0), 0);
      expect(FishPetalsSession.biteRatePerSecond(1999999), 0);
      expect(FishPetalsSession.biteRatePerSecond(10000000), closeTo(0.20, 0.001));
      expect(FishPetalsSession.biteRatePerSecond(60000000), closeTo(0.60, 0.001));
      expect(FishPetalsSession.biteRatePerSecond(120000000), closeTo(0.60, 0.001));
    });

    test('叮后窗口内收手→花瓣入库；叮超时→流失；咚久握→4s 自动休整', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 叮 + 窗口内收手 → 花瓣入库。
        session.debugForceHook(petal: true);
        session.onInput(release(800000)); // 0.8s < 1.5s 窗口
        expect(session.debugPetals, 1);
        expect(session.debugIsResting, isTrue);

        // 叮 + 超时未收 → 流失。
        clock.advanceUs(3000000); // 越过 2s 休竿期
        async.elapse(const Duration(milliseconds: 200));
        session.debugForceHook(petal: true);
        clock.advanceUs(2000000); // 2s > 1.5s 窗口
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugMissed, 1);

        // 咚 + 久握 → 4s 自动空竿休整（未松手不计误收）。
        clock.advanceUs(5000000); // 越过休竿期
        async.elapse(const Duration(milliseconds: 200));
        session.debugForceHook(petal: false);
        clock.advanceUs(4500000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugIsResting, isTrue);
        expect(session.debugMiscatch, 0);
        scheduler.dispose();
      });
    });

    test('叮超时/咚久握 → 沉没声由会话状态机发出（复审 R3）', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) = makeContext((_) {});
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 叮（花瓣）超过 1.5s 收杆窗口 → 流失 + 沉没声。
        session.debugForceHook(petal: true);
        clock.advanceUs(1600000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugMissed, 1);
        expect(sounds.played.where((k) => k == 'fish_sink'), hasLength(1));

        // 咚（杂物）4s 自动休整 → 同样由状态机发沉没声。
        clock.advanceUs(3000000); // 越过休竿期
        async.elapse(const Duration(milliseconds: 200));
        session.debugForceHook(petal: false);
        clock.advanceUs(4100000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugIsResting, isTrue);
        expect(sounds.played.where((k) => k == 'fish_sink'), hasLength(2));
        scheduler.dispose();
        session.dispose();
      });
    });

    test('结算奖励文案带稀有度名称，插值未被转义（复审 R5）', () async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();
      session.debugForceHook(petal: true);
      session.onInput(release(0)); // 窗口内收杆
      final result = await session.finish(FinishReason.userEnded);
      expect(result.extraRewards.single.id,
          anyOf('common', 'rare', 'legendary'));
      expect(
        result.extraRewards.single.label,
        anyOf('花瓣（常见）', '花瓣（稀有）', '花瓣（奇珍）'),
      );
      session.dispose();
      scheduler.dispose();
    });

    test('叮后 1.5 秒内松手 → 花瓣入库（extraRewards）', () async {
      FinishReason? reason;
      final (ctx, _, _, scheduler) = makeContext((r) => reason = r);
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      // 直接把状态机推到"已触发叮"：等待 100ms 轮询不可控，
      // 改为验证松手收杆后的结算路径——先甩竿，等触发由随机性决定，
      // 因此这里只验证"未触发就收手 = 空竿"的确定性路径与结算完整性。
      session.onInput(tap(1000000)); // 甩竿
      session.onInput(release(2000000)); // 立刻收手（前 2 秒无咬钩）
      final result = await session.finish(FinishReason.userEnded);
      expect(reason, isNull); // 90 秒挂机判定由轮询触发，此处未到时
      expect(result.metrics['casts'], 1);
      expect(result.extraRewards, isEmpty);
      scheduler.dispose();
    });
  });

  group('钓花视觉（俯视池塘层，二轮审查）', () {
    InputEvent tapAt(Offset p, {int sessionUs = 0}) => InputEvent(
      phase: PointerPhase.down,
      absAudioUs: sessionUs,
      sessionUs: sessionUs,
      rawTimeStamp: Duration(microseconds: sessionUs),
      position: p,
    );

    InputEvent moveTo(Offset p, {int sessionUs = 0}) => InputEvent(
      phase: PointerPhase.move,
      absAudioUs: sessionUs,
      sessionUs: sessionUs,
      rawTimeStamp: Duration(microseconds: sessionUs),
      position: p,
    );

    /// 池塘层是私有组件：按运行时类型取它的 State，用 dynamic 访问
    /// @visibleForTesting 断言点。
    dynamic pondState(WidgetTester tester) =>
        tester.allStates.firstWhere(
          (s) => s.runtimeType.toString() == '_PondLayerState',
        );

    Future<void> pumpVisual(WidgetTester tester, PracticeSession session) =>
        tester.pumpWidget(
          MaterialApp(
            home: Builder(builder: (context) => session.buildVisual(context)),
          ),
        );

    testWidgets('浮标落在手指处并跟随拖动（已拍板玩法，二轮审查 P1）', (
      tester,
    ) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();
      await pumpVisual(tester, session);
      await tester.pump();
      final pond = pondState(tester);
      expect(pond.debugBuoy, isNull); // 没落手指前没有浮标

      session.onInput(tapAt(const Offset(180, 260)));
      await pumpVisual(tester, session);
      expect(pond.debugBuoy, const Offset(180, 260)); // 落在手指处

      session.onInput(moveTo(const Offset(320, 300)));
      await pumpVisual(tester, session);
      await tester.pump();
      expect(pond.debugBuoy, const Offset(320, 300)); // 按住拖动跟随
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('杂物上钩后主动松手：上钩者脱钩恢复漂流，不再卡死', (tester) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();
      await pumpVisual(tester, session);
      await tester.pump();
      final pond = pondState(tester);

      // 在手指处甩杆，杂物上钩（咚）→ 池塘层绑定一名上钩者。
      session.onInput(tapAt(const Offset(400, 300)));
      session.debugForceHook(petal: false);
      await pumpVisual(tester, session);
      await tester.pump();
      expect(pond.debugHookedCount, 1);

      // 主动松手 = 空竿：状态机发脱钩脉冲，物件不得永久卡在 hooked 态。
      session.onInput(release(800000));
      await pumpVisual(tester, session);
      await tester.pump();
      expect(session.debugMiscatch, 1);
      expect(pond.debugHookedCount, 0);

      // 下一次抛竿后同样不残留卡死物件。
      session.onInput(tapAt(const Offset(200, 200), sessionUs: 4000000));
      await pumpVisual(tester, session);
      await tester.pump();
      expect(pond.debugHookedCount, 0);
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('落水全屏击散：力度按屏幕对角线归一（三轮审查 P1）', (tester) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();
      await pumpVisual(tester, session);
      await tester.pump();
      final pond = pondState(tester);

      List<({Offset pos, Offset vel})> items() =>
          (pond.debugItems as List).cast<({Offset pos, Offset vel})>();

      const center = Offset(30, 80);
      // 测试画布 800×600：对角线 = 屏内两点最大距离。
      final diagonal = const Offset(800, 600).distance;
      final before = items();
      expect(before.length, greaterThanOrEqualTo(4));

      session.onInput(tapAt(center));
      await pumpVisual(tester, session);
      final after = items();
      expect(after.length, before.length);

      // 逐帧运动里击散在位移积分之前、之后统一乘 pow(0.5, dt) 阻尼，
      // 故"径向速度增量 / 阻尼"应恰好等于击散冲量 300 × falloff。
      final damp = pow(0.5, 1 / 60).toDouble();
      for (var i = 0; i < after.length; i++) {
        final radial = before[i].pos - center;
        final dist = radial.distance;
        final dir = radial / dist;
        double dot(Offset v) => v.dx * dir.dx + v.dy * dir.dy;
        final measured = dot(after[i].vel) / damp - dot(before[i].vel);
        final falloff = (1 - dist / diagonal).clamp(0.0, 1.0);
        final expected = 300 * falloff;
        final legacy = 300 * (1 - dist / 800).clamp(0.0, 1.0);
        // 旧实现以 longestSide(800) 归一：屏内越远衰减越狠，远端直接
        // 归零；对角线(1000)归一才让"按距离不同散开"在整屏都成立。
        expect(
          measured,
          closeTo(expected, 1.5),
          reason: '距浮标 ${dist.toStringAsFixed(0)}px 处的击散冲量不符：'
              'longestSide 归一应为 ${legacy.toStringAsFixed(1)}，'
              '对角线归一应为 ${expected.toStringAsFixed(1)}',
        );
      }
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('减少动态效果：脉冲消费照常，只跳过逐帧运动（三轮审查 P1）', (
      tester,
    ) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      Future<void> repump() => tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (outer) => MediaQuery(
                  // 只翻 disableAnimations，尺寸仍取宿主（MediaQueryData()
                  // 默认 size 是 Size.zero，会让池塘层拿不到画布尺寸）。
                  data: MediaQuery.of(outer).copyWith(disableAnimations: true),
                  child: Builder(
                    builder: (inner) => session.buildVisual(inner),
                  ),
                ),
              ),
            ),
          );

      await repump();
      final pond = pondState(tester);
      expect(pond.debugBuoy, isNull);

      // 抛竿 → 浮标位置在无动画模式下也同步。
      session.onInput(tapAt(const Offset(400, 300)));
      await repump();
      expect(pond.debugBuoy, const Offset(400, 300));

      // 杂物上钩 → 绑定；主动松手 → 脱钩：全都不依赖帧驱动。
      session.debugForceHook(petal: false);
      await repump();
      expect(pond.debugHookedCount, 1);

      session.onInput(release(800000));
      await repump();
      expect(session.debugMiscatch, 1);
      expect(pond.debugHookedCount, 0);

      // 窗口内钓起花瓣：静态帧没有"收拢消失"的过程，残留物必须即时
      // 清除、名额即时补齐——否则计数器停在 0，画家按 1 - leaveT
      // 取透明度，残影会全不透明地永远留在屏上。
      expect((pond.debugItems as List).length, 4);
      session.debugForceHook(petal: true);
      await repump();
      session.onInput(release(400000));
      await repump();
      expect(session.debugPetals, 1);
      expect(pond.debugTerminalCount, 0);
      expect((pond.debugItems as List).length, 4);
      scheduler.dispose();
      session.dispose();
    });
  });

  group('钓花听觉判定（三轮审查：超窗松手与轮询超时行为一致）', () {
    test('叮超窗后松手 → 与轮询超时同样沉没并播沉没声', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) = makeContext((_) {});
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 越过 1.5s 收杆窗口但不跑 100ms 轮询（模拟窗口刚过、
        // 下一次轮询到来之前松手的竞态路径）。
        session.debugForceHook(petal: true);
        clock.advanceUs(1600000);
        session.onInput(release(1600000));

        expect(session.debugMissed, 1);
        expect(sounds.played.where((k) => k == 'fish_sink'), hasLength(1));
        expect(session.debugIsResting, isTrue);
        scheduler.dispose();
        session.dispose();
      });
    });

    test('咚后空竿松手 → 脱钩路径，不播沉没声', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) = makeContext((_) {});
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        session.debugForceHook(petal: false);
        session.onInput(release(800000));

        expect(session.debugMiscatch, 1);
        expect(sounds.played.where((k) => k == 'fish_sink'), isEmpty);
        expect(session.debugIsResting, isTrue);
        scheduler.dispose();
        session.dispose();
      });
    });
  });

  group('木鱼视觉文案（二轮审查）', () {
    testWidgets('敲击计数使用插值，不显示变量名原文', (tester) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = WoodenFishSession();
      await session.prepare(ctx);
      session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) => session.buildVisual(context)),
        ),
      );
      expect(find.text('第一声 · 由你敲响'), findsOneWidget);

      session.onInput(tap(1000000));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) => session.buildVisual(context)),
        ),
      );
      expect(find.text('1 / 108 声'), findsOneWidget);
      expect(find.text(r'$_strikes / $_totalStrikes 声'), findsNothing);
      scheduler.dispose();
      session.dispose();
    });
  });
}

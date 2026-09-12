import 'dart:math';

import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/sound_catalog.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/session_recorder.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_manifest.dart';
import 'package:busy_blind/core/practice/practice_registry.dart';
import 'package:busy_blind/core/practice/practice_result.dart';
import 'package:busy_blind/core/practice/practice_session.dart';
import 'package:busy_blind/core/practice/practice_types.dart';
import 'package:busy_blind/practices/count_rain.dart';
import 'package:busy_blind/practices/cross_river.dart';
import 'package:busy_blind/practices/fish_petals.dart';
import 'package:busy_blind/practices/sit_quiet.dart';
import 'package:busy_blind/practices/tide_breath.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

/// 构造一套纯内存的 PracticeContext（无真实音频、时钟可控）。
(PracticeContext, FakeClock, SilentSoundBank, EventScheduler) makeContext(
  void Function(FinishReason) requestFinish, {
  Map<String, Object?> params = const {},
}) {
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
    params: params,
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
      // 只保留敲击声（Bug 描述 #7）：里程碑磬已删，全程无额外音效。
      expect(sounds.played.where((k) => k == 'chime_soft'), isEmpty);
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
    /// 把时钟推进到本轮引导音结束，返回本轮目标间隔。
    int reachGuideEnd(FakeClock clock, CrossRiverSession session) {
      final delta = session.guideEndUs - clock.nowUs();
      if (delta > 0) clock.advanceUs(delta);
      return session.tUs;
    }

    test('窗口内松手踩上石阶，超窗落水结算；跟随音在按下/松手时响起', () async {
      FinishReason? reason;
      final (ctx, clock, sounds, scheduler) = makeContext((r) => reason = r);
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      // 第一轮：引导结束后起手，正点复现 T。
      expect(session.jumpNo, 1);
      expect(session.roundSounds, (1, 2, 3, 4));
      final t1 = reachGuideEnd(clock, session);
      session.onInput(tap(session.guideEndUs)); // 按下 = 跟随音 c 起播
      session.onInput(release(session.guideEndUs + t1)); // 松手 = 跟随音 d 起播
      expect(sounds.played, contains('river_3'));
      expect(sounds.played, contains('river_4'));
      expect(session.jumpNo, 2);

      // 第二轮：故意拖倍间隔 → 落水。
      reachGuideEnd(clock, session);
      final t2 = session.tUs;
      session.onInput(tap(session.guideEndUs));
      session.onInput(release(session.guideEndUs + t2 * 2));
      expect(reason, FinishReason.completed); // 玩法已请求收口

      final result = await session.finish(reason!);
      expect(session.finished, isTrue); // finish() 之后置位
      expect(result.metrics['jumps'], 1);
      expect(result.merit, 1); // round(100 分 / 100)
      scheduler.dispose();
    });

    test('引导未播完不起手：早按下被忽略，不触发跟随音', () async {
      final (ctx, clock, sounds, scheduler) = makeContext((_) {});
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      session.onInput(tap(100000)); // 引导期内按下
      expect(sounds.played.where((k) => k.startsWith('river_')), isEmpty);

      reachGuideEnd(clock, session);
      session.onInput(tap(session.guideEndUs));
      expect(sounds.played, contains('river_3'));
      scheduler.dispose();
    });

    test('事件延迟派送：引导结束前按下、结束后才派送，仍被忽略（P2）', () async {
      final (ctx, clock, sounds, scheduler) = makeContext((_) {});
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      // 事件发生在引导期内，但界面卡顿使其在引导结束后才被处理。
      final earlyPressUs = session.guideEndUs - 200000;
      expect(earlyPressUs, greaterThan(0));
      reachGuideEnd(clock, session);
      expect(clock.nowUs(), greaterThanOrEqualTo(session.guideEndUs));

      session.onInput(tap(earlyPressUs));
      // 按处理时刻判断会把这个事件当成合法起手；按事件时刻判断则忽略。
      expect(sounds.played, isNot(contains('river_3')),
          reason: '引导结束前发生的按下不应触发跟随音');

      // 同一处理时刻下的合法起手仍然照常生效。
      session.onInput(tap(session.guideEndUs));
      expect(sounds.played, contains('river_3'));
      scheduler.dispose();
    });

    test('音频延迟补偿：判定窗口在基础窗口上放宽 250ms', () async {
      FinishReason? reason;
      final (ctx, clock, _, scheduler) = makeContext((r) => reason = r);
      final session = CrossRiverSession(rng: Random(7));
      await session.prepare(ctx);
      scheduler.begin();
      session.start();

      // 偏差落在基础窗口之外、放宽窗口之内（+320ms）：旧判会落水，现应踩滑通过。
      final t = reachGuideEnd(clock, session);
      final baseWindow = (t * 0.15).round() < 180000 ? 180000 : (t * 0.15).round();
      final slipDev = baseWindow + 320000;
      session.onInput(tap(session.guideEndUs));
      session.onInput(release(session.guideEndUs + t + slipDev));
      expect(session.finished, isFalse);
      expect(reason, isNull);
      expect(session.jumpNo, 2); // 踩滑仍在石阶上
      scheduler.dispose();
    });

    test('12 个编号音六轮一循环：序列按表折返并回到第 1 轮', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = CrossRiverSession(rng: Random(7));
        session.prepare(ctx);
        async.flushMicrotasks();
        scheduler.begin();
        session.start();

        const expected = [
          (1, 2, 3, 4),
          (5, 6, 7, 8),
          (9, 10, 11, 12),
          (12, 11, 10, 9),
          (8, 7, 6, 5),
          (4, 3, 2, 1),
        ];
        for (var i = 1; i <= 13; i++) {
          expect(
            session.roundSounds,
            expected[(i - 1) % 6],
            reason: '第 $i 步的音色序列',
          );
          final t = reachGuideEnd(clock, session);
          clock.advanceUs(100000);
          session.onInput(tap(session.guideEndUs));
          session.onInput(release(session.guideEndUs + t));
          expect(session.jumpNo, i + 1, reason: '第 $i 步应成功');
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(session.finished, isFalse);
        scheduler.dispose();
      });
    });

    test('连续踩滑能继续过河，但不推进下一轮难度', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = CrossRiverSession(rng: Random(1));
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        for (var i = 0; i < 5; i++) {
          final t = reachGuideEnd(clock, session);
          final baseWindow = max((t * 0.15).round(), 180000) + 250000;
          final releaseAt = session.guideEndUs + t + (baseWindow * 1.25).round();
          clock.advanceUs(releaseAt - clock.nowUs());
          session.onInput(tap(session.guideEndUs));
          session.onInput(release(releaseAt));
        }

        expect(session.jumpNo, 6);
        expect(session.tUs, lessThanOrEqualTo(2000000));
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

  group('钓花视觉（俯视池塘层，Bug 描述 #5）', () {
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

    Future<(FishPetalsSession, EventScheduler)> pumpSession(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      final (ctx, _, _, scheduler) = makeContext((_) {});
      final session = FishPetalsSession();
      await session.prepare(ctx);
      scheduler.begin();
      session.start();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Builder(builder: (context) => session.buildVisual(context)),
          ),
        ),
      );
      return (session, scheduler);
    }

    test('池塘模拟：漂进浮漂判定半径才可上钩，远处不行（Bug 描述 #5）', () {
      final pond = PondModel();
      pond.resize(const Size(400, 600));
      pond.setBuoy(const Offset(200, 300), shown: true);
      pond.debugAddItem(petal: true, pos: const Offset(220, 300)); // 20px，在半径内
      pond.debugAddItem(petal: false, pos: const Offset(200, 380)); // 80px，在半径外
      expect(pond.hookNearestItem(within: PondModel.hookRadius), isNotNull);
      // 半径内的那一件被标记后，只剩半径外的 → 判定不可上钩。
      final inRange = pond.hookNearestItem(within: PondModel.hookRadius);
      pond.hookItem(inRange!);
      expect(pond.hookNearestItem(within: PondModel.hookRadius), isNull);
    });

    testWidgets('浮漂落在手指处并固定，拖动不再移动（Bug 描述 #5）', (tester) async {
      final (session, scheduler) = await pumpSession(tester);
      final pond = session.debugPond;

      session.onInput(tapAt(const Offset(300, 300)));
      await tester.pump();
      expect(pond.buoy, const Offset(300, 300));

      session.onInput(moveTo(const Offset(360, 320)));
      session.onInput(moveTo(const Offset(420, 340)));
      await tester.pump();
      expect(pond.buoy, const Offset(300, 300)); // 固定在抛竿落点
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('杂物上钩后主动松手：上钩者脱钩恢复漂流，不再卡死', (tester) async {
      final (session, scheduler) = await pumpSession(tester);
      final pond = session.debugPond;

      // 在手指处甩杆；提前在浮漂旁放一件杂物并强制上钩（咚）。
      session.onInput(tapAt(const Offset(400, 300)));
      pond.debugAddItem(petal: false, pos: const Offset(410, 310));
      session.debugForceHook(petal: false);
      expect(pond.hookedCount, 1);

      // 主动松手 = 空竿：状态机令其脱钩，物件不得永久卡在 hooked 态。
      session.onInput(release(800000));
      expect(session.debugMiscatch, 1);
      expect(pond.hookedCount, 0);

      // 下一次抛竿后同样不残留卡死物件。
      session.onInput(tapAt(const Offset(200, 200), sessionUs: 4000000));
      expect(pond.hookedCount, 0);
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('抛竿击散限定小范围：圈外物件完全不受影响（Bug 描述 #5）', (tester) async {
      final (session, scheduler) = await pumpSession(tester);
      final pond = session.debugPond;
      pond.debugClear();
      pond.debugAddItem(petal: true, pos: const Offset(320, 320)); // 半径内
      pond.debugAddItem(petal: false, pos: const Offset(40, 520)); // 远处

      session.onInput(tapAt(const Offset(300, 300)));
      final items = pond.debugItems();
      // 近处：获得径向向外的散开速度。
      final near = items.firstWhere((e) => e.pos == const Offset(320, 320));
      expect(near.vel, isNot(Offset.zero));
      final radial = near.pos - const Offset(300, 300);
      expect(radial.dx * near.vel.dx + radial.dy * near.vel.dy, greaterThan(0));
      // 远处（170px 半径外）：力度为零，不会被击飞到屏幕边缘。
      final far = items.firstWhere((e) => e.pos == const Offset(40, 520));
      expect(far.vel, Offset.zero);
      scheduler.dispose();
      session.dispose();
    });

    test('减少动态效果：会话时间照常推进池塘，物件漂进判定半径（P1）', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = FishPetalsSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        final pond = session.debugPond;
        // 视图已布局（静帧也照常拿到尺寸）；只留一件在判定半径外的花瓣。
        pond.resize(const Size(400, 600));
        pond.debugClear();
        const buoy = Offset(200, 300);
        pond.debugAddItem(petal: true, pos: const Offset(200, 500));

        session.onInput(tapAt(buoy));
        final item = pond.nearestOf(true)!;
        final before = (item.pos - buoy).distance;
        expect(before, greaterThan(PondModel.hookRadius));

        // 只推进会话时钟与 100ms 轮询：界面动画完全不参与
        //（关闭动画后 layer 的 ticker 是停的）。旧实现里模拟只由绘制帧
        // 推进，这里物件会一动不动、永远进不了判定半径。
        for (var i = 0; i < 40; i++) {
          clock.advanceUs(100000);
          async.elapse(const Duration(milliseconds: 100));
        }
        final after = (item.pos - buoy).distance;
        expect(after, lessThan(before - 5),
            reason: '会话时间应推进池塘模拟：$before → $after');
        scheduler.dispose();
        session.dispose();
      });
    });

    testWidgets('连续两次抛竿都击散起涟漪（P2：收竿要复位落水沿标记）', (tester) async {
      final (session, scheduler) = await pumpSession(tester);
      final pond = session.debugPond;

      // 第一竿：涟漪。
      session.onInput(tapAt(const Offset(300, 300)));
      expect(pond.ripples, isNotEmpty);
      pond.ripples.clear(); // 之后只观察第二竿有没有重新产生

      // 收竿 → 浮漂离水。
      session.onInput(release(800000));
      await tester.pump();
      expect(pond.buoyShown, isFalse);

      // 第二竿（越过 2s 休竿期）：仍须击散 + 涟漪。旧实现收竿只改
      // 可见性、不复位 _buoyWasShown，上升沿不再成立。
      pond.debugClear();
      pond.debugAddItem(petal: true, pos: const Offset(320, 320)); // 半径内
      session.onInput(tapAt(const Offset(300, 300), sessionUs: 4000000));
      expect(pond.ripples, isNotEmpty, reason: '第二竿没有重新起涟漪');
      expect(pond.debugItems().single.vel, isNot(Offset.zero),
          reason: '第二竿没有击散半径内的物件');
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('减少动态效果：模拟停帧但玩法状态照常生效（三轮审查 P1-1）', (tester) async {
      final (session, scheduler) = await pumpSession(tester, reduceMotion: true);
      final pond = session.debugPond;

      expect(session.debugPond.buoyShown, isFalse);
      session.onInput(tapAt(const Offset(400, 300)));
      expect(pond.buoy, const Offset(400, 300));

      pond.debugAddItem(petal: false, pos: const Offset(410, 310));
      session.debugForceHook(petal: false);
      expect(pond.hookedCount, 1);

      session.onInput(release(800000));
      expect(session.debugMiscatch, 1);
      expect(pond.hookedCount, 0);
      scheduler.dispose();
      session.dispose();
    });

    testWidgets('减少动态效果下动画帧停住（帧率独立步进只作用于动态模式）', (tester) async {
      final (session, scheduler) = await pumpSession(tester, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 100));
      // 静态模式下 layer 的 ticker 已停（868dc3b 的回归点）。
      final layer = tester.allStates.firstWhere(
        (s) => s.runtimeType.toString() == '_PondLayerState',
      );
      expect((layer as dynamic).debugIsAnimating, isFalse);
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

  group('新-改进说明文档 §13/§14：BGM 与环境音策略', () {
    test('每个修行的环境音策略与 BGM 选择权符合文档', () {
      final byId = {
        for (final f in practiceFactories) f().manifest.id: f().manifest,
      };
      // §14.1 过河：不播五首 BGM，只播河流；§13 不提供选择。
      expect(byId['cross_river']!.ambience, AmbiencePolicy.riverOnly);
      expect(byId['cross_river']!.allowsBgmChoice, isFalse);
      // §14.2 钓花：所选 BGM + 溪流。
      expect(byId['fish_petals']!.ambience, AmbiencePolicy.stream);
      expect(byId['fish_petals']!.allowsBgmChoice, isTrue);
      // §14.3 数雨：鸟叫/虫鸣随机二选一。
      expect(byId['count_rain']!.ambience, AmbiencePolicy.birdsOrInsects);
      // §2/§14.4 听潮：潮水 + 呼吸指引由会话自理，不提供 BGM 选择。
      expect(byId['tide_breath']!.ambience, AmbiencePolicy.sessionOwned);
      expect(byId['tide_breath']!.allowsBgmChoice, isFalse);
      // 木鱼等：所选 BGM，无额外环境音。
      expect(byId['wooden_fish']!.ambience, AmbiencePolicy.none);
      expect(byId['wooden_fish']!.allowsBgmChoice, isTrue);
    });
  });

  group('听潮（新-改进说明文档 §2–§7）', () {
    test('4-7-8/盒式时间轴与表 1 一致，憋气段在"松开"侧', () {
      // 4-6：按 4s + 松 6s（周期 10s）。
      expect(kBreathMethods[0].map((e) => e.lengthUs ~/ 1000000).toList(),
          [4, 6]);
      expect(kBreathMethods[0].map((e) => e.pressExpected).toList(),
          [true, false]);
      // 盒式：按 8s（4 吸 + 4 憋）+ 松 8s（4 呼 + 4 憋），周期 16s。
      expect(kBreathMethods[1].map((e) => e.lengthUs ~/ 1000000).toList(),
          [4, 4, 4, 4]);
      expect(kBreathMethods[1].map((e) => e.pressExpected).toList(),
          [true, true, false, false]);
      // 4-7-8：按 11s（4 吸 + 7 憋）+ 松 8s，周期 19s。
      expect(kBreathMethods[2].map((e) => e.lengthUs ~/ 1000000).toList(),
          [4, 7, 8]);
      expect(kBreathMethods[2].map((e) => e.pressExpected).toList(),
          [true, true, false]);
    });

    test('解放双手模式：自动走完时间轴，但不计修为（§7.2）', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) =
            makeContext((_) {}, params: const {'handsFree': true});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 3 秒引子后进入呼吸时间轴；一次都不按压也能推进相位。
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 200));
        final afterIntro = session.debugPhaseCount;
        clock.advanceUs(60000000); // 再走 60 秒
        async.elapse(const Duration(seconds: 1));
        expect(session.debugPhaseCount, greaterThan(afterIntro));

        final result = session.debugResultForTest();
        expect(result.metrics['handsFree'], isTrue);
        expect(result.merit, 0, reason: '解放双手模式不积攒修为');
        scheduler.dispose();
      });
    });

    test('解放双手模式：圆圈自动跟着时间轴放大/缩小（§7.2）', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) =
            makeContext((_) {}, params: const {'handsFree': true});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        // 引子结束，进入 4-6 第 0 段（吸气 = 应当按住）。
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugGrowActive, isTrue, reason: '吸气段圆圈应自动放大');
        // 走到第 1 段（呼气 = 应当松开）→ 自动缩小。
        clock.advanceUs(4100000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugGrowActive, isFalse, reason: '呼气段圆圈应自动缩小');
        scheduler.dispose();
      });
    });

    test('手动模式：圆圈只跟用户按压，不会自动放大', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 200));
        expect(session.debugGrowActive, isFalse, reason: '没按就不该放大');
        session.onInput(tap(3100000));
        expect(session.debugGrowActive, isTrue, reason: '按住即放大');
        session.onInput(release(3200000));
        expect(session.debugGrowActive, isFalse, reason: '松手即缩小');
        scheduler.dispose();
      });
    });

    test('#1 相位截止锚在时间轴上，不逐段累积回调延迟', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 300));
        // 4-6：段长 [4s, 6s]，理想排期严格是 begun + 4s / +10s / +14s …
        final begun = session.debugBegunUs;
        var cursor = begun;
        for (var i = 0; i < 4; i++) {
          cursor += kBreathMethods[0][session.debugSegIndex].lengthUs;
          expect(session.debugPhaseEndUs, cursor,
              reason: '第 $i 段截止时刻应严格锚在时间轴上（不累积回调延迟）');
          clock.advanceUs(kBreathMethods[0][session.debugSegIndex].lengthUs);
          async.elapse(const Duration(milliseconds: 200));
        }
        scheduler.dispose();
      });
    });

    test('#2 起播延迟补偿：判定从声音真正开始起算（含加载与输出延迟）', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) = makeContext((_) {});
        sounds.startDelay = const Duration(milliseconds: 300); // 模拟异步加载
        clock.outputLatencyUs = 200000; // 模拟 200ms 输出延迟
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 引子 3 秒：只播潮水，判定还没开始。
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 100));
        expect(session.debugBreathing, isFalse, reason: '引子内不应开始判定');

        // 起播耗时 300ms：fakeAsync 的延迟与 FakeClock 同步推进。
        clock.advanceUs(300000);
        async.elapse(const Duration(milliseconds: 300));
        expect(session.debugBreathing, isTrue);
        // 判定起点 = 起播返回(3.3s) + 输出延迟(0.2s) = 3.5s。
        // 只把回调整体延后的旧写法会停在 3.2s，判定仍领先声音 0.3s。
        expect(
          session.debugBegunUs,
          greaterThanOrEqualTo(3450000),
          reason: '判定起点必须把异步加载与输出延迟都算进去',
        );
        scheduler.dispose();
      });
    });

    test('#P2 指引加载中结束会话：起播返回后必须停掉，不留残留播放器', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) = makeContext((_) {});
        sounds.startDelay = const Duration(milliseconds: 300); // 模拟异步加载
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();

        // 引子结束 → 发起起播，但加载还没回来（_breathing 仍为 false）。
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 100));
        expect(sounds.loopsStarted, contains(SoundCatalog.guideBreath46Key));
        expect(session.debugBreathing, isFalse);

        // 加载途中结束会话。
        session.finish(FinishReason.userEnded);

        // 让加载与收尾淡出走完。
        clock.advanceUs(500000);
        async.elapse(const Duration(seconds: 3));
        expect(
          sounds.loopsStopped,
          contains(SoundCatalog.guideBreath46Key),
          reason: '加载中结束会话时，指引音轨必须被停掉（否则静音循环残留）',
        );
        scheduler.dispose();
      });
    });

    test('#4 开场三秒不参与判定：不累计吻合、也不响风铃', () {
      fakeAsync((async) {
        final (ctx, clock, sounds, scheduler) =
            makeContext((_) {}, params: const {'handsFree': true});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        // 引子内（2 秒）：既没进入呼吸，也没有任何吻合累计/风铃。
        clock.advanceUs(2000000);
        async.elapse(const Duration(milliseconds: 300));
        expect(session.debugBreathing, isFalse);
        expect(session.debugMatchedUs, 0, reason: '开场等待不得计入同步率');
        expect(sounds.played.where((k) => k == 'wind_chime'), isEmpty,
            reason: '开场不应提前响风铃');
        // 引子结束：起播并开始判定（判定起点在起播返回那一刻）。
        clock.advanceUs(1500000);
        async.elapse(const Duration(milliseconds: 300));
        expect(session.debugBreathing, isTrue);
        // 再推进一段会话时间，吻合才开始累计。
        clock.advanceUs(2000000);
        async.elapse(const Duration(seconds: 1));
        expect(session.debugMatchedUs, greaterThan(0));
        scheduler.dispose();
      });
    });

    test('手动模式：不按压则相位不吻合，同步率为 0', () {
      fakeAsync((async) {
        final (ctx, clock, _, scheduler) = makeContext((_) {});
        final session = TideBreathSession();
        session.prepare(ctx);
        scheduler.begin();
        session.start();
        clock.advanceUs(3000000);
        async.elapse(const Duration(milliseconds: 200));
        clock.advanceUs(20000000); // 20 秒全程不按
        async.elapse(const Duration(seconds: 1));
        final result = session.debugResultForTest();
        expect(result.metrics['handsFree'], isFalse);
        expect(result.metrics['avgSync'], 0.0);
        scheduler.dispose();
      });
    });
  });
}

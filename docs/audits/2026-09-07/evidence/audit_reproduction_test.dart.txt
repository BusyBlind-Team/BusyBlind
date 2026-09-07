// Audit evidence: assertions intentionally describe the observed defects.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_host.dart';
import 'package:busy_blind/core/practice/practice_types.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/domain/achievements.dart';
import 'package:busy_blind/features/me/me_page.dart';
import 'package:busy_blind/features/monk/achievements_page.dart';
import 'package:busy_blind/features/monk/meditation_page.dart';
import 'package:busy_blind/features/monk/sign_page.dart';
import 'package:busy_blind/features/tutorial/calibration_page.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:busy_blind/practices/count_rain.dart';
import 'package:busy_blind/practices/fish_petals.dart';
import 'package:busy_blind/practices/tide_breath.dart';
import 'package:busy_blind/practices/cross_river.dart';
import 'package:busy_blind/widgets/petal_icon.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'helpers/fake_clock.dart';
import 'practices_test.dart' as fixtures;

Widget harness(Widget home, AppStore store, {FakeClock? clock, SilentSoundBank? sounds}) => ProviderScope(
  overrides: [storeProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(clock ?? FakeClock()),
    soundBankProvider.overrideWithValue(sounds ?? SilentSoundBank())],
  child: MaterialApp(home: home),
);

class OffsetClock extends FakeClock {
  @override
  int touchToAudioUs(int rawTouchUs) => rawTouchUs - userOffsetUs;
}

class BeatClock extends FakeClock {
  final controller = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> beats(int periodUs) => controller.stream;
}

class AuditPathProvider extends PathProviderPlatform {
  AuditPathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class UpperBoundRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0.5;
}

void main() {
  test('R1: nonzero calibration changes absAudioUs but not gameplay sessionUs', () {
    final clock = OffsetClock()..userOffsetUs = 200000;
    final input = InputCapture(clock).capture(
      const PointerDownEvent(timeStamp: Duration(seconds: 1)), () => 1000000);
    expect(input.absAudioUs, 800000);
    expect(input.sessionUs, 1000000);
  });

  test('R2: paused scheduler advances and fishing anti-idle fires', () {
    fakeAsync((async) {
      FinishReason? reason;
      final (ctx, clock, _, scheduler) = fixtures.makeContext((r) => reason = r);
      final session = FishPetalsSession();
      session.prepare(ctx);
      scheduler.begin();
      session.start();
      scheduler.pause();
      clock.advanceUs(91000000);
      async.elapse(const Duration(milliseconds: 100));
      expect(scheduler.isRunning, isTrue);
      expect(scheduler.nowUs(), 91000000);
      expect(reason, FinishReason.antiIdle);
      scheduler.dispose();
      session.dispose();
    });
  });

  test('R3: no-input cancellation pays wooden fish 6 and rain 5 merit', () async {
    final (ctx, _, _, scheduler) = fixtures.makeContext((_) {});
    scheduler.begin();
    final wooden = WoodenFishSession();
    await wooden.prepare(ctx);
    wooden.start();
    final woodenResult = await wooden.finish(FinishReason.cancelled);
    expect(woodenResult.merit, 6);
    expect(woodenResult.metrics['strikes'], 0);
    expect(kAchievements.firstWhere((a) => a.id == 'muyu_steady').test(
      AchievementEval(store: AppStore.inMemory(), lastResult: woodenResult,
        lastManifest: wooden.manifest)), isTrue);
    final rain = CountRainSession();
    await rain.prepare(ctx);
    final rainResult = await rain.finish(FinishReason.cancelled);
    expect(rainResult.merit, 5);
    scheduler.dispose();
    wooden.dispose();
    rain.dispose();
  });

  testWidgets('R4: store changes do not refresh MePage', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(const MePage(), store));
    expect(find.text('累计修行 0 次 · 修为 0'), findsOneWidget);
    store.addMerit(100);
    await tester.pump();
    expect(store.merit, 100);
    expect(find.text('累计修行 0 次 · 修为 0'), findsOneWidget);
    expect(find.text('累计修行 0 次 · 修为 100'), findsNothing);
  });

  testWidgets('R5: stale fuse button consumes petals twice for one flower', (tester) async {
    final store = AppStore.inMemory();
    for (var i = 0; i < 6; i++) { store.addPetal('sakura'); }
    await tester.pumpWidget(harness(const AchievementsPage(), store));
    await tester.scrollUntilVisible(find.text('合成（3 朵）'), 400);
    await tester.tap(find.text('合成（3 朵）'));
    await tester.pump();
    expect(store.petals['sakura'], 3);
    expect(tester.widget<PetalRow>(find.byType(PetalRow).first).count, 6);
    await tester.tap(find.text('合成（3 朵）'));
    await tester.pump();
    expect(store.petals['sakura'], 0);
    expect(store.flowers, ['sakura']);
  });

  testWidgets('R6: calibration still plays beats after its page is disposed', (tester) async {
    final clock = BeatClock();
    final sounds = SilentSoundBank();
    await tester.pumpWidget(harness(const CalibrationPage(), AppStore.inMemory(), clock: clock, sounds: sounds));
    await tester.tap(find.text('开始校准'));
    await tester.pump();
    clock.controller.add(800000);
    await tester.pump();
    expect(sounds.played.length, 1);
    await tester.pumpWidget(const SizedBox());
    expect(clock.controller.hasListener, isTrue);
    clock.controller.add(1600000);
    expect(sounds.played.length, 2);
    await clock.controller.close();
  });

  testWidgets('R7: leaving sign page within 700ms produces disposed-ref exception', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(const SignPage(), store));
    await tester.tap(find.text('抽签'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 800));
    // Intentionally fails on the unhandled StateError: this is the evidence.
    expect(store.signedToday, isFalse);
  });

  testWidgets('R8: meditation system back skips session persistence', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MeditationPage())),
      child: const Text('open')))), store));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(store.merit, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MeditationPage), findsNothing);
    expect(store.sessions, isEmpty);
  });

  testWidgets('R9: real host credits cancelled empty wooden fish session', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(PracticeHostPage(factory: WoodenFishSession.new), store));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(store.merit, 6);
    expect(store.sessions.single['completed'], false);
    expect(store.isUnlocked('muyu_steady'), true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('R10: sleep-mode finishing exposes an active start button', (tester) async {
    await tester.pumpWidget(harness(PracticeHostPage(factory: TideBreathSession.new,
      params: const {'sleepMode': true}), AppStore.inMemory()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('结束'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('开始（磬响后请闭眼）'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 400)); }
  });

  test('R11: seven cancelled sessions qualify as seven completed sessions', () {
    final store = AppStore.inMemory();
    for (var i = 0; i < 7; i++) {
      store.addSession(practiceId: 'wooden_fish', merit: 0, completed: false, durationMs: 0);
    }
    expect(kAchievements.firstWhere((a) => a.id == 'sessions_7').test(AchievementEval(store: store)), true);
  });

  test('R12: truncated storage silently becomes a new empty account', () async {
    final dir = await Directory.systemTemp.createTemp('fuckthon-audit-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = AuditPathProvider(dir.path);
    try {
      await File('${dir.path}/busy_blind.json').writeAsString('{"merit":1000,"sessions":[');
      final store = await AppStore.load();
      expect(store.merit, 0);
      expect(store.sessionCount, 0);
      expect(store.tutorialDone, false);
    } finally {
      PathProviderPlatform.instance = previous;
      await dir.delete(recursive: true);
    }
  });

  test('R13: five slips still increase the river difficulty', () async {
    final (ctx, clock, _, scheduler) = fixtures.makeContext((_) {});
    final session = CrossRiverSession(rng: UpperBoundRandom());
    await session.prepare(ctx);
    scheduler.begin();
    session.start();
    for (var i = 0; i < 5; i++) {
      final anchor = session.dongAnchorUs;
      final t = session.t1Us;
      final window = max((t * 0.15).round(), 180000);
      final releaseAt = anchor + t + (window * 1.25).round();
      session.onInput(fixtures.tap(anchor));
      clock.advanceUs(releaseAt - clock.nowUs());
      session.onInput(fixtures.release(releaseAt));
    }
    expect(session.jumpNo, 6);
    expect(session.t1Us, greaterThan(2000000));
    scheduler.dispose();
    session.dispose();
  });
}

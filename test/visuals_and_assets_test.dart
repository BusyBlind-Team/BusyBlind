import 'dart:io';


import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/session_recorder.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/audio/sound_catalog.dart';
import 'package:busy_blind/core/practice/practice_registry.dart';
import 'package:busy_blind/core/practice/practice_session.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:busy_blind/widgets/practice_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

/// Golden rasterization differs slightly between Skia on Windows and Linux.
/// Keep the threshold low enough that structural regressions still fail while
/// sub-pixel paint antialiasing does not make CI platform-dependent.
/// Measured cross-host delta for the text-free scenes: ~0.55%.
class _CrossPlatformGoldenComparator extends LocalFileComparator {
  _CrossPlatformGoldenComparator(super.testFile);

  static const double _maxDiffPercent = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final withinTolerance =
        result.passed || result.diffPercent <= _maxDiffPercent;
    result.dispose();
    if (withinTolerance) return true;

    // Delegate genuine failures so Flutter still writes the standard
    // master/test/masked diff images and its familiar diagnostic message.
    return super.compare(imageBytes, golden);
  }
}

void main() {
  final defaultGoldenComparator = goldenFileComparator;
  setUpAll(() {
    if (defaultGoldenComparator is LocalFileComparator) {
      goldenFileComparator = _CrossPlatformGoldenComparator(
        defaultGoldenComparator.basedir.resolve('visuals_and_assets_test.dart'),
      );
    }
  });
  tearDownAll(() => goldenFileComparator = defaultGoldenComparator);

  test('声音目录全部切到 MP3，且总体积至少减少一半', () {
    // 16 个 SFX (mp3) + 5 首 BGM (m4a)。
    expect(SoundCatalog.catalog, hasLength(21));
    expect(
      SoundCatalog.catalog.entries.every(
        (e) =>
            (e.key.startsWith('bgm_') && e.value.endsWith('.m4a')) ||
            (!e.key.startsWith('bgm_') && e.value.endsWith('.mp3')),
      ),
      isTrue,
    );

    var sfxBytes = 0;
    var bgmBytes = 0;
    for (final path in SoundCatalog.catalog.values) {
      final file = File('assets/$path');
      expect(file.existsSync(), isTrue, reason: '缺少音效：${file.path}');
      if (path.startsWith('bgm/')) {
        bgmBytes += file.lengthSync();
      } else {
        sfxBytes += file.lengthSync();
      }
    }
    // 压缩守门只针对 SFX；BGM 是新增环境音乐，单独给 2MB 上限。
    expect(sfxBytes, lessThan(2376370 ~/ 2));
    expect(bgmBytes, lessThan(2 * 1024 * 1024));
    expect(
      Directory('assets/sfx')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav')),
      isEmpty,
    );
  });

  test('玩法输入会递增视觉版本', () async {
    final clock = FakeClock();
    final sounds = SilentSoundBank();
    late final EventScheduler scheduler;
    final recorder = SessionRecorder(() => scheduler.nowUs());
    scheduler = EventScheduler(clock, sounds, recorder: recorder);
    final session = WoodenFishSession();
    final context = PracticeContext(
      clock: clock,
      scheduler: scheduler,
      sounds: sounds,
      recorder: recorder,
      input: InputCapture(clock),
      requestFinish: (_) {},
    );
    await session.prepare(context);
    scheduler.begin();
    session.start();
    final before = session.visualRevision.value;
    session.onInput(
      const InputEvent(
        phase: PointerPhase.down,
        absAudioUs: 1000000,
        sessionUs: 1000000,
        rawTimeStamp: Duration(seconds: 1),
      ),
    );
    expect(session.visualRevision.value, before + 1);
    scheduler.dispose();
    session.dispose();
  });

  testWidgets('六个玩法均提供独立运行场景', (tester) async {
    for (final factory in practiceFactories) {
      final clock = FakeClock();
      final sounds = SilentSoundBank();
      late final EventScheduler scheduler;
      final recorder = SessionRecorder(() => scheduler.nowUs());
      scheduler = EventScheduler(clock, sounds, recorder: recorder);
      final session = factory();
      final context = PracticeContext(
        clock: clock,
        scheduler: scheduler,
        sounds: sounds,
        recorder: recorder,
        input: InputCapture(clock),
        requestFinish: (_) {},
      );
      await session.prepare(context);
      scheduler.begin();
      session.start();

      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: session.buildVisual)),
      );
      expect(find.byType(PracticeScene), findsOneWidget);

      scheduler.dispose();
      session.dispose();
    }
  });

  testWidgets('场景在窄屏、标准手机与横屏下无布局异常', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const sizes = [Size(320, 568), Size(390, 844), Size(844, 390)];
    for (final size in sizes) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      for (final kind in PracticeSceneKind.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: PracticeScene(
              kind: kind,
              title: '修 行',
              subtitle: '闭眼 · 听见当下',
              progress: 0.6,
              active: true,
              count: 7,
              accent: 1,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byKey(ValueKey('practice-scene-${kind.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('减少动态效果时场景保持可读且停止连续动画', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PracticeScene(
            kind: PracticeSceneKind.tideBreath,
            title: '潮 涨 · 吸',
            subtitle: '按住屏幕 · 缓缓吸气',
            active: true,
          ),
        ),
      ),
    );
    expect(find.text('潮 涨 · 吸'), findsOneWidget);
    expect(find.text('按住屏幕 · 缓缓吸气'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('六个运行场景视觉快照', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;

    for (final kind in PracticeSceneKind.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: PracticeScene(
              kind: kind,
              // Keep goldens host-font independent. Functional tests above verify
              // that the production Chinese copy remains visible and readable.
              title: kind.name.toUpperCase(),
              subtitle: 'CLOSE YOUR EYES - LISTEN',
              progress: 0.6,
              active: true,
              count: 7,
              accent: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PracticeScene),
        matchesGoldenFile('goldens/practice_${kind.name}.png'),
      );
    }
  });
  testWidgets('中文命名图片资产与 BGM 可加载', (tester) async {
    await tester.runAsync(() async {
      final images = ['木鱼', '敲木鱼的棒子', '菩提叶', '雨滴'];
      for (final name in images) {
        final data = await rootBundle.load('assets/images/$name.png');
        expect(data.lengthInBytes, greaterThan(0), reason: name);
      }
      final bgm = await rootBundle.load('assets/bgm/bgm_linjian.m4a');
      expect(bgm.lengthInBytes, greaterThan(0));
    });
  });

}
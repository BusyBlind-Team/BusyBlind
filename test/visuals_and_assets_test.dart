import 'dart:io';


import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/session_recorder.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/audio/sound_catalog.dart';
import 'package:busy_blind/core/practice/practice_registry.dart';
import 'package:busy_blind/core/practice/practice_session.dart';
import 'package:busy_blind/domain/petals.dart';
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

  test('声音目录格式与体积守门（含 §14 环境音与呼吸指引）', () {
    // 16 短音效(mp3) + 12 过河编号音(m4a) + 5 BGM(m4a)
    // + 5 环境音(m4a) + 3 呼吸指引(m4a)。
    expect(SoundCatalog.catalog, hasLength(16 + 12 + 5 + 5 + 3));
    // 长音轨（BGM/环境音/指引）与过河编号音一律 AAC(m4a)；短音效保持 mp3。
    expect(
      SoundCatalog.catalog.entries.every(
        (e) =>
            (SoundCatalog.isStreamedKey(e.key) || e.key.startsWith('river_'))
                ? e.value.endsWith('.m4a')
                : e.value.endsWith('.mp3'),
      ),
      isTrue,
    );

    var sfxBytes = 0; // 短音效：压缩守门对象
    var riverBytes = 0;
    var bgmBytes = 0; // 5 首 BGM + 3 条呼吸指引
    var ambBytes = 0; // §14 环境音（约 10 分钟单声道 64k）
    for (final entry in SoundCatalog.catalog.entries) {
      final path = entry.value;
      final file = File('assets/$path');
      expect(file.existsSync(), isTrue, reason: '缺少音效：${file.path}');
      final n = file.lengthSync();
      if (path.startsWith('sfx/amb_')) {
        ambBytes += n;
      } else if (path.startsWith('bgm/')) {
        bgmBytes += n;
      } else if (path.startsWith('sfx/river/')) {
        riverBytes += n;
      } else {
        sfxBytes += n;
      }
    }
    // 压缩守门只针对短 SFX。
    expect(sfxBytes, lessThan(2376370 ~/ 2));
    expect(riverBytes, lessThan(3 * 1024 * 1024));
    // 5 首 BGM（~6.4MB）+ 3 条呼吸指引（~1.1MB）。
    expect(bgmBytes, lessThan(9 * 1024 * 1024));
    // §14：5 条环境音各约 10 分钟、单声道 64k AAC，合计约 24.6MB。
    // 上界守住"裁到 10 分钟 + 单声道"的决定，防止有人把 320k 母带打进来。
    expect(ambBytes, lessThan(30 * 1024 * 1024));
    expect(
      Directory('assets/sfx')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav')),
      isEmpty,
    );
  });

  test('资源注册与预解码分开：BGM 只注册即可做环境循环（复审 R1）', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bank = AudioPlayersSoundBank();
    await bank.register(SoundCatalog.catalog);
    await bank.preload(const {}); // BGM 不进预解码内存池
    final key = SoundCatalog.catalog.keys.firstWhere((k) => k.startsWith('bgm_'));
    // 注册过但未预解码：startLoop 应能查到资产并走到流式播放器创建
    // （测试环境无音频后端，到平台层报缺插件即可）；绝不允许再触发
    // “未预加载音轨”断言——那正是复审 R1 里听潮包络的失效点。
    await expectLater(
      bank.startLoop(key),
      throwsA(isNot(isA<AssertionError>())),
    );
    bank.dispose();
  });

  test('每个花种 id 都能解析到已提交的正式美术（复审 R4）', () {
    for (final species in kFlowerSpecies) {
      final path = flowerArtAsset(species.id);
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '缺少正式美术：$path（花种 ${species.id}）',
      );
    }
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
  testWidgets('图片与 BGM 资产可加载（ASCII 资产名，规避安卓非 ASCII 路径问题）', (tester) async {
    await tester.runAsync(() async {
      final images = ['muyu', 'muyu_stick', 'bodhi_leaf', 'raindrop'];
      for (final name in images) {
        final data = await rootBundle.load('assets/images/$name.png');
        expect(data.lengthInBytes, greaterThan(0), reason: name);
      }
      final bgm = await rootBundle.load('assets/bgm/bgm_liming.m4a');
      expect(bgm.lengthInBytes, greaterThan(0));
    });
  });

  test('Android 主清单声明 INTERNET 权限（修炼报告联网）', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('BGM 曲目解析：无 → null，随机 → 有效曲目，固定 → 对应曲目', () {
    expect(SoundCatalog.resolveTrack(SoundCatalog.bgmTrackNone), isNull);
    final randomPick = SoundCatalog.resolveTrack(SoundCatalog.bgmTrackRandom);
    expect(randomPick, isNotNull);
    expect(
      SoundCatalog.bgmTracks.contains(randomPick),
      isTrue,
      reason: '随机结果必须是曲目表里的一首',
    );
    expect(
      SoundCatalog.resolveTrack(2)?.name,
      SoundCatalog.bgmTracks[2].name,
    );
    // 越界设置按随机处理，不会崩。
    expect(SoundCatalog.resolveTrack(99), isNotNull);
  });

}
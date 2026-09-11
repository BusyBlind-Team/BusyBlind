import 'package:busy_blind/app.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_host.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/monk/sign_page.dart';
import 'package:busy_blind/features/monk/meditation_page.dart';
import 'package:busy_blind/practices/tide_breath.dart';
import 'package:busy_blind/practices/fish_petals.dart';
import 'package:busy_blind/features/me/me_page.dart';
import 'package:busy_blind/practices/sit_quiet.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:busy_blind/practices/cross_river.dart';
import 'package:busy_blind/practices/count_rain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

Widget harness({
  required Widget home,
  AppStore? store,
  FakeClock? clock,
  SilentSoundBank? sounds,
}) {
  return ProviderScope(
    overrides: [
      storeProvider.overrideWith((ref) => store ?? AppStore.inMemory()),
      soundBankProvider.overrideWithValue(sounds ?? SilentSoundBank()),
      clockProvider.overrideWithValue(clock ?? FakeClock()),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('AppShell 三页签 + 僧页 + 修行列表可完整渲染', (tester) async {
    final store = AppStore.inMemory()..addMerit(66); // 居士档位
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) => store),
          soundBankProvider.overrideWithValue(SilentSoundBank()),
          clockProvider.overrideWithValue(FakeClock()),
        ],
        child: const BusyBlindApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 底部三页签。
    expect(find.text('修'), findsWidgets);
    expect(find.text('僧'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);

    // 僧页：等级称号随修为变化（66 → 居士），修为条数字 66 / 200。
    expect(find.text('居士'), findsOneWidget);
    expect(find.text('66 / 200'), findsOneWidget);
    // 四按钮。
    expect(find.text('签'), findsOneWidget);
    expect(find.text('成'), findsOneWidget);
    expect(find.text('禅'), findsOneWidget);
    expect(find.text('友'), findsOneWidget);

    // 滑到左页签「修」：五个修行条目齐全（静坐已按改进列表移除）。
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('静坐'), findsNothing);
    expect(find.text('木鱼'), findsOneWidget);
    expect(find.text('数雨'), findsOneWidget);
    expect(find.text('听潮'), findsOneWidget);
    expect(find.text('钓花'), findsOneWidget);
    expect(find.text('过河'), findsOneWidget);

    // 点开一个修行：居中展开详情与确定/取消。
    await tester.tap(find.text('木鱼'));
    await tester.pumpAndSettle();
    expect(find.text('确定'), findsWidgets); // 每个条目都带详情（默认折叠）
    expect(find.text('取消'), findsWidgets);
  });

  testWidgets('修行运行中触发系统返回 → 拦截为"用户结束"并出结算页', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('wooden_fish');
    await tester.pumpWidget(
      harness(
        home: PracticeHostPage(factory: WoodenFishSession.new),
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    // 开始修行（开场页 → 运行中）。
    await tester.tap(find.textContaining('开始'));
    // 运行画面包含持续氛围动画，不能等待到“完全静止”。
    await tester.pump(const Duration(milliseconds: 16));

    // 模拟系统返回手势/返回键。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // 页面没有退出（仍能找到结算页内容），而是走了正常结算收口。
    expect(find.text('修行中断'), findsOneWidget);
    expect(find.text('回去'), findsOneWidget);
  });

  testWidgets('空木鱼经系统返回会记录中断，但不解锁精准类成就', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('wooden_fish');
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: WoodenFishSession.new), store: store),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('开始'));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(store.sessions.single['completed'], isFalse);
    expect(store.merit, 0);
    expect(store.isUnlocked('muyu_offset5'), isFalse);
  });

  testWidgets('完成修行 → 结算页展示修为与新解锁的成就', (tester) async {
    final clock = FakeClock();
    final store = AppStore.inMemory()..touchLogin();
    await tester.pumpWidget(
      harness(
        home: PracticeHostPage(factory: SitQuietSession.new),
        store: store,
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('开始'));
    await tester.pump(const Duration(milliseconds: 16));

    // 静坐一分钟走完：推进时钟，让调度器触发结算收口。
    clock.advanceUs(61000000);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('修行结束'), findsOneWidget);
    expect(find.text('修为 +1'), findsOneWidget);
    expect(find.textContaining('刹那'), findsOneWidget); // 登录成就可见
    expect(store.isUnlocked('login_1'), isTrue);
    expect(store.isUnlocked('level_langzi'), isTrue); // 浪子档随 1 点修为达成
    // 教程试玩是"静坐"（sit_quiet），不计入打坐（meditation）成就。
    expect(store.isUnlocked('meditation_1'), isFalse);
  });

  testWidgets('背景音乐选"无"：修行仍正常开始（复审 P1）', (tester) async {
    final store = AppStore.inMemory()
      ..markTutorialSeen('wooden_fish')
      ..setBgmSettings(track: -2); // 无背景音乐
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: WoodenFishSession.new), store: store),
    );
    await tester.pumpAndSettle();

    // 点开始后必须真正进入运行态（退出按钮可见），而不是停在开始界面。
    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('退出'), findsOneWidget);
    expect(find.text('开始'), findsNothing);
    expect(find.textContaining('木 鱼'), findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets('钓花宿主：浮漂固定在抛竿落点，拖动不移杆（减少动态效果=$reduced，Bug 描述 #5）', (tester) async {
      final store = AppStore.inMemory()
        ..markTutorialSeen('fish_petals')
        ..setBgmSettings(track: -2);
      await tester.pumpWidget(harness(
        store: store,
        home: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: PracticeHostPage(factory: FishPetalsSession.new),
        )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始'));
      await tester.pump();
      final dynamic pond = (tester.allStates.firstWhere(
        (s) => s.runtimeType.toString() == '_PondLayerState',
      ) as dynamic).debugPond;
      final gesture = await tester.startGesture(const Offset(300, 300));
      await tester.pump();
      expect(pond.buoy, const Offset(300, 300));
      for (final target in [const Offset(360, 320), const Offset(420, 340)]) {
        await gesture.moveTo(target);
        await tester.pump();
        // 浮漂固定在抛竿落点：后续拖动不移杆（Bug 描述 #5）。
        expect(pond.buoy, const Offset(300, 300));
      }
      await gesture.up();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('听潮不播五首 BGM：背景改潮水，无曲名指示（§2/§13）', (tester) async {
    final store = AppStore.inMemory()
      ..markTutorialSeen('tide_breath')
      ..setBgmSettings(track: 2); // 全局选了"风铃"
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: TideBreathSession.new), store: store),
    );
    await tester.pumpAndSettle();

    // §13：听潮不提供 BGM 选择入口（背景固定为潮水）。
    expect(find.textContaining('背景音乐：'), findsNothing);
    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('退出'), findsOneWidget);
    // §2：不再播五首 BGM，所以没有曲名/唱片指示。
    expect(find.text('♪ 风铃'), findsNothing);
  });

  testWidgets('§13：木鱼开始界面提供 BGM 选择，默认随机', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('wooden_fish');
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: WoodenFishSession.new), store: store),
    );
    await tester.pumpAndSettle();
    expect(find.text('背景音乐：随机背景音乐'), findsOneWidget);
  });

  testWidgets('§13：过河不提供 BGM 选择（只播河流，§14.1）', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('cross_river');
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: CrossRiverSession.new), store: store),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('背景音乐：'), findsNothing);
  });

  testWidgets('#3 开始界面改选 BGM 后，按最终选择播放（数雨）', (tester) async {
    final store = AppStore.inMemory()
      ..markTutorialSeen('count_rain')
      ..setBgmSettings(track: 2); // 进入页面时全局是"风铃"
    final sounds = SilentSoundBank();
    await tester.pumpWidget(
      harness(
        home: PracticeHostPage(factory: CountRainSession.new),
        store: store,
        sounds: sounds,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('背景音乐：风铃'), findsOneWidget);

    // 开始前改成"不要背景音乐"（旧实现在进页面时就定死了参数）。
    await tester.tap(find.text('背景音乐：风铃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不要背景音乐'));
    await tester.pumpAndSettle();
    expect(find.text('背景音乐：不要背景音乐'), findsOneWidget);

    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sounds.loopsStarted, isNot(contains('bgm_fengling')),
        reason: '改选"不要"之后不应还播进入页面时的那首');
    expect(sounds.loopsStarted, contains('forest_loop'));
  });

  testWidgets('#2 离开页面时兜底停掉环境音（过河只播河流）', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('cross_river');
    final sounds = SilentSoundBank();
    await tester.pumpWidget(
      harness(
        home: PracticeHostPage(factory: CrossRiverSession.new),
        store: store,
        sounds: sounds,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sounds.loopsStarted, contains('amb_river'));
    expect(sounds.loopsStarted.any((k) => k.startsWith('bgm_')), isFalse,
        reason: '§14.1：过河不播五首 BGM');

    // 结算后立刻返回：渐出定时器会被取消，必须由销毁兜底停止音轨。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(sounds.loopsStopped, contains('amb_river'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('§6：听潮开始界面点击呼吸法展开节奏与难度', (tester) async {
    final store = AppStore.inMemory()..markTutorialSeen('tide_breath');
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: TideBreathSession.new), store: store),
    );
    await tester.pumpAndSettle();
    // 默认选中 4-6：展示它的节奏与难度。
    expect(find.text('4 秒吸气，6 秒呼气'), findsOneWidget);
    expect(find.text('难度低，容易上手'), findsOneWidget);
    // 切到 4-7-8 后换文案。
    await tester.tap(find.text('4-7-8 呼吸'));
    await tester.pump();
    expect(find.text('4 秒吸气，7 秒憋气，8 秒呼气'), findsOneWidget);
    expect(find.text('有一定难度，但放松效果很好'), findsOneWidget);
  });

  testWidgets('抽签动画中离开页面不会读取已卸载的 ref', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(home: const SignPage(), store: store));
    await tester.tap(find.text('抽签'));
    await tester.pumpWidget(const SizedBox());

    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(store.signedToday, isFalse);
  });

  testWidgets('打坐经系统返回也会写入会话并结算成就', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(
      harness(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MeditationPage()),
            ),
            child: const Text('开始打坐'),
          ),
        ),
        store: store,
      ),
    );
    await tester.tap(find.text('开始打坐'));
    await tester.pumpAndSettle();
    // 经过真实的每秒计时，并在五分钟提示时确认在场。
    for (var second = 1; second <= 600; second++) {
      await tester.pump(const Duration(seconds: 1));
      if (second % 300 == 0) {
        await tester.tap(find.text('——你在吗？轻触任意处——'));
        await tester.pump();
      }
    }

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(store.sessions.single['practiceId'], 'meditation');
    expect(store.isUnlocked('meditation_1'), isTrue);
    expect(store.sessions.single['durationMs'], 600000);
    expect(find.byType(MeditationPage), findsNothing);
    expect(find.text('开始打坐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('外部存储更新会刷新已显示的个人页', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(home: const MePage(), store: store));
    expect(find.text('累计修行 0 次 · 修为 0'), findsOneWidget);

    store.addMerit(100);
    await tester.pump();

    expect(find.text('累计修行 0 次 · 修为 100'), findsOneWidget);
  });
}

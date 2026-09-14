import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/audio/sound_catalog.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/tutorial/sound_guide.dart';
import 'package:busy_blind/features/tutorial/tutorial_page.dart';
import 'package:busy_blind/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

Widget tutorialHarness(
  AppStore store, {
  FakeClock? clock,
  SilentSoundBank? sounds,
}) {
  return ProviderScope(
    overrides: [
      storeProvider.overrideWith((ref) => store),
      soundBankProvider.overrideWithValue(sounds ?? SilentSoundBank()),
      clockProvider.overrideWithValue(clock ?? FakeClock()),
    ],
    child: const MaterialApp(home: TutorialPage()),
  );
}

/// 单独挂载「声音的语言」列表（试听生命周期用）。
///
/// 列表本身是 Column，七行都会构建；但试听按钮必须真的在视口内才点得到，
/// 所以把测试视口调高，避免"找到了却点不到"的假失败。
Widget soundGuideHarness(WidgetTester tester, SilentSoundBank sounds) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return ProviderScope(
    overrides: [
      soundBankProvider.overrideWithValue(sounds),
      clockProvider.overrideWithValue(FakeClock()),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SoundGuideList()),
      ),
    ),
  );
}

void main() {
  testWidgets('首启教程两页式：出发提示 → 声音语言 → 进入主界面', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(tutorialHarness(store));
    await tester.pumpAndSettle();

    // ① 出发提示页（Bug 描述 #3 新增）。
    expect(find.text('建议戴上耳机，享受片刻宁静'), findsOneWidget);
    expect(find.text('修行过程中，全程可闭眼'), findsOneWidget);

    // ② 声音语义表：五条声音语言，按 Bug 描述 #3 改名/改描述。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('声音的语言'), findsOneWidget);
    expect(find.text('轻快的筝'), findsOneWidget);
    expect(find.text('沉重的筝'), findsOneWidget);
    expect(find.text('筝的音阶'), findsOneWidget);
    expect(find.text('花瓣/杂物上钩的声音'), findsOneWidget);
    expect(find.textContaining('花瓣/杂物上钩了'), findsOneWidget);
    expect(find.text('木鱼声'), findsOneWidget);
    expect(find.textContaining('一秒一声的节拍'), findsOneWidget);
    // 极轻的磬整项删除；试玩页与校准页不再出现。
    expect(find.textContaining('极轻的磬'), findsNothing);
    expect(find.textContaining('确认你还在'), findsNothing);
    expect(find.text('先坐一分钟'), findsNothing);
    expect(find.textContaining('贴合你的耳朵'), findsNothing);

    await tester.scrollUntilVisible(
      find.byTooltip('试听').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('试听').first);
    await tester.pumpAndSettle();

    // 完成后进入主界面：教程标记持久化。
    await tester.tap(find.text('进入山门'));
    await tester.pumpAndSettle();

    expect(store.tutorialDone, isTrue);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('签'), findsOneWidget);
  });

  testWidgets('教程两页间上一步可回退，进度点随步进切换', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(tutorialHarness(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('声音的语言'), findsOneWidget);

    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('建议戴上耳机，享受片刻宁静'), findsOneWidget);
  });

  testWidgets('弦音试听：离开页面必须停掉长音轨（不能留着一直播）', (tester) async {
    final sounds = SilentSoundBank();
    await tester.pumpWidget(soundGuideHarness(tester, sounds));
    await tester.pumpAndSettle();

    // 弦音是最后一条；先确认七条都渲染出来了，行没被裁掉。
    expect(find.byTooltip('试听'), findsNWidgets(7));
    await tester.tap(find.byTooltip('试听').last);
    await tester.pump();
    expect(sounds.loopsStarted, contains(SoundCatalog.guideBreath478Key));

    // 4 秒片段还没到点就离开页面。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(sounds.loopsStopped, contains(SoundCatalog.guideBreath478Key),
        reason: '离开页面必须立刻停掉正在试听的长音轨，否则会一直播下去');

    // 放掉在途的 4 秒定时器，避免测试结束时报"仍有未完成的计时器"。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('弦音试听：连点两次，上一次的延迟停止不得掐掉新的一段', (tester) async {
    final sounds = SilentSoundBank();
    await tester.pumpWidget(soundGuideHarness(tester, sounds));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('试听').last);
    await tester.pump();
    // 隔 0.5 秒再点一次：两段的"4 秒到点"因此错开。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('试听').last);
    await tester.pump();
    expect(sounds.loopsStarted, hasLength(2));
    expect(sounds.loopsStopped, hasLength(1), reason: '重开前应先停掉上一段');

    // 走到第一段的 4 秒到点之后、第二段到点之前。
    await tester.pump(const Duration(milliseconds: 3600));
    expect(sounds.loopsStopped, hasLength(1),
        reason: '第一次试听的延迟停止把第二次刚点开的那段掐掉了——'
            '必须用代号判断自己是否还是"当前那次试听"');

    // 第二段自己到点后正常收尾。
    await tester.pump(const Duration(milliseconds: 500));
    expect(sounds.loopsStopped, hasLength(2));
  });
}

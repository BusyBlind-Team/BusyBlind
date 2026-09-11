import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
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
    expect(find.text('筝'), findsOneWidget);
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
}

import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/tutorial/tutorial_page.dart';
import 'package:busy_blind/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

Widget tutorialHarness(AppStore store) {
  return ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      soundBankProvider.overrideWithValue(SilentSoundBank()),
      clockProvider.overrideWithValue(FakeClock()),
    ],
    child: const MaterialApp(home: TutorialPage()),
  );
}

void main() {
  testWidgets('首启教程三段式：语义表 → 试玩 → 校准收尾 → 进入主界面', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(tutorialHarness(store));
    await tester.pumpAndSettle();

    // ① 声音语义表：六条声音语言可见，可试听。
    expect(find.text('声音的语言'), findsOneWidget);
    expect(find.text('磬一声'), findsOneWidget);
    expect(find.text('磬两声'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('木鱼声'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('木鱼声'), findsOneWidget);
    await tester.tap(find.byTooltip('试听').first);
    await tester.pumpAndSettle();

    // ② 试玩段：含试玩入口。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('先坐一分钟'), findsOneWidget);
    expect(find.text('试玩一分钟'), findsOneWidget);

    // ③ 校准段：可跳过，直接完成。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('贴合你的耳朵'), findsOneWidget);
    expect(find.textContaining('「我」页随时可以校准'), findsOneWidget);

    await tester.tap(find.text('进入山门'));
    await tester.pumpAndSettle();

    // 教程完成：标记持久化 + 主界面三页签出现。
    expect(store.tutorialDone, isTrue);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('签'), findsOneWidget);
  });

  testWidgets('教程各段上一步可回退，进度点随步进切换', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(tutorialHarness(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('先坐一分钟'), findsOneWidget);

    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('声音的语言'), findsOneWidget);
  });
}

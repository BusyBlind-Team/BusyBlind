import 'package:busy_blind/app.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_host.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/monk/sign_page.dart';
import 'package:busy_blind/practices/sit_quiet.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

Widget harness({required Widget home, AppStore? store, FakeClock? clock}) {
  return ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store ?? AppStore.inMemory()),
      soundBankProvider.overrideWithValue(SilentSoundBank()),
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
          storeProvider.overrideWithValue(store),
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

  testWidgets('抽签动画中离开页面不会读取已卸载的 ref', (tester) async {
    final store = AppStore.inMemory();
    await tester.pumpWidget(harness(home: const SignPage(), store: store));
    await tester.tap(find.text('抽签'));
    await tester.pumpWidget(const SizedBox());

    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(store.signedToday, isFalse);
  });
}

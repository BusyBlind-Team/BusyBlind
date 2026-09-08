import 'package:busy_blind/app.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_host.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/monk/sign_page.dart';
import 'package:busy_blind/features/monk/meditation_page.dart';
import 'package:busy_blind/practices/tide_breath.dart';
import 'package:busy_blind/features/me/me_page.dart';
import 'package:busy_blind/practices/sit_quiet.dart';
import 'package:busy_blind/practices/wooden_fish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

Widget harness({required Widget home, AppStore? store, FakeClock? clock}) {
  return ProviderScope(
    overrides: [
      storeProvider.overrideWith((ref) => store ?? AppStore.inMemory()),
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

    // 滑到左页签「修」：六个修行条目齐全。
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('静坐'), findsOneWidget);
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
    await tester.pumpWidget(
      harness(home: PracticeHostPage(factory: WoodenFishSession.new)),
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

  testWidgets('空木鱼经系统返回会记录中断，但不解锁稳定性成就', (tester) async {
    final store = AppStore.inMemory();
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
    expect(store.isUnlocked('muyu_steady'), isFalse);
  });

  testWidgets('完成修行 → 结算页展示修为与新解锁的成就', (tester) async {
    final clock = FakeClock();
    final store = AppStore.inMemory();
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
    expect(find.textContaining('初入山门'), findsOneWidget); // 首次修行成就可见
    expect(store.isUnlocked('first_session'), isTrue);
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
    expect(store.isUnlocked('meditate_10'), isTrue);
    expect(store.sessions.single['durationMs'], 600000);
    expect(find.byType(MeditationPage), findsNothing);
    expect(find.text('开始打坐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('助眠结算期间不显示可点击的开始按钮', (tester) async {
    await tester.pumpWidget(
      harness(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PracticeHostPage(
                  factory: TideBreathSession.new,
                  params: const {'sleepMode': true},
                ),
              ),
            ),
            child: const Text('进入助眠'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入助眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始（磬响后请闭眼）'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('结束'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('开始（磬响后请闭眼）'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 每一步都会在异步音量调用后安排下一个延迟，逐步推进整个淡出。
    for (var step = 0; step < 11; step++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
    expect(find.byType(PracticeHostPage), findsNothing);
    expect(find.text('进入助眠'), findsOneWidget);
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

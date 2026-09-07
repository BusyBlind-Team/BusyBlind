import 'dart:math';

import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/domain/petals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppStore（本地优先数据层）', () {
    test('修为累加与读取', () {
      final store = AppStore.inMemory();
      expect(store.merit, 0);
      store.addMerit(12);
      store.addMerit(9);
      expect(store.merit, 21);
    });

    test('打坐单日上限 60 点', () {
      final store = AppStore.inMemory();
      final got = store.addMeditationMerit(70);
      expect(got, 60); // 超出部分截断
      expect(store.merit, 60);
      expect(store.addMeditationMerit(1), 0); // 当日已满
      expect(store.merit, 60);
    });

    test('助眠补发：到期才入账', () {
      final store = AppStore.inMemory();
      store.queuePendingMerit(7, now: DateTime.now()); // due = 今天
      expect(store.merit, 0);
      expect(store.takePendingMerit(), 7);
      expect(store.merit, 7);
      expect(store.takePendingMerit(), 0); // 不重复入账

      // 未到期的补发不入账。
      store.queuePendingMerit(
        5,
        now: DateTime.now().add(const Duration(days: 3)),
      );
      expect(store.takePendingMerit(), 0);
      expect(store.merit, 7);
    });

    test('花瓣收集与按档合成（待对齐 #6：4/5/6/8 瓣）', () {
      final store = AppStore.inMemory();
      // 花瓣不足：合不出，也不扣花瓣。
      store.addPetals(3);
      expect(store.craftFlower(4), isNull);
      expect(store.petalCount, 3);

      // 4 瓣档：只可能抽到桂花或丁香。
      store.addPetals(1);
      final drawn = store.craftFlower(4, rng: Random(7));
      expect(drawn, isNotNull);
      expect(drawn!.petals, 4);
      expect(drawn.id, anyOf('osmanthus', 'lilac'));
      expect(store.flowers, contains(drawn.id));
      expect(store.petalCount, 0);
    });

    test('花瓣不分物种：旧版按物种存储的存量迁移为总数', () {
      final migrated = AppStore.applyMigrations({
        'tutorialDone': false,
        'merit': 0,
        'sessions': <Object?>[],
        'petals': {'sakura': 2, 'peach': 3},
      });
      expect(migrated['petals'], 5);
    });

    test('8 瓣档固定产出奇珍莲花；抽取只落在对应档位', () {
      final store = AppStore.inMemory();
      for (var i = 0; i < 5; i++) {
        store.addPetals(8);
        final drawn = store.craftFlower(8, rng: Random(i));
        expect(drawn!.id, 'lotus');
        expect(drawn.rarity, FlowerRarity.legendary);
      }
      // 5 瓣档：只可能出 5 瓣池里的花。
      store.addPetals(5);
      final five = store.craftFlower(5, rng: Random(3))!;
      expect(five.petals, 5);
      expect(five.id, anyOf('peach', 'pear', 'sakura', 'crabapple'));
    });

    test('成就解锁幂等', () {
      final store = AppStore.inMemory();
      expect(store.unlockAchievements(['a', 'b']), ['a', 'b']);
      expect(store.unlockAchievements(['b', 'c']), ['c']);
      expect(store.achievements, ['a', 'b', 'c']);
    });

    test('每日抽签：当日一次，+10 修为（待对齐 #4）', () {
      final store = AppStore.inMemory();
      expect(store.signedToday, isFalse);
      store.recordSign(slipId: 's1', text: '测试签文', fortune: '上签');
      expect(store.signedToday, isTrue);
      expect(store.slips.single['text'], '测试签文');
      expect(store.merit, AppStore.kSignMerit);
    });

    test('修行记录写入与截断', () {
      final store = AppStore.inMemory();
      for (var i = 0; i < 320; i++) {
        store.addSession(
          practiceId: 'wooden_fish',
          merit: 1,
          completed: true,
          durationMs: 1000,
        );
      }
      expect(store.sessionCount, 300); // 上限截断
      expect(store.sessions.last['practiceId'], 'wooden_fish');
    });
  });
}

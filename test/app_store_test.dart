import 'package:busy_blind/data/app_store.dart';
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

    test('花瓣收集与合成（3 朵合一）', () {
      final store = AppStore.inMemory();
      expect(store.fuseFlower('sakura'), isFalse);
      store.addPetal('sakura');
      store.addPetal('sakura');
      expect(store.fuseFlower('sakura'), isFalse);
      store.addPetal('sakura');
      expect(store.fuseFlower('sakura'), isTrue);
      expect(store.flowers, contains('sakura'));
      expect(store.petals['sakura'], 0);
    });

    test('成就解锁幂等', () {
      final store = AppStore.inMemory();
      expect(store.unlockAchievements(['a', 'b']), ['a', 'b']);
      expect(store.unlockAchievements(['b', 'c']), ['c']);
      expect(store.achievements, ['a', 'b', 'c']);
    });

    test('每日抽签：当日一次', () {
      final store = AppStore.inMemory();
      expect(store.signedToday, isFalse);
      store.recordSign(slipId: 's1', text: '测试签文', fortune: '上签');
      expect(store.signedToday, isTrue);
      expect(store.slips.single['text'], '测试签文');
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

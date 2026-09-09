import 'dart:math';
import 'dart:io';

import 'package:busy_blind/core/llm/llm_client.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/domain/petals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

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

    test('背景音乐设置：曲目与音量持久化，音量截断到 0..1', () {
      final store = AppStore.inMemory();
      expect(store.bgmTrackIndex, -1); // 默认随机
      expect(store.bgmVolume, 0.35);
      store.setBgmSettings(track: 2, volume: 1.5);
      expect(store.bgmTrackIndex, 2);
      expect(store.bgmVolume, 1.0);
      store.setBgmSettings(track: -1);
      expect(store.bgmTrackIndex, -1);
      expect(store.bgmVolume, 1.0); // 未改音量保持
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

    test('主存档损坏时从备份恢复并保留损坏文件', () async {
      final dir = await Directory.systemTemp.createTemp('busy-blind-store-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(dir.path);
      try {
        final primary = File('${dir.path}/busy_blind.json');
        await primary.writeAsString('{"merit":1000,"sessions":[');
        await File('${dir.path}/busy_blind.json.bak').writeAsString('{"merit":42}');

        final store = await AppStore.load();

        expect(store.merit, 42);
        expect(store.persistenceError, contains('备份恢复'));
        expect(await primary.exists(), isFalse);
        // 恢复后尚未产生新保存，再次启动仍必须读取备份。
        final reopened = await AppStore.load();
        expect(reopened.merit, 42);
        reopened.addMerit(1);
        expect(await reopened.waitForSave(), isTrue);
        expect((await AppStore.load()).merit, 43);
        expect(
          (await dir.list().toList()).any((entry) => entry.path.contains('.corrupt-')),
          isTrue,
        );
      } finally {
        PathProviderPlatform.instance = previous;
        await dir.delete(recursive: true);
      }
    });

    test('保存保留备份，并允许调用方等待结果', () async {
      final dir = await Directory.systemTemp.createTemp('busy-blind-store-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(dir.path);
      try {
        final primary = File('${dir.path}/busy_blind.json');
        await primary.writeAsString('{"merit":10}');
        final store = await AppStore.load();
        store.addMerit(5);

        expect(await store.waitForSave(), isTrue);
        expect((await primary.readAsString()), contains('"merit":15'));
        expect(
          (await File('${dir.path}/busy_blind.json.bak').readAsString()),
          contains('"merit":10'),
        );
      } finally {
        PathProviderPlatform.instance = previous;
        await dir.delete(recursive: true);
      }
    });

    test('无有效备份时阻止新账户覆盖损坏存档', () async {
      final dir = await Directory.systemTemp.createTemp('busy-blind-store-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(dir.path);
      try {
        final primary = File('${dir.path}/busy_blind.json');
        const corrupted = '{"merit":1000,"sessions":[';
        await primary.writeAsString(corrupted);
        final store = await AppStore.load();
        store.addMerit(1);

        expect(store.persistenceError, contains('未自动覆盖'));
        expect(await store.waitForSave(), isFalse);
        expect(await primary.readAsString(), corrupted);
      } finally {
        PathProviderPlatform.instance = previous;
        await dir.delete(recursive: true);
      }
    });

    test('LLM 配置：默认智谱 GLM 预设、Key 空；保存后可读回', () {
      final store = AppStore.inMemory();
      expect(store.llmConfig.model, 'glm-4-flash');
      expect(store.llmConfig.baseUrl, LlmPresets.glm.baseUrl);
      expect(store.llmReady, isFalse); // Key 为空 → 未就绪

      store.saveLlmConfig(LlmPresets.deepseek.copyWith(apiKey: ' sk-x '));
      expect(store.llmReady, isTrue);
      expect(store.llmConfig.model, 'deepseek-chat');
      expect(store.llmConfig.apiKey, ' sk-x '); // 原样保存，裁剪交给 UI 层
    });

    test('修炼报告：倒序插入、只保留最近 10 份', () {
      final store = AppStore.inMemory();
      for (var i = 1; i <= 12; i++) {
        store.addReport({
          'generatedAt': '2026-09-0${(i % 9) + 1}T10:00:00',
          'source': 'llm',
          'model': 'glm-4-flash',
          'text': '第 $i 份',
        });
      }
      expect(store.reports.length, AppStore.kMaxReports);
      expect(store.reports.first['text'], '第 12 份'); // 最新的在最前
      expect(store.reports.last['text'], '第 3 份'); // 最早的 1、2 份被截掉
    });

    test('reset 清空 LLM 配置与报告', () {
      final store = AppStore.inMemory()
        ..saveLlmConfig(LlmPresets.glm.copyWith(apiKey: 'sk-x'))
        ..addReport({'generatedAt': '2026-09-09T10:00:00', 'text': 'r'});
      store.reset();
      expect(store.llmReady, isFalse);
      expect(store.llmConfig.model, 'glm-4-flash'); // 回到默认预设
      expect(store.reports, isEmpty);
    });
  });
}

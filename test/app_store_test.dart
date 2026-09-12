import 'dart:math';
import 'dart:io';

import 'package:busy_blind/core/llm/llm_client.dart';
import 'package:busy_blind/core/practice/practice_result.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/domain/achievements.dart';
import 'package:busy_blind/domain/petals.dart';
import 'package:busy_blind/practices/tide_breath.dart';
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

    test('花瓣按稀有度收集与合成（新改进意见：70/25/5）', () {
      final store = AppStore.inMemory();
      // 花瓣不足：合不出，也不扣花瓣。
      for (var i = 0; i < 3; i++) {
        store.addPetal(PetalRarity.common);
      }
      expect(store.craftFlower(4, PetalRarity.common), isNull);
      expect(store.petalCountOf(PetalRarity.common), 3);

      // 4 枚常见花瓣 → 常见 4 瓣花（桂花）。
      store.addPetal(PetalRarity.common);
      final drawn = store.craftFlower(4, PetalRarity.common, rng: Random(7));
      expect(drawn, isNotNull);
      expect(drawn!.petals, 4);
      expect(drawn.id, 'osmanthus');
      expect(store.flowers, contains(drawn.id));
      expect(store.petalCountOf(PetalRarity.common), 0);
      // 其他稀有度桶不受影响。
      expect(store.petalCountOf(PetalRarity.rare), 0);
    });

    test('旧版花瓣存量迁移：物种 Map → 总数 → 常见桶（三段链，幂等）', () {
      // v0：物种 Map 存档。
      final migrated = AppStore.applyMigrations({
        'tutorialDone': false,
        'merit': 0,
        'sessions': <Object?>[],
        'petals': {'sakura': 2, 'peach': 3},
        'petalsByRarity': {'common': 0, 'rare': 0, 'legendary': 0},
      });
      // 一段迁移后：总数 5 且已全额计入"常见"桶（第 16 轮修正前
      // 分桶恒为 0，存量被遗弃）。
      expect(migrated['petals'], 0);
      expect(
        (migrated['petalsByRarity'] as Map)['common'],
        5,
      );

      // v1：总数 int 存档 → 直接入桶。
      final migrated2 = AppStore.applyMigrations({
        'tutorialDone': false,
        'merit': 0,
        'sessions': <Object?>[],
        'petals': 5,
        'petalsByRarity': {'common': 0, 'rare': 0, 'legendary': 0},
      });
      expect(migrated2['petals'], 0);
      expect(migrated2['petalsByRarity'], containsPair('common', 5));

      // 幂等：对同一份数据重复迁移不重复累加。
      final again = AppStore.applyMigrations(
        Map<String, Object?>.from(migrated2),
      );
      expect(again['petalsByRarity'], containsPair('common', 5));
    });

    test('8 枚奇珍花瓣固定合成莲花；稀有度不串桶', () {
      final store = AppStore.inMemory();
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 8; j++) {
          store.addPetal(PetalRarity.legendary);
        }
        final drawn = store.craftFlower(8, PetalRarity.legendary, rng: Random(i));
        expect(drawn!.id, 'lotus');
        expect(drawn.rarity, FlowerRarity.legendary);
      }
      // 稀有 5 瓣档：只可能出 5 瓣稀有池里的花（海棠），且不消耗常见桶。
      for (var i = 0; i < 5; i++) {
        store.addPetal(PetalRarity.rare);
      }
      store.addPetal(PetalRarity.common);
      final commonBefore = store.petalCountOf(PetalRarity.common);
      final five = store.craftFlower(5, PetalRarity.rare, rng: Random(3))!;
      expect(five.petals, 5);
      expect(five.id, 'crabapple');
      expect(store.petalCountOf(PetalRarity.common), commonBefore);
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

    test('LLM Key 按服务商分别保存，切换不串用（复审 P1-2）', () {
      final store = AppStore.inMemory();
      store.saveLlmConfig(LlmPresets.glm.copyWith(apiKey: 'glm-key'));
      expect(store.keyForBaseUrl(LlmPresets.glm.baseUrl), 'glm-key');

      // 切到 DeepSeek 且尚未填 Key：不该把智谱的 Key 发给 DeepSeek。
      store.saveLlmConfig(LlmPresets.deepseek.copyWith(apiKey: ''));
      expect(store.llmReady, isFalse);
      expect(store.keyForBaseUrl(LlmPresets.deepseek.baseUrl), '');

      store.saveLlmConfig(LlmPresets.deepseek.copyWith(apiKey: 'ds-key'));
      expect(store.keyForBaseUrl(LlmPresets.glm.baseUrl), 'glm-key');
      expect(store.keyForBaseUrl(LlmPresets.deepseek.baseUrl), 'ds-key');
    });

    test('迁移：升级前已填的 Key 按 baseUrl 播种进 llmKeys', () {
      final migrated = AppStore.applyMigrations({
        'tutorialDone': false,
        'merit': 0,
        'sessions': <Object?>[],
        'petals': 0,
        'llm': {
          'baseUrl': LlmPresets.glm.baseUrl,
          'model': 'glm-4-flash',
          'apiKey': 'legacy-key',
        },
        'llmKeys': <String, String>{},
      });
      expect(
        migrated['llmKeys'],
        containsPair(LlmPresets.glm.baseUrl, 'legacy-key'),
      );
    });

    test('致命节奏/爆裂木鱼手必须完整敲满 108 声（复审 P2-6）', () {
      final offset = kAchievements.firstWhere((a) => a.id == 'muyu_offset5');
      final burst = kAchievements.firstWhere((a) => a.id == 'muyu_15s');

      // 敲 2 下、间隔 107 秒、中途退出：总间隔接近满拍也不解锁。
      final store = AppStore.inMemory();
      store.addSession(
        practiceId: 'wooden_fish',
        merit: 0,
        completed: false,
        durationMs: 107000,
        metrics: {'strikes': 2, 'totalMs': 107000},
      );
      expect(offset.test(AchievementEval(store: store)), isFalse);
      expect(burst.test(AchievementEval(store: store)), isFalse);

      // 完整敲满 108 声、偏移 3 秒 → 致命节奏解锁；15 秒内不成立。
      final store2 = AppStore.inMemory();
      store2.addSession(
        practiceId: 'wooden_fish',
        merit: 10,
        completed: true,
        durationMs: 110000,
        metrics: {'strikes': 108, 'totalMs': 110000},
      );
      expect(offset.test(AchievementEval(store: store2)), isTrue);
      expect(burst.test(AchievementEval(store: store2)), isFalse);
    });

    test('助眠会话入库后，听潮成就当场可解（复审 R2）', () {
      final tide1 = kAchievements.firstWhere((a) => a.id == 'tide_1');
      final tideSync90 = kAchievements.firstWhere((a) => a.id == 'tide_sync90');
      const result = PracticeResult(
        effectiveDuration: Duration(minutes: 1),
        quality: 0.95,
        merit: 2,
        note: 'sleep_mode',
        metrics: {'phaseCount': 2, 'avgSync': 0.95},
      );
      AchievementEval evalOf(AppStore store) => AchievementEval(
        store: store,
        lastResult: result,
        lastManifest: TideBreathSession().manifest,
      );

      // 会话未入库（宿主若在 addSession 之前评估，即复审复现的现象）：
      // 听潮成就读的是 store.sessions，lastResult 不参与历史扫描。
      final notSaved = AppStore.inMemory();
      expect(tide1.test(evalOf(notSaved)), isFalse);
      expect(tideSync90.test(evalOf(notSaved)), isFalse);

      // 公共结算步骤先入库再评估：完成 1 分钟、phaseCount≥2、avgSync>0.90
      // → 潮涌潮落与水之呼吸当场解锁。
      final store = AppStore.inMemory();
      store.addSession(
        practiceId: 'tide_breath',
        merit: 2,
        completed: true,
        durationMs: 60000,
        metrics: result.metrics,
      );
      expect(tide1.test(evalOf(store)), isTrue);
      expect(tideSync90.test(evalOf(store)), isTrue);

      // 助眠修为走次日补发队列，不直接入账；到期才补。
      expect(store.merit, 0);
      store.queuePendingMerit(
        2,
        now: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(store.takePendingMerit(), 2);
      expect(store.merit, 2);
    });

    test('普通成就都注明了达成条件（隐藏成就单独处理）', () {
      final regular = kAchievements.where((a) => !a.hidden).toList();
      final hidden = kAchievements.where((a) => a.hidden).toList();
      expect(regular, hasLength(31), reason: '常规成就 31 条');
      expect(hidden, hasLength(5), reason: '隐藏成就 5 条');
      for (final a in regular) {
        expect(a.condition, isNotEmpty, reason: '${a.id} 缺少达成条件文案');
        expect(a.condition, isNot(contains('TODO')));
      }
      // 条件文案不能只是复述标题，否则等于没写。
      for (final a in regular) {
        expect(a.condition, isNot(equals(a.title)));
      }
    });

    test('水之呼吸：解放双手模式下不可达成（第二轮）', () {
      // 解放双手时相位吻合恒为真、avgSync 必是满值，若只看同步率会白拿。
      AppStore run({required bool handsFree, required double sync}) {
        final store = AppStore.inMemory();
        store.addSession(
          practiceId: 'tide_breath',
          merit: 0,
          completed: true,
          durationMs: 300000,
          metrics: {
            'phaseCount': 10,
            'avgSync': sync,
            'handsFree': handsFree,
          },
        );
        evaluateAchievements(store);
        return store;
      }

      expect(run(handsFree: true, sync: 1.0).isUnlocked('tide_sync90'), isFalse,
          reason: '解放双手模式不应解锁「水之呼吸」');
      expect(run(handsFree: false, sync: 0.95).isUnlocked('tide_sync90'), isTrue,
          reason: '普通模式下同步率 >90% 应正常解锁');
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

    test('中断记录不计入累计完成次数 completedSessionCount', () {
      final store = AppStore.inMemory();
      for (var i = 0; i < 7; i++) {
        store.addSession(
          practiceId: 'wooden_fish',
          merit: 0,
          completed: false,
          durationMs: 0,
        );
      }
      expect(store.completedSessionCount, 0);

      for (var i = 0; i < 7; i++) {
        store.addSession(
          practiceId: 'wooden_fish',
          merit: 1,
          completed: true,
          durationMs: 1000,
        );
      }
      expect(store.completedSessionCount, 7);
    });
  });
}

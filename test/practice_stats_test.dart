import 'dart:math';

import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/domain/petals.dart';
import 'package:busy_blind/domain/practice_stats.dart';
import 'package:flutter_test/flutter_test.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('buildPracticeDigest（纯数字摘要）', () {
    test('总览：次数/修为/活跃天数/花瓣/花种/签文数；不含签文文本', () {
      final store = AppStore.inMemory()
        ..addMerit(37)
        ..recordSign(slipId: 's1', text: '签文内容不上传', fortune: '上签')
        ..addPetal(PetalRarity.common)
        // 8 枚奇珍花瓣合成莲花，剩 1 枚奇珍——总瓣数 9 → 1。
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..addPetal(PetalRarity.legendary)
        ..craftFlower(8, PetalRarity.legendary, rng: Random(0));
      store.addSession(
        practiceId: 'sit_quiet',
        merit: 1,
        completed: true,
        durationMs: 60000,
        date: _ymd(DateTime.now()),
      );

      final overview =
          (buildPracticeDigest(store)['overview'] as Map).cast<String, Object?>();
      expect(overview['totalSessions'], 1);
      expect(overview['totalMerit'], 37 + AppStore.kSignMerit); // 抽签 +10 也入修为
      expect(overview['activeDays'], 1);
      expect(overview['petals'], 1); // 9 − 8（合成一朵 8 瓣莲花）
      expect(overview['flowerKinds'], 1);
      expect(overview['signCount'], 1);
      // 隐私红线：摘要里不得出现签文文本。
      expect(buildPracticeDigest(store).toString().contains('签文内容不上传'), isFalse);
    });

    test('streak：连续天数从今天往回数；今天未修从昨天起算；断档清零', () {
      final now = DateTime.now();
      final store = AppStore.inMemory();
      for (final back in [3, 2, 1]) {
        store.addSession(
          practiceId: 'sit_quiet',
          merit: 1,
          completed: true,
          durationMs: 60000,
          date: _ymd(now.subtract(Duration(days: back))),
        );
      }
      // 今天还没修：streak = 3（昨天/前天/大前天）。
      expect((buildPracticeDigest(store)['overview'] as Map)['streakDays'], 3);

      // 今天补一次 → 4。
      store.addSession(
        practiceId: 'sit_quiet',
        merit: 1,
        completed: true,
        durationMs: 60000,
        date: _ymd(now),
      );
      expect((buildPracticeDigest(store)['overview'] as Map)['streakDays'], 4);

      // 只留 7 天前一次（断档）→ 0。
      final far = AppStore.inMemory();
      far.addSession(
        practiceId: 'sit_quiet',
        merit: 1,
        completed: true,
        durationMs: 60000,
        date: _ymd(now.subtract(const Duration(days: 7))),
      );
      expect((buildPracticeDigest(far)['overview'] as Map)['streakDays'], 0);
    });

    test('按修行聚合：名称取自注册表，次数/完成率/分钟/修为/木鱼专项正确', () {
      final store = AppStore.inMemory()
        ..addSession(
          practiceId: 'wooden_fish',
          merit: 12,
          completed: true,
          durationMs: 107000,
          metrics: {'totalMs': 107000, 'intervalMeanUs': 1000000, 'intervalStdUs': 50000},
        )
        ..addSession(
          practiceId: 'wooden_fish',
          merit: 0,
          completed: false,
          durationMs: 50000,
          metrics: {'totalMs': 50000, 'intervalMeanUs': 1000000, 'intervalStdUs': 50000},
        )
        ..addSession(
          practiceId: 'meditation',
          merit: 0,
          completed: true,
          durationMs: 5 * 60000,
          metrics: {'minutes': 5},
        );

      final practices =
          (buildPracticeDigest(store)['practices'] as List).cast<Map>();
      expect(practices.length, 2);
      final fish = practices.first.cast<String, Object?>();
      expect(fish['name'], '木鱼'); // 名称来自 practice_registry 的 manifest
      expect(fish['count'], 2);
      expect(fish['completionRatePct'], 50);
      expect(fish['totalMinutes'], 3); // 107s→2 + 50s→1
      expect(fish['totalMerit'], 12);
      // 木鱼专项：偏移秒只算完成局（与 107s 满拍的差）；稳定度 = 1 − 标准差/均值。
      expect(fish['avgOffsetSec'], 0);
      expect(fish['stabilityPct'], 95);

      final meditation = practices[1].cast<String, Object?>();
      expect(meditation['name'], '打坐'); // 非插件修行，兜底命名
      expect(meditation['totalMinutes'], 5);
      expect(meditation.containsKey('avgOffsetSec'), isFalse); // 无专项指标
    });

    test('专项指标：数雨误差 / 听潮同步率 / 钓花空竿率 / 过河每跳得分', () {
      final store = AppStore.inMemory()
        ..addSession(
          practiceId: 'count_rain',
          merit: 8,
          completed: true,
          durationMs: 180000,
          metrics: {'error': 2, 'errorRate': 0.1},
        )
        ..addSession(
          practiceId: 'count_rain',
          merit: 10,
          completed: true,
          durationMs: 180000,
          metrics: {'error': 1},
        )
        ..addSession(
          practiceId: 'tide_breath',
          merit: 9,
          completed: true,
          durationMs: 300000,
          metrics: {'avgSync': 0.9, 'phaseCount': 30},
        )
        ..addSession(
          practiceId: 'fish_petals',
          merit: 9,
          completed: true,
          durationMs: 240000,
          metrics: {'casts': 10, 'petalsCaught': 3, 'miscatch': 4, 'missed': 3},
        )
        ..addSession(
          practiceId: 'cross_river',
          merit: 18,
          completed: true,
          durationMs: 120000,
          metrics: {'jumps': 20, 'score': 1600, 'avgDeviationUs': 90000},
        );

      final practices = (buildPracticeDigest(store)['practices'] as List)
          .cast<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();
      final byId = {for (final p in practices) p['id'] as String: p};
      expect(byId['count_rain']!['avgErrorDrops'], 1.5);
      expect(byId['tide_breath']!['avgSyncPct'], 90);
      expect(byId['fish_petals']!['petalsCaught'], 3);
      expect(byId['fish_petals']!['emptyRodPct'], 40);
      expect(byId['cross_river']!['avgScorePerJump'], 80);
    });

    test('最近 14 天逐日：长度 14、今天有值、窗口外不计、日期 MM-DD', () {
      final now = DateTime.now();
      final store = AppStore.inMemory()
        ..addSession(
          practiceId: 'sit_quiet',
          merit: 1,
          completed: true,
          durationMs: 60000,
          date: _ymd(now),
        )
        ..addSession(
          practiceId: 'sit_quiet',
          merit: 1,
          completed: true,
          durationMs: 90000,
          date: _ymd(now.subtract(const Duration(days: 13))),
        )
        ..addSession(
          practiceId: 'sit_quiet',
          merit: 1,
          completed: true,
          durationMs: 30000,
          date: _ymd(now.subtract(const Duration(days: 20))), // 窗口外
        );

      final days = (buildPracticeDigest(store)['last14Days'] as List).cast<Map>();
      expect(days.length, 14);
      // 序列按时间正序：first = 13 天前，last = 今天。
      expect(days.first['date'],
          _ymd(now.subtract(const Duration(days: 13))).substring(5));
      expect(days.first['count'], 1);
      expect(days.last['date'], _ymd(now).substring(5));
      expect(days.last['count'], 1);
      expect(days.last['minutes'], 1);
      expect(days.last['merit'], 1);
      expect(days.where((d) => d['count'] == 0).length, 12); // 其余日子为 0
    });
  });

  group('提示词与本地模板报告', () {
    test('User 提示词内嵌 digest JSON 并限定输出格式', () {
      final prompt =
          buildReportUserPrompt(buildPracticeDigest(AppStore.inMemory()));
      expect(prompt, contains('"overview"'));
      expect(prompt, contains('本期概览'));
      expect(prompt, contains('400 字'));
    });

    test('本地模板报告：四段齐全，引用真实数字，空记录也有话说', () {
      final store = AppStore.inMemory()
        ..addMerit(12) // 修为余额与单局 merit 分开记（宿主单独入账）
        ..addSession(
          practiceId: 'wooden_fish',
          merit: 12,
          completed: true,
          durationMs: 110000,
          metrics: {'totalMs': 110000, 'intervalMeanUs': 1000000, 'intervalStdUs': 100000},
        );
      final report = buildLocalReport(buildPracticeDigest(store));
      expect(report, contains('【本期概览】'));
      expect(report, contains('【值得肯定】'));
      expect(report, contains('【可精进处】'));
      expect(report, contains('【下期建议】'));
      expect(report, contains('修为 12'));
      expect(report, contains('木鱼平均偏移 3.0 秒'));

      // 空记录：不崩、不编数字。
      final empty = buildLocalReport(buildPracticeDigest(AppStore.inMemory()));
      expect(empty, contains('【本期概览】'));
      expect(empty, contains('先坐下来'));
    });
  });
}

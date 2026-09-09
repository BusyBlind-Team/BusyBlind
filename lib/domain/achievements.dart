import '../data/app_store.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';

/// 成就定义：判定由宿主结算时统一触发（Domain 层成就引擎），玩法不感知。
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.test,
  });

  final String id;
  final String title;
  final String description;
  final bool Function(AchievementEval eval) test;
}

/// 成就判定的输入快照。
class AchievementEval {
  const AchievementEval({required this.store, this.lastResult, this.lastManifest});

  final AppStore store;
  final PracticeResult? lastResult;
  final PracticeManifest? lastManifest;
}

final List<AchievementDef> kAchievements = [
  AchievementDef(
    id: 'first_session',
    title: '初入山门',
    description: '完成第一次修行',
    test: (e) => e.lastResult != null && e.lastResult!.completed,
  ),
  AchievementDef(
    id: 'muyu_108',
    title: '百八之声',
    description: '一口气敲完一百零八声木鱼',
    test: (e) =>
        e.lastManifest?.id == 'wooden_fish' &&
        (e.lastResult?.metrics['strikes'] as int? ?? 0) >= 108,
  ),
  AchievementDef(
    id: 'muyu_steady',
    title: '心如止水',
    description: '木鱼单局稳定性标准差 ≤ 120ms',
    test: (e) {
      final std = (e.lastResult?.metrics['intervalStdUs'] as num?)?.toDouble();
      final strikes = e.lastResult?.metrics['strikes'] as int? ?? 0;
      // 至少三个间隔才有稳定性样本；空局或一两下不能凭 0 标准差解锁。
      return e.lastManifest?.id == 'wooden_fish' &&
          strikes >= 4 &&
          std != null &&
          std <= 120000;
    },
  ),
  AchievementDef(
    id: 'rain_good',
    title: '听雨知数',
    description: '数雨平均误差 ≤ 10%',
    test: (e) {
      final err = (e.lastResult?.metrics['errorRate'] as num?)?.toDouble();
      return e.lastManifest?.id == 'count_rain' && err != null && err <= 0.10;
    },
  ),
  AchievementDef(
    id: 'river_10',
    title: '步履不停',
    description: '过河连续踏上 10 块石阶',
    test: (e) =>
        e.lastManifest?.id == 'cross_river' &&
        (e.lastResult?.metrics['jumps'] as int? ?? 0) >= 10,
  ),
  AchievementDef(
    id: 'meditate_10',
    title: '枯坐有味',
    description: '单次打坐累计 10 分钟',
    test: (e) =>
        e.lastManifest?.id == 'meditation' &&
        (e.lastResult?.metrics['minutes'] as num? ?? 0) >= 10,
  ),
  AchievementDef(
    id: 'merit_100',
    title: '百修为',
    description: '累计修为达到 100',
    test: (e) => e.store.merit >= 100,
  ),
  AchievementDef(
    id: 'petals_5',
    title: '拾花人',
    description: '图鉴集齐 5 种花',
    test: (e) => e.store.flowers.length >= 5,
  ),
  AchievementDef(
    id: 'sessions_7',
    title: '日课',
    description: '累计完成 7 次修行',
    test: (e) => e.store.completedSessionCount >= 7,
  ),
];

import '../data/app_store.dart';
import 'merit.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import 'petals.dart';

/// 成就定义：判定由宿主结算/启动评估时统一触发（Domain 层成就引擎）。
///
/// 文案与触发条件来自《文案：成就》：常规 31 条 + 隐藏 5 条。
/// "达到一次/累计 N 次"类成就直接扫描本地修行历史（sessions），
/// 老用户升级后也能追认解锁。
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.test,
    this.hidden = false,
  });

  final String id;
  final String title;
  final String description;

  /// 隐藏成就：解锁前在成就页不显示名称与条件。
  final bool hidden;

  final bool Function(AchievementEval eval) test;
}

/// 成就判定的输入快照。
class AchievementEval {
  const AchievementEval({required this.store, this.lastResult, this.lastManifest});

  final AppStore store;
  final PracticeResult? lastResult;
  final PracticeManifest? lastManifest;
}

// ---- 历史扫描小工具 ----

int _countSessions(AppStore store, String practiceId) => store.sessions
    .where((s) => s['practiceId'] == practiceId)
    .length;

bool _anySession(
  AppStore store,
  String practiceId,
  bool Function(Map<String, Object?> metrics) where, {
  bool requireCompleted = false,
}) =>
    store.sessions.any(
      (s) =>
          s['practiceId'] == practiceId &&
          (!requireCompleted || s['completed'] == true) &&
          where((s['metrics'] as Map?)?.cast<String, Object?>() ?? const {}),
    );

double? _metric(Map<String, Object?> metrics, String key) =>
    (metrics[key] as num?)?.toDouble();

bool _loginAtLeast(AppStore store, int days) => store.loginDays >= days;

bool _levelAtLeast(AppStore store, int minMerit) => store.merit >= minMerit;

final List<AchievementDef> kAchievements = [
  // ---- 登录天数 ----
  AchievementDef(
    id: 'login_1',
    title: '刹那',
    description: '当下一念，使我们相逢。',
    test: (e) => _loginAtLeast(e.store, 1),
  ),
  AchievementDef(
    id: 'login_7',
    title: '禅七',
    description: '若七日，一心不乱。',
    test: (e) => _loginAtLeast(e.store, 7),
  ),
  AchievementDef(
    id: 'login_30',
    title: '期月',
    description: '月升，月落，月满，月残。该去撕掉一页日历了。',
    test: (e) => _loginAtLeast(e.store, 30),
  ),
  AchievementDef(
    id: 'login_90',
    title: '九旬',
    description: '修行九十天，能叫九旬老人吗（笑',
    test: (e) => _loginAtLeast(e.store, 90),
  ),
  AchievementDef(
    id: 'login_365',
    title: '一腊',
    description: '"这个星球的人在庆祝什么？""他们的行星绕着恒星转了一圈。"',
    test: (e) => _loginAtLeast(e.store, 365),
  ),
  AchievementDef(
    id: 'login_520',
    title: '久久',
    description: '是的，我爱修行，我要进行一辈子修行。',
    test: (e) => _loginAtLeast(e.store, 520),
  ),
  AchievementDef(
    id: 'login_3650',
    title: '十年',
    description: '大约没人能达成这个成就，达成的也已经成佛了。',
    test: (e) => _loginAtLeast(e.store, 3650),
  ),

  // ---- 修为等级 ----
  AchievementDef(
    id: 'level_langzi',
    title: '浪子',
    description: '打野0-8-1的时期。',
    test: (e) => _levelAtLeast(e.store, kMeritLevels[0].minMerit),
  ),
  AchievementDef(
    id: 'level_jushi',
    title: '居士',
    description: '青莲居士是酒鬼，东坡居士是饭桶，而我只爱修行。',
    test: (e) => _levelAtLeast(e.store, 50),
  ),
  AchievementDef(
    id: 'level_xingzhe',
    title: '行者',
    description: '我身上能看到那位大圣曾经的影子吗？',
    test: (e) => _levelAtLeast(e.store, 200),
  ),
  AchievementDef(
    id: 'level_shami',
    title: '沙弥',
    description: '不要迷恋哥，哥已经与红尘做了了断。',
    test: (e) => _levelAtLeast(e.store, 500),
  ),
  AchievementDef(
    id: 'level_biqiu',
    title: '比丘',
    description: '修行了这么久，终于转正了。',
    test: (e) => _levelAtLeast(e.store, 1000),
  ),
  AchievementDef(
    id: 'level_fangzhang',
    title: '方丈',
    description: '得罪了方丈还想走？',
    test: (e) => _levelAtLeast(e.store, 2000),
  ),
  AchievementDef(
    id: 'level_luohan',
    title: '罗汉',
    description: '才不是因为吃了罗汉果。',
    test: (e) => _levelAtLeast(e.store, 5000),
  ),
  AchievementDef(
    id: 'level_pusa',
    title: '菩萨',
    description: '脱离苦海，普渡众生。',
    test: (e) => _levelAtLeast(e.store, 10000),
  ),

  // ---- 打坐 ----
  AchievementDef(
    id: 'meditation_1',
    title: '妄念息止',
    description: '什么都不做也是一种修行。',
    test: (e) => _countSessions(e.store, 'meditation') >= 1,
  ),
  AchievementDef(
    id: 'meditation_24h',
    title: '寂照澄明',
    description: '一日之计在于打坐。',
    test: (e) =>
        e.store.sessions
            .where((s) => s['practiceId'] == 'meditation')
            .fold<int>(0, (a, s) => a + (s['durationMs'] as int? ?? 0)) >=
        24 * 3600000,
  ),
  AchievementDef(
    id: 'meditation_1h',
    title: '万籁俱寂',
    description: 'I hear the sound of silence.',
    test: (e) => e.store.sessions.any(
      (s) =>
          s['practiceId'] == 'meditation' &&
          (s['durationMs'] as int? ?? 0) > 3600000,
    ),
  ),

  // ---- 木鱼 ----
  AchievementDef(
    id: 'muyu_1',
    title: '咚咚笃笃',
    description: '木鱼里传来低沉而空灵，仿若心跳的灵魂之音。',
    test: (e) => _countSessions(e.store, 'wooden_fish') >= 1,
  ),
  AchievementDef(
    id: 'muyu_10',
    title: '木鱼宇宙',
    description: '原来木鱼里藏着一个小宇宙，我听见的就是它的心跳。',
    test: (e) => _countSessions(e.store, 'wooden_fish') >= 10,
  ),
  AchievementDef(
    id: 'muyu_offset5',
    title: '致命节奏',
    description: '我是一个忧伤节拍器。',
    // 必须完整敲满 108 声——只敲两下、间隔 107 秒再退出不算（复审 P2-6）。
    test: (e) => _anySession(
      e.store,
      'wooden_fish',
      (m) {
        final totalMs = (m['totalMs'] as num?)?.toDouble();
        final strikes = m['strikes'] as int? ?? 0;
        return totalMs != null &&
            strikes >= 108 &&
            ((totalMs - WoodenFishPace.idealTotalMs).abs() / 1000 <= 5);
      },
      requireCompleted: true,
    ),
  ),

  // ---- 数雨 ----
  AchievementDef(
    id: 'rain_1',
    title: '时落之雨',
    description: '追随季节的讯息赶来的时雨，流连于屋檐不愿落下。',
    test: (e) => _countSessions(e.store, 'count_rain') >= 1,
  ),
  AchievementDef(
    id: 'rain_10',
    title: '润物无声',
    description: '听觉之外，还有不计其数的雨滴在无声地润泽着大地。',
    test: (e) => _countSessions(e.store, 'count_rain') >= 10,
  ),
  AchievementDef(
    id: 'rain_perfect5',
    title: '动杯雨接',
    description: '用杯子把每一滴雨都接住，好像就能数对了。',
    test: (e) =>
        e.store.sessions
            .where(
              (s) =>
                  s['practiceId'] == 'count_rain' &&
                  // 必须真正报过数：中途退出的会话 error 无意义
                  //（第 15 轮自检：秒退 N 次不能白拿"完全准确"）。
                  ((s['metrics'] as Map?)?['userReport'] != null) &&
                  ((s['metrics'] as Map?)?['error'] as num? ?? -1) == 0,
            )
            .length >=
        5,
  ),

  // ---- 听潮 ----
  AchievementDef(
    id: 'tide_1',
    title: '潮涌潮落',
    description: '东临碣石，任潮水涤净心灵。',
    test: (e) => _countSessions(e.store, 'tide_breath') >= 1,
  ),
  AchievementDef(
    id: 'tide_10',
    title: '天地吐息',
    description: '一呼一吸之间，我与这颗星球融为一体。',
    test: (e) => _countSessions(e.store, 'tide_breath') >= 10,
  ),
  AchievementDef(
    id: 'tide_sync90',
    title: '水之呼吸',
    description: '已经是堪比ECMO的存在。',
    test: (e) => _anySession(
      e.store,
      'tide_breath',
      (m) =>
          ((m['phaseCount'] as num?) ?? 0) >= 2 &&
          (_metric(m, 'avgSync') ?? 0) > 0.90,
    ),
  ),

  // ---- 过河 ----
  AchievementDef(
    id: 'river_1',
    title: '秋水寒',
    description: '人不可能两次踏入同一条河流。开玩笑的，下次还踏。',
    test: (e) => _countSessions(e.store, 'cross_river') >= 1,
  ),
  AchievementDef(
    id: 'river_3000',
    title: '生命流',
    description: '膏泽众生的水呵，潺潺响声就是生命的合奏。',
    test: (e) => _anySession(
      e.store,
      'cross_river',
      (m) => (_metric(m, 'score') ?? 0) >= 3000,
    ),
  ),

  // ---- 钓花与图鉴 ----
  AchievementDef(
    id: 'fish_1',
    title: '愿花上钩',
    description: '这条至清的溪流中只有缓缓漂流的花瓣，在此垂钓算不得杀生。',
    test: (e) => _countSessions(e.store, 'fish_petals') >= 1,
  ),
  AchievementDef(
    id: 'flower_1',
    title: '再闻花名',
    description: '历经万难重塑君之旧貌，只为再闻君芳名。',
    test: (e) => e.store.flowers.isNotEmpty,
  ),

  // ---- 隐藏成就 ----
  AchievementDef(
    id: 'muyu_15s',
    title: '爆裂木鱼手',
    description: '朋友，也许乐队更适合你……',
    hidden: true,
    test: (e) => _anySession(
      e.store,
      'wooden_fish',
      (m) {
        final strikes = m['strikes'] as int? ?? 0;
        final totalMs = m['totalMs'] as int? ?? 1 << 31;
        return strikes >= 108 && totalMs <= 15000;
      },
      requireCompleted: true,
    ),
  ),
  AchievementDef(
    id: 'rain_err10',
    title: '雨一直下',
    description: '雨太大了，不清楚到底多少滴，乱报一个数算了。',
    hidden: true,
    test: (e) => _anySession(e.store, 'count_rain', (m) {
      final reported = m['userReport'];
      final error = (m['error'] as num?)?.toInt();
      return reported != null && error != null && error >= 10;
    }),
  ),
  AchievementDef(
    id: 'tide_sync10',
    title: '立刻抢救',
    description: '喂，我只是睡着了，又不是没呼吸了！',
    hidden: true,
    test: (e) => _anySession(
      e.store,
      'tide_breath',
      (m) =>
          ((m['phaseCount'] as num?) ?? 0) >= 2 &&
          (_metric(m, 'avgSync') ?? 1) < 0.10,
    ),
  ),
  AchievementDef(
    id: 'river_9999',
    title: '跳大神',
    description: '我当年可是跳一跳大神。等等，不是跳大神。',
    hidden: true,
    test: (e) => _anySession(
      e.store,
      'cross_river',
      (m) => (_metric(m, 'score') ?? 0) >= 9999,
    ),
  ),
  AchievementDef(
    id: 'flower_all',
    title: '完结撒花',
    description: '这里，就是终点了吗……其实可以把花放生了再钓一轮。',
    hidden: true,
    test: (e) => e.store.flowers.length >= kFlowerSpecies.length,
  ),
];

/// 木鱼满拍总时长（毫秒）：108 声之间 107 个 1 秒间隔。
abstract final class WoodenFishPace {
  static const double idealTotalMs = 107000;
}

/// 统一评估入口：按当前存储快照（可选带最近一局结果）解锁所有满足条件的成就。
///
/// 宿主结算与启动时各调一次——历史扫描类条件靠启动评估追认。
List<String> evaluateAchievements(
  AppStore store, {
  PracticeResult? lastResult,
  PracticeManifest? lastManifest,
}) {
  final eval = AchievementEval(
    store: store,
    lastResult: lastResult,
    lastManifest: lastManifest,
  );
  return store.unlockAchievements(
    kAchievements.where((a) => a.test(eval)).map((a) => a.id),
  );
}

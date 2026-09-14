import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/llm/llm_client.dart';
import '../domain/petals.dart';

/// 本地优先的数据层（设计方案原则 4）。
///
/// v0.1 用 JSON 文档存储，字段结构即未来 Drift 表的草图；
/// 迁移 SQLite 时只动本文件，Domain 与 UI 不感知。
/// 断网时全部功能可用；服务器只负责同步与好友社交（v0.1 未接入）。
class AppStore extends ChangeNotifier {
  AppStore._(
    this._data,
    this._file, {
    this.persistenceError,
  });

  final Map<String, Object?> _data;
  final File? _file;
  bool _persistenceBlocked = false;

  /// 当前运行检测到的存档问题。UI 应提示用户，不能静默回退为空账户。
  String? persistenceError;

  static Future<AppStore> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/busy_blind.json');
    final backup = File('${file.path}.bak');
    Map<String, Object?>? data;
    if (await file.exists() || await backup.exists()) {
      data = await _readJson(file);
      if (data == null) {
        final backupData = await _readJson(backup);
        if (backupData == null) {
          return AppStore._(
            _defaults({}),
            file,
            persistenceError: '本地存档无法读取，原文件已保留，未自动覆盖。',
          ).._persistenceBlocked = true;
        }
        final quarantined = File('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        var blocked = false;
        try {
          if (await file.exists()) await file.rename(quarantined.path);
        } catch (_) {
          // 无法隔离时仍不覆盖原文件；备份数据只在本次运行用于恢复。
          blocked = true;
        }
        return AppStore._(
          applyMigrations(_defaults(backupData)),
          file,
          persistenceError: '主存档缺失或损坏，已从上一份备份恢复；已有文件已保留。',
        ).._persistenceBlocked = blocked;
      }
    }
    return AppStore._(applyMigrations(_defaults(data ?? {})), file);
  }

  static Future<Map<String, Object?>?> _readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  /// 数据迁移：老版本升级后的字段口径修正。
  ///
  /// 教程门控上线时，已有修行记录/修为的老用户不应被强制重看教程。
  @visibleForTesting
  static Map<String, Object?> applyMigrations(Map<String, Object?> data) {
    final tutorialDone = data['tutorialDone']! as bool;
    final hasHistory =
        (data['sessions']! as List).isNotEmpty || (data['merit']! as int) > 0;
    if (!tutorialDone && hasHistory) {
      data['tutorialDone'] = true;
    }
    // 花瓣口径迁移（第 16 轮自检修正）：三段链 v0 物种 Map → v1 总数
    // int → v2 按稀有度分桶。注意第二段读取的是 data['petals']（上一段
    // 刚写入的 int），不是过期的局部变量；清零保证重复迁移幂等。
    final petals = data['petals'];
    if (petals is Map) {
      var total = 0;
      for (final v in petals.values) {
        total += v as int? ?? 0;
      }
      data['petals'] = total;
    }
    final petalsNow = data['petals'];
    final byRarity = data['petalsByRarity'];
    if (byRarity is Map && petalsNow is int && petalsNow > 0) {
      byRarity['common'] = (byRarity['common'] as int? ?? 0) + petalsNow;
      data['petals'] = 0;
    }
    // 花瓣口径迁移 v3（新要求 #1）：花瓣在上钩那一刻就定种，所以存量改为
    // 按**花种**分桶。老存档里"只知稀有度、不知花种"的余量按图鉴顺序
    // 轮流摊到该稀有度的花种上（确定性、总数不丢），摊完清零 —— 这也让
    // 迁移天然幂等：再跑一次时余量已经是 0。
    final bySpecies = data['petalsBySpecies'];
    if (byRarity is Map && bySpecies is Map) {
      for (final rarity in PetalRarity.values) {
        var left = byRarity[rarity.id] as int? ?? 0;
        if (left <= 0) continue;
        final pool = flowerSpeciesOfRarity(rarity);
        if (pool.isEmpty) continue;
        var i = 0;
        while (left > 0) {
          final id = pool[i % pool.length].id;
          bySpecies[id] = (bySpecies[id] as int? ?? 0) + 1;
          left--;
          i++;
        }
        byRarity[rarity.id] = 0;
      }
    }
    // Key 分服务商保存（PR #14 复审 P1-2）：把升级前已填的 Key
    // 按其 baseUrl 播种进 llmKeys，避免老用户升级后丢 Key。
    final llm = data['llm'];
    if (llm is Map) {
      final baseUrl = llm['baseUrl'] as String? ?? '';
      final apiKey = llm['apiKey'] as String? ?? '';
      final keys = data['llmKeys'];
      if (keys is Map && baseUrl.isNotEmpty && apiKey.isNotEmpty) {
        keys[baseUrl] ??= apiKey;
      }
    }
    return data;
  }

  /// 测试与预览用：不落盘。
  factory AppStore.inMemory() => AppStore._(_defaults({}), null);

  static Map<String, Object?> _defaults(Map<String, Object?> data) => {
    'merit': data['merit'] ?? 0,
    'tutorialDone': data['tutorialDone'] ?? false,
    'meditation': data['meditation'] ?? {'date': '', 'earnedToday': 0},
    'dailySign': data['dailySign'] ?? {'lastDate': '', 'slips': []},
    'petals': data['petals'] ?? 0,
    'flowers': data['flowers'] ?? <String>[],
    'achievements': data['achievements'] ?? <String>[],
    'pendingMerit': data['pendingMerit'] ?? <Object?>[],
    'sessions': data['sessions'] ?? <Object?>[],
    // lUserUs 字段已废弃（校准功能删除，Bug 描述 #3）；老存档里的
    // 残留值不再读入，也不迁移。
    'llm': data['llm'] ??
        {
          'baseUrl': LlmPresets.glm.baseUrl,
          'model': LlmPresets.glm.model,
          'apiKey': '',
        },
    'reports': data['reports'] ?? <Object?>[],
    // 登录天数（成就：刹那/禅七/……）与各修行首次教程已读标记。
    'login': data['login'] ?? {'count': 0, 'lastDate': ''},
    'tutorialsSeen': data['tutorialsSeen'] ?? <String>[],
    // 背景音乐设置：track = -2 无 / -1 随机 / 0..4 固定曲目；volume = 0..1。
    'bgm': data['bgm'] ?? {'track': -1, 'volume': 0.35},
    // 花瓣按**花种**分桶（新要求 #1：上钩那一刻就定种）。
    'petalsBySpecies': data['petalsBySpecies'] ?? <String, int>{},
    // 已废弃（迁移 v3 会把余量摊到花种上并清零）；保留键只做老存档兼容。
    'petalsByRarity': data['petalsByRarity'] ??
        {'common': 0, 'rare': 0, 'legendary': 0},
    // 各服务商（按 baseUrl）分别保存的 API Key，避免切换服务商串密钥。
    'llmKeys': data['llmKeys'] ?? <String, String>{},
  };

  // ---- 首启教程 ----

  bool get tutorialDone => _data['tutorialDone']! as bool;

  set tutorialDone(bool value) {
    _data['tutorialDone'] = value;
    _save();
    notifyListeners();
  }

  // ---- 修为 ----

  int get merit => _data['merit']! as int;

  void addMerit(int amount) {
    if (amount == 0) return;
    _data['merit'] = merit + amount;
    _save();
    notifyListeners();
  }

  /// 打坐单日上限（设计方案 6.4：单日 60 点）。
  static const int kDailyMeditationCap = 60;

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  int meditationEarnedToday() {
    final m = _data['meditation']! as Map;
    return m['date'] == _today ? (m['earnedToday'] as int? ?? 0) : 0;
  }

  /// 返回实际入账的打坐修为（可能因单日上限截断）。
  int addMeditationMerit(int amount) {
    final m = _data['meditation']! as Map;
    if (m['date'] != _today) {
      m['date'] = _today;
      m['earnedToday'] = 0;
    }
    final room = (kDailyMeditationCap - (m['earnedToday'] as int? ?? 0))
        .clamp(0, amount);
    if (room <= 0) return 0;
    m['earnedToday'] = (m['earnedToday'] as int? ?? 0) + room;
    _data['merit'] = merit + room;
    _save();
    notifyListeners();
    return room;
  }

  // ---- 助眠补发：修为次日打开时入账 ----

  /// 把上次标记为"次日补发"的修为入账，返回本次补发的数量。
  int takePendingMerit() {
    final list = _data['pendingMerit']! as List;
    if (list.isEmpty) return 0;
    final due = list
        .cast<Map>()
        .where((e) => e['dueDate'] is String && (e['dueDate'] as String).compareTo(_today) <= 0)
        .toList();
    if (due.isEmpty) return 0;
    var total = 0;
    for (final e in due) {
      total += e['amount'] as int? ?? 0;
      list.remove(e);
    }
    _data['merit'] = merit + total;
    _save();
    notifyListeners();
    return total;
  }

  void queuePendingMerit(int amount, {DateTime? now}) {
    final n = now ?? DateTime.now().add(const Duration(days: 1));
    final due =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    (_data['pendingMerit']! as List).add({'amount': amount, 'dueDate': due});
    _save();
    notifyListeners();
  }

  // ---- 每日抽签（每日一次；待对齐清单 #4：+10 修为 + 树叶签文收藏）----

  /// 抽签固定修为奖励（待对齐清单 #4 拍板：抽签还是 +10 修为）。
  static const int kSignMerit = 10;

  String? get lastSignDate => (_data['dailySign']! as Map)['lastDate'] as String?;

  List<Map<String, Object?>> get slips =>
      ((_data['dailySign']! as Map)['slips'] as List).cast<Map<String, Object?>>();

  bool get signedToday => lastSignDate == _today;

  void recordSign({required String slipId, required String text, required String fortune}) {
    final d = _data['dailySign']! as Map
      ..['lastDate'] = _today;
    (d['slips'] as List).add({
      'date': _today,
      'id': slipId,
      'text': text,
      'fortune': fortune,
    });
    _data['merit'] = merit + kSignMerit;
    _save();
    notifyListeners();
  }

  // ---- 花瓣与图鉴（新要求 #1：上钩即定种；攒够该花种的瓣数合成这朵花）----

  /// 各花种花瓣存量，key 为 FlowerSpecies.id（osmanthus/peach/…）。
  Map<String, int> get petalsBySpecies =>
      (_data['petalsBySpecies']! as Map).cast<String, int>();

  /// 老存档遗留的"只知稀有度、不知花种"余量（迁移 v3 已摊到花种上并
  /// 清零；这里保留读取，未迁移的存档也不会丢瓣数）。
  Map<String, int> get petalsByRarity =>
      (_data['petalsByRarity']! as Map).cast<String, int>();

  int petalCountOfSpecies(String speciesId) =>
      petalsBySpecies[speciesId] ?? 0;

  /// 稀有度存量：该稀有度各花种之和（老存档未摊完的余量也计入）。
  int petalCountOf(PetalRarity rarity) {
    var total = petalsByRarity[rarity.id] ?? 0;
    for (final species in flowerSpeciesOfRarity(rarity)) {
      total += petalCountOfSpecies(species.id);
    }
    return total;
  }

  int get petalCount => petalsBySpecies.values.fold(0, (a, b) => a + b);

  List<String> get flowers => (_data['flowers']! as List).cast<String>();

  bool ownsFlower(String speciesId) => flowers.contains(speciesId);

  /// 钓到一片 [speciesId] 的花瓣。
  void addPetal(String speciesId) {
    final p = _data['petalsBySpecies']! as Map;
    p[speciesId] = (p[speciesId] as int? ?? 0) + 1;
    _save();
    notifyListeners();
  }

  /// 投入该花种所需的瓣数（4/5/6/8），合成这朵花。
  ///
  /// 花瓣按花种分别计数，所以"钓到的是哪种花的花瓣"直接决定能合成什么：
  /// 4 片桂花花瓣 → 桂花，8 片莲花花瓣 → 莲花。瓣数不足返回 null
  ///（不扣花瓣）；成功则扣花瓣并记入图鉴。
  FlowerSpecies? craftFlower(String speciesId) {
    final species = flowerById(speciesId);
    if (species.id != speciesId) return null; // 未知花种，不误合成桂花
    if (petalCountOfSpecies(speciesId) < species.petals) return null;
    final p = _data['petalsBySpecies']! as Map;
    p[speciesId] = (p[speciesId] as int) - species.petals;
    final flowers = _data['flowers']! as List;
    if (!flowers.contains(species.id)) {
      flowers.add(species.id);
    }
    _save();
    notifyListeners();
    return species;
  }

  // ---- 成就 ----

  List<String> get achievements => (_data['achievements']! as List).cast<String>();

  bool isUnlocked(String achievementId) => achievements.contains(achievementId);

  /// 返回本次新解锁的成就 id。
  List<String> unlockAchievements(Iterable<String> ids) {
    final list = _data['achievements']! as List;
    final fresh = <String>[];
    for (final id in ids) {
      if (!list.contains(id)) {
        list.add(id);
        fresh.add(id);
      }
    }
    if (fresh.isNotEmpty) {
      _save();
      notifyListeners();
    }
    return fresh;
  }

  // ---- 修行记录 ----

  List<Map<String, Object?>> get sessions =>
      (_data['sessions']! as List).cast<Map<String, Object?>>();

  int get sessionCount => sessions.length;

  /// 只有真正完成的会话才能计入“累计完成”。中断记录保留给历史回顾，
  /// 但不能推进以完成次数为条件的成就。
  int get completedSessionCount =>
      sessions.where((session) => session['completed'] == true).length;

  void addSession({
    required String practiceId,
    required int merit,
    required bool completed,
    required int durationMs,
    Map<String, Object?> metrics = const {},
    @visibleForTesting String? date,
  }) {
    (_data['sessions']! as List).add({
      'practiceId': practiceId,
      'merit': merit,
      'completed': completed,
      'durationMs': durationMs,
      'date': date ?? _today,
      'metrics': metrics,
    });
    final list = _data['sessions']! as List;
    if (list.length > 300) {
      list.removeRange(0, list.length - 300);
    }
    _save();
    notifyListeners();
  }

  // ---- LLM 配置与修炼报告 ----

  LlmConfig get llmConfig {
    final m = _data['llm']! as Map;
    return LlmConfig(
      baseUrl: m['baseUrl'] as String? ?? '',
      model: m['model'] as String? ?? '',
      apiKey: m['apiKey'] as String? ?? '',
    );
  }

  bool get llmReady => llmConfig.apiKey.trim().isNotEmpty;

  /// 某服务商（baseUrl）此前保存过的 Key；没有则 null。
  String? keyForBaseUrl(String baseUrl) =>
      (_data['llmKeys']! as Map)[baseUrl] as String?;

  void saveLlmConfig(LlmConfig config) {
    _data['llm'] = {
      'baseUrl': config.baseUrl,
      'model': config.model,
      'apiKey': config.apiKey,
    };
    // 按 baseUrl 记录 Key：切换服务商时各用各的，互不串用（复审 P1-2）。
    (_data['llmKeys']! as Map)[config.baseUrl] = config.apiKey;
    _save();
    notifyListeners();
  }

  List<Map<String, Object?>> get reports =>
      (_data['reports']! as List).cast<Map<String, Object?>>();

  /// 收入一份报告（倒序插入），只保留最近 [kMaxReports] 份。
  void addReport(Map<String, Object?> report) {
    (_data['reports']! as List).insert(0, report);
    final list = _data['reports']! as List;
    if (list.length > kMaxReports) {
      list.removeRange(kMaxReports, list.length);
    }
    _save();
    notifyListeners();
  }

  static const int kMaxReports = 10;

  // ---- 校准 ----
  // 用户时机校准（lUserUs）已随"时机校准"功能整体删除——Bug 描述 #3。

  // ---- 登录天数（成就"刹那/禅七/……"口径：累计到访的自然日数）----

  int get loginDays => (_data['login']! as Map)['count']! as int;

  /// 每次启动调用：跨天则累计登录天数，返回是否跨天（供成就重新评估）。
  bool touchLogin() {
    final login = _data['login']! as Map;
    if (login['lastDate'] == _today) return false;
    login['lastDate'] = _today;
    login['count'] = (login['count']! as int) + 1;
    _save();
    notifyListeners();
    return true;
  }

  // ---- 背景音乐设置（首页"乐"入口：音量 + 曲目，2 个循环环境音对应替换）----

  /// -2 = 无背景音乐；-1 = 每次修行随机选曲；0..4 = 固定选 bgmTracks[i]。
  int get bgmTrackIndex => (_data['bgm']! as Map)['track']! as int;

  double get bgmVolume =>
      ((_data['bgm']! as Map)['volume'] as num?)?.toDouble() ?? 0.35;

  void setBgmSettings({int? track, double? volume}) {
    final m = _data['bgm']! as Map;
    if (track != null) m['track'] = track;
    if (volume != null) m['volume'] = volume.clamp(0.0, 1.0);
    _save();
    notifyListeners();
  }

  // ---- 修行首次教程（改进列表：每个修行第一次打开先看浮窗教程）----

  bool isTutorialSeen(String practiceId) =>
      (_data['tutorialsSeen']! as List).contains(practiceId);

  void markTutorialSeen(String practiceId) {
    final list = _data['tutorialsSeen']! as List;
    if (list.contains(practiceId)) return;
    list.add(practiceId);
    _save();
    notifyListeners();
  }

  // ---- 持久化 ----

  Future<bool>? _saveQueue;

  /// 等待已经排队的保存完成；false 表示原文件已保护或本次写盘失败。
  Future<bool> waitForSave() => _saveQueue ?? Future<bool>.value(!_persistenceBlocked);

  /// 串行化原子写盘：先写并刷新临时文件，保留上一份有效备份，再替换主文件。
  Future<bool> _save() {
    _saveQueue = (_saveQueue ?? Future<bool>.value(true)).then((_) async {
      final file = _file;
      if (file == null) return true;
      if (_persistenceBlocked) return false;
      final temp = File('${file.path}.tmp');
      final backup = File('${file.path}.bak');
      try {
        await temp.writeAsString(jsonEncode(_data), flush: true);
        if (await file.exists()) {
          await file.copy(backup.path);
        }
        await temp.rename(file.path);
        return true;
      } catch (e) {
        persistenceError = '本地存档保存失败，原文件未被覆盖：$e';
        notifyListeners();
        if (await temp.exists()) {
          await temp.delete();
        }
        return false;
      }
    });
    return _saveQueue!;
  }

  /// 清空全部数据（调试用，UI 侧有二次确认）。
  void reset() {
    _data
      ..clear()
      ..addAll(_defaults({}));
    _save();
    notifyListeners();
  }
}

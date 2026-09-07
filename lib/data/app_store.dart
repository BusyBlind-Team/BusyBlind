import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 本地优先的数据层（设计方案原则 4）。
///
/// v0.1 用 JSON 文档存储，字段结构即未来 Drift 表的草图；
/// 迁移 SQLite 时只动本文件，Domain 与 UI 不感知。
/// 断网时全部功能可用；服务器只负责同步与好友社交（v0.1 未接入）。
class AppStore extends ChangeNotifier {
  AppStore._(this._data, this._file);

  final Map<String, Object?> _data;
  final File? _file;

  static Future<AppStore> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/busy_blind.json');
    Map<String, Object?> data = {};
    if (await file.exists()) {
      try {
        data = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
      } catch (_) {
        data = {};
      }
    }
    return AppStore._(applyMigrations(_defaults(data)), file);
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
    return data;
  }

  /// 测试与预览用：不落盘。
  factory AppStore.inMemory() => AppStore._(_defaults({}), null);

  static Map<String, Object?> _defaults(Map<String, Object?> data) => {
    'merit': data['merit'] ?? 0,
    'tutorialDone': data['tutorialDone'] ?? false,
    'meditation': data['meditation'] ?? {'date': '', 'earnedToday': 0},
    'dailySign': data['dailySign'] ?? {'lastDate': '', 'slips': []},
    'petals': data['petals'] ?? <String, int>{},
    'flowers': data['flowers'] ?? <String>[],
    'achievements': data['achievements'] ?? <String>[],
    'pendingMerit': data['pendingMerit'] ?? <Object?>[],
    'sessions': data['sessions'] ?? <Object?>[],
    'lUserUs': data['lUserUs'] ?? 0,
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

  // ---- 每日抽签（每日一次；奖励口径按设计方案建议 b：签文收藏，不发修为）----

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
    _save();
    notifyListeners();
  }

  // ---- 花瓣与图鉴 ----

  Map<String, int> get petals => (_data['petals']! as Map).cast<String, int>();

  List<String> get flowers => (_data['flowers']! as List).cast<String>();

  void addPetal(String speciesId) {
    final p = _data['petals']! as Map;
    p[speciesId] = (p[speciesId] as int? ?? 0) + 1;
    _save();
    notifyListeners();
  }

  /// 同种花瓣合成一朵花（待对齐：3 朵合一）。成功则扣花瓣并记入图鉴。
  bool fuseFlower(String speciesId, {int need = 3}) {
    final p = _data['petals']! as Map;
    if ((p[speciesId] as int? ?? 0) < need) return false;
    p[speciesId] = (p[speciesId] as int) - need;
    final flowers = _data['flowers']! as List;
    if (!flowers.contains(speciesId)) {
      flowers.add(speciesId);
    }
    _save();
    notifyListeners();
    return true;
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

  void addSession({
    required String practiceId,
    required int merit,
    required bool completed,
    required int durationMs,
    Map<String, Object?> metrics = const {},
  }) {
    (_data['sessions']! as List).add({
      'practiceId': practiceId,
      'merit': merit,
      'completed': completed,
      'durationMs': durationMs,
      'date': _today,
      'metrics': metrics,
    });
    final list = _data['sessions']! as List;
    if (list.length > 300) {
      list.removeRange(0, list.length - 300);
    }
    _save();
    notifyListeners();
  }

  // ---- 校准 ----

  int get lUserUs => _data['lUserUs']! as int;
  set lUserUs(int us) {
    _data['lUserUs'] = us;
    _save();
    notifyListeners();
  }

  // ---- 持久化 ----

  Future<void>? _saveQueue;

  /// 串行化写盘：连续快速变更时排队写入，避免文件写入交错损坏。
  Future<void> _save() {
    _saveQueue = (_saveQueue ?? Future<void>.value()).then((_) async {
      final file = _file;
      if (file == null) return;
      try {
        await file.writeAsString(jsonEncode(_data));
      } catch (e) {
        debugPrint('AppStore save failed: $e');
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

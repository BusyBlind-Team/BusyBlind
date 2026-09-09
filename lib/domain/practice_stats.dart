import 'dart:convert';

import '../core/practice/practice_registry.dart';
import '../data/app_store.dart';

/// 把修行记录聚合成纯数字摘要（digest）。
///
/// 隐私原则：这里产出的 JSON 是唯一会上传的内容——只有次数、时长、
/// 修为、误差、同步率等聚合数字，不含签文文本与逐次时间戳明细。
Map<String, Object?> buildPracticeDigest(AppStore store, {DateTime? now}) {
  final sessions = store.sessions;
  final today = now ?? DateTime.now();

  // ---- 总览 ----
  final dates = sessions.map((s) => s['date'] as String? ?? '').toSet()..remove('');
  var totalMinutes = 0;
  for (final s in sessions) {
    totalMinutes += ((s['durationMs'] as num? ?? 0) / 60000).round();
  }
  final overview = <String, Object?>{
    'totalSessions': sessions.length,
    'totalMerit': store.merit,
    'totalMinutes': totalMinutes,
    'activeDays': dates.length,
    'streakDays': _streakDays(dates, today),
    'petals': store.petalCount,
    'flowerKinds': store.flowers.length,
    'signCount': store.slips.length,
  };

  // ---- 按修行聚合（注册表顺序 + 打坐殿后）----
  final names = {for (final m in collectManifests()) m.id: m.name};
  names['meditation'] = '打坐';
  final buckets = <String, List<Map<String, Object?>>>{};
  for (final s in sessions) {
    final id = s['practiceId'] as String? ?? '';
    (buckets[id] ??= []).add(s);
  }
  final practiceOrder = [
    ...collectManifests().map((m) => m.id),
    'meditation',
  ];
  final practices = <Map<String, Object?>>[];
  for (final id in practiceOrder) {
    final list = buckets[id];
    if (list == null || list.isEmpty) continue;
    practices.add(_practiceSummary(id, names[id] ?? id, list));
  }

  // ---- 最近 14 天逐日 ----
  final last14 = <Map<String, Object?>>[];
  for (var i = 13; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final key = _ymd(day);
    var count = 0;
    var minutes = 0;
    var merit = 0;
    for (final s in sessions) {
      if (s['date'] != key) continue;
      count++;
      minutes += ((s['durationMs'] as num? ?? 0) / 60000).round();
      merit += s['merit'] as int? ?? 0;
    }
    last14.add({
      'date': key.substring(5), // MM-DD，省 token
      'count': count,
      'minutes': minutes,
      'merit': merit,
    });
  }

  return {'overview': overview, 'practices': practices, 'last14Days': last14};
}

Map<String, Object?> _practiceSummary(
  String id,
  String name,
  List<Map<String, Object?>> list,
) {
  final completed = list.where((s) => s['completed'] == true).toList();
  final summary = <String, Object?>{
    'id': id,
    'name': name,
    'count': list.length,
    'completionRatePct': (completed.length * 100 / list.length).round(),
    'totalMinutes': list.fold<int>(
      0,
      (a, s) => a + ((s['durationMs'] as num? ?? 0) / 60000).round(),
    ),
    'totalMerit': list.fold<int>(0, (a, s) => a + (s['merit'] as int? ?? 0)),
  };
  final metrics =
      list.map((s) => (s['metrics'] as Map?)?.cast<String, Object?>() ?? const {}).toList();

  // 专项指标：只统计该指标存在的记录，均值保留 1 位小数。
  double avg(Iterable<num> xs) =>
      xs.isEmpty ? 0 : (xs.fold<double>(0, (a, b) => a + b) / xs.length * 10).round() / 10;
  switch (id) {
    case 'wooden_fish':
      // 偏移秒：完成局与满拍总时长 107s 的差（快慢都算），与修为公式同口径。
      summary['avgOffsetSec'] = avg([
        for (final s in list)
          if (s['completed'] == true)
            (((s['metrics'] as Map)['totalMs'] as num? ?? 0) - 107000).abs() / 1000,
      ]);
      // 稳定度：1 − 单击间隔标准差/均值，越高越稳（直接算均值，不经过 1 位小数舍入）。
      final stabilities = [
        for (final m in metrics)
          if ((m['intervalMeanUs'] as num? ?? 0) > 0)
            (1 - (m['intervalStdUs'] as num? ?? 0) / (m['intervalMeanUs'] as num))
                .clamp(0.0, 1.0),
      ];
      summary['stabilityPct'] = stabilities.isEmpty
          ? 0
          : (stabilities.fold<double>(0, (a, b) => a + b) / stabilities.length * 100).round();
    case 'count_rain':
      summary['avgErrorDrops'] = avg([
        for (final m in metrics)
          if (m['error'] is num) m['error'] as num,
      ]);
    case 'tide_breath':
      summary['avgSyncPct'] = avg([
        for (final m in metrics)
          if (m['avgSync'] is num) (m['avgSync'] as num) * 100,
      ]);
    case 'fish_petals':
      final casts = metrics.fold<int>(0, (a, m) => a + (m['casts'] as int? ?? 0));
      summary['petalsCaught'] =
          metrics.fold<int>(0, (a, m) => a + (m['petalsCaught'] as int? ?? 0));
      summary['emptyRodPct'] =
          casts == 0 ? 0 : (metrics.fold<int>(0, (a, m) => a + (m['miscatch'] as int? ?? 0)) * 100 / casts).round();
    case 'cross_river':
      final jumps = metrics.fold<int>(0, (a, m) => a + (m['jumps'] as int? ?? 0));
      summary['avgScorePerJump'] = jumps == 0
          ? 0
          : (metrics.fold<double>(0, (a, m) => a + (m['score'] as num? ?? 0)) / jumps * 10).round() / 10;
  }
  return summary;
}

/// 连续修行天数：从今天往回数；今天还没修则从昨天起算（当天结束前不清零）。
int _streakDays(Set<String> dates, DateTime today) {
  var streak = 0;
  var day = today;
  if (!dates.contains(_ymd(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  while (dates.contains(_ymd(day))) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---- 修炼报告提示词 ----

/// 口吻设定：平和、带禅意、不说教。
const String kReportSystemPrompt =
    '你是闭眼修行 App「忙僧」的禅修导师。口吻平和、带一点禅意，像一位'
    '安静的同行者，不说教、不评判、不用感叹号堆砌热情。';

String buildReportUserPrompt(Map<String, Object?> digest) => '''
以下是用户全部修行记录的聚合统计（JSON，其中数字是真实数据）：
${const JsonEncoder.withIndent('  ').convert(digest)}

请据此为用户写一份修炼报告，要求：
1. 分四段，段首依次用「本期概览」「值得肯定」「可精进处」「下期建议」；
2. 全文不超过 400 字，用"你"称呼用户；
3. 只能引用上面给出的数字，不得编造或推算未提供的数据；
4. 「可精进处」结合数字指出一两个具体短板；「下期建议」给一条可执行的
   小目标（如某种修行的次数或某个指标的改进方向）。
''';

// ---- 本地模板报告（无 Key / 断网降级用，同样的摘要套模板句）----

String buildLocalReport(Map<String, Object?> digest) {
  final overview = (digest['overview'] as Map).cast<String, Object?>();
  final practices =
      ((digest['practices'] as List).cast<Map>()).map((m) => m.cast<String, Object?>()).toList();
  final last14 = (digest['last14Days'] as List).cast<Map>();

  final buffer = StringBuffer();
  buffer
    ..writeln('【本期概览】')
    ..writeln(
      '你已累计修行 ${overview['totalSessions']} 次、共 ${overview['totalMinutes']} 分钟，'
      '修为 ${overview['totalMerit']}；活跃 ${overview['activeDays']} 天，'
      '近期连续 ${overview['streakDays']} 天。'
      '途中拾得花瓣 ${overview['petals']} 片、养出花 ${overview['flowerKinds']} 种，'
      '求得签文 ${overview['signCount']} 张。',
    );

  buffer
    ..writeln()
    ..writeln('【值得肯定】');
  final most = practices.fold<Map<String, Object?>?>(null, (a, p) =>
      a == null || (p['count'] as int) > (a['count'] as int) ? p : a);
  final days14 = last14.fold<int>(0, (a, d) => a + (d['count'] as int? ?? 0));
  if (most != null) {
    buffer.writeln(
      '${most['name']}练得最多，共 ${most['count']} 次、完成率 ${most['completionRatePct']}%。'
      '最近 14 天你修了 $days14 次——山不高，一步步走，就已经在路上。',
    );
  } else {
    buffer.writeln('路还长，不急。先坐下来，就是好的开始。');
  }

  buffer
    ..writeln()
    ..writeln('【可精进处】');
  final weaknesses = <String>[];
  for (final p in practices) {
    final s = _specialtyLine(p);
    if (s != null) weaknesses.add(s);
  }
  buffer.writeln(
      weaknesses.isEmpty ? '暂无短板记录，继续保持。' : '${weaknesses.take(3).join('；')}。');

  buffer
    ..writeln()
    ..writeln('【下期建议】')
    ..writeln(
      most == null
          ? '不妨从一分钟的静坐开始，让耳朵先习惯安静。'
          : '不妨每天留一段固定的时间给「${most['name']}」，哪怕很短；'
              '节奏慢下来，偏差自然会小。',
    )
    ..writeln()
    ..writeln('—— 本地模板生成（未调用 AI），数据与你同在手机里。');
  return buffer.toString().trim();
}

/// 单个修行的专项指标一句话；无专项指标的修行（静坐/打坐）返回 null。
String? _specialtyLine(Map<String, Object?> p) {
  switch (p['id'] as String) {
    case 'wooden_fish':
      return '木鱼平均偏移 ${p['avgOffsetSec']} 秒、稳定度 ${p['stabilityPct']}%';
    case 'count_rain':
      return '数雨平均误差 ${p['avgErrorDrops']} 滴';
    case 'tide_breath':
      return '听潮平均同步率 ${p['avgSyncPct']}%';
    case 'fish_petals':
      return '钓花收得 ${p['petalsCaught']} 片花瓣、空竿率 ${p['emptyRodPct']}%';
    case 'cross_river':
      return '过河平均每跳得 ${p['avgScorePerJump']} 分';
    default:
      return null; // 静坐/打坐无专项指标
  }
}

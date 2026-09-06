import 'practice_types.dart';

/// 统一结算对象：宿主据此发修为、判成就、入库。
///
/// 修为换算公式属于玩法规则的一部分（各修行不同），由会话在 [merit] 里给出；
/// 宿主只做统一校验（上限 clamp、防负值），保证经济口径单点可调。
class PracticeResult {
  const PracticeResult({
    required this.effectiveDuration,
    required this.quality,
    required this.merit,
    this.metrics = const {},
    this.extraRewards = const [],
    this.completed = true,
    this.note,
  });

  /// 有效专注时长（已扣除中断）。
  final Duration effectiveDuration;

  /// 0..1，玩法自评的完成质量。
  final double quality;

  /// 本次应发修为（宿主结算前会按 manifest.meritBase 做 clamp）。
  final int merit;

  /// 玩法私有指标，存库供曲线与复盘用。
  final Map<String, Object?> metrics;

  /// 额外奖励（花瓣、签文等）。
  final List<Reward> extraRewards;

  final bool completed;

  /// 特殊标记（如 'sleep_mode'：助眠模式，不弹结算页、修为次日补发）。
  final String? note;
}

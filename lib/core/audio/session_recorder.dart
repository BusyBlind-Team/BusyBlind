/// 一条原始记录：(会话音频时间戳, 事件类型, 载荷)。
class RecEvent {
  const RecEvent({
    required this.sessionUs,
    required this.type,
    this.data = const {},
  });

  final int sessionUs;
  final String type;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    't': sessionUs,
    'type': type,
    ...data,
  };
}

/// 全程记录 (音频时间戳, 事件类型) 的原始序列。
///
/// 所有分析（木鱼频率曲线、呼吸同步率、过河与钓花的判定、数雨对账）
/// 都是事后对同一份原始数据做计算，不在玩法代码里边玩边算。
/// 好处：调参不用改玩法、可以复算历史数据、便于导出调试。
class SessionRecorder {
  /// [nowUs] 提供当前会话音频时间（通常传 scheduler.nowUs 的 tear-off）。
  SessionRecorder(this._nowUs);

  final int Function() _nowUs;
  final List<RecEvent> events = [];

  void log(String type, [Map<String, Object?> data = const {}]) {
    events.add(
      RecEvent(sessionUs: _nowUs(), type: type, data: data),
    );
  }

  /// 按类型取全部记录（输入事件统一记为 input:down / input:up / input:cancel）。
  List<RecEvent> byType(String type) =>
      events.where((e) => e.type == type).toList(growable: false);

  void clear() => events.clear();
}

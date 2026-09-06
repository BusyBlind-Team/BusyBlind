/// 修行契约的公共枚举与奖励类型。
library;

/// 训练类型标签（修行列表与筛选用）。
enum TrainingTag {
  focus('专注'),
  rhythm('节奏'),
  breath('呼吸'),
  patience('耐心'),
  collect('收集'),
  sleep('助眠'),
  noise('白噪声');

  const TrainingTag(this.label);
  final String label;
}

/// 眼态：所有玩法必须在闭眼前提下成立，画面只是睁眼奖励。
enum EyeMode {
  eyesClosed('全程闭眼'),
  openThenClosed('开局睁眼 → 闭眼'),
  eyesOpen('全程睁眼');

  const EyeMode(this.label);
  final String label;
}

/// 结束原因。
enum FinishReason {
  completed('完成'),
  userEnded('用户结束'),
  cancelled('取消'),
  interrupted('中断'),
  antiIdle('挂机超时');

  const FinishReason(this.label);
  final String label;
}

/// 中断原因：来电 / 通知 / 退后台。
enum InterruptReason { appBackgrounded, phoneCall, notification }

/// 奖励类型。
enum RewardKind { petal, slip }

/// 统一奖励（如钓花的花瓣、抽签的签文收藏）。
class Reward {
  const Reward({required this.kind, required this.id, required this.label});

  final RewardKind kind;

  /// 花瓣=物种 id；签文=文案 id。
  final String id;
  final String label;
}

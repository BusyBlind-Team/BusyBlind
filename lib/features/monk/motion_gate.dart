import 'dart:math';

/// 打坐反挂机第三重的判定门（设计方案 6.4）：
/// 检测"持续大幅位移（如走路）"，命中则暂停计时；安静后自动恢复。
///
/// 纯逻辑、可测试：滑动窗口内"运动样本占比 ≥ dutyThreshold"判为走动。
/// 判定输入是加速度合模长对重力（≈9.81）的偏离幅值。
class MotionGate {
  MotionGate({
    this.windowMs = 5000,
    this.deviationThreshold = 2.5,
    this.dutyThreshold = 0.4,
  });

  /// 观察窗口：越长越抗抖，但恢复越迟钝。
  final int windowMs;

  /// 单样本运动阈值（m/s²）。静坐的呼吸/手抖远低于此，步行明显高于此。
  final double deviationThreshold;

  /// 窗口内运动样本占比达到该值判为"走动"。
  final double dutyThreshold;

  final List<(int, bool)> _samples = [];

  /// 喂入一个样本，返回当前是否判为走动。
  bool feed(int tMs, double deviationMs2) {
    _samples.add((tMs, deviationMs2 >= deviationThreshold));
    while (_samples.isNotEmpty && tMs - _samples.first.$1 > windowMs) {
      _samples.removeAt(0);
    }
    if (_samples.isEmpty) return false;
    final moved = _samples.where((s) => s.$2).length;
    return moved / _samples.length >= dutyThreshold;
  }

  /// 重置窗口（如页面恢复前台时，避免陈旧样本误判）。
  void reset() => _samples.clear();
}

/// 便捷计算：三轴加速度的合模长对重力的偏离。
double deviationFromGravity(double x, double y, double z) {
  return sqrt(x * x + y * y + z * z) - 9.81;
}

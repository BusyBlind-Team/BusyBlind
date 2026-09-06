/// 修为等级（区间沿用框架提示词，按半开区间 [min, next) 实现，避免边界重叠）。
class MeritLevel {
  const MeritLevel(this.minMerit, this.title);

  final int minMerit;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is MeritLevel && other.minMerit == minMerit && other.title == title;

  @override
  int get hashCode => Object.hash(minMerit, title);
}

const List<MeritLevel> kMeritLevels = [
  MeritLevel(0, '浪子'),
  MeritLevel(50, '居士'),
  MeritLevel(200, '行者'),
  MeritLevel(500, '沙弥'),
  MeritLevel(1000, '比丘'),
  MeritLevel(2000, '方丈'),
  MeritLevel(5000, '罗汉'),
  MeritLevel(10000, '菩萨'),
];

MeritLevel levelForMerit(int merit) {
  var level = kMeritLevels.first;
  for (final l in kMeritLevels) {
    if (merit >= l.minMerit) level = l;
  }
  return level;
}

/// 距下一级所需的总修为；已至最高级返回 null。
int? nextLevelThreshold(int merit) {
  for (final l in kMeritLevels) {
    if (merit < l.minMerit) return l.minMerit;
  }
  return null;
}

/// 当前等级区间的下限（修为条按比例显示用）。
int currentLevelFloor(int merit) => levelForMerit(merit).minMerit;

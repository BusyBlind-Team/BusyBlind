import 'package:busy_blind/domain/merit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('修为等级（半开区间 [min, next)）', () {
    test('边界值', () {
      expect(levelForMerit(0).title, '浪子');
      expect(levelForMerit(49).title, '浪子');
      expect(levelForMerit(50).title, '居士');
      expect(levelForMerit(199).title, '居士');
      expect(levelForMerit(200).title, '行者');
      expect(levelForMerit(500).title, '沙弥');
      expect(levelForMerit(999).title, '沙弥');
      expect(levelForMerit(1000).title, '比丘');
      expect(levelForMerit(2000).title, '方丈');
      expect(levelForMerit(5000).title, '罗汉');
      expect(levelForMerit(9999).title, '罗汉');
      expect(levelForMerit(10000).title, '菩萨');
      expect(levelForMerit(999999).title, '菩萨');
    });

    test('下一级阈值', () {
      expect(nextLevelThreshold(0), 50);
      expect(nextLevelThreshold(49), 50);
      expect(nextLevelThreshold(5000), 10000);
      expect(nextLevelThreshold(10000), isNull);
    });

    test('当前等级下限（修为条比例用）', () {
      expect(currentLevelFloor(60), 50);
      expect(currentLevelFloor(12345), 10000);
    });
  });
}

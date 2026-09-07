import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/features/monk/motion_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionGate（打坐反挂机第三重：持续大幅位移判定）', () {
    test('静坐呼吸/手抖：远低于阈值，不判走动', () {
      final gate = MotionGate();
      var moving = false;
      for (var i = 0; i < 60; i++) {
        // 呼吸级起伏 ±0.5 m/s²。
        moving = gate.feed(i * 100, 0.2 + 0.3 * (i % 3));
      }
      expect(moving, isFalse);
    });

    test('持续步行：运动样本占半数以上，判走动', () {
      final gate = MotionGate();
      var moving = false;
      for (var i = 0; i < 60; i++) {
        // 步频冲击：一半样本超阈值。
        final dev = i.isEven ? 0.4 : 4.5;
        moving = gate.feed(i * 100, dev);
      }
      expect(moving, isTrue);
    });

    test('单次急动不会误判；安静 5 秒后自动恢复', () {
      final gate = MotionGate();
      var moving = false;
      for (var i = 0; i < 50; i++) {
        moving = gate.feed(i * 100, 0.3);
      }
      // 一次拿手机的动作。
      moving = gate.feed(50 * 100, 6.0);
      expect(moving, isFalse, reason: '一个尖峰占窗口比例过低');
      // 之后持续安静：窗口滑过尖峰后仍是 false。
      for (var i = 51; i < 110; i++) {
        moving = gate.feed(i * 100, 0.3);
      }
      expect(moving, isFalse);
    });

    test('停止走动后：窗口滑出即恢复（约 5 秒迟滞）', () {
      final gate = MotionGate();
      // 6 秒步行。
      for (var i = 0; i < 60; i++) {
        gate.feed(i * 100, i.isEven ? 0.4 : 4.5);
      }
      expect(gate.feed(6000, 0.3), isTrue);
      // 安静 5.1 秒：全部运动样本滑出窗口。
      for (var i = 61; i <= 111; i++) {
        gate.feed(6000 + (i - 60) * 100, 0.3);
      }
      expect(gate.feed(6000 + 5200, 0.3), isFalse);
    });

    test('deviationFromGravity：静止时约 0，冲击量级明显', () {
      // 静止（只受重力）→ 偏离 0。
      expect(deviationFromGravity(0, 0, 9.81).abs(), lessThan(0.001));
      // 同轴冲击 3 m/s² → 偏离 3。注：静态倾斜（水平轴加速度）因矢量
      // 合成产生的偏离远小于其数值，走步检测靠的是步频冲击期的模长震荡。
      expect(deviationFromGravity(0, 0, 12.81).abs(), greaterThan(2.9));
    });
  });

  group('AppStore.tutorialDone', () {
    test('默认未完成；置位后可读', () {
      final store = AppStore.inMemory();
      expect(store.tutorialDone, isFalse);
      store.tutorialDone = true;
      expect(store.tutorialDone, isTrue);
    });
  });
}

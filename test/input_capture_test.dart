import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

void main() {
  test('pointer timestamp is projected onto the gameplay session timeline', () {
    final clock = FakeClock(2000000);
    final scheduler = EventScheduler(clock, SilentSoundBank());
    scheduler.begin();
    final input = InputCapture(clock);

    // 触摸发生在 3.0s，映射到音频时间轴后投影到本会话为 1.0s。
    // 当前时钟仍在 2.0s，确保断言不依赖事件被处理时的“现在”。
    // （用户校准偏移已随"时机校准"功能删除——Bug 描述 #3。）
    final event = input.capture(
      const PointerDownEvent(timeStamp: Duration(seconds: 3)),
      scheduler.toSessionUs,
    );

    expect(event.absAudioUs, 3000000);
    expect(event.sessionUs, 1000000);
    scheduler.dispose();
  });
}

import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/input_capture.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

class _OffsetClock extends FakeClock {
  _OffsetClock(super.initialUs);

  @override
  int touchToAudioUs(int rawTouchUs) => rawTouchUs - userOffsetUs;
}

void main() {
  test('calibrated pointer timestamp is projected onto the gameplay session timeline', () {
    final clock = _OffsetClock(2000000)..userOffsetUs = 200000;
    final scheduler = EventScheduler(clock, SilentSoundBank());
    scheduler.begin();
    final input = InputCapture(clock);

    // 触摸发生在 3.0s；校准后音频时刻应为 2.8s，映射到本会话为 0.8s。
    // 当前时钟仍在 2.0s，确保断言不依赖事件被处理时的“现在”。
    final event = input.capture(
      const PointerDownEvent(timeStamp: Duration(seconds: 3)),
      scheduler.toSessionUs,
    );

    expect(event.absAudioUs, 2800000);
    expect(event.sessionUs, 800000);
    scheduler.dispose();
  });
}

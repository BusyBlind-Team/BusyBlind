import 'package:busy_blind/core/audio/event_scheduler.dart';
import 'package:busy_blind/core/audio/session_recorder.dart';
import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'helpers/fake_clock.dart';

void main() {
  test('事件按音频时间触发；暂停期间会话时间轴冻结', () {
    fakeAsync((async) {
      final clock = FakeClock(1000000);
      final sounds = SilentSoundBank();
      late final EventScheduler scheduler;
      final recorder = SessionRecorder(() => scheduler.nowUs());
      scheduler = EventScheduler(clock, sounds, recorder: recorder);
      scheduler.begin(); // base = 1_000_000

      var fired = false;
      scheduler.scheduleCallback(2000000, () => fired = true);
      scheduler.scheduleSound(600000, 'tick', gain: 0.5);

      clock.advanceUs(500000);
      async.elapse(const Duration(milliseconds: 200));
      expect(fired, isFalse);
      expect(sounds.played, contains('tick')); // 0.6s 事件在预约窗口内已触发

      // 暂停 1 秒（真实时钟走，会话时间轴不走）。
      scheduler.pause();
      clock.advanceUs(1000000);
      async.elapse(const Duration(milliseconds: 100));
      expect(fired, isFalse);

      scheduler.resume();
      // 会话时间应仍为 0.5s：clock 2.5M − base 1M − 暂停 1M。
      expect(scheduler.nowUs(), 500000);

      clock.advanceUs(600000);
      async.elapse(const Duration(milliseconds: 100));
      expect(fired, isFalse); // 会话时间 1.1s < 2s

      clock.advanceUs(1000000);
      async.elapse(const Duration(milliseconds: 200));
      expect(fired, isTrue); // 会话时间 2.1s ≥ 2s
      expect(recorder.events.where((e) => e.type == 'sound:tick'), isNotEmpty);

      scheduler.dispose();
    });
  });

  test('cancelAll 丢弃未触发事件', () {
    fakeAsync((async) {
      final clock = FakeClock();
      final scheduler = EventScheduler(clock, SilentSoundBank());
      scheduler.begin();

      var fired = false;
      scheduler.scheduleCallback(5000000, () => fired = true);
      scheduler.cancelAll();

      clock.advanceUs(6000000);
      async.elapse(const Duration(milliseconds: 200));
      expect(fired, isFalse);

      scheduler.dispose();
    });
  });
}

import 'package:busy_blind/core/audio/audio_clock.dart';

/// 测试用可控时钟。
class FakeClock implements AudioClock {
  FakeClock([int initialUs = 0]) : _now = initialUs;

  int _now;

  void advanceUs(int us) => _now += us;

  @override
  int nowUs() => _now;

  @override
  int touchToAudioUs(int rawTouchUs) => rawTouchUs;

  @override
  void noteTouchEvent(int rawTouchUs) {}

  @override
  int outputLatencyUs = 0;

  @override
  int userOffsetUs = 0;

  @override
  Stream<int> beats(int periodUs) => const Stream<int>.empty();

  @override
  void dispose() {}
}

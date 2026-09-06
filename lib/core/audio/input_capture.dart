import 'package:flutter/gestures.dart';

import 'audio_clock.dart';

enum PointerPhase { down, up, cancel }

/// 统一输入事件：带音频时间戳。
///
/// 判定一律使用 [sessionUs] / [absAudioUs]（补偿后的音频时间），
/// 不使用系统墙钟时间——这是"时机即体验"原则的落地。
class InputEvent {
  const InputEvent({
    required this.phase,
    required this.absAudioUs,
    required this.sessionUs,
    required this.rawTimeStamp,
  });

  final PointerPhase phase;
  final int absAudioUs;
  final int sessionUs;

  /// 原始事件时间戳，保留供未来更精细的补偿复算。
  final Duration rawTimeStamp;
}

/// 把 Flutter pointer 事件转成带音频时间戳的统一输入。
class InputCapture {
  InputCapture(this._clock);

  final AudioClock _clock;

  InputEvent capture(PointerEvent event, int Function() sessionNowUs) {
    _clock.noteTouchEvent(event.timeStamp.inMicroseconds);
    final absUs = _clock.touchToAudioUs(event.timeStamp.inMicroseconds);
    return InputEvent(
      phase: switch (event) {
        PointerDownEvent() => PointerPhase.down,
        PointerUpEvent() => PointerPhase.up,
        PointerCancelEvent() => PointerPhase.cancel,
        _ => PointerPhase.cancel,
      },
      absAudioUs: absUs,
      sessionUs: sessionNowUs(),
      rawTimeStamp: event.timeStamp,
    );
  }
}

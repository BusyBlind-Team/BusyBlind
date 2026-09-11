/// 基座一：AudioClock（音频时钟）。
///
/// 所有事件的调度与判定共用同一根时间轴（微秒）。
/// v0.1 用单调时钟实现，并预留输出延迟 L_out 的补偿位（用户校准偏移
/// L_user 已随"时机校准"功能删除——Bug 描述 #3）；
/// 后续接入原生音频渲染时钟（AVAudioEngine / Oboe）时只需替换实现，接口不变。
abstract class AudioClock {
  /// 当前音频时间（微秒）。
  int nowUs();

  /// 输入时刻（微秒）→ 补偿后的音频时间。
  /// 实现方需先经 [noteTouchEvent] 建立输入时间轴与音频时间轴的映射。
  int touchToAudioUs(int rawTouchUs);

  /// 每次 pointer 事件到达时调用一次，用于标定输入时间轴与音频时间轴的映射。
  void noteTouchEvent(int rawTouchUs);

  /// 平台报告的输出延迟（iOS AVAudioSession.outputLatency / Android AudioTrack）。
  int get outputLatencyUs;
  set outputLatencyUs(int us);

  /// 采样精度的节拍流（用于校准节拍器）。
  Stream<int> beats(int periodUs);

  void dispose();
}

class SystemAudioClock implements AudioClock {
  SystemAudioClock() {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();

  @override
  int nowUs() => _stopwatch.elapsedMicroseconds;

  int _outputLatency = 0;

  // 输入事件时间轴（e.timeStamp 的纪元）与音频时间轴的映射，
  // 在第一个输入事件到达时标定一次。
  bool _touchMapped = false;
  int _touchMapUs = 0;

  @override
  void noteTouchEvent(int rawTouchUs) {
    if (!_touchMapped) {
      _touchMapUs = nowUs() - rawTouchUs;
      _touchMapped = true;
    }
  }

  @override
  int touchToAudioUs(int rawTouchUs) {
    if (!_touchMapped) {
      // 尚未有任何输入事件到达：退化为"处理时刻即输入时刻"。
      return nowUs();
    }
    return rawTouchUs + _touchMapUs - _outputLatency;
  }

  @override
  int get outputLatencyUs => _outputLatency;
  @override
  set outputLatencyUs(int us) => _outputLatency = us;

  @override
  Stream<int> beats(int periodUs) {
    final duration = Duration(microseconds: periodUs);
    return Stream<int>.periodic(duration, (_) => nowUs());
  }

  @override
  void dispose() {}
}

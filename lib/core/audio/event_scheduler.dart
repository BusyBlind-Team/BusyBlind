import 'dart:async';

import 'audio_clock.dart';
import 'session_recorder.dart';
import 'sound_bank.dart';

/// 按音频时间预排的事件调度器。
///
/// 所有"几秒后播一声钟"的需求都提交到这里：事件提交后由调度器在
/// [lookaheadUs] 提前量内预约播放（一次性 Timer 精确到毫秒级触发），
/// 而不是到点才触发。即使 UI 线程卡顿，声音节奏依然精准。
///
/// 调度器维护一根"会话时间轴"（session µs）：从 [begin] 起算，
/// [pause]/[resume] 时自动累计暂停时长，所有已排事件在会话时间轴上的
/// 位置不变——中断恢复后节奏照旧。
class EventScheduler {
  EventScheduler(
    this._clock,
    this._sounds, {
    SessionRecorder? recorder,
    this.lookaheadUs = 200000,
    this.tickInterval = const Duration(milliseconds: 40),
  }) : _recorder = recorder;

  final AudioClock _clock;
  final SoundBank _sounds;
  final SessionRecorder? _recorder;

  /// 提前预约窗口：进入窗口的事件立即预约一次性触发。
  final int lookaheadUs;
  final Duration tickInterval;

  int _baseUs = 0;
  int _pausedTotalUs = 0;
  int? _pausedAtUs;
  bool _running = false;
  Timer? _ticker;

  final List<_SchedItem> _items = [];
  final List<Timer> _pendingWallTimers = [];

  bool get isRunning => _running;

  /// 开始一根新的会话时间轴。
  void begin() {
    _baseUs = _clock.nowUs();
    _pausedTotalUs = 0;
    _pausedAtUs = null;
    _items.clear();
    _cancelWallTimers();
    _running = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
  }

  /// 会话时间轴当前时刻（µs，自 begin 起算，不含暂停）。
  int nowUs() => _clock.nowUs() - _baseUs - _pausedTotalUs;

  /// 绝对音频时间 → 会话时间。
  int toSessionUs(int absAudioUs) => absAudioUs - _baseUs - _pausedTotalUs;

  /// 在会话时间 atUs 播放音效。
  void scheduleSound(int atUs, String soundKey, {double gain = 1.0}) {
    _items.add(_SchedItem(atUs, soundKey: soundKey, gain: gain));
  }

  /// 在会话时间 atUs 执行回调（相位切换、结算收口等）。
  void scheduleCallback(int atUs, void Function() fn) {
    _items.add(_SchedItem(atUs, fn: fn));
  }

  void pause() {
    if (!_running || _pausedAtUs != null) return;
    _pausedAtUs = _clock.nowUs();
    _cancelWallTimers();
  }

  void resume() {
    if (_pausedAtUs == null) return;
    _pausedTotalUs += _clock.nowUs() - _pausedAtUs!;
    _pausedAtUs = null;
  }

  void cancelAll() {
    _items.removeWhere((e) => !e.fired);
    _cancelWallTimers();
  }

  void dispose() {
    _ticker?.cancel();
    _cancelWallTimers();
    _items.clear();
    _running = false;
  }

  void _cancelWallTimers() {
    for (final t in _pendingWallTimers) {
      t.cancel();
    }
    _pendingWallTimers.clear();
    for (final item in _items) {
      if (item.armed) {
        item
          ..armed = false
          ..fired = false;
      }
    }
  }

  void _tick() {
    if (!_running || _pausedAtUs != null) return;
    final now = nowUs();
    final horizon = now + lookaheadUs;
    for (final item in _items) {
      if (!item.fired && !item.armed && item.atUs <= horizon) {
        item.armed = true;
        final delayUs = item.atUs - now;
        final timer = Timer(
          Duration(microseconds: delayUs < 0 ? 0 : delayUs),
          () => _fire(item),
        );
        _pendingWallTimers.add(timer);
      }
    }
  }

  void _fire(_SchedItem item) {
    item.fired = true;
    _pendingWallTimers.removeWhere((t) => !t.isActive);
    if (item.soundKey != null) {
      _recorder?.log('sound:${item.soundKey}');
      _sounds.play(item.soundKey!, gain: item.gain);
    }
    item.fn?.call();
  }
}

class _SchedItem {
  _SchedItem(this.atUs, {this.soundKey, this.gain = 1.0, this.fn});

  final int atUs;
  final String? soundKey;
  final double gain;
  final void Function()? fn;

  bool armed = false;
  bool fired = false;
}

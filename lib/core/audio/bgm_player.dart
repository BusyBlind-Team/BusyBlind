import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_catalog.dart';

/// 修行 BGM（改进列表）：开始修行时从五首里随机挑一首，
/// 放完等待一秒从头再放；结束修行或退后台时暂停/停止。
class BgmPlayer {
  BgmPlayer();

  AudioPlayer? _player;
  String? _asset;
  bool _stopped = true;
  bool _paused = false;

  /// 当前曲名（空串 = 未在播放）。
  String _trackName = '';
  String get trackName => _trackName;

  StreamSubscription<void>? _completeSub;

  static const double _volume = 0.32;

  /// 随机选曲并开始播放。重复调用先停旧的再起新的。
  /// 无音频环境（测试/无设备）静默降级为不播放。
  Future<void> start() async {
    await stop();
    try {
      final track = SoundCatalog
          .bgmTracks[Random().nextInt(SoundCatalog.bgmTracks.length)];
      final player = AudioPlayer();
      _stopped = false;
      _paused = false;
      _asset = SoundCatalog.catalog[track.key];
      _trackName = track.name;
      _completeSub = player.onPlayerComplete.listen((_) => _replayAfterGap());
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_volume);
      await player.play(AssetSource(_asset!));
      _player = player;
    } catch (e) {
      debugPrint('BgmPlayer unavailable: $e');
      _stopped = true;
      _paused = false;
      _asset = null;
      _trackName = '';
      await _player?.dispose();
      _player = null;
    }
  }

  /// 放完歇一秒，从头再放。
  Future<void> _replayAfterGap() async {
    if (_stopped) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_stopped || _paused) return;
    try {
      await _player?.play(AssetSource(_asset!));
    } on Exception {
      // 播放器已被释放（页面退出竞态），静默结束。
    }
  }

  Future<void> pause() async {
    if (_stopped || _paused) return;
    _paused = true;
    await _player?.pause();
  }

  Future<void> resume() async {
    if (_stopped || !_paused) return;
    _paused = false;
    await _player?.resume();
  }

  Future<void> stop() async {
    if (_stopped && _player == null) return;
    _stopped = true;
    _paused = false;
    _trackName = '';
    _completeSub?.cancel();
    _completeSub = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } on Exception {
        // 已释放则忽略。
      }
    }
  }
}

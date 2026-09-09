import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_catalog.dart';

/// 修行 BGM（改进列表）：开始修行时按设置播一首（可随机/固定/无），
/// 放完等待一秒从头再放；结束修行时停止，退后台时暂停、回前台恢复。
class BgmPlayer {
  BgmPlayer();

  AudioPlayer? _player;
  String? _asset;
  bool _stopped = true;
  bool _paused = false;

  /// 启动期间退到后台：播放器完成准备但不发声，标记待播，
  /// resume() 时从头播放（复审 P2：区分暂停与停止，保留可恢复状态）。
  bool _pendingPlay = false;

  /// 当前曲名（空串 = 未在播放）。
  String _trackName = '';
  String get trackName => _trackName;

  StreamSubscription<void>? _completeSub;
  double _volume = 0.35;

  /// 启动代数：每次 start/stop 递增。start() 的每一步 await 后都核对
  /// 代数与停止标记，退出竞态下会把半路启动的播放器就地释放（复审 P2-3）。
  int _generation = 0;

  /// 开始播放：[trackIndex] 为 -1 时随机选曲；[asset] 直接指定资产
  /// （宿主已为整局解析好同一首）；[volume] 0..1。
  /// 重复调用先停旧的再起新的。无音频环境（测试/无设备）静默降级为不播放。
  Future<void> start({int trackIndex = -1, double volume = 0.35, String? asset}) async {
    await stop();
    final gen = _generation;
    AudioPlayer? player;
    try {
      final tracks = SoundCatalog.bgmTracks;
      var track = (trackIndex >= 0 && trackIndex < tracks.length)
          ? tracks[trackIndex]
          : tracks[Random().nextInt(tracks.length)];
      if (asset != null) {
        track = tracks.firstWhere(
          (t) => SoundCatalog.catalog[t.key] == asset,
          orElse: () => track,
        );
      }
      player = AudioPlayer();
      // 先登记再 await：期间被 stop()/dispose() 也能停到它。
      _player = player;
      _stopped = false;
      _paused = false;
      _pendingPlay = false;
      _asset = SoundCatalog.catalog[track.key];
      _trackName = track.name;
      _volume = volume.clamp(0.0, 1.0);
      _completeSub = player.onPlayerComplete.listen((_) => _replayAfterGap());
      await player.setReleaseMode(ReleaseMode.stop);
      // 停止/换代 → 释放半路播放器并立即退出启动流程，
      // 不得再操作已释放的播放器（复审 P2-3）。
      if (_stopped || gen != _generation) {
        await _abandon(player);
        return;
      }
      await player.setVolume(_volume);
      if (_stopped || gen != _generation) {
        await _abandon(player);
        return;
      }
      if (_paused) {
        // 启动期间已退到后台：完成准备但不发声，resume() 时从头播放。
        _pendingPlay = true;
      } else {
        await player.play(AssetSource(_asset!));
        // play 期间退到后台的：启动完成后立即补暂停。
        if (_paused && !_stopped && gen == _generation) {
          await player.pause();
        }
      }
    } catch (e) {
      debugPrint('BgmPlayer unavailable: $e');
      _stopped = true;
      _paused = false;
      _pendingPlay = false;
      _asset = null;
      _trackName = '';
      await player?.dispose();
      if (_player == player) _player = null;
    }
  }

  /// 启动中途被取消：释放半路播放器，不改动新状态。
  Future<void> _abandon(AudioPlayer player) async {
    try {
      await player.dispose();
    } on Exception {
      // 已释放则忽略。
    }
    if (_player == player) _player = null;
  }

  /// 放完歇一秒，从头再放；歇的期间退后台 → 标记待播，恢复时再放。
  Future<void> _replayAfterGap() async {
    if (_stopped) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_stopped) return;
    if (_paused) {
      _pendingPlay = true;
      return;
    }
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
    if (_pendingPlay) {
      // 启动期间被挂起的首次播放。
      _pendingPlay = false;
      try {
        await _player?.play(AssetSource(_asset!));
      } on Exception {
        // 播放器已被释放（页面退出竞态），静默结束。
      }
      return;
    }
    await _player?.resume();
  }

  Future<void> stop() async {
    _generation++;
    if (_stopped && _player == null) return;
    _stopped = true;
    _paused = false;
    _pendingPlay = false;
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

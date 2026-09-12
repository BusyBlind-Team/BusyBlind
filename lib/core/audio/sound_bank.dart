import 'package:audioplayers/audioplayers.dart' as ap;

/// 音效库：短音效预加载进内存池，禁止播放时解码。
///
/// v0.1 用 audioplayers 的 AudioPool 实现（一次加载、多路复用、低延迟触发）；
/// 后续替换为原生 AVAudioEngine / Oboe 或 soLoud 时接口不变。
abstract class SoundBank {
  /// 注册 key → asset 相对路径，只登记不加载。
  ///
  /// 供按需流式播放的长音轨使用（BGM、被曲目替换的环境循环）：注册后
  /// startLoop 能找到资产；短音效的零延迟触发仍走 [preload]。
  Future<void> register(Map<String, String> assetByKey);

  /// 预加载 key → asset 相对路径（AssetSource 形式，如 'sfx/muyu.mp3'）。
  Future<void> preload(Map<String, String> assetByKey);

  /// 触发一声短音效（可多路叠加）。
  Future<void> play(String key, {double gain = 1.0});

  /// 循环长音轨（潮汐、白噪声背景）。
  ///
  /// [startAt] 用于从音轨的随机时间点起播（新-改进说明文档 §14：环境音
  /// "随机选择音频的一个时间点开始播放，播完后从头循环"）。
  Future<void> startLoop(String key, {double gain = 1.0, Duration? startAt});
  Future<void> setLoopGain(String key, double gain);
  Future<void> stopLoop(String key);

  Future<void> pauseAll();
  Future<void> resumeAll();
  void dispose();
}

/// 测试与静音模式用的空实现。
class SilentSoundBank implements SoundBank {
  final List<String> played = [];

  /// 循环音轨的起停记录（复审 #2/#3 的回归观察点）。
  final List<String> loopsStarted = [];
  final List<String> loopsStopped = [];
  final List<(String key, double gain)> loopGainChanges = [];

  /// 模拟起播耗时（测试"发起播放"与"开始判定"分离用）。
  Duration startDelay = Duration.zero;

  @override
  Future<void> register(Map<String, String> assetByKey) async {}

  @override
  Future<void> preload(Map<String, String> assetByKey) async {}

  @override
  Future<void> play(String key, {double gain = 1.0}) async {
    played.add(key);
  }

  @override
  Future<void> startLoop(String key, {double gain = 1.0, Duration? startAt}) async {
    loopsStarted.add(key);
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
  }

  @override
  Future<void> setLoopGain(String key, double gain) async {
    loopGainChanges.add((key, gain));
  }

  @override
  Future<void> stopLoop(String key) async {
    loopsStopped.add(key);
  }

  @override
  Future<void> pauseAll() async {}

  @override
  Future<void> resumeAll() async {}

  @override
  void dispose() {}
}

/// 长音轨播放器的最小适配层。
///
/// 将平台播放器隔离出来，既能保证资源准备阶段完全静音，也能在测试中精确
/// 控制准备时机，覆盖后台切换等异步竞态。
abstract interface class LoopPlayer {
  Future<void> setLooping();
  Future<void> setVolume(double gain);
  Future<void> prepareAsset(String asset);
  Future<void> seek(Duration position);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

typedef LoopPlayerFactory = LoopPlayer Function();

class _AudioPlayersLoopPlayer implements LoopPlayer {
  _AudioPlayersLoopPlayer() : _player = ap.AudioPlayer();

  final ap.AudioPlayer _player;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> prepareAsset(String asset) =>
      _player.setSource(ap.AssetSource(asset));

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setLooping() => _player.setReleaseMode(ap.ReleaseMode.loop);

  @override
  Future<void> setVolume(double gain) => _player.setVolume(gain);

  @override
  Future<void> stop() => _player.stop();
}

class AudioPlayersSoundBank implements SoundBank {
  AudioPlayersSoundBank({
    this.poolSize = 5,
    LoopPlayerFactory? loopPlayerFactory,
  }) : _loopPlayerFactory = loopPlayerFactory ?? _AudioPlayersLoopPlayer.new;

  final int poolSize;
  final Map<String, ap.AudioPool> _pools = {};
  final LoopPlayerFactory _loopPlayerFactory;
  final Map<String, LoopPlayer> _loops = {};
  final Map<String, String> _assets = {};
  final Set<String> _activeLoopKeys = {};

  /// 生命周期的全局暂停状态不能只根据当前播放器列表推断：播放器仍在
  /// prepareAsset 时，应用可能已经进入后台。准备完成后 [startLoop] 会再次
  /// 读取此标记，确保不会漏播。
  bool _allPaused = false;

  /// 每次生命周期暂停/恢复都会推进版本。异步播放器操作返回时，只有仍是
  /// 当前版本的操作才允许继续，避免旧的 pause 在快速恢复后反过来停掉音轨。
  int _lifecycleVersion = 0;

  @override
  Future<void> register(Map<String, String> assetByKey) async {
    _assets.addAll(assetByKey);
  }

  @override
  Future<void> preload(Map<String, String> assetByKey) async {
    _assets.addAll(assetByKey);
    for (final key in assetByKey.keys) {
      await _ensurePool(key);
    }
  }

  Future<void> _ensurePool(String key) async {
    if (_pools.containsKey(key)) return;
    final asset = _assets[key];
    assert(asset != null, 'SoundBank: 未预加载音效 "$key"');
    if (asset == null) return;
    _pools[key] = await ap.AudioPool.create(
      source: ap.AssetSource(asset),
      maxPlayers: poolSize,
    );
  }

  @override
  Future<void> play(String key, {double gain = 1.0}) async {
    await _ensurePool(key);
    final pool = _pools[key];
    await pool?.start(volume: gain.clamp(0.0, 1.0));
  }

  @override
  Future<void> startLoop(
    String key, {
    double gain = 1.0,
    Duration? startAt,
  }) async {
    final asset = _assets[key];
    assert(asset != null, 'SoundBank: 未预加载音轨 "$key"');
    if (asset == null) return;
    var player = _loops[key];
    player ??= await _createLoopPlayer(key, asset);
    _activeLoopKeys.add(key);
    await player.setVolume(gain.clamp(0.0, 1.0).toDouble());
    if (startAt != null && startAt > Duration.zero) {
      await player.seek(startAt);
    }
    if (_allPaused) {
      await player.pause();
      return;
    }
    await player.resume();
    // pauseAll 可能发生在上面的 await resume 期间；再次检查才能覆盖这条
    // 竞态，避免后台已经切入却仍自动起播。
    if (_allPaused) await player.pause();
  }

  Future<LoopPlayer> _createLoopPlayer(String key, String asset) async {
    final player = _loopPlayerFactory();
    await player.setLooping();
    // setSource 是不发声的准备流程。必须先静音，再准备资源，避免旧版
    // play → stop 在耳机中短促突响；真正的目标音量在 resume 前设置。
    await player.setVolume(0);
    await player.prepareAsset(asset);
    _loops[key] = player;
    return player;
  }

  @override
  Future<void> setLoopGain(String key, double gain) async {
    await _loops[key]?.setVolume(gain.clamp(0.0, 1.0).toDouble());
  }

  @override
  Future<void> stopLoop(String key) async {
    _activeLoopKeys.remove(key);
    final player = _loops.remove(key);
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  @override
  Future<void> pauseAll() async {
    _allPaused = true;
    final version = ++_lifecycleVersion;
    // pause/stop/start 都可能在 await 之间修改活动集合；遍历快照，且在
    // 回来后确认仍是同一播放器，避免 ConcurrentModificationError 及误操作
    // 已被替换的实例。
    for (final key in _activeLoopKeys.toList(growable: false)) {
      if (!_isCurrentLifecycle(version, paused: true)) return;
      final player = _loops[key];
      if (player == null || !_activeLoopKeys.contains(key)) continue;
      await player.pause();
      if (!_isCurrentLifecycle(version, paused: true)) return;
      if (!_isActiveLoopPlayer(key, player)) continue;
    }
  }

  @override
  Future<void> resumeAll() async {
    _allPaused = false;
    final version = ++_lifecycleVersion;
    for (final key in _activeLoopKeys.toList(growable: false)) {
      if (!_isCurrentLifecycle(version, paused: false)) return;
      final player = _loops[key];
      if (player == null || !_activeLoopKeys.contains(key)) continue;
      await player.resume();
      if (!_isCurrentLifecycle(version, paused: false)) return;
      if (!_isActiveLoopPlayer(key, player)) continue;
      if (_allPaused) {
        await player.pause();
        if (!_isActiveLoopPlayer(key, player)) continue;
      }
    }
  }

  bool _isActiveLoopPlayer(String key, LoopPlayer player) =>
      _activeLoopKeys.contains(key) && identical(_loops[key], player);

  bool _isCurrentLifecycle(int version, {required bool paused}) =>
      _lifecycleVersion == version && _allPaused == paused;

  @override
  void dispose() {
    for (final pool in _pools.values) {
      pool.dispose();
    }
    _pools.clear();
    for (final player in _loops.values) {
      player.dispose();
    }
    _loops.clear();
    _activeLoopKeys.clear();
  }
}

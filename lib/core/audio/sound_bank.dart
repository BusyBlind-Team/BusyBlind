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

  @override
  Future<void> register(Map<String, String> assetByKey) async {}

  @override
  Future<void> preload(Map<String, String> assetByKey) async {}

  @override
  Future<void> play(String key, {double gain = 1.0}) async {
    played.add(key);
  }

  @override
  Future<void> startLoop(String key, {double gain = 1.0, Duration? startAt}) async {}

  @override
  Future<void> setLoopGain(String key, double gain) async {}

  @override
  Future<void> stopLoop(String key) async {}

  @override
  Future<void> pauseAll() async {}

  @override
  Future<void> resumeAll() async {}

  @override
  void dispose() {}
}

class AudioPlayersSoundBank implements SoundBank {
  AudioPlayersSoundBank({this.poolSize = 5});

  final int poolSize;
  final Map<String, ap.AudioPool> _pools = {};
  final Map<String, ap.AudioPlayer> _loops = {};
  final Map<String, String> _assets = {};
  final List<String> _pausedLoopKeys = [];

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
    await player.setVolume(gain.clamp(0.0, 1.0));
    if (startAt != null && startAt > Duration.zero) {
      await player.seek(startAt);
    }
    await player.resume();
  }

  Future<ap.AudioPlayer> _createLoopPlayer(String key, String asset) async {
    final player = ap.AudioPlayer();
    await player.setReleaseMode(ap.ReleaseMode.loop);
    await player.play(ap.AssetSource(asset));
    await player.stop(); // 就绪但不发声，等 startLoop 的 resume。
    _loops[key] = player;
    return player;
  }

  @override
  Future<void> setLoopGain(String key, double gain) async {
    await _loops[key]?.setVolume(gain.clamp(0.0, 1.0));
  }

  @override
  Future<void> stopLoop(String key) async {
    final player = _loops.remove(key);
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  @override
  Future<void> pauseAll() async {
    for (final entry in _loops.entries) {
      if (entry.value.state == ap.PlayerState.playing) {
        _pausedLoopKeys.add(entry.key);
        await entry.value.pause();
      }
    }
  }

  @override
  Future<void> resumeAll() async {
    for (final key in _pausedLoopKeys) {
      await _loops[key]?.resume();
    }
    _pausedLoopKeys.clear();
  }

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
  }
}

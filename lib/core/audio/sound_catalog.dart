import 'dart:math';

/// 全 app 统一的声音语言（SoundBank 提供的音效目录）。
///
/// 命名与《设计方案·七、教程与声音语言》的声音语义表对应：
/// - 磬一声 chime        ：开始 / 请闭眼
/// - 磬两声 chime_double ：结束 / 可以睁眼
/// - 过河 river_1..12    ：编号音色引导/跟随（Bug 描述 #8，替代旧叮咚）
/// - 叮咚（钓花）fish_ding / fish_dong：花瓣 / 杂物判定
///   与过河编号音语义不同，音色与包络必须拉开，防止用户迁移错误预期。
abstract final class SoundCatalog {
  // 代码里引用语义化常量，资产表用字符串 key，二者编译期对齐。
  static const String chimeKey = 'chime';
  static const String chimeDoubleKey = 'chime_double';
  static const String tickKey = 'tick';
  static const String muyuKey = 'muyu';
  static const String fishDingKey = 'fish_ding';
  static const String fishDongKey = 'fish_dong';
  static const String fishSinkKey = 'fish_sink';
  static const String windChimeKey = 'wind_chime';
  static const String swishKey = 'swish';
  static const String tideLoopKey = 'tide_loop';
  static const String forestLoopKey = 'forest_loop';

  // ---- 新-改进说明文档 §2/§14：环境音与呼吸指引 ----
  /// 听潮背景：潮水（原文件名为 .mp3 实为 m4a 容器，已统一为单声道 64k）。
  static const String ambTideKey = 'amb_tide';

  /// 过河背景环境音：河流（不播五首 BGM）。
  static const String ambRiverKey = 'amb_river';

  /// 钓花叠加的环境水声：溪流。
  static const String ambStreamKey = 'amb_stream';

  /// 数雨随机二选一：鸟叫 / 虫鸣（单局内不切换）。
  static const String ambBirdsKey = 'amb_birds';
  static const String ambInsectsKey = 'amb_insects';

  /// 听潮呼吸指引音乐（循环播放），下标与 kBreathMethods 对齐。
  static const String guideBreath46Key = 'guide_breath_4_6';
  static const String guideBreathBoxKey = 'guide_breath_box';
  static const String guideBreath478Key = 'guide_breath_4_7_8';
  static const List<String> breathGuideKeys = [
    guideBreath46Key,
    guideBreathBoxKey,
    guideBreath478Key,
  ];

  /// 过河引导/跟随音（Bug 描述 #8）：12 个编号音色，替换原"叮——咚"。
  /// key = 'river_1' … 'river_12'。
  static String riverSoundKey(int n) => 'river_$n';

  /// 修行 BGM（改进列表：可选手一首或随机/无，放完隔一秒循环）。
  /// name 是播放时展示给用户的名字。
  static const List<({String key, String name})> bgmTracks = [
    (key: 'bgm_liming', name: '黎明'),
    (key: 'bgm_guzhong', name: '古钟'),
    (key: 'bgm_fengling', name: '风铃'),
    (key: 'bgm_hanlin', name: '寒林'),
    (key: 'bgm_qingxi', name: '清溪'),
  ];

  /// 曲目设置：无背景音乐。
  static const int bgmTrackNone = -2;

  /// 曲目设置：每次修行随机抽一首（默认）。
  static const int bgmTrackRandom = -1;

  /// 把设置值解析成具体曲目：无 → null，随机 → 抽一首，其余 → 固定曲目。
  static ({String key, String name})? resolveTrack(int setting, [Random? rng]) {
    if (setting == bgmTrackNone) return null;
    final tracks = bgmTracks;
    if (setting >= 0 && setting < tracks.length) return tracks[setting];
    return tracks[(rng ?? Random()).nextInt(tracks.length)];
  }

  /// 长音轨（BGM / 环境音 / 呼吸指引）：按需流式播放，绝不进内存池。
  ///
  /// 新-改进说明文档 §2/§14 起环境音是约 10 分钟的单声道音轨，整段预解码
  /// 进 AudioPool 会白白吃掉几十 MB 内存。
  static bool isStreamedKey(String key) =>
      key.startsWith('bgm_') ||
      key.startsWith('amb_') ||
      key.startsWith('guide_');

  /// key → AssetSource 路径（audioplayers 的 AssetSource 会自动补 assets/ 前缀）。
  /// final 而非 const：包含 for 展开（BGM 音轨与过河编号音），编译期常量不支持。
  static final Map<String, String> catalog = {
    'chime': 'sfx/chime.mp3',
    'chime_double': 'sfx/chime_double.mp3',
    'tick': 'sfx/tick.mp3',
    'muyu': 'sfx/muyu.mp3',
    'muyu_muffled': 'sfx/muyu_muffled.mp3',
    'fish_ding': 'sfx/fish_ding.mp3',
    'fish_dong': 'sfx/fish_dong.mp3',
    'rain_drop_1': 'sfx/rain_drop_1.mp3',
    'rain_drop_2': 'sfx/rain_drop_2.mp3',
    'rain_drop_3': 'sfx/rain_drop_3.mp3',
    'fish_sink': 'sfx/fish_sink.mp3',
    'bell_low': 'sfx/bell_low.mp3',
    'wind_chime': 'sfx/wind_chime.mp3',
    'swish': 'sfx/swish.mp3',
    'forest_loop': 'sfx/forest_loop.mp3',
    'tide_loop': 'sfx/tide_loop.mp3',
    // 新-改进说明文档 §2/§14：环境音（长音轨，按需流式）与呼吸指引。
    ambTideKey: 'sfx/amb_tide.m4a',
    ambRiverKey: 'sfx/amb_river.m4a',
    ambStreamKey: 'sfx/amb_stream.m4a',
    ambBirdsKey: 'sfx/amb_birds.m4a',
    ambInsectsKey: 'sfx/amb_insects.m4a',
    guideBreath46Key: 'bgm/guide_breath_4_6.m4a',
    guideBreathBoxKey: 'bgm/guide_breath_box.m4a',
    guideBreath478Key: 'bgm/guide_breath_4_7_8.m4a',
    // 过河 12 个编号音色（Bug 描述 #8，替换原叮/咚）。
    for (var i = 1; i <= 12; i++) riverSoundKey(i): 'sfx/river/$i.m4a',
    for (final t in bgmTracks) t.key: 'bgm/${t.key}.m4a',
  };
}

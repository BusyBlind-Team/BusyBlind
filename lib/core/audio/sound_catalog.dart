import 'dart:math';

/// 全 app 统一的声音语言（SoundBank 提供的音效目录）。
///
/// 命名与《设计方案·七、教程与声音语言》的声音语义表对应：
/// - 磬一声 chime        ：开始 / 请闭眼
/// - 磬两声 chime_double ：结束 / 可以睁眼
/// - 极轻的磬 chime_soft ：打坐在场确认 / 修行里程碑
/// - 叮咚（过河）he_ding / he_dong：间隔度量
/// - 叮咚（钓花）fish_ding / fish_dong：花瓣 / 杂物判定
///   两处叮/咚语义不同，音色与包络必须拉开（过河=明亮钟声+低沉鼓点，
///   钓花=拨弦质感+闷响），防止用户迁移错误预期。
abstract final class SoundCatalog {
  // 代码里引用语义化常量，资产表用字符串 key，二者编译期对齐。
  static const String chimeKey = 'chime';
  static const String chimeDoubleKey = 'chime_double';
  static const String chimeSoftKey = 'chime_soft';
  static const String tickKey = 'tick';
  static const String muyuKey = 'muyu';
  static const String heDingKey = 'he_ding';
  static const String heDongKey = 'he_dong';
  static const String fishDingKey = 'fish_ding';
  static const String fishDongKey = 'fish_dong';
  static const String windChimeKey = 'wind_chime';
  static const String swishKey = 'swish';
  static const String tideLoopKey = 'tide_loop';
  static const String forestLoopKey = 'forest_loop';

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

  /// key → AssetSource 路径（audioplayers 的 AssetSource 会自动补 assets/ 前缀）。
  /// final 而非 const：包含 for 展开（BGM 音轨），编译期常量不支持。
  static final Map<String, String> catalog = {
    'chime': 'sfx/chime.mp3',
    'chime_soft': 'sfx/chime_soft.mp3',
    'chime_double': 'sfx/chime_double.mp3',
    'tick': 'sfx/tick.mp3',
    'muyu': 'sfx/muyu.mp3',
    'muyu_muffled': 'sfx/muyu_muffled.mp3',
    'he_ding': 'sfx/he_ding.mp3',
    'he_dong': 'sfx/he_dong.mp3',
    'fish_ding': 'sfx/fish_ding.mp3',
    'fish_dong': 'sfx/fish_dong.mp3',
    'rain_drop': 'sfx/rain_drop.mp3',
    'bell_low': 'sfx/bell_low.mp3',
    'wind_chime': 'sfx/wind_chime.mp3',
    'swish': 'sfx/swish.mp3',
    'forest_loop': 'sfx/forest_loop.mp3',
    'tide_loop': 'sfx/tide_loop.mp3',
    for (final t in bgmTracks) t.key: 'bgm/${t.key}.m4a',
  };
}

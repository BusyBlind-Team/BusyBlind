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
  static const String tideLoopKey = 'tide_loop';
  static const String forestLoopKey = 'forest_loop';

  /// key → AssetSource 路径（audioplayers 的 AssetSource 会自动补 assets/ 前缀）。
  static const Map<String, String> catalog = {
    'chime': 'sfx/chime.wav',
    'chime_soft': 'sfx/chime_soft.wav',
    'chime_double': 'sfx/chime_double.wav',
    'tick': 'sfx/tick.wav',
    'muyu': 'sfx/muyu.wav',
    'muyu_muffled': 'sfx/muyu_muffled.wav',
    'he_ding': 'sfx/he_ding.wav',
    'he_dong': 'sfx/he_dong.wav',
    'fish_ding': 'sfx/fish_ding.wav',
    'fish_dong': 'sfx/fish_dong.wav',
    'rain_drop': 'sfx/rain_drop.wav',
    'bell_low': 'sfx/bell_low.wav',
    'wind_chime': 'sfx/wind_chime.wav',
    'swish': 'sfx/swish.wav',
    'forest_loop': 'sfx/forest_loop.wav',
    'tide_loop': 'sfx/tide_loop.wav',
  };
}

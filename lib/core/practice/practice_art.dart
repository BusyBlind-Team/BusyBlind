/// 修行插画（iconKey → 正式美术）。打坐不在列表、静坐已移出列表，均无插画。
///
/// 使用位置（Bug 描述 #2）：
/// - 修行列表未点开时的 48×48 缩略图（保留）；
/// - 点击"确定"后的修行准备开始界面横幅（原介绍详情里的横幅已移到此处）。
library;

const kPracticeArt = <String, String>{
  'wooden_fish': 'assets/art/illustrations/play_wooden_fish.webp',
  'count_rain': 'assets/art/illustrations/count_rain.webp',
  'tide_breath': 'assets/art/illustrations/tide_breath.webp',
  'cross_river': 'assets/art/illustrations/cross_river.webp',
  'fish_petals': 'assets/art/illustrations/fish_petals.webp',
};

String? practiceArtFor(String iconKey) => kPracticeArt[iconKey];

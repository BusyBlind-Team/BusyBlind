import '../audio/sound_catalog.dart';

/// 单页教程浮窗：一段文字，可选在浮窗出现时播一个声音。
class PracticeTutorialPage {
  const PracticeTutorialPage(this.text, {this.soundKey, this.soundGain = 0.9});

  final String text;
  final String? soundKey;
  final double soundGain;
}

/// 一门修行的首次教程：多页浮窗 + 可选的背景循环（如听潮的潮声）。
class PracticeTutorial {
  const PracticeTutorial(this.pages, {this.ambientLoopKey});

  final List<PracticeTutorialPage> pages;

  /// 教程期间持续循环的环境声（页面上不另播声音时也保持氛围）。
  final String? ambientLoopKey;
}

/// 各修行的首次教程脚本（final：riverSoundKey 为方法调用不能入 const；
/// 改进列表：所有修行第一次打开时，
/// 进入开始界面前强制进入教程；浮窗点击继续，最后一段点击直接进入开始界面）。
final Map<String, PracticeTutorial> kPracticeTutorials = {
  'wooden_fish': PracticeTutorial([
    PracticeTutorialPage('点击屏幕，可以敲响木鱼'),
    PracticeTutorialPage('保持节奏，每秒敲响一次木鱼'),
    PracticeTutorialPage(
      '敲响第一百零八下后，会听见这个声音',
      soundKey: SoundCatalog.chimeKey,
    ),
  ]),
  'count_rain': PracticeTutorial([
    PracticeTutorialPage('三分钟内，雨滴每隔数秒落下一次'),
    PracticeTutorialPage('什么都不需要做，闭上眼数数就行'),
    PracticeTutorialPage(
      '听见这个声音时，不再有雨滴落下',
      soundKey: SoundCatalog.chimeKey,
    ),
  ]),
  'tide_breath': PracticeTutorial(
    // 新-改进说明文档 §5：原 9 页教程替换为这 6 句，顺序照录。
    [
      PracticeTutorialPage('跟随音乐的引导，与潮水一同呼吸'),
      PracticeTutorialPage('用鼻吸气时，按住屏幕，憋气时也不要松开'),
      PracticeTutorialPage('用嘴呼气时，松开屏幕，直到下一次吸气'),
      PracticeTutorialPage('如此重复五分钟，不必睁眼'),
      PracticeTutorialPage('开始界面有三种呼吸法可以选择'),
      PracticeTutorialPage('祝好梦'),
    ],
    ambientLoopKey: SoundCatalog.ambTideKey,
  ),
  'fish_petals': PracticeTutorial([
    PracticeTutorialPage(
      '长按屏幕抛竿，会听见这个声音',
      soundKey: SoundCatalog.swishKey,
    ),
    PracticeTutorialPage(
      '不是花瓣上钩时，会听见这个声音',
      soundKey: SoundCatalog.fishDongKey,
    ),
    PracticeTutorialPage(
      '花瓣上钩时，会听见这个声音',
      soundKey: SoundCatalog.fishDingKey,
    ),
    PracticeTutorialPage('甩杆会打散附近的花瓣，抛竿后请耐心等待'),
    PracticeTutorialPage('钓花随时可以退出，清点收获'),
    PracticeTutorialPage('一定数量钓到的花瓣可以在成就界面合成一朵完整的花'),
    PracticeTutorialPage('努力收集花的图鉴吧'),
  ]),
  'cross_river': PracticeTutorial([
    PracticeTutorialPage('师傅走在前面，跟随他的脚步声过河吧'),
    PracticeTutorialPage(
      '这是引导音：两个音之间的间隔，是师傅的一步',
      soundKey: SoundCatalog.riverSoundKey(1),
    ),
    PracticeTutorialPage(
      '第二个音落下后，按下屏幕，会响起你的跟随音',
      soundKey: SoundCatalog.riverSoundKey(3),
    ),
    PracticeTutorialPage('自认为到了间隔就松开，跟随音会再次响起'),
    PracticeTutorialPage('试着走远些，别掉进河水中吧'),
  ]),
};

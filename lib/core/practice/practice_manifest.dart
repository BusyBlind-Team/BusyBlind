import 'practice_types.dart';

/// 修行的静态描述：修行列表展示与筛选只用它，不需要实例化会话。
class PracticeManifest {
  const PracticeManifest({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.tags,
    required this.eyeMode,
    required this.typicalLength,
    required this.meritBase,
    this.needsHeadphones = true,
    required this.iconKey,
    this.rulesText,
    this.allowManualEnd = false,
    this.introTags = '',
    this.intro = '',
    this.usesAmbientLoop = false,
  });

  /// 唯一 id，如 'wooden_fish'。
  final String id;
  final String name;
  final String subtitle;

  /// 训练类型标签 = 修行列表的"训练类型"项。
  final List<TrainingTag> tags;

  final EyeMode eyeMode;

  /// 单局时长（"自定"时给典型值）。
  final Duration typicalLength;

  /// 基准修为（宿主结算时用于修为上限校验）。
  final int meritBase;

  final bool needsHeadphones;

  /// 图标 key（v0.1 用文字/图形占位，接美术后换成资源 key）。
  final String iconKey;

  /// 开局睁眼阶段的规则说明（openThenClosed 模式的引导页文案）。
  final String? rulesText;

  /// 自定时长类修行（听潮/钓花）需要手动结束入口。
  final bool allowManualEnd;

  /// 修行介绍的一行标签（如"专注·节奏"，修行介绍文案）。
  final String introTags;

  /// 修行介绍正文（修行列表详情展示；直接取自《修行介绍》文案）。
  final String intro;

  /// 会话是否持续播放一条环境循环轨（听潮/数雨）。
  ///
  /// 选了 BGM 曲目时，这条循环被替换为所选曲目本身，宿主便不再另起
  /// BgmPlayer——否则两个声道同时播同一首（复审 R1）。
  final bool usesAmbientLoop;
}

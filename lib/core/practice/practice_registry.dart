import '../../practices/count_rain.dart';
import '../../practices/cross_river.dart';
import '../../practices/fish_petals.dart';
import '../../practices/tide_breath.dart';
import '../../practices/wooden_fish.dart';
import 'practice_manifest.dart';
import 'practice_session.dart';

/// 修行注册表：启动时扫描这里，生成"修·修行界面"的列表。
///
/// 新增一个修行的全部动作：
/// 1. 写一个 PracticeSession 实现（新文件）；
/// 2. 在 [practiceFactories] 里加一行；
/// 3. 需要的音效加进 SoundCatalog。
/// 不改宿主与其他修行的任何一行——这是模块化设计的验收标准。
typedef PracticeSessionFactory = PracticeSession Function();

const List<PracticeSessionFactory> practiceFactories = [
  // 静坐已从列表移除（改进列表）；SitQuietSession 保留给教程 60 秒试玩。
  WoodenFishSession.new, // 木鱼
  CountRainSession.new, // 数雨
  TideBreathSession.new, // 听潮
  FishPetalsSession.new, // 钓花
  CrossRiverSession.new, // 过河
];

List<PracticeManifest> collectManifests() =>
    practiceFactories.map((f) => f().manifest).toList(growable: false);

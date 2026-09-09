import 'dart:math';
import 'dart:ui';

/// 花之稀有度（待对齐清单 #6：常见 / 稀有 / 奇珍）。
enum FlowerRarity { common, rare, legendary }

/// 花的物种。花瓣本身不分物种；合成时按投入的瓣数决定从哪一档花池抽取。
/// （待对齐清单 #6：4 瓣桂花/丁香，5 瓣桃/梨/樱/海棠，6 瓣迎春/水仙/百合，8 瓣莲花。）
class FlowerSpecies {
  const FlowerSpecies({
    required this.id,
    required this.name,
    required this.displayName,
    required this.color,
    required this.petals,
    required this.rarity,
  });

  final String id;

  /// 单字简称（花瓣图标/结算徽记用）。
  final String name;

  /// 全名（图鉴展示用：丁香花、海棠、水仙……见改进列表花名修正）。
  final String displayName;

  final Color color;

  /// 合成该档花需要投入的花瓣数（4 / 5 / 6 / 8）。
  final int petals;
  final FlowerRarity rarity;

  String get rarityLabel => switch (rarity) {
    FlowerRarity.common => '常见',
    FlowerRarity.rare => '稀有',
    FlowerRarity.legendary => '奇珍',
  };
}

/// 图鉴花池。同一档内稀有度决定抽取权重（常见 1.0 / 稀有 0.35，拟定值）。
const List<FlowerSpecies> kFlowerSpecies = [
  // 4 瓣档。
  FlowerSpecies(
    id: 'osmanthus',
    name: '桂',
    displayName: '桂花',
    color: Color(0xFFF3D9A4),
    petals: 4,
    rarity: FlowerRarity.common,
  ),
  FlowerSpecies(
    id: 'lilac',
    name: '丁',
    displayName: '丁香花',
    color: Color(0xFFC7A6D9),
    petals: 4,
    rarity: FlowerRarity.rare,
  ),
  // 5 瓣档。
  FlowerSpecies(
    id: 'peach',
    name: '桃',
    displayName: '桃花',
    color: Color(0xFFF5A79A),
    petals: 5,
    rarity: FlowerRarity.common,
  ),
  FlowerSpecies(
    id: 'pear',
    name: '梨',
    displayName: '梨花',
    color: Color(0xFFE7EFD2),
    petals: 5,
    rarity: FlowerRarity.common,
  ),
  FlowerSpecies(
    id: 'sakura',
    name: '樱',
    displayName: '樱花',
    color: Color(0xFFF2B8C6),
    petals: 5,
    rarity: FlowerRarity.common,
  ),
  FlowerSpecies(
    id: 'crabapple',
    name: '海',
    displayName: '海棠',
    color: Color(0xFFE88B9D),
    petals: 5,
    rarity: FlowerRarity.rare,
  ),
  // 6 瓣档。
  FlowerSpecies(
    id: 'winterJasmine',
    name: '迎',
    displayName: '迎春花',
    color: Color(0xFFEFD98A),
    petals: 6,
    rarity: FlowerRarity.common,
  ),
  FlowerSpecies(
    id: 'narcissus',
    name: '仙',
    displayName: '水仙',
    color: Color(0xFFDDE8D0),
    petals: 6,
    rarity: FlowerRarity.rare,
  ),
  FlowerSpecies(
    id: 'lily',
    name: '百',
    displayName: '百合花',
    color: Color(0xFFEDE6F2),
    petals: 6,
    rarity: FlowerRarity.rare,
  ),
  // 8 瓣档。
  FlowerSpecies(
    id: 'lotus',
    name: '莲',
    displayName: '莲花',
    color: Color(0xFFE8A0A8),
    petals: 8,
    rarity: FlowerRarity.legendary,
  ),
];

FlowerSpecies flowerById(String id) =>
    kFlowerSpecies.firstWhere((s) => s.id == id, orElse: () => kFlowerSpecies.first);

/// 通用花瓣色（花瓣已不分物种，视觉统一用这个柔和粉色）。
const Color kGenericPetalColor = Color(0xFFEFC3C4);

/// 合成可用的档位（升序）。
const List<int> kCraftTiers = [4, 5, 6, 8];

/// 稀有度抽取权重（拟定值：稀有约三分之一概率落到）。
const double _kCommonWeight = 1.0;
const double _kRareWeight = 0.35;

/// 投入 [tierPetalCount] 片花瓣，从对应档位的花池按稀有度抽一朵。
/// 池为空（如未来档位调整）时返回 null。
FlowerSpecies? drawFlower(int tierPetalCount, Random rng) {
  final pool = kFlowerSpecies
      .where((s) => s.petals == tierPetalCount)
      .toList();
  if (pool.isEmpty) return null;
  final weights = [
    for (final s in pool)
      s.rarity == FlowerRarity.common ? _kCommonWeight : _kRareWeight,
  ];
  final total = weights.fold<double>(0, (a, b) => a + b);
  var roll = rng.nextDouble() * total;
  for (var i = 0; i < pool.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return pool[i];
  }
  return pool.last;
}

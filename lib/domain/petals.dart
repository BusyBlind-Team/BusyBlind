import 'dart:ui';

/// 花瓣物种。钓花钓起的花瓣按物种入库，同种 3 朵合成一朵花，入图鉴。
class PetalSpecies {
  const PetalSpecies({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;
}

const List<PetalSpecies> kPetalSpecies = [
  PetalSpecies(id: 'sakura', name: '樱', color: Color(0xFFF2B8C6)),
  PetalSpecies(id: 'peach', name: '桃', color: Color(0xFFF5A79A)),
  PetalSpecies(id: 'apricot', name: '杏', color: Color(0xFFF7DFAE)),
  PetalSpecies(id: 'pear', name: '梨', color: Color(0xFFE7EFD2)),
  PetalSpecies(id: 'plum', name: '梅', color: Color(0xFFD98CA0)),
  PetalSpecies(id: 'orchid', name: '兰', color: Color(0xFFC9D8C5)),
];

PetalSpecies petalById(String id) =>
    kPetalSpecies.firstWhere((s) => s.id == id, orElse: () => kPetalSpecies.first);

/// 花瓣合成数量（设计方案待对齐 #6，建议 3 朵合一朵）。
const int kPetalsPerFlower = 3;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/achievements.dart';
import '../../domain/petals.dart';
import '../../domain/merit.dart';
import '../../theme.dart';
import '../../widgets/petal_icon.dart';

/// 成（成就列表，文案见《文案：成就》）：常规 + 隐藏两区，
/// 隐藏成就解锁前只显示"？？？"。附带：修为等级表 + 花瓣图鉴（收集/合成）。
class AchievementsPage extends ConsumerWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('成')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          const _SectionTitle('常规成就'),
          for (final def in kAchievements.where((a) => !a.hidden))
            _AchievementRow(
              title: def.title,
              description: def.description,
              unlocked: store.isUnlocked(def.id),
            ),
          const SizedBox(height: 20),
          const _SectionTitle('隐藏成就'),
          for (final def in kAchievements.where((a) => a.hidden))
            _AchievementRow(
              title: store.isUnlocked(def.id) ? def.title : '？？？',
              description: store.isUnlocked(def.id)
                  ? def.description
                  : '尚未参透的修行……',
              unlocked: store.isUnlocked(def.id),
            ),
          const SizedBox(height: 20),
          const _SectionTitle('修为等级'),
          const Text(
            '修为只来自真实完成的专注时间（打坐 1 点/分钟，单日上限 60）。',
            style: TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final level in kMeritLevels.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(level.title, style: const TextStyle(color: AppTheme.inkDim, fontSize: 13)),
                  Text(
                    level.minMerit == 10000 ? '10000 +' : '${level.minMerit} +',
                    style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const _SectionTitle('花瓣图鉴'),
          Text(
            '钓到的花瓣带稀有度（概率：常见 70% / 稀有 25% / 奇珍 5%）。'
            '当前：常见 ${store.petalCountOf(PetalRarity.common)} · '
            '稀有 ${store.petalCountOf(PetalRarity.rare)} · '
            '奇珍 ${store.petalCountOf(PetalRarity.legendary)} 枚。'
            '投入对应稀有度的瓣数，合成对应的花。好友交换走"友"（暂未开放）。',
            style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          // 每个组合一行：档位 × 稀有度（该组合有花才显示）。
          for (final tier in kCraftTiers)
            for (final rarity in PetalRarity.values)
              if (kFlowerSpecies
                  .any((f) => f.petals == tier && f.rarity.rarityKey == rarity.id))
                CraftRow(
                  tierPetalCount: tier,
                  rarity: rarity,
                  petalCount: store.petalCountOf(rarity),
                  onCraft: () => _craft(context, ref, tier, rarity),
                ),
          const SizedBox(height: 12),
          // 按稀有度依次排列：瓣数升档，档内常见在前（改进列表花名修正）。
          for (final species
              in (kFlowerSpecies.toList()
                ..sort((a, b) {
                  final byTier = a.petals.compareTo(b.petals);
                  if (byTier != 0) return byTier;
                  return a.rarity.index.compareTo(b.rarity.index);
                })))
            FlowerRow(
              species: species,
              owned: store.flowers.contains(species.id),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _craft(BuildContext context, WidgetRef ref, int tier, PetalRarity rarity) {
    final drawn = ref.read(storeProvider).craftFlower(tier, rarity);
    if (drawn == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('合成了一朵${drawn.displayName}（${drawn.rarityLabel}）'),
        backgroundColor: const Color(0xFF2A2620),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.gold,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 3,
        ),
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({
    required this.title,
    required this.description,
    required this.unlocked,
  });

  final String title;
  final String description;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0x1AD8B36A) : const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.spa : Icons.spa_outlined,
            color: unlocked ? AppTheme.gold : AppTheme.inkFaint,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: unlocked ? AppTheme.ink : AppTheme.inkFaint,
                    fontSize: 15,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: unlocked ? AppTheme.inkDim : AppTheme.inkFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

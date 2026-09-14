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
              // 普通成就用小字注明达成条件；隐藏成就不展示（避免剧透）。
              condition: def.condition,
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
            '钓到的花瓣在上钩那一刻就定了花种（概率：常见 70% / 稀有 25% / '
            '奇珍 5%，同一稀有度内各花机会均等）。当前：'
            '常见 ${store.petalCountOf(PetalRarity.common)} · '
            '稀有 ${store.petalCountOf(PetalRarity.rare)} · '
            '奇珍 ${store.petalCountOf(PetalRarity.legendary)} 枚。'
            '攒够某朵花所需的瓣数，即可合成它。好友交换走"友"（暂未开放）。',
            style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          // 按瓣数升档、档内常见在前（改进列表花名修正）；
          // 每行即一个花种：已有瓣数 / 需要瓣数，够了就能合成。
          for (final species
              in (kFlowerSpecies.toList()
                ..sort((a, b) {
                  final byTier = a.petals.compareTo(b.petals);
                  if (byTier != 0) return byTier;
                  return a.rarity.index.compareTo(b.rarity.index);
                })))
            FlowerRow(
              species: species,
              owned: store.ownsFlower(species.id),
              petalCount: store.petalCountOfSpecies(species.id),
              onCraft: () => _craft(context, ref, species),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _craft(BuildContext context, WidgetRef ref, FlowerSpecies species) {
    final drawn = ref.read(storeProvider).craftFlower(species.id);
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
    this.condition,
  });

  final String title;
  final String description;
  final bool unlocked;

  /// 达成条件；为空则不显示（隐藏成就解锁前不剧透）。
  final String? condition;

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
                if (condition != null && condition!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '达成条件：$condition',
                      style: TextStyle(
                        color: unlocked
                            ? AppTheme.inkFaint
                            : AppTheme.inkFaint.withValues(alpha: 0.7),
                        fontSize: 11,
                        height: 1.35,
                      ),
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

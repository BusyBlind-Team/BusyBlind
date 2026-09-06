import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../domain/achievements.dart';
import '../../domain/merit.dart';
import '../../domain/petals.dart';
import '../../theme.dart';
import '../../widgets/petal_icon.dart';

/// 成（成就列表）：未解锁的成就灰色显示。
/// 附带：修为等级表常驻说明 + 花瓣图鉴（收集/合成）。
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
          const _SectionTitle('成就'),
          for (final def in kAchievements)
            _AchievementRow(
              title: def.title,
              description: def.description,
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
          const Text(
            '钓花钓起的花瓣按种类收藏；同种花瓣可合成一朵花。好友交换走"友"（暂未开放）。',
            style: TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final species in kPetalSpecies)
            PetalRow(
              species: species,
              count: store.petals[species.id] ?? 0,
              flowerOwned: store.flowers.contains(species.id),
              onFuse: () => ref
                  .read(storeProvider)
                  .fuseFlower(species.id, need: kPetalsPerFlower),
            ),
          const SizedBox(height: 32),
        ],
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

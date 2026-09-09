import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_store.dart';
import '../../di.dart';
import '../../domain/merit.dart';
import '../../theme.dart';
import '../../widgets/low_poly_button.dart';
import '../../widgets/monk_figure.dart';
import 'achievements_page.dart';
import 'friends_page.dart';
import 'meditation_page.dart';
import 'sign_page.dart';

/// 僧 · 主界面：盲僧立绘 + 修为条 + 签·成·禅·友 四按钮。
class MonkPage extends ConsumerWidget {
  const MonkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final merit = store.merit;
    final level = levelForMerit(merit);
    final next = nextLevelThreshold(merit);
    final floor = currentLevelFloor(merit);
    final progress = next == null ? 1.0 : (merit - floor) / (next - floor);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 等级称号 + 修为条（立绘上方）。
            Align(
              alignment: Alignment(0, -0.82),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    level.title,
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: const Color(0x22E8DFC8),
                            valueColor: const AlwaysStoppedAnimation(AppTheme.gold),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          next == null ? '$merit / —（已至菩萨）' : '$merit / $next',
                          style: const TextStyle(color: AppTheme.inkDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 盲僧立绘（居中）。
            Center(child: MonkFigure(dim: false)),

            // 四个按钮方块：左上签、左下成、右上禅、右下友。
            Align(
              alignment: const Alignment(-0.62, -0.28),
              child: LowPolyButton(
                label: '签',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SignPage()),
                  );
                },
              ),
            ),
            Align(
              alignment: const Alignment(-0.62, 0.28),
              child: LowPolyButton(
                label: '成',
                seed: 3,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AchievementsPage()),
                  );
                },
              ),
            ),
            Align(
              alignment: const Alignment(0.62, -0.28),
              child: LowPolyButton(
                label: '禅',
                seed: 5,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const MeditationPage()),
                  );
                },
              ),
            ),
            Align(
              alignment: const Alignment(0.62, 0.28),
              child: LowPolyButton(
                label: '友',
                seed: 9,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const FriendsPage()),
                  );
                },
              ),
            ),

            // 今日打坐提示。
            Align(
              alignment: const Alignment(0, 0.88),
              child: Text(
                '今日打坐已得 ${store.meditationEarnedToday()} / ${AppStore.kDailyMeditationCap} 修为',
                style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

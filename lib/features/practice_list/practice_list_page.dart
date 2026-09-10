import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/practice/practice_host.dart';
import '../../core/practice/practice_manifest.dart';
import '../../core/practice/practice_registry.dart';
import '../../core/practice/practice_types.dart';
import '../../theme.dart';

/// 修行插画（iconKey → 正式美术）。打坐不在列表、静坐已移出列表，均无插画。
const _kPracticeArt = <String, String>{
  'wooden_fish': 'assets/art/illustrations/play_wooden_fish.webp',
  'count_rain': 'assets/art/illustrations/count_rain.webp',
  'tide_breath': 'assets/art/illustrations/tide_breath.webp',
  'cross_river': 'assets/art/illustrations/cross_river.webp',
  'fish_petals': 'assets/art/illustrations/fish_petals.webp',
};

/// 修 · 修行列表：纵向滑动列表，点击方块立刻滑动使其居中，
/// 展开详情（图标、训练类型、耗时）与"确定 / 取消"按钮。
class PracticeListPage extends ConsumerStatefulWidget {
  const PracticeListPage({super.key});

  @override
  ConsumerState<PracticeListPage> createState() => _PracticeListPageState();
}

class _PracticeListPageState extends ConsumerState<PracticeListPage> {
  final List<PracticeManifest> _manifests = practiceFactories
      .map((f) => f().manifest)
      .toList(growable: false);
  final Map<int, GlobalKey> _itemKeys = {};

  int? _selected;
  int _breathTier = 0;
  bool _sleepMode = false;

  GlobalKey _keyFor(int index) => _itemKeys.putIfAbsent(index, GlobalKey.new);

  void _onTapItem(int index) {
    if (_selected == index) {
      setState(() => _selected = null);
      return;
    }
    setState(() => _selected = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keyFor(index);
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _confirm(int index) {
    final factory = practiceFactories[index];
    final manifest = _manifests[index];
    final params = <String, Object?>{};
    if (manifest.id == 'tide_breath') {
      params['tier'] = _breathTier;
      params['sleepMode'] = _sleepMode;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeHostPage(factory: factory, params: params),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        itemCount: _manifests.length,
        itemBuilder: (context, index) {
          final m = _manifests[index];
          final selected = _selected == index;
          final art = _kPracticeArt[m.iconKey];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [
                // 名称方块（横向矩形）：左侧插画缩略 + 名称与标签。
                GestureDetector(
                  key: _keyFor(index),
                  onTap: () => _onTapItem(index),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x26D8B36A)
                          : const Color(0x14E8DFC8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppTheme.goldDim : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (art != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              art,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 48, height: 48),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Text(
                            m.name,
                            style: TextStyle(
                              color: selected ? AppTheme.gold : AppTheme.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 8,
                            ),
                          ),
                        ),
                        Text(
                          m.introTags.isNotEmpty
                              ? m.introTags
                              : m.tags.map((t) => t.label).join(' · '),
                          style: const TextStyle(
                            color: AppTheme.inkFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 详情 + 确定 / 取消。
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeOut,
                  crossFadeState: selected
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: _PracticeDetail(
                    manifest: m,
                    breathTier: _breathTier,
                    sleepMode: _sleepMode,
                    onTierChanged: (t) => setState(() => _breathTier = t),
                    onSleepModeChanged: (v) => setState(() => _sleepMode = v),
                    onConfirm: () => _confirm(index),
                    onCancel: () => setState(() => _selected = null),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PracticeDetail extends StatelessWidget {
  const _PracticeDetail({
    required this.manifest,
    required this.breathTier,
    required this.sleepMode,
    required this.onTierChanged,
    required this.onSleepModeChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final PracticeManifest manifest;
  final int breathTier;
  final bool sleepMode;
  final ValueChanged<int> onTierChanged;
  final ValueChanged<bool> onSleepModeChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  String get _lengthLabel {
    final d = manifest.typicalLength;
    if (manifest.id == 'tide_breath') return '自定（三档节奏）';
    if (manifest.id == 'fish_petals') return '自定';
    if (manifest.id == 'cross_river') return '由跳数决定';
    if (manifest.id == 'wooden_fish') return '108 下（约 2 分钟）';
    if (d.inMinutes >= 1) return '${d.inMinutes} 分钟';
    return '${d.inSeconds} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0AE8DFC8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 详情横幅：修行插画（居中构图裁为横幅）。
          if (_kPracticeArt[manifest.iconKey] != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                _kPracticeArt[manifest.iconKey]!,
                width: double.infinity,
                height: 132,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(
                manifest.eyeMode == EyeMode.eyesClosed
                    ? Icons.nights_stay
                    : Icons.remove_red_eye_outlined,
                color: AppTheme.goldDim,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                manifest.eyeMode.label,
                style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _lengthLabel,
                style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
              ),
            ],
          ),
          if (manifest.introTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                manifest.introTags,
                style: const TextStyle(
                  color: AppTheme.goldDim,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
          if (manifest.needsHeadphones)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.headphones, color: AppTheme.inkFaint, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '建议佩戴耳机（时机判定依赖立体声与低延迟）',
                    style: TextStyle(color: AppTheme.inkFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (manifest.intro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                manifest.intro,
                style: const TextStyle(
                  color: AppTheme.inkDim,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ),
          // 旧版玩法说明段已按新改进意见删除（介绍文本以 manifest.intro 为准）。
          if (manifest.id == 'tide_breath') ...[
            // 呼吸法选择已移到开始界面（改进列表）。
            const SizedBox(height: 6),
            Row(
              children: [
                Switch(
                  value: sleepMode,
                  onChanged: onSleepModeChanged,
                  activeThumbColor: AppTheme.gold,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '助眠模式：结束不弹结算页，音频渐弱至静音，修为次日补发',
                    style: TextStyle(color: AppTheme.inkFaint, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.bg,
                  ),
                  child: const Text('确定'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.inkDim,
                    side: const BorderSide(color: AppTheme.inkFaint),
                  ),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

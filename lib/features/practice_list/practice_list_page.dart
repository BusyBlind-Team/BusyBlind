import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/practice/practice_art.dart';
import '../../core/practice/practice_host.dart';
import '../../core/practice/practice_manifest.dart';
import '../../core/practice/practice_registry.dart';
import '../../theme.dart';

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
  bool _handsFree = false;

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
      params['handsFree'] = _handsFree;
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
          final art = practiceArtFor(m.iconKey);
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
                    handsFree: _handsFree,
                    onTierChanged: (t) => setState(() => _breathTier = t),
                    onHandsFreeChanged: (v) => setState(() => _handsFree = v),
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
    required this.handsFree,
    required this.onTierChanged,
    required this.onHandsFreeChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final PracticeManifest manifest;
  final int breathTier;
  final bool handsFree;
  final ValueChanged<int> onTierChanged;
  final ValueChanged<bool> onHandsFreeChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  String get _lengthLabel {
    final d = manifest.typicalLength;
    if (manifest.id == 'tide_breath') return '5分钟';
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
          // 大横幅插图已移到修行准备开始界面（Bug 描述 #2：介绍详情里不放）。
          // §11.1：删除"全程闭眼"整行（含左侧眼睛图标与文字），
          // 只保留右上角的时长标签。
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _lengthLabel,
              style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
            ),
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
          // §11.1(2)：删除"建议佩戴耳机"整行（对所有修行项生效）。
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
            // §7.1：删除助眠模式；§9.1：原"助眠模式"开关位置改为
            // "解放双手模式"（呼吸法选择仍在开始界面）。
            const SizedBox(height: 6),
            Row(
              children: [
                Switch(
                  value: handsFree,
                  onChanged: onHandsFreeChanged,
                  activeThumbColor: AppTheme.gold,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '解放双手模式：不用动手，专心呼吸，但无法积攒修为',
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

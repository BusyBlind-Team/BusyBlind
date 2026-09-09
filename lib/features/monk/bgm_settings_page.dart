import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../theme.dart';

/// 音乐与音效设置（首页"乐"入口）：
/// - 音量：作用于修行 BGM，并对应替换数雨（鸟鸣虫鸣）与
///   听潮（潮声）两个循环环境音。
/// - 曲目：随机 或 五首之一；本局修行内固定，下次修行生效。
class BgmSettingsPage extends ConsumerStatefulWidget {
  const BgmSettingsPage({super.key});

  @override
  ConsumerState<BgmSettingsPage> createState() => _BgmSettingsPageState();
}

class _BgmSettingsPageState extends ConsumerState<BgmSettingsPage> {
  /// 拖动中的临时音量：拖动过程只改本地，松手（onChangeEnd）才落盘。
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final track = store.bgmTrackIndex;
    final volume = _dragVolume ?? store.bgmVolume;

    return Scaffold(
      appBar: AppBar(title: const Text('音乐与音效')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          const Text(
            '音量',
            style: TextStyle(
              color: AppTheme.gold,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          Slider(
            value: volume,
            // 拖动过程只更新本地预览，松手才写存储（第 12 轮自检）。
            onChanged: (v) => setState(() => _dragVolume = v),
            onChangeEnd: (v) {
              ref.read(storeProvider).setBgmSettings(volume: v);
              setState(() => _dragVolume = null);
            },
          ),
          Text(
            '${(volume * 100).round()}% —— 修行背景音乐与数雨/听潮的环境声',
            style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
          ),
          const SizedBox(height: 28),
          const Text(
            '曲目',
            style: TextStyle(
              color: AppTheme.gold,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          _TrackRow(
            label: '随机（每次修行抽一首）',
            selected: track == SoundCatalog.bgmTrackRandom,
            onTap: () => ref
                .read(storeProvider)
                .setBgmSettings(track: SoundCatalog.bgmTrackRandom),
          ),
          _TrackRow(
            label: '无（不播背景音乐）',
            selected: track == SoundCatalog.bgmTrackNone,
            onTap: () => ref
                .read(storeProvider)
                .setBgmSettings(track: SoundCatalog.bgmTrackNone),
          ),
          for (var i = 0; i < SoundCatalog.bgmTracks.length; i++)
            _TrackRow(
              label: SoundCatalog.bgmTracks[i].name,
              selected: track == i,
              onTap: () => ref
                  .read(storeProvider)
                  .setBgmSettings(track: i),
            ),
          const SizedBox(height: 24),
          const Text(
            '所选项从下一次修行开始生效；数雨的鸟鸣虫鸣与听潮的潮声'
            '会对应替换为所选曲目（听潮的涨落包络仍会作用其上）。',
            style: TextStyle(color: AppTheme.inkFaint, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x1AD8B36A) : const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.music_note,
                  color: selected ? AppTheme.gold : AppTheme.inkFaint,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppTheme.ink : AppTheme.inkDim,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

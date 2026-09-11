import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../theme.dart';

/// 声音语义表的数据（首次教程第 ② 页与「我 → 声音指引」共用一份）。
///
/// final 而非 const：riverSoundKey 是方法调用，不能进编译期常量。
final List<({String sound, String meaning, List<String> keys, int gapMs})>
kSoundGuideRows = [
  (
    sound: '轻快的筝',
    meaning: '开始 / 请闭眼',
    keys: [SoundCatalog.chimeKey],
    gapMs: 900,
  ),
  (
    sound: '沉重的筝',
    meaning: '结束 / 可以睁眼',
    keys: [SoundCatalog.chimeDoubleKey],
    gapMs: 900,
  ),
  // 过河的引导音就是"筝"。示例：播 1 → 间隔 1 秒 → 播 2。
  (
    sound: '筝',
    meaning: '过河：复现这个间隔',
    keys: [SoundCatalog.riverSoundKey(1), SoundCatalog.riverSoundKey(2)],
    gapMs: 1000,
  ),
  (
    sound: '花瓣/杂物上钩的声音',
    meaning: '花瓣/杂物上钩了',
    keys: [SoundCatalog.fishDingKey, SoundCatalog.fishDongKey],
    gapMs: 900,
  ),
  (
    sound: '木鱼声',
    meaning: '一秒一声的节拍',
    keys: [SoundCatalog.muyuKey],
    gapMs: 900,
  ),
];

/// 声音语义表列表（每条可现场试听）。
class SoundGuideList extends ConsumerWidget {
  const SoundGuideList({super.key});

  Future<void> _playDemo(WidgetRef ref, List<String> keys, int gapMs) async {
    final sounds = ref.read(soundBankProvider);
    for (final key in keys) {
      await sounds.play(key);
      await Future<void>.delayed(Duration(milliseconds: gapMs));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final row in kSoundGuideRows)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x10FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.sound,
                        style: const TextStyle(
                          color: AppTheme.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row.meaning,
                        style: const TextStyle(
                          color: AppTheme.inkDim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '试听',
                  onPressed: () => _playDemo(ref, row.keys, row.gapMs),
                  icon: const Icon(
                    Icons.volume_up_outlined,
                    color: AppTheme.goldDim,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// §12：「我」页常驻的"声音指引"页——完整展示首次启动的声音指引内容，
/// 随时可进入查看与试听，不随首启结束消失。
class SoundGuidePage extends StatelessWidget {
  const SoundGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('声音指引')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        children: const [
          Text(
            '声音的语言',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '这个世界用声音说话。记住它们，闭上眼睛就不会迷路。点一下可以试听。',
            style: TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.6),
          ),
          SizedBox(height: 18),
          SoundGuideList(),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

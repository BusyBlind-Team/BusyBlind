import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_bank.dart';
import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../theme.dart';

/// 声音语义表的数据（首次教程第 ② 页与「我 → 声音指引」共用一份）。
///
/// final 而非 const：riverSoundKey 是方法调用，不能进编译期常量。
final List<
  ({
    String sound,
    String meaning,
    List<String> keys,
    int gapMs,
    int? previewSeconds,
  })
>
kSoundGuideRows = [
  (
    sound: '轻快的筝',
    meaning: '开始 / 请闭眼',
    keys: [SoundCatalog.chimeKey],
    gapMs: 900,
    previewSeconds: null,
  ),
  (
    sound: '沉重的筝',
    meaning: '结束 / 可以睁眼',
    keys: [SoundCatalog.chimeDoubleKey],
    gapMs: 900,
    previewSeconds: null,
  ),
  // Bug#4（第二轮）：原"筝 / 过河：复现这个间隔"改为"筝的音阶 /
  // 复现音符间的间隔"。示例仍是播 1 → 间隔 1 秒 → 播 2。
  (
    sound: '筝的音阶',
    meaning: '复现音符间的间隔',
    keys: [SoundCatalog.riverSoundKey(1), SoundCatalog.riverSoundKey(2)],
    gapMs: 1000,
    previewSeconds: null,
  ),
  (
    sound: '花瓣/杂物上钩的声音',
    meaning: '花瓣/杂物上钩了',
    keys: [SoundCatalog.fishDingKey, SoundCatalog.fishDongKey],
    gapMs: 900,
    previewSeconds: null,
  ),
  (
    sound: '木鱼声',
    meaning: '一秒一声的节拍',
    keys: [SoundCatalog.muyuKey],
    gapMs: 900,
    previewSeconds: null,
  ),
  // Bug#4 新增：三种雨滴依次试听。
  (
    sound: '雨滴',
    meaning: '屋檐落下的雨滴',
    keys: [
      'rain_drop_1',
      'rain_drop_2',
      'rain_drop_3',
    ],
    gapMs: 900,
    previewSeconds: null,
  ),
  // Bug#4 新增：弦音＝4-7-8 呼吸指引音频，试听只放前 4 秒。
  (
    sound: '弦音',
    meaning: '跟随音乐的变化调整呼吸',
    keys: [SoundCatalog.guideBreath478Key],
    gapMs: 900,
    previewSeconds: 4,
  ),
];

/// 声音语义表列表（每条可现场试听）。
class SoundGuideList extends ConsumerStatefulWidget {
  const SoundGuideList({super.key});

  @override
  ConsumerState<SoundGuideList> createState() => _SoundGuideListState();
}

class _SoundGuideListState extends ConsumerState<SoundGuideList> {
  /// 试听代号：每次点击 +1。到点的停止动作只在代号未变时执行，
  /// 于是"上一次试听的延迟停止"不会截断刚点开的下一次。
  int _previewToken = 0;

  /// 当前正在试听的长音轨 key（离开页面时要停掉）。
  String? _previewKey;

  /// 记下音效库：dispose 里不能再安全地 read provider。
  SoundBank? _bank;

  /// 试听一条。
  ///
  /// [previewSeconds] 非空时该条目是长音轨（如呼吸指引），只截取前若干秒：
  /// 用流式循环播放起播，到点停掉——短音效池播不了"前 4 秒"这种片段。
  Future<void> _playDemo(
    List<String> keys,
    int gapMs, {
    int? previewSeconds,
  }) async {
    final sounds = ref.read(soundBankProvider);
    _bank = sounds;
    if (previewSeconds != null) {
      final key = keys.first;
      final token = ++_previewToken;
      // 先停掉上一次的试听，避免两段叠在一起。
      await _stopPreview();
      if (!mounted || token != _previewToken) return;
      _previewKey = key;
      await sounds.startLoop(key, gain: 0.8);
      await Future<void>.delayed(Duration(seconds: previewSeconds));
      // 已被新的试听取代、或页面已销毁：本次不再动播放器，
      // 否则会把后点开的那一段截断。
      if (!mounted || token != _previewToken) return;
      _previewKey = null;
      await sounds.stopLoop(key);
      return;
    }
    await sounds.play(keys.first);
    for (final key in keys.skip(1)) {
      await Future<void>.delayed(Duration(milliseconds: gapMs));
      if (!mounted) return;
      await sounds.play(key);
    }
    await Future<void>.delayed(Duration(milliseconds: gapMs));
  }

  Future<void> _stopPreview() async {
    final key = _previewKey;
    _previewKey = null;
    if (key == null) return;
    final bank = _bank;
    if (bank == null) {
      await ref.read(soundBankProvider).stopLoop(key);
      return;
    }
    await bank.stopLoop(key);
  }

  @override
  void dispose() {
    // 离开页面立刻停掉正在试听的长音轨；并推进代号让在途的延迟停止失效。
    _previewToken++;
    final key = _previewKey;
    final bank = _bank;
    if (key != null && bank != null) {
      unawaited(bank.stopLoop(key));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => _playDemo(
                    row.keys,
                    row.gapMs,
                    previewSeconds: row.previewSeconds,
                  ),
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

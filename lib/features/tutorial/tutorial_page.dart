import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../di.dart';
import '../../shell/app_shell.dart';
import '../../theme.dart';

/// 首启教程（两页式，Bug 描述 #3）：
/// ① 出发提示——建议戴耳机、修行全程可闭眼；
/// ② 声音语义表——教一门声音语言，每条可现场试听。
/// （原"先坐一分钟"试玩页与"时机校准"页及其功能已整体删除。）
class TutorialPage extends ConsumerStatefulWidget {
  const TutorialPage({super.key});

  @override
  ConsumerState<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends ConsumerState<TutorialPage> {
  int _step = 0;

  /// final 而非 const：riverSoundKey 是方法调用，不能进编译期常量。
  static final List<({String sound, String meaning, List<String> keys})>
  _soundRows = [
    (sound: '轻快的筝', meaning: '开始 / 请闭眼', keys: [SoundCatalog.chimeKey]),
    (sound: '沉重的筝', meaning: '结束 / 可以睁眼', keys: [SoundCatalog.chimeDoubleKey]),
    (
      sound: '过河引导音',
      meaning: '过河：复现这个间隔',
      keys: [SoundCatalog.riverSoundKey(1), SoundCatalog.riverSoundKey(2)],
    ),
    (
      sound: '花瓣/杂物上钩的声音',
      meaning: '花瓣/杂物上钩了',
      keys: [SoundCatalog.fishDingKey, SoundCatalog.fishDongKey],
    ),
    (sound: '木鱼声', meaning: '一秒一声的节拍', keys: [SoundCatalog.muyuKey]),
  ];

  void _next() {
    if (_step < 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _finish() {
    final store = ref.read(storeProvider);
    store.tutorialDone = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  Future<void> _playDemo(List<String> keys) async {
    final sounds = ref.read(soundBankProvider);
    for (final key in keys) {
      await sounds.play(key);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('入山门'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 进度点。
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _step
                            ? AppTheme.gold
                            : const Color(0x33E8DFC8),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: switch (_step) {
                  0 => _welcomeStep(),
                  _ => _soundLanguageStep(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('上一步', style: TextStyle(color: AppTheme.inkDim)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.bg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                    child: Text(_step == 1 ? '进入山门' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 第 ① 页：出发提示（Bug 描述 #3 新增）----

  Widget _welcomeStep() {
    return Padding(
      key: const ValueKey('step0'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.headphones_outlined,
            color: AppTheme.goldDim,
            size: 56,
          ),
          const SizedBox(height: 28),
          const Text(
            '建议戴上耳机，享受片刻宁静',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '修行过程中，全程可闭眼',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.inkDim, fontSize: 15, height: 1.7),
          ),
        ],
      ),
    );
  }

  // ---- 第 ② 页：声音语义表 ----

  Widget _soundLanguageStep() {
    return ListView(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const Text(
          '声音的语言',
          style: TextStyle(
            color: AppTheme.ink,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '这个世界用声音说话。记住它们，闭上眼睛就不会迷路。点一下可以试听。',
          style: TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 18),
        for (final row in _soundRows)
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
                        style: const TextStyle(color: AppTheme.inkDim, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '试听',
                  onPressed: () => _playDemo(row.keys),
                  icon: const Icon(Icons.volume_up_outlined, color: AppTheme.goldDim),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

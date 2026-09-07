import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_catalog.dart';
import '../../core/practice/practice_host.dart';
import '../../data/app_store.dart';
import '../../di.dart';
import '../../practices/sit_quiet.dart';
import '../../shell/app_shell.dart';
import '../../theme.dart';
import 'calibration_page.dart';

/// 首启教程（设计方案·八，三段式）：
/// ① 声音语义表——教一门声音语言，每条可现场试听；
/// ② 60 秒试玩——复用"静坐"（同时是插件框架验收用例）；
/// ③ 校准收尾——跟拍 16 次取中位数写入 L_user（可跳过，之后在"我"页随时可做）。
class TutorialPage extends ConsumerStatefulWidget {
  const TutorialPage({super.key});

  @override
  ConsumerState<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends ConsumerState<TutorialPage> {
  int _step = 0;
  bool _tried = false;

  static const List<({String sound, String meaning, List<String> keys})>
  _soundRows = [
    (sound: '磬一声', meaning: '开始 / 请闭眼', keys: [SoundCatalog.chimeKey]),
    (sound: '磬两声', meaning: '结束 / 可以睁眼', keys: [SoundCatalog.chimeDoubleKey]),
    (
      sound: '极轻的磬',
      meaning: '打坐时确认你还在（30 秒内轻触任意处）',
      keys: [SoundCatalog.chimeSoftKey],
    ),
    (sound: '叮 —— 咚', meaning: '过河：复现这个间隔', keys: ['he_ding', 'he_dong']),
    (sound: '叮 / 咚', meaning: '钓花：花瓣 / 杂物，叮则收手', keys: ['fish_ding', 'fish_dong']),
    (sound: '木鱼声', meaning: '节拍锚——由你自己敲出', keys: [SoundCatalog.muyuKey]),
  ];

  void _next() {
    if (_step < 2) {
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
    final store = ref.watch(storeProvider);
    _tried = _tried || store.sessionCount > 0;

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
                  for (var i = 0; i < 3; i++)
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
                  0 => _soundLanguageStep(),
                  1 => _trialStep(),
                  _ => _calibrationStep(store),
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
                    child: Text(_step == 2 ? '进入山门' : '下一步'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 第 ① 段：声音语义表 ----

  Widget _soundLanguageStep() {
    return ListView(
      key: const ValueKey('step0'),
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

  // ---- 第 ② 段：60 秒试玩 ----

  Widget _trialStep() {
    return Padding(
      key: const ValueKey('step1'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '先坐一分钟',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '什么都不用做：磬响后闭上眼，一分钟后再听到磬声，就睁眼回来。\n\n'
            '这就是一次完整的修行。所有修行都这样——几分钟，闭眼，跟着声音动一下。',
            style: TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.8),
          ),
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PracticeHostPage(factory: SitQuietSession.new),
                ),
              );
              if (mounted) setState(() => _tried = true);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.gold,
              side: const BorderSide(color: AppTheme.goldDim),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_tried ? '再试一次' : '试玩一分钟'),
          ),
        ],
      ),
    );
  }

  // ---- 第 ③ 段：校准与完成 ----

  Widget _calibrationStep(AppStore store) {
    final calibrated = store.lUserUs != 0;
    return Padding(
      key: const ValueKey('step2'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '最后一步：贴合你的耳朵',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '跟着节拍轻点 16 次，此后每一次声音与触摸的相遇，都会贴着你的耳朵来计算。\n\n'
            '也可以先跳过——在「我」页随时可以校准。',
            style: TextStyle(color: AppTheme.inkDim, fontSize: 14, height: 1.8),
          ),
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CalibrationPage()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.gold,
              side: const BorderSide(color: AppTheme.goldDim),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(calibrated ? '重新校准 ✓' : '去校准'),
          ),
        ],
      ),
    );
  }
}

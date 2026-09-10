import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'core/audio/audio_clock.dart';
import 'core/audio/sound_bank.dart';
import 'core/audio/sound_catalog.dart';
import 'data/app_store.dart';
import 'di.dart';
import 'domain/achievements.dart';
import 'features/tutorial/tutorial_page.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地优先：先读本地数据（断网时除加好友外全部功能可用）。
  final store = await AppStore.load();
  // 助眠模式次日补发的修为到账。
  store.takePendingMerit();

  // 音效库：资源注册与短音效预解码分开（复审 R1）。
  // 全部 key 先注册——听潮/数雨在选了曲目时用同一 BGM key 做环境循环，
  // 潮起潮落的音量包络靠 startLoop/setLoopGain 作用在这条流式音轨上，
  // 不注册就会静默失效。BGM（bgm_*）不预解码进内存池（第 17 轮自检：
  // 5 首 80 秒曲目整段解码进内存会无谓占用大量内存），由环境循环/
  // BgmPlayer 按需流式播放。
  final sounds = AudioPlayersSoundBank();
  sounds.register(SoundCatalog.catalog);
  await sounds.preload({
    for (final e in SoundCatalog.catalog.entries)
      if (!e.key.startsWith('bgm_')) e.key: e.value,
  });

  // 时钟：载入用户校准偏移。
  final clock = SystemAudioClock();
  clock.userOffsetUs = store.lUserUs;

  // 进入软件后屏幕常亮（改进列表）；不可用的平台静默降级。
  try {
    await WakelockPlus.enable();
  } catch (_) {}

  // 登录天数累计 + 启动追认成就（登录/等级/历史条件，如"动杯雨接"）。
  store.touchLogin();
  evaluateAchievements(store);

  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWith((ref) => store),
        soundBankProvider.overrideWithValue(sounds),
        clockProvider.overrideWithValue(clock),
      ],
      child: BusyBlindApp(
        home: store.tutorialDone ? const AppShell() : const TutorialPage(),
      ),
    ),
  );
}

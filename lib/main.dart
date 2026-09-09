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

  // 音效库：短音效全部预加载进内存池，禁止播放时解码。
  // BGM（bgm_*）不进内存池——由 BgmPlayer 按需流式播放（第 17 轮自检：
  // 5 首 80 秒曲目整段解码进内存会无谓占用大量内存）。
  final sounds = AudioPlayersSoundBank();
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

import 'package:audioplayers/audioplayers.dart';
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

  // 音频焦点：全局"混合播放"（Bug 描述 #1）。audioplayers 默认每路
  // 播放都申请独占音频焦点（gain），SFX 一响就把正在播的 BGM 挤停且
  // 不会自动恢复；设为 mixWithOthers 后，Android 不再申请焦点、iOS
  // 以 mixWithOthers 混音——BGM 与 SFX 各自独立叠加，互不中断。
  try {
    final context = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();
    await AudioPlayer.global.setAudioContext(context);
  } catch (_) {
    // 不支持音频上下文的平台（如测试环境）静默降级。
  }

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
      if (!SoundCatalog.isStreamedKey(e.key)) e.key: e.value,
  });

  // 时钟：全局音频时间轴（用户校准已随"时机校准"功能删除——Bug 描述 #3）。
  final clock = SystemAudioClock();

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

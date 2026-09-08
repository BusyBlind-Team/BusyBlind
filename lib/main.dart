import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio/audio_clock.dart';
import 'core/audio/sound_bank.dart';
import 'core/audio/sound_catalog.dart';
import 'data/app_store.dart';
import 'di.dart';
import 'features/tutorial/tutorial_page.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地优先：先读本地数据（断网时除加好友外全部功能可用）。
  final store = await AppStore.load();
  // 助眠模式次日补发的修为到账。
  store.takePendingMerit();

  // 音效库：全部预加载进内存池，禁止播放时解码。
  final sounds = AudioPlayersSoundBank();
  await sounds.preload(SoundCatalog.catalog);

  // 时钟：载入用户校准偏移。
  final clock = SystemAudioClock();
  clock.userOffsetUs = store.lUserUs;

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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_clock.dart';
import 'core/audio/input_capture.dart';
import 'core/audio/sound_bank.dart';
import 'data/app_store.dart';

/// 依赖注入：全 app 一根时钟、一个音效库、一份本地数据。
///
/// EventScheduler 与 SessionRecorder 是会话级的，由 PracticeHost 按会话创建。
/// AppStore 是 ChangeNotifier；使用可监听的 provider，使跨页面的存储更新
/// 能重建正在展示修为、成就和花瓣的界面。
final storeProvider = ChangeNotifierProvider<AppStore>(
  (ref) => throw UnimplementedError(),
);

final clockProvider = Provider<AudioClock>((ref) => SystemAudioClock());

final soundBankProvider = Provider<SoundBank>((ref) => throw UnimplementedError());

final inputCaptureProvider = Provider<InputCapture>(
  (ref) => InputCapture(ref.watch(clockProvider)),
);

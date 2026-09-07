// 音效合成脚本：先生成临时 PCM WAV，再用 FFmpeg 转为 mono MP3。
//
// v0.1 的占位音色：合成参数刻意匹配设计方案的声音语义表——
// 雨滴高频短促、钟声低频长尾、过河与钓花的叮/咚音色包络拉开，
// 正式音效由 Domingo 录制后直接替换同名文件即可，代码无需改动。
//
// 运行：dart run tool/gen_sounds.dart
// FFmpeg 不在 PATH 时：FFMPEG_PATH=/path/to/ffmpeg dart run tool/gen_sounds.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int sampleRate = 44100;
late final Directory scratchDir;
late final String ffmpegExecutable;

void main() {
  final outDir = Directory('assets/sfx');
  outDir.createSync(recursive: true);
  scratchDir = Directory('build/generated_audio_pcm')
    ..createSync(recursive: true);
  ffmpegExecutable = Platform.environment['FFMPEG_PATH'] ?? 'ffmpeg';

  final probe = Process.runSync(ffmpegExecutable, const ['-version']);
  if (probe.exitCode != 0) {
    stderr.writeln('找不到 FFmpeg。请先安装 ffmpeg，或通过 FFMPEG_PATH 指向可执行文件。');
    exitCode = 2;
    return;
  }

  write('chime.mp3', chime(gain: 0.85, decay: 1.3, seconds: 3.2));
  write('chime_soft.mp3', chime(gain: 0.4, decay: 0.9, seconds: 2.0));
  write('chime_double.mp3', chimeDouble());
  write('tick.mp3', tick());
  write('muyu.mp3', muyu(dark: false));
  write('muyu_muffled.mp3', muyu(dark: true));
  // 短瞬态音效保留 44.1kHz；低频长尾与环境循环降到 22.05kHz 省包体。
  write(
    'he_ding.mp3',
    bell(
      [1760, 2640, 3520],
      amps: [1.0, 0.4, 0.2],
      decay: 0.7,
      gain: 0.8,
      seconds: 2.0,
    ),
  );
  write('he_dong.mp3', decimate2(thud(base: 196, decay: 0.5, gain: 0.85)));
  write(
    'fish_ding.mp3',
    bell([880, 1320], amps: [1.0, 0.3], decay: 0.28, gain: 0.85, pluck: true),
  );
  write('fish_dong.mp3', decimate2(thud(base: 150, decay: 0.2, gain: 0.8)));
  write(
    'rain_drop.mp3',
    bell([3200, 4800], amps: [1.0, 0.3], decay: 0.07, gain: 0.7),
  );
  write(
    'bell_low.mp3',
    decimate2(
      bell(
        [330, 660, 990],
        amps: [1.0, 0.5, 0.25],
        decay: 1.7,
        gain: 0.7,
        seconds: 2.6,
      ),
    ),
  );
  write('wind_chime.mp3', windChime());
  write('swish.mp3', swish());
  write('forest_loop.mp3', decimate2(forestLoop()), rate: 22050);
  write('tide_loop.mp3', decimate2(tideLoop()), rate: 22050);

  if (scratchDir.existsSync() && scratchDir.listSync().isEmpty) {
    scratchDir.deleteSync();
  }
  final count = outDir.listSync().where((f) => f.path.endsWith('.mp3')).length;
  stdout.writeln('已生成 $count 个 MP3 音效 → assets/sfx/');
}

// ---------- 合成基元 ----------

/// 敲击类频谱：多个非谐分音 + 指数衰减 + 软起音。
List<double> bell(
  List<double> freqs, {
  List<double> amps = const [1.0],
  required double decay,
  required double gain,
  double seconds = -1,
  bool pluck = false,
}) {
  final n = ((seconds < 0 ? decay * 4 : seconds) * sampleRate).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < freqs.length; i++) {
    final a = i < amps.length ? amps[i] : 0.2;
    final w = 2 * pi * freqs[i] / sampleRate;
    for (var s = 0; s < n; s++) {
      final t = s / sampleRate;
      final env = exp(-t / decay);
      final attack = min(1.0, t / (pluck ? 0.003 : 0.008));
      out[s] += a * env * attack * sin(w * s);
    }
  }
  return normalize(out, gain);
}

/// 磬：偏金属碗声，加一点不谐和抖动。
List<double> chime({
  required double gain,
  required double decay,
  required double seconds,
}) {
  final out = bell(
    [700, 1421, 2280, 3130],
    amps: [1.0, 0.5, 0.22, 0.1],
    decay: decay,
    gain: gain,
    seconds: seconds,
  );
  return out;
}

List<double> chimeDouble() {
  final strike = chime(gain: 0.8, decay: 1.0, seconds: 2.4);
  final gap = (0.9 * sampleRate).round();
  final out = List<double>.filled(strike.length + gap, 0);
  for (var i = 0; i < strike.length; i++) {
    out[i] += strike[i];
    out[i + gap] += strike[i] * 0.95;
  }
  return normalize(out, 0.85);
}

List<double> tick() =>
    bell([1200, 2400], amps: [1.0, 0.2], decay: 0.03, gain: 0.8, seconds: 0.06);

/// 木鱼：短促叩击；dark=true 时为"变闷"音色（低频、更快衰减）。
List<double> muyu({required bool dark}) {
  final out = bell(
    dark ? [520, 1040, 1560] : [820, 1640, 2460],
    amps: dark ? [1.0, 0.35, 0.1] : [1.0, 0.55, 0.3],
    decay: dark ? 0.09 : 0.13,
    gain: 0.85,
    seconds: 0.35,
    pluck: true,
  );
  // 叩击瞬态。
  final rng = Random(7);
  for (var s = 0; s < sampleRate * 8 ~/ 1000; s++) {
    out[s] +=
        (rng.nextDouble() * 2 - 1) * 0.25 * (1 - s / (sampleRate * 0.008));
  }
  return normalize(out, 0.85);
}

/// 低沉鼓点（过河"咚"）。
List<double> thud({
  required double base,
  required double decay,
  required double gain,
}) {
  final out = bell(
    [base, base * 2, base * 0.5],
    amps: [1.0, 0.4, 0.35],
    decay: decay,
    gain: gain,
    seconds: decay * 2.5,
    pluck: true,
  );
  final rng = Random(3);
  for (var s = 0; s < sampleRate * 15 ~/ 1000; s++) {
    out[s] += (rng.nextDouble() * 2 - 1) * 0.4 * (1 - s / (sampleRate * 0.015));
  }
  return normalize(out, gain);
}

List<double> windChime() {
  final n = (1.0 * sampleRate).round();
  final out = List<double>.filled(n, 0);
  final pings = [(2093.0, 0.0), (2637.0, 0.07), (3322.0, 0.15)];
  for (final (f, t0) in pings) {
    final start = (t0 * sampleRate).round();
    final w = 2 * pi * f / sampleRate;
    for (var s = start; s < n; s++) {
      final t = (s - start) / sampleRate;
      out[s] +=
          0.4 * exp(-t / 0.35) * min(1.0, t / 0.003) * sin(w * (s - start));
    }
  }
  return normalize(out, 0.6);
}

/// 甩竿的水声擦音。
List<double> swish() {
  final dur = 0.35;
  final n = (dur * sampleRate).round();
  final rng = Random(5);
  var lp = 0.0;
  final out = List<double>.filled(n, 0);
  for (var s = 0; s < n; s++) {
    final t = s / n;
    final env = sin(pi * t) * sin(pi * t);
    final white = rng.nextDouble() * 2 - 1;
    lp = lp * 0.82 + white * 0.18; // 简单低通，质感像水声
    out[s] = lp * env * 2.2;
  }
  return normalize(out, 0.6);
}

/// 鸟鸣虫鸣白噪声背景（12 秒无缝循环）。
List<double> forestLoop() {
  const dur = 12.0;
  final rng = Random(42);
  final n = (dur * sampleRate).round();
  final out = List<double>.filled(n, 0);

  // 底噪：柔和的褐色噪声。
  var brown = 0.0;
  for (var s = 0; s < n; s++) {
    brown = (brown + (rng.nextDouble() * 2 - 1) * 0.02) * 0.998;
    out[s] = brown * 3.0;
  }

  // 虫鸣：4.2kHz 载波 + 28Hz 幅度调制，随机散布。
  for (var k = 0; k < 10; k++) {
    final start = rng.nextInt(n - sampleRate);
    final len = (0.4 + rng.nextDouble() * 0.6) * sampleRate;
    final w = 2 * pi * 4200 / sampleRate;
    for (var s = 0; s < len && start + s < n; s++) {
      final t = s / sampleRate;
      final am = 0.5 + 0.5 * sin(2 * pi * 28 * t);
      final env = min(1.0, t / 0.05) * min(1.0, (len - s) / sampleRate / 0.05);
      out[start + s] += 0.06 * am * env * sin(w * s);
    }
  }

  // 鸟叫：几段短促下滑音。
  for (var k = 0; k < 6; k++) {
    final start = rng.nextInt(n - sampleRate);
    final len = (0.12 + rng.nextDouble() * 0.15) * sampleRate;
    final f0 = 2800 + rng.nextDouble() * 1600;
    for (var s = 0; s < len && start + s < n; s++) {
      final t = s / sampleRate;
      final f = f0 * (1 - 0.25 * t / 0.3);
      final env = sin(pi * s / len);
      out[start + s] += 0.12 * env * sin(2 * pi * f * t);
    }
  }
  return loopable(normalize(out, 0.7), 1.0);
}

/// 潮汐循环（12 秒，两个浪涌周期，供音量包络再调度）。
List<double> tideLoop() {
  const dur = 12.0;
  final rng = Random(11);
  final n = (dur * sampleRate).round();
  final out = List<double>.filled(n, 0);

  var brown = 0.0;
  for (var s = 0; s < n; s++) {
    brown = (brown + (rng.nextDouble() * 2 - 1) * 0.03) * 0.997;
    // 浪涌：6 秒一个周期（涨落各半），叠一点随机起伏。
    final t = s / sampleRate;
    final swell = 0.5 + 0.5 * sin(2 * pi * t / 6 - pi / 2);
    final shimmer = 0.85 + 0.15 * sin(2 * pi * t / 2.3);
    out[s] = brown * 4.0 * swell * shimmer;
  }
  return loopable(normalize(out, 0.85), 1.5);
}

/// 尾部交叉渐隐进头部，做无缝循环。
List<double> loopable(List<double> input, double fadeSeconds) {
  final fade = (fadeSeconds * sampleRate).round();
  final n = input.length - fade;
  final out = List<double>.filled(n, 0);
  for (var s = 0; s < n; s++) {
    out[s] = input[s];
    if (s < fade) {
      final x = s / fade;
      out[s] = input[s] * x + input[n + s] * (1 - x);
    }
  }
  return out;
}

/// 2:1 抽取降采样（44.1k → 22.05k）。用于低频/噪声类音轨，
/// 语义表里的最高频成分（虫鸣 4.2kHz、鸟叫 ≤4.4kHz）远离新奈奎斯特频率。
List<double> decimate2(List<double> input) {
  final out = <double>[];
  for (var i = 0; i + 1 < input.length; i += 2) {
    out.add((input[i] + input[i + 1]) / 2);
  }
  return out;
}

List<double> normalize(List<double> input, double peak) {
  var maxAbs = 0.0;
  for (final v in input) {
    final a = v.abs();
    if (a > maxAbs) maxAbs = a;
  }
  if (maxAbs == 0) return input;
  final k = peak / maxAbs;
  return [for (final v in input) v * k];
}

// ---------- PCM 写出 + MP3 转码 ----------

void write(String name, List<double> samples, {int rate = sampleRate}) {
  final n = samples.length;
  final data = BytesBuilder();
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.addByte(v & 0xff);
    data.addByte((v >> 8) & 0xff);
  }
  final payload = data.takeBytes();

  final header = BytesBuilder()
    ..add([
      ...utf8list('RIFF'),
      ...u32(36 + payload.length),
      ...utf8list('WAVE'),
    ])
    ..add([...utf8list('fmt '), ...u32(16), ...u16(1), ...u16(1)])
    ..add([...u32(rate), ...u32(rate * 2), ...u16(2), ...u16(16)])
    ..add([...utf8list('data'), ...u32(payload.length)]);

  final stem = name.endsWith('.mp3')
      ? name.substring(0, name.length - 4)
      : name;
  final wavFile = File('${scratchDir.path}/$stem.wav');
  wavFile.writeAsBytesSync([...header.takeBytes(), ...payload]);

  final isLoop = stem == 'forest_loop' || stem == 'tide_loop';
  final result = Process.runSync(ffmpegExecutable, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    wavFile.path,
    '-map_metadata',
    '-1',
    '-vn',
    '-ac',
    '1',
    '-c:a',
    'libmp3lame',
    '-b:a',
    isLoop ? '64k' : '128k',
    '-id3v2_version',
    '0',
    '-write_xing',
    '1',
    'assets/sfx/$stem.mp3',
  ]);
  wavFile.deleteSync();
  if (result.exitCode != 0) {
    throw StateError('FFmpeg 转码失败：$stem\n${result.stderr}');
  }
}

List<int> utf8list(String s) => s.codeUnits;
List<int> u32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];
List<int> u16(int v) => [v & 0xff, (v >> 8) & 0xff];

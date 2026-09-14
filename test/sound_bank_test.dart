import 'dart:async';

import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedLoopPlayer implements LoopPlayer {
  final prepareStarted = Completer<void>();
  final prepared = Completer<void>();
  final calls = <String>[];
  void Function()? onPause;
  Future<void>? pauseGate;

  @override
  Future<void> dispose() async => calls.add('dispose');

  @override
  Future<void> pause() async {
    calls.add('pause');
    onPause?.call();
    final gate = pauseGate;
    if (gate != null) await gate;
  }

  @override
  Future<void> prepareAsset(String asset) async {
    calls.add('prepare:$asset');
    prepareStarted.complete();
    await prepared.future;
  }

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> seek(Duration position) async => calls.add('seek:$position');

  @override
  Future<void> setLooping() async => calls.add('loop');

  @override
  Future<void> setVolume(double gain) async => calls.add('volume:$gain');

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  test('加载中切后台，准备完成后仍保持暂停，回前台才播放', () async {
    final player = _DelayedLoopPlayer();
    final bank = AudioPlayersSoundBank(loopPlayerFactory: () => player);
    await bank.register({'rain': 'sfx/rain.m4a'});

    final starting = bank.startLoop('rain', gain: 0.35);
    await player.prepareStarted.future;
    await bank.pauseAll();
    player.prepared.complete();
    await starting;

    expect(player.calls, contains('pause'));
    expect(player.calls, isNot(contains('resume')));

    await bank.resumeAll();
    expect(player.calls.last, 'resume');
    bank.dispose();
  });

  test('准备环境音不播放，且首次播放前已经设置目标音量', () async {
    final player = _DelayedLoopPlayer();
    final bank = AudioPlayersSoundBank(loopPlayerFactory: () => player);
    await bank.register({'river': 'sfx/river.m4a'});

    final starting = bank.startLoop('river', gain: 0.35);
    await player.prepareStarted.future;
    expect(
      player.calls,
      ['loop', 'volume:0.0', 'prepare:sfx/river.m4a'],
      reason: '资源准备不能通过 play 产生任何可闻声音',
    );

    player.prepared.complete();
    await starting;
    expect(
      player.calls,
      ['loop', 'volume:0.0', 'prepare:sfx/river.m4a', 'volume:0.35', 'resume'],
    );
    bank.dispose();
  });

  test('暂停期间音轨被停止时，仍会继续暂停其余音轨', () async {
    final first = _DelayedLoopPlayer();
    final second = _DelayedLoopPlayer();
    final players = [first, second];
    final bank = AudioPlayersSoundBank(
      loopPlayerFactory: () => players.removeAt(0),
    );
    await bank.register({
      'first': 'sfx/first.m4a',
      'second': 'sfx/second.m4a',
    });

    final firstStart = bank.startLoop('first');
    final secondStart = bank.startLoop('second');
    await Future.wait([
      first.prepareStarted.future,
      second.prepareStarted.future,
    ]);
    first.prepared.complete();
    second.prepared.complete();
    await Future.wait([firstStart, secondStart]);

    first.onPause = () => unawaited(bank.stopLoop('first'));
    await bank.pauseAll();

    expect(second.calls, contains('pause'));
    bank.dispose();
  });

  test('旧暂停在快速恢复后不会再次暂停其余音轨', () async {
    final first = _DelayedLoopPlayer();
    final second = _DelayedLoopPlayer();
    final players = [first, second];
    final bank = AudioPlayersSoundBank(
      loopPlayerFactory: () => players.removeAt(0),
    );
    await bank.register({
      'first': 'sfx/first.m4a',
      'second': 'sfx/second.m4a',
    });

    final firstStart = bank.startLoop('first');
    final secondStart = bank.startLoop('second');
    await Future.wait([
      first.prepareStarted.future,
      second.prepareStarted.future,
    ]);
    first.prepared.complete();
    second.prepared.complete();
    await Future.wait([firstStart, secondStart]);

    final gate = Completer<void>();
    final firstPauseStarted = Completer<void>();
    first
      ..pauseGate = gate.future
      ..onPause = firstPauseStarted.complete;
    final stalePause = bank.pauseAll();
    await firstPauseStarted.future;

    await bank.resumeAll();
    gate.complete();
    await stalePause;

    expect(
      second.calls.last,
      'resume',
      reason: '恢复后的第二条音轨不能被过期暂停再次停掉',
    );
    bank.dispose();
  });

  test('加载中停止音轨：准备完成后不得播放（P1）', () async {
    final player = _DelayedLoopPlayer();
    final bank = AudioPlayersSoundBank(loopPlayerFactory: () => player);
    await bank.register({'rain': 'sfx/rain.m4a'});

    final starting = bank.startLoop('rain', gain: 0.3);
    await player.prepareStarted.future;

    // 加载还没完成就停止：此时播放器尚未登记，stopLoop 看不到它。
    await bank.stopLoop('rain');
    player.prepared.complete();
    await starting;

    expect(player.calls, isNot(contains('resume')),
        reason: '已经停止的音轨，不能在加载完成后照样起播');
    expect(player.calls, contains('stop'),
        reason: '加载返回后应丢弃这个刚建好的播放器');
  });

  test('复用播放器时显式零起点必须 seek（P2）', () async {
    final player = _DelayedLoopPlayer();
    final bank = AudioPlayersSoundBank(loopPlayerFactory: () => player);
    await bank.register({'guide': 'bgm/guide.m4a'});

    final first = bank.startLoop('guide', gain: 0.4, startAt: Duration.zero);
    await player.prepareStarted.future;
    player.prepared.complete();
    await first;
    player.calls.clear();

    // 第二次启动复用同一个播放器：显式零起点必须真的回到 0。
    await bank.startLoop('guide', gain: 0.4, startAt: Duration.zero);
    expect(player.calls, contains('seek:${Duration.zero}'),
        reason: '复用播放器时把零当成"不 seek"，会保留上一局的进度');
  });

  test('不传起点（null）时保持原位，不额外 seek', () async {
    final player = _DelayedLoopPlayer();
    final bank = AudioPlayersSoundBank(loopPlayerFactory: () => player);
    await bank.register({'birds': 'sfx/birds.m4a'});

    final first = bank.startLoop('birds', gain: 0.3);
    await player.prepareStarted.future;
    player.prepared.complete();
    await first;
    player.calls.clear();

    await bank.startLoop('birds', gain: 0.3);
    expect(player.calls.where((c) => c.startsWith('seek')), isEmpty,
        reason: 'null 的语义是保持原位，不该 seek');
  });

}

import 'package:busy_blind/core/audio/sound_bank.dart';
import 'package:busy_blind/core/practice/practice_host.dart';
import 'package:busy_blind/data/app_store.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/practices/cross_river.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

void main() {
  testWidgets('环境音慢加载时，渐入从就绪后才开始', (tester) async {
    final sounds = SilentSoundBank()
      ..startDelay = const Duration(seconds: 2);
    final store = AppStore.inMemory()..markTutorialSeen('cross_river');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) => store),
          soundBankProvider.overrideWithValue(sounds),
          clockProvider.overrideWithValue(FakeClock()),
        ],
        child: MaterialApp(home: PracticeHostPage(factory: CrossRiverSession.new)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(seconds: 1));
    expect(sounds.loopGainChanges, isEmpty, reason: '加载中不能消耗渐入计时');

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      sounds.loopGainChanges,
      contains(
        predicate<(String key, double gain)>(
          (change) => change.$1 == 'amb_river' && change.$2 > 0,
        ),
      ),
      reason: '就绪后才从静音开始第一档渐入',
    );
  });
}

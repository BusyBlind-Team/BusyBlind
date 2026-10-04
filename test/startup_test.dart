import 'dart:convert';
import 'dart:io';

import 'package:busy_blind/app.dart';
import 'package:busy_blind/di.dart';
import 'package:busy_blind/features/tutorial/tutorial_page.dart';
import 'package:busy_blind/main.dart' as app;
import 'package:busy_blind/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StartupPathProvider extends PathProviderPlatform {
  _StartupPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final tutorialDone in [false, true]) {
    testWidgets(
      'main renders ${tutorialDone ? 'the app shell' : 'the tutorial'} '
      'when sound preload fails',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'busy_blind_startup_',
        );
        final originalPathProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _StartupPathProvider(directory.path);
        addTearDown(() {
          PathProviderPlatform.instance = originalPathProvider;
          directory.deleteSync(recursive: true);
        });
        if (tutorialDone) {
          File('${directory.path}/busy_blind.json')
              .writeAsStringSync(jsonEncode({'tutorialDone': true}));
        }

        final messenger = tester.binding.defaultBinaryMessenger;
        // Let global setup succeed so this specifically exercises the real
        // AudioPool creation inside main's awaited sound preload.
        messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global/events'),
          (_) async => null,
        );
        var playerCreationAttempts = 0;
        messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (call) async {
            if (call.method == 'create') {
              playerCreationAttempts++;
              throw PlatformException(
                code: 'startup_audio_unavailable',
                message: 'Audio backend unavailable during startup',
              );
            }
            return null;
          },
        );

        final reportedErrors = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.library == 'busy_blind') {
            reportedErrors.add(details);
          } else {
            originalOnError?.call(details);
          }
        };
        try {
          await tester.runAsync(app.main);
        } finally {
          FlutterError.onError = originalOnError;
        }
        await tester.pumpAndSettle();

        expect(playerCreationAttempts, 1);
        expect(reportedErrors, hasLength(1));
        expect(
          reportedErrors.single.exception,
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'startup_audio_unavailable',
          ),
        );
        expect(find.byType(BusyBlindApp), findsOneWidget);
        expect(
          find.byType(tutorialDone ? AppShell : TutorialPage),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BusyBlindApp)),
        );
        await tester.runAsync(
          () => container.read(storeProvider).waitForSave(),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

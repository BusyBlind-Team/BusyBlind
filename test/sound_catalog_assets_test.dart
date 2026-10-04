import 'package:busy_blind/core/audio/sound_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every catalog sound is included in the Flutter asset bundle', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final bundledAssets = manifest.listAssets();

      for (final entry in SoundCatalog.catalog.entries) {
        final path = 'assets/${entry.value}';
        expect(
          bundledAssets,
          contains(path),
          reason: '${entry.key} must be declared in pubspec.yaml',
        );
        final data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0), reason: entry.key);
      }
    });
  });
}

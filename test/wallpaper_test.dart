import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_app.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Widget _host({required Widget child}) {
  return OasisHost(
    appearance: OasisAppearance(),
    updates: UpdateService(),
    setLocale: (_) {},
    child: child,
  );
}

void main() {
  test('wallpaper service defaults to the built-in dunes', () {
    final s = OasisWallpaperService();
    expect(s.imagePath, isNull);
    expect(s.hasCustomImage, isFalse);
    expect(s.fit, BoxFit.cover);
    s.dispose();
  });

  test('wallpaper service persists path and fit', () {
    final store = MemoryOasisStore();
    final s = OasisWallpaperService(store: store);
    var notified = 0;
    s.addListener(() => notified++);

    s.imagePath = '/pics/dune.png';
    s.imagePath = '/pics/dune.png';
    expect(store.read(OasisWallpaperService.kImagePathKey),
        '/pics/dune.png');
    expect(notified, 1);

    s.fit = BoxFit.contain;
    s.fit = BoxFit.contain;
    expect(
        store.read(OasisWallpaperService.kFitKey), 'contain');
    expect(notified, 2);

    final restored = OasisWallpaperService(store: store);
    expect(restored.imagePath, '/pics/dune.png');
    expect(restored.fit, BoxFit.contain);

    s.useDefault();
    expect(s.hasCustomImage, isFalse);
    expect(store.read(OasisWallpaperService.kImagePathKey), isNull);
    s.dispose();
    restored.dispose();
  });

  test('switching between presets still notifies listeners', () {
    final s = OasisWallpaperService();
    var notified = 0;
    s.addListener(() => notified++);

    s.usePreset('aurora');
    expect(notified, 1);
    s.usePreset('ember');
    expect(notified, 2);
    expect(s.preset, 'ember');
    s.dispose();
  });

  test('wallpaper service falls back for unknown fit names', () {
    final store = MemoryOasisStore();
    store.write(OasisWallpaperService.kFitKey, 'bogus');
    final s = OasisWallpaperService(store: store);
    expect(s.fit, BoxFit.cover);
    for (final fit in OasisWallpaperService.supportedFits) {
      store.write(OasisWallpaperService.kFitKey, fit.name);
      expect(OasisWallpaperService(store: store).fit, fit);
    }
    s.dispose();
  });

  test('oasis stores read, write and remove', () async {
    final memory = MemoryOasisStore();
    expect(memory.read('k'), isNull);
    await memory.write('k', 'v');
    expect(memory.read('k'), 'v');
    await memory.remove('k');
    expect(memory.read('k'), isNull);

    SharedPreferences.setMockInitialValues({'seed': '1'});
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsOasisStore(prefs);
    expect(store.read('seed'), '1');
    await store.write('k', 'v');
    expect(prefs.getString('k'), 'v');
    await store.remove('seed');
    expect(prefs.getString('seed'), isNull);
  });

  testWidgets('wallpaper renders dunes without a service',
      (tester) async {
    await pumpOasis(tester, const OasisWallpaper());
    expect(find.byType(OasisWallpaper), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('wallpaper renders a custom image and bad paths fall back',
      (tester) async {
    final s = OasisWallpaperService();
    addTearDown(s.dispose);
    final file = File(
        '${Directory.systemTemp.path}/oasis_wallpaper_test.png');
    await tester.runAsync(() async {
      await file.writeAsBytes(base64Decode(_pngBase64));
    });
    addTearDown(() => file.deleteSync());

    await pumpOasis(tester, OasisWallpaper(service: s));

    s.imagePath = file.path;
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.runAsync(() async {
      s.imagePath = '/definitely/missing.png';
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    expect(find.byType(OasisWallpaper), findsOneWidget);
  });

  testWidgets('wallpaper pane applies custom image, fit and reset',
      (tester) async {
    final wallpaper = OasisWallpaperService();
    addTearDown(wallpaper.dispose);
    await pumpOasis(
      tester,
      _host(child: SettingsHome(wallpaper: wallpaper)),
      size: const Size(900, 620),
    );

    await tester.tap(find.text('Wallpaper'));
    await tester.pumpAndSettle();
    expect(find.text('Oasis Dunes'), findsOneWidget);
    expect(find.text('Fit'), findsNothing);

    await tester.enterText(
        find.byType(TextField), '/pics/lagoon.png');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(wallpaper.imagePath, '/pics/lagoon.png');
    expect(find.text('lagoon.png'), findsOneWidget);
    expect(find.text('Fit to screen'), findsOneWidget);

    await tester.ensureVisible(find.text('Fit to screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit to screen'));
    await tester.pumpAndSettle();
    expect(wallpaper.fit, BoxFit.contain);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(wallpaper.imagePath, '/pics/lagoon.png');

    await tester.tap(find.text('Oasis Dunes'));
    await tester.pumpAndSettle();
    expect(wallpaper.hasCustomImage, isFalse);
  });

  testWidgets('settings sidebar lists the wallpaper pane',
      (tester) async {
    final state = SettingsState();
    addTearDown(state.dispose);
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: state)),
      size: const Size(900, 620),
    );
    state.selectPane(SettingsPane.wallpaper);
    await tester.pumpAndSettle();
    expect(find.text('Custom image'), findsOneWidget);
    expect(find.byType(OasisSearchField), findsOneWidget);
  });
}

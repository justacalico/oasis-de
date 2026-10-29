import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_app.dart';

class _NeverChecker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String v) => Completer<AppUpdate>().future;
}

class _FakeChecker extends UpdateChecker {
  _FakeChecker(this.result, {this.error});

  final AppUpdate result;
  final Object? error;

  @override
  Future<AppUpdate> check(String currentVersion) async {
    if (error != null) throw error!;
    return result;
  }
}

Widget _host({
  required Widget child,
  OasisAppearance? appearance,
  UpdateChecker? checker,
  Locale? locale,
  void Function(Locale?)? setLocale,
  List<String>? opened,
}) {
  final app = appearance ?? OasisAppearance();
  return OasisHost(
    appearance: app,
    updates: UpdateService(checker: checker),
    setLocale: setLocale ?? (_) {},
    locale: locale,
    openUrl: opened?.add,
    child: child,
  );
}

void main() {
  test('SettingsState selects panes and persists toggles', () async {
    final store = MemorySettingsStore();
    final s = SettingsState(store: store);
    expect(s.pane, SettingsPane.appearance);
    s.selectPane(SettingsPane.appearance);
    s.selectPane(SettingsPane.about);
    expect(s.pane, SettingsPane.about);
    s.wifiEnabled = false;
    s.bluetoothEnabled = false;
    expect(store.read('shell.wifi'), '0');
    expect(store.read('shell.bluetooth'), '0');

    final s2 = SettingsState(store: store);
    expect(s2.wifiOn, isFalse);
    expect(s2.bluetoothOn, isFalse);
    s.dispose();
    s2.dispose();
  });

  test('PrefsSettingsStore reads and writes', () async {
    SharedPreferences.setMockInitialValues({'k': 'v'});
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsSettingsStore(prefs);
    expect(store.read('k'), 'v');
    store.write('n', 'x');
    expect(prefs.getString('n'), 'x');
  });

  testWidgets('settings home navigates every pane', (tester) async {
    await pumpOasis(
      tester,
      _host(child: const SettingsHome(version: '9.9.9')),
      size: const Size(900, 620),
    );
    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('OLED'), findsOneWidget);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('Traditional English'), findsOneWidget);
    expect(find.text('Gaeilge'), findsOneWidget);

    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.byType(OasisToggle), findsOneWidget);

    await tester.tap(find.text('Bluetooth'));
    await tester.pumpAndSettle();
    expect(find.byType(OasisToggle), findsOneWidget);
    await tester.tap(find.byType(OasisToggle));
    await tester.pumpAndSettle();

    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    expect(find.text('Version 9.9.9'), findsOneWidget);
    expect(find.text('Check for Updates'), findsWidgets);
  });

  testWidgets('appearance pane switches theme and accent', (tester) async {
    final appearance = OasisAppearance();
    await pumpOasis(
      tester,
      _host(child: const SettingsHome(), appearance: appearance),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(appearance.themeMode, OasisThemeMode.dark);
    await tester.tap(find.text('OLED'));
    await tester.pumpAndSettle();
    expect(appearance.themeMode, OasisThemeMode.oled);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final swatches = find.byType(GestureDetector);
    await tester.tap(swatches.at(10));
    await tester.pumpAndSettle();
  });

  testWidgets('language picker updates host locale', (tester) async {
    Locale? chosen = const Locale('en', 'GB');
    await pumpOasis(
      tester,
      _host(
        child: const SettingsHome(),
        locale: chosen,
        setLocale: (l) => chosen = l,
      ),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(chosen, const Locale('ru'));
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });

  testWidgets('update tile shows every state', (tester) async {
    final opened = <String>[];
    await pumpOasis(
      tester,
      _host(
        child: const SettingsHome(),
        opened: opened,
        checker: _FakeChecker(
          const AppUpdate(
            latestVersion: '2.0.0',
            updateAvailable: true,
            releaseUrl: 'https://r/1',
          ),
        ),
      ),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    expect(find.text('Version 2.0.0 is available'), findsOneWidget);
    await tester.tap(find.text('View release'));
    expect(opened, contains('https://r/1'));
    await tester.tap(find.text('All releases'));
    expect(opened.last, contains('releases'));

    await pumpOasis(
      tester,
      _host(
        child: const SettingsHome(),
        checker: _FakeChecker(const AppUpdate(latestVersion: '1.0.0')),
      ),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    expect(find.text('Oasis is up to date'), findsOneWidget);

    await pumpOasis(
      tester,
      _host(
        child: const SettingsHome(),
        checker: _FakeChecker(const AppUpdate(), error: 'no network'),
      ),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't check for updates"), findsOneWidget);
  });

  testWidgets('standalone settings app renders', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisSettingsApp(
        updateChecker: _FakeChecker(const AppUpdate()),
        openUrl: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('update tile spinner while checking', (tester) async {
    final service = UpdateService(checker: _NeverChecker());
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        updates: service,
        setLocale: (_) {},
        child: Builder(
          builder: (context) {
            return UpdateCheckTile(service: service);
          },
        ),
      ),
    );
    service.check();
    await tester.pump();
    expect(find.text('Checking for updates…'), findsOneWidget);
    service.dispose();
  });

  testWidgets('standalone settings check and openUrl', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      OasisSettingsApp(
        updateChecker: _FakeChecker(
          const AppUpdate(
            latestVersion: '9.0.0',
            updateAvailable: true,
            releaseUrl: 'https://rel/9',
          ),
        ),
        openUrl: opened.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View release'));
    expect(opened, contains('https://rel/9'));
  });

  testWidgets('standalone settings setLocale and wifi toggle', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const OasisSettingsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OasisToggle));
    await tester.pumpAndSettle();
  });
  testWidgets('wallpaper pane picks bundled presets', (tester) async {
    final wallpaper = OasisWallpaperService(store: MemoryOasisStore());
    await pumpOasis(
      tester,
      Scaffold(body: WallpaperPane(wallpaper: wallpaper)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peaks'));
    await tester.pumpAndSettle();
    expect(wallpaper.preset, 'peaks');
    wallpaper.useDefault();
    wallpaper.imagePath = '/tmp/x.png';
    expect(wallpaper.hasCustomImage, isTrue);
    wallpaper.usePreset('aurora');
    expect(wallpaper.preset, 'aurora');
    expect(wallpaper.hasCustomImage, isFalse);
  });
}

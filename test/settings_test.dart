import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    updates: UpdateService(checker: checker, currentVersion: () async => '1.0.0'),
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
    expect(find.text('English (UK)'), findsOneWidget);
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
    await tester.tap(find.text('Check now'));
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
    await tester.tap(find.text('Check now'));
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
    await tester.tap(find.text('Check now'));
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
    final service = UpdateService(checker: _NeverChecker(), currentVersion: () async => '1.0.0');
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

  testWidgets('update tile installs a verifiable asset', (tester) async {
    final bytes = utf8.encode('pkg');
    final hex = sha256.convert(bytes).toString();
    final service = UpdateService(
      checker: _FakeChecker(
        const AppUpdate(
          latestVersion: '2.0.0',
          updateAvailable: true,
          releaseUrl: 'https://r',
          asset: UpdateAsset(
            name: 'oasis.deb',
            url: 'https://x/oasis.deb',
            checksumUrl: 'https://x/sums',
          ),
        ),
      ),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async =>
          uri.path.endsWith('sums') ? utf8.encode(hex) : bytes,
      writeFile: (_, __) async {},
      installer: (_) async => true,
    );
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        updates: service,
        setLocale: (_) {},
        child: UpdateCheckTile(service: service),
      ),
    );
    await service.check();
    await tester.pump();
    expect(find.text('Install'), findsOneWidget);
    await tester.tap(find.text('Install'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Update installed'), findsOneWidget);
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
    await tester.tap(find.text('Check now'));
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

  test('SettingsState brightness, volume, night light and search', () async {
    final store = MemorySettingsStore();
    final calls = <String>[];
    final s = SettingsState(
      store: store,
      backend: _StubBackend(
        calls,
        state: const OasisSystemState(
          brightness: 0.5,
          volume: 0.25,
          nightLight: true,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.brightness, 0.5);
    expect(s.volume, 0.25);
    expect(s.nightLightOn, isTrue);

    s.brightnessLevel = 0.4;
    s.volumeLevel = 0.3;
    s.nightLightEnabled = false;
    expect(store.read('shell.brightness'), '0.4');
    expect(store.read('shell.volume'), '0.3');
    expect(store.read('shell.nightLight'), '0');
    expect(calls, containsAllInOrder(['brightness', 'volume', 'nightLight']));

    s.searchQuery = 'wi';
    expect(s.query, 'wi');
    s.searchQuery = 'wi';
    s.searchQuery = '';
    expect(s.query, isEmpty);

    await s.battery();
    s.session(OasisSessionAction.suspend);
    expect(calls, contains('session'));

    final plain = SettingsState();
    expect((await plain.battery()).level, isNull);
    plain.session(OasisSessionAction.lock);
    s.dispose();
    plain.dispose();
  });

  testWidgets('settings sidebar search filters panes', (tester) async {
    await pumpOasis(
      tester,
      _host(child: const SettingsHome()),
      size: const Size(900, 620),
    );
    expect(find.text('Displays'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'dis');
    await tester.pumpAndSettle();
    expect(find.text('Displays'), findsOneWidget);
    expect(find.byType(OasisNavRow), findsNWidgets(1));
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(find.byType(OasisNavRow), findsNWidgets(11));
  });

  testWidgets('new panes drive backend and render', (tester) async {
    final calls = <String>[];
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend(
        calls,
        state: const OasisSystemState(brightness: 0.5, volume: 0.4),
        batteryValue: const OasisBattery(level: 0.72, charging: true),
      ),
    );
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: s)),
      size: const Size(900, 620),
    );

    await tester.tap(find.text('Displays'));
    await tester.pumpAndSettle();
    expect(find.byType(OasisSlider), findsOneWidget);
    await tester.tap(find.byType(OasisSlider));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OasisToggle));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OasisSlider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Power'));
    await tester.pumpAndSettle();
    expect(find.text('72%'), findsOneWidget);
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Power off'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date & Time'));
    await tester.pumpAndSettle();
    expect(find.text('Time zone'), findsOneWidget);

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(
      calls.where((c) => c == 'session').length,
      greaterThanOrEqualTo(4),
    );
  });
}

class _StubBackend extends NoopSystemBackend {
  _StubBackend(this.calls, {this.state = const OasisSystemState(), this.batteryValue});

  final List<String> calls;
  final OasisSystemState state;
  final OasisBattery? batteryValue;

  @override
  Future<OasisSystemState> read() async => state;

  @override
  Future<void> brightness(double level) async {
    calls.add('brightness');
  }

  @override
  Future<void> volume(double level) async {
    calls.add('volume');
  }

  @override
  Future<void> nightLight(bool enabled) async {
    calls.add('nightLight');
  }

  @override
  Future<OasisBattery> battery() async =>
      batteryValue ?? const OasisBattery(level: null, charging: false);

  @override
  void session(OasisSessionAction action) {
    calls.add('session');
  }
}

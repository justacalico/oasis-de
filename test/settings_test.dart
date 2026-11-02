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
    expect(find.text('System'), findsNothing);
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

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(appearance.accent, isNull);
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
      writeFile: (file, bytes) async {},
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

  testWidgets('update tile shows installing and failed states', (
    tester,
  ) async {
    final bytes = utf8.encode('pkg');
    final hex = sha256.convert(bytes).toString();
    final gate = Completer<bool>();
    const update = AppUpdate(
      latestVersion: '2.0.0',
      updateAvailable: true,
      releaseUrl: 'https://r',
      asset: UpdateAsset(
        name: 'oasis.deb',
        url: 'https://x/oasis.deb',
        checksumUrl: 'https://x/sums',
      ),
    );
    final service = UpdateService(
      checker: _FakeChecker(update),
      currentVersion: () async => '1.0.0',
      downloader: (uri) async =>
          uri.path.endsWith('sums') ? utf8.encode(hex) : bytes,
      writeFile: (file, bytes) async {},
      installer: (_) => gate.future,
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
    await tester.tap(find.text('Install'));
    await tester.pump();
    expect(find.text('Downloading and installing…'), findsOneWidget);
    gate.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Couldn\'t install the update'), findsOneWidget);
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

  test('SettingsState scans and joins wifi networks', () async {
    final calls = <String>[];
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend(
        calls,
        networks: const [OasisWifiNetwork(ssid: 'Cafe', signal: 55)],
      ),
    );
    await s.refreshWifiNetworks();
    expect(s.wifiNetworks.single.ssid, 'Cafe');
    expect(s.wifiScanning, isFalse);

    await s.connectWifiNetwork('Cafe');
    expect(calls, contains('connect:Cafe'));

    s.wifiEnabled = false;
    expect(s.wifiNetworks, isEmpty);
    await s.refreshWifiNetworks();

    s.wifiEnabled = true;
    await Future<void>.delayed(Duration.zero);
    expect(s.wifiNetworks.single.ssid, 'Cafe');

    final plain = SettingsState();
    await plain.refreshWifiNetworks();
    await plain.connectWifiNetwork('x');
    s.dispose();
    plain.dispose();
  });

  test('SettingsState tolerates backend failures', () async {
    final s = SettingsState(
      store: MemorySettingsStore(),
      displayBackend: _ThrowDisplays(),
    );
    await s.refreshDisplays();
    expect(s.displays, isEmpty);
    expect(s.displaysBusy, isFalse);

    s.wifiOn = false;
    s.wifiNetworks = const [OasisWifiNetwork(ssid: 'Stale')];
    var notified = 0;
    s.addListener(() => notified++);
    await s.refreshWifiNetworks();
    expect(s.wifiNetworks, isEmpty);
    expect(notified, greaterThan(0));
    s.dispose();
  });

  test('SettingsState wifi futures tolerate disposal', () async {
    final scanGate = Completer<List<OasisWifiNetwork>>();
    final connectGate = Completer<void>();
    final s = SettingsState(
      backend:
          _StubBackend([], scanGate: scanGate, connectGate: connectGate),
    );
    final scan = s.refreshWifiNetworks();
    final join = s.connectWifiNetwork('x');
    s.dispose();
    scanGate.complete(const []);
    connectGate.complete();
    await Future.wait([scan, join]);
  });

  testWidgets('wifi pane lists networks and connects', (tester) async {
    final calls = <String>[];
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend(
        calls,
        networks: const [
          OasisWifiNetwork(
            ssid: 'HomeBase',
            signal: 90,
            secured: true,
            connected: true,
          ),
          OasisWifiNetwork(ssid: 'Cafe', signal: 55, secured: true),
          OasisWifiNetwork(ssid: 'Faraway', signal: 10),
        ],
      ),
    );
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: s)),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('Networks'), findsOneWidget);
    expect(find.text('HomeBase'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Faraway'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Cafe'));
    await tester.pumpAndSettle();
    expect(calls, contains('connect:Cafe'));

    await tester.tap(find.byType(OasisToggle));
    await tester.pumpAndSettle();
    expect(find.text('Networks'), findsNothing);
    expect(s.wifiNetworks, isEmpty);
    s.dispose();
  });

  testWidgets('wifi pane shows scanning and empty states', (tester) async {
    final gate = Completer<List<OasisWifiNetwork>>();
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend([], scanGate: gate),
    );
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: s)),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('Wi-Fi'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Scanning…'), findsOneWidget);
    gate.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No networks found'), findsOneWidget);
    s.dispose();
  });

  test('SettingsState refreshes and selects audio devices', () async {
    final calls = <String>[];
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend(
        calls,
        outputs: const [
          OasisAudioDevice(
            name: 'spk',
            description: 'Speakers',
            isDefault: true,
          ),
          OasisAudioDevice(name: 'hdmi', description: 'HDMI'),
        ],
        inputs: const [
          OasisAudioDevice(name: 'mic', description: 'Mic'),
        ],
        cards: const [
          OasisAudioCard(
            name: 'card',
            description: 'Card',
            activeProfile: 'a',
            profiles: [
              OasisAudioProfile(name: 'a'),
              OasisAudioProfile(name: 'b'),
            ],
          ),
          OasisAudioCard(name: 'card2', activeProfile: 'x'),
        ],
      ),
    );
    await s.refreshAudio();
    expect(s.audioOutputs.length, 2);
    expect(s.audioInputs.length, 1);
    expect(s.audioCards.length, 2);

    await s.selectAudioOutput('hdmi');
    expect(calls, contains('output:hdmi'));
    expect(s.audioOutputs[0].isDefault, isFalse);
    expect(s.audioOutputs[1].isDefault, isTrue);

    await s.selectAudioInput('mic');
    expect(calls, contains('input:mic'));
    expect(s.audioInputs[0].isDefault, isTrue);

    await s.selectAudioProfile('card', 'b');
    expect(calls, contains('profile:card:b'));
    expect(s.audioCards[0].activeProfile, 'b');
    expect(s.audioCards[0].profiles.length, 2);
    expect(s.audioCards[1].activeProfile, 'x');

    final plain = SettingsState();
    await plain.refreshAudio();
    await plain.selectAudioOutput('x');
    await plain.selectAudioInput('x');
    await plain.selectAudioProfile('c', 'p');
    expect(plain.audioOutputs, isEmpty);
    s.dispose();
    plain.dispose();
  });

  testWidgets('sound pane picks devices and profiles', (tester) async {
    final calls = <String>[];
    final s = SettingsState(
      store: MemorySettingsStore(),
      backend: _StubBackend(
        calls,
        outputs: const [
          OasisAudioDevice(
            name: 'spk',
            description: 'Speakers',
            isDefault: true,
          ),
          OasisAudioDevice(name: 'hdmi'),
        ],
        inputs: const [
          OasisAudioDevice(name: 'mic', description: 'Microphone'),
        ],
        cards: const [
          OasisAudioCard(
            name: 'card1',
            description: 'Built-in Audio',
            activeProfile: 'stereo',
            profiles: [
              OasisAudioProfile(
                name: 'stereo',
                description: 'Analog Stereo',
              ),
              OasisAudioProfile(name: 'pro', description: 'Pro Audio'),
            ],
          ),
          OasisAudioCard(name: 'card2'),
          OasisAudioCard(
            name: 'card3',
            activeProfile: 'ghost',
            profiles: [OasisAudioProfile(name: 'off')],
          ),
        ],
      ),
    );
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: s)),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();

    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.text('hdmi'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Device profiles'), findsOneWidget);
    expect(find.text('Built-in Audio'), findsOneWidget);
    expect(find.text('card3'), findsOneWidget);

    await tester.tap(find.text('hdmi'));
    await tester.pumpAndSettle();
    expect(calls, contains('output:hdmi'));

    await tester.tap(find.text('Microphone'));
    await tester.pumpAndSettle();
    expect(calls, contains('input:mic'));

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro Audio').last);
    await tester.pumpAndSettle();
    expect(calls, contains('profile:card1:pro'));
    s.dispose();
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
    expect(find.byType(OasisNavRow), findsNWidgets(12));
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
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Power off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shut Down'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 minutes').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date & Time'));
    await tester.pumpAndSettle();
    expect(find.text('Time zone'), findsOneWidget);

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    expect(
      calls.where((c) => c == 'session').length,
      greaterThanOrEqualTo(4),
    );
  });

  testWidgets('power pane sleep delays persist and apply', (tester) async {
    final store = MemorySettingsStore();
    final power = _StubPowerBackend();
    final s = SettingsState(store: store, powerBackend: power);
    await pumpOasis(
      tester,
      _host(child: SettingsHome(state: s)),
      size: const Size(900, 620),
    );
    await tester.tap(find.text('Power'));
    await tester.pumpAndSettle();
    expect(find.text('Turn display off after'), findsOneWidget);
    expect(find.text('Sleep after'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 minutes').last);
    await tester.pumpAndSettle();
    expect(s.displayOffDelay, const Duration(minutes: 10));
    expect(store.read('shell.displayOffAfter'), '600000');

    await tester.tap(find.byType(DropdownButton<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 hours').last);
    await tester.pumpAndSettle();
    expect(s.sleepDelay, const Duration(hours: 2));
    expect(store.read('shell.sleepAfter'), '7200000');
    expect(power.calls, ['600000:0', '600000:7200000']);

    await tester.tap(find.byType(DropdownButton<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never').last);
    await tester.pumpAndSettle();
    expect(s.sleepDelay, Duration.zero);
    expect(power.calls.last, '600000:0');

    final restored = SettingsState(store: store);
    expect(restored.displayOffDelay, const Duration(minutes: 10));
    expect(restored.sleepDelay, Duration.zero);
    s.dispose();
    restored.dispose();
  });
}

class _StubPowerBackend extends NoopPowerBackend {
  final calls = <String>[];

  @override
  Future<void> setIdleTimeouts(
      {Duration? displayOff, Duration? suspend}) async {
    calls.add(
      '${displayOff?.inMilliseconds ?? 0}:'
      '${suspend?.inMilliseconds ?? 0}',
    );
  }
}

class _ThrowDisplays extends NoopDisplayBackend {
  @override
  Future<List<OasisDisplay>> displays() async => throw StateError('down');
}

class _StubBackend extends NoopSystemBackend {
  _StubBackend(
    this.calls, {
    this.state = const OasisSystemState(),
    this.batteryValue,
    this.outputs = const [],
    this.inputs = const [],
    this.cards = const [],
    this.networks = const [],
    this.scanGate,
    this.connectGate,
  });

  final List<String> calls;
  final OasisSystemState state;
  final OasisBattery? batteryValue;
  final List<OasisAudioDevice> outputs;
  final List<OasisAudioDevice> inputs;
  final List<OasisAudioCard> cards;
  final List<OasisWifiNetwork> networks;
  final Completer<List<OasisWifiNetwork>>? scanGate;
  final Completer<void>? connectGate;

  @override
  Future<List<OasisWifiNetwork>> wifiNetworks() =>
      scanGate?.future ?? Future.value(networks);

  @override
  Future<void> connectWifi(String ssid) async {
    calls.add('connect:$ssid');
    await connectGate?.future;
  }

  @override
  Future<List<OasisAudioDevice>> audioOutputs() async => outputs;

  @override
  Future<List<OasisAudioDevice>> audioInputs() async => inputs;

  @override
  Future<List<OasisAudioCard>> audioCards() async => cards;

  @override
  Future<void> setAudioOutput(String name) async =>
      calls.add('output:$name');

  @override
  Future<void> setAudioInput(String name) async =>
      calls.add('input:$name');

  @override
  Future<void> setAudioCardProfile(String card, String profile) async =>
      calls.add('profile:$card:$profile');

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

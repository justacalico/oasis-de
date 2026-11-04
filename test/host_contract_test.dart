import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_settings/settings_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

final _covered = <String>{};

void _cov(String member) {
  expect(
    kOasisHostMethods.contains(member) || kOasisHostEvents.contains(member),
    isTrue,
    reason: '$member is not part of the host protocol',
  );
  _covered.add(member);
}

class _FakeUpdates extends OasisUpdateApi {
  var checkCalls = 0;
  var installCalls = 0;
  AppUpdate? nextUpdate;
  bool installResult = true;

  @override
  AppUpdate? update;
  @override
  bool checking = false;
  @override
  bool failed = false;
  @override
  bool installing = false;
  @override
  bool installDone = false;
  @override
  bool installFailed = false;
  @override
  String releasesPageUrl = 'https://releases.invalid';

  void mutate(void Function() fn) {
    fn();
    notifyListeners();
  }

  @override
  Future<AppUpdate?> check() async {
    checkCalls++;
    update = nextUpdate;
    notifyListeners();
    return nextUpdate;
  }

  @override
  Future<bool> install() async {
    installCalls++;
    installDone = installResult;
    installFailed = !installResult;
    notifyListeners();
    return installResult;
  }
}

class _ProbeLink implements OasisHostLink {
  _ProbeLink(this.state);

  final eventsCtrl = StreamController<Map<String, Object?>>.broadcast();
  final Map<String, Object?> state;

  @override
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) =>
      Future.value(Map.of(state));

  @override
  Stream<Map<String, Object?>> get events => eventsCtrl.stream;

  @override
  Future<void> close() => eventsCtrl.close();
}

class _FailLink implements OasisHostLink {
  final _events = StreamController<Map<String, Object?>>.broadcast();

  @override
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) =>
      Future.error(StateError('link down'));

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<void> close() => _events.close();
}

class _Server {
  _Server({bool updates = true, bool openUrl = true}) {
    endpoint = OasisHostEndpoint(
      appearance: appearance,
      updates: updates ? this.updates : null,
      locale: locale,
      setLocale: (l) {
        localeCalls.add(l);
        locale.value = l;
      },
      openUrl: openUrl ? urlCalls.add : null,
    );
  }

  final appearance = OasisAppearance();
  final updates = _FakeUpdates();
  final locale = ValueNotifier<Locale?>(const Locale('en'));
  final localeCalls = <Locale?>[];
  final urlCalls = <String>[];
  late final OasisHostEndpoint endpoint;
}

class _Rig {
  const _Rig(this.server, this.client, this._close, {this.clientBus});

  final _Server server;
  final OasisHostConnection client;
  final DBusClient? clientBus;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

Future<OasisHostConnection> _connect(OasisHostLink link) {
  _cov('getState');
  return OasisHostConnection.connect(link);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not met');
}

Future<_Rig> _localRig({_Server? server}) async {
  final s = server ?? _Server();
  final client = await _connect(OasisHostLocalLink(s.endpoint));
  return _Rig(s, client, () async {
    await client.close();
    s.endpoint.dispose();
  });
}

Future<_Rig> _dbusRig({_Server? server}) async {
  final bus = DBusServer();
  final dir = await Directory.systemTemp.createTemp('oasis-host-test');
  final address = await bus.listenAddress(
    DBusAddress('unix:path=${dir.path}/bus'),
  );
  final serverBus = DBusClient(address);
  final clientBus = DBusClient(address);
  final s = server ?? _Server();
  final service = OasisHostDbusServer(s.endpoint, connect: () => serverBus);
  await service.serve();
  final client = await _connect(OasisHostDbusLink(clientBus));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return _Rig(
    s,
    client,
    () async {
      await client.close();
      await clientBus.close();
      await service.close();
      await bus.close();
      s.endpoint.dispose();
      await dir.delete(recursive: true);
    },
    clientBus: clientBus,
  );
}

void _hostContract(String name, Future<_Rig> Function() open) {
  group(name, () {
    test('state snapshot mirrors server', () async {
      final r = await open();
      expect(r.client.appearance.themeMode, OasisThemeMode.light);
      expect(r.client.appearance.accent, isNull);
      expect(r.client.locale.value, const Locale('en'));
      expect(r.client.openUrl, isNotNull);
      final updates = r.client.updates!;
      expect(updates.releasesPageUrl, 'https://releases.invalid');
      expect(updates.checking, isFalse);
      expect(updates.failed, isFalse);
      expect(updates.installing, isFalse);
      expect(updates.installDone, isFalse);
      expect(updates.installFailed, isFalse);
      expect(updates.update, isNull);
      await r.close();
    });

    test('theme mode round-trips', () async {
      final r = await open();
      _cov('setThemeMode');
      var notified = 0;
      r.client.appearance.addListener(() => notified++);
      r.client.appearance.themeMode = OasisThemeMode.dark;
      expect(notified, 1);
      await _until(
        () => r.server.appearance.themeMode == OasisThemeMode.dark,
      );
      _cov('appearance');
      r.server.appearance.themeMode = OasisThemeMode.oled;
      await _until(
        () => r.client.appearance.themeMode == OasisThemeMode.oled,
      );
      expect(r.client.appearance.theme.brightness, Brightness.dark);
      await r.close();
    });

    test('accent round-trips', () async {
      final r = await open();
      _cov('setAccent');
      _cov('appearance');
      const color = Color(0xFFFF5722);
      r.client.appearance.accent = color;
      await _until(() => r.server.appearance.accent == color);
      r.server.appearance.accent = const Color(0xFF00FF00);
      await _until(
        () => r.client.appearance.accent == const Color(0xFF00FF00),
      );
      await r.close();
    });

    test('locale round-trips', () async {
      final r = await open();
      _cov('setLocale');
      _cov('locale');
      r.client.setLocale(const Locale('zh', 'CN'));
      await _until(() => r.server.localeCalls.isNotEmpty);
      await _until(() => r.client.locale.value == const Locale('zh', 'CN'));
      expect(r.server.localeCalls, [const Locale('zh', 'CN')]);
      r.server.locale.value = const Locale('ga');
      await _until(() => r.client.locale.value == const Locale('ga'));
      await r.close();
    });

    test('openUrl reaches the shell', () async {
      final r = await open();
      _cov('openUrl');
      r.client.openUrl!('https://oasis.invalid');
      await _until(() => r.server.urlCalls.isNotEmpty);
      expect(r.server.urlCalls, ['https://oasis.invalid']);
      await r.close();
    });

    test('checkUpdates returns the update', () async {
      final r = await open();
      _cov('checkUpdates');
      _cov('updates');
      const update = AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
        updateAvailable: true,
        releaseUrl: 'https://releases.invalid/2',
        asset: UpdateAsset(
          name: 'oasis.rpm',
          url: 'https://releases.invalid/oasis.rpm',
          checksumUrl: 'https://releases.invalid/sums',
        ),
      );
      r.server.updates.nextUpdate = update;
      expect(await r.client.updates!.check(), update);
      expect(r.server.updates.checkCalls, 1);
      await _until(() => r.client.updates!.update == update);
      await r.close();
    });

    test('installUpdate reports the result', () async {
      final r = await open();
      _cov('installUpdate');
      _cov('updates');
      r.server.updates.installResult = false;
      expect(await r.client.updates!.install(), isFalse);
      expect(r.server.updates.installCalls, 1);
      await _until(() => r.client.updates!.installFailed);
      await r.close();
    });

    test('flags and listeners propagate', () async {
      final r = await open();
      _cov('updates');
      var notified = 0;
      r.client.updates!.addListener(() => notified++);
      r.server.updates.mutate(() => r.server.updates.checking = true);
      await _until(() => r.client.updates!.checking);
      expect(notified, greaterThan(0));
      notified = 0;
      r.server.updates.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notified, 0);
      await r.close();
    });

    test('unknown method fails', () async {
      final r = await open();
      await expectLater(
        r.client.link.request('bogus'),
        throwsA(anything),
      );
      await r.close();
    });
  });
}

void main() {
  _hostContract('local link', _localRig);
  _hostContract('dbus', _dbusRig);

  group('endpoint edge cases', () {
    test('no updates service gives a null remote service', () async {
      final r = await _localRig(server: _Server(updates: false));
      expect(r.client.updates, isNull);
      expect(await r.client.link.request('checkUpdates'), {'update': null});
      expect(await r.client.link.request('installUpdate'), {'ok': false});
      await r.close();
    });

    test('no openUrl handler hides the capability', () async {
      final r = await _localRig(server: _Server(openUrl: false));
      expect(r.client.openUrl, isNull);
      r.server.endpoint.handleRequest('openUrl', {'url': 'x'});
      expect(r.server.urlCalls, isEmpty);
      await r.close();
    });

    test('unknown theme mode keeps current', () async {
      final r = await _localRig();
      await r.client.link.request('setThemeMode', {'mode': 'plaid'});
      expect(r.server.appearance.themeMode, OasisThemeMode.light);
      await r.close();
    });

    test('malformed events are ignored safely', () async {
      final link = _ProbeLink({
        'themeMode': 'dark',
        'accent': null,
        'locale': 'en',
        'openUrl': false,
        'updates': null,
      });
      final conn = await OasisHostConnection.connect(link);
      expect(conn.appearance.themeMode, OasisThemeMode.dark);
      link.eventsCtrl.add({
        'event': 'appearance',
        'themeMode': 'plaid',
        'accent': 0xFF00FF00,
      });
      link.eventsCtrl.add({'event': 'locale', 'locale': 'ru'});
      link.eventsCtrl.add({'event': 'bogus'});
      await _until(
        () => conn.appearance.accent == const Color(0xFF00FF00),
      );
      expect(conn.appearance.themeMode, OasisThemeMode.dark);
      await conn.close();
    });
  });

  group('codec', () {
    test('locale tags round-trip', () {
      for (final l in [
        const Locale('en'),
        const Locale('zh', 'CN'),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        ),
      ]) {
        expect(hostLocaleFromTag(hostLocaleToTag(l)), l);
      }
      expect(hostLocaleFromTag(null), isNull);
      expect(hostLocaleFromTag(''), isNull);
      expect(hostLocaleToTag(null), isNull);
    });

    test('accent codec handles null', () {
      expect(hostAccentToJson(null), isNull);
      expect(hostAccentFromJson(null), isNull);
      expect(
        hostAccentFromJson(0xFFFF5722),
        const Color(0xFFFF5722),
      );
    });

    test('AppUpdate codec is lossless', () {
      const update = AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
        updateAvailable: true,
        releaseUrl: 'https://x.invalid/r',
        asset: UpdateAsset(
          name: 'a.rpm',
          url: 'https://x.invalid/a',
          checksumUrl: 'https://x.invalid/s',
        ),
      );
      expect(hostAppUpdateFromJson(hostAppUpdateToJson(update)), update);
      expect(
        hostAppUpdateFromJson(hostAppUpdateToJson(const AppUpdate())),
        const AppUpdate(),
      );
      expect(hostAppUpdateFromJson(null), isNull);
      expect(hostUpdateAssetFromJson(null), isNull);
      expect(
        hostAppUpdateFromJson({'asset': null})!.asset,
        isNull,
      );
    });

    test('update snapshot codec is lossless', () {
      const snap = OasisUpdateSnapshot(
        update: AppUpdate(latestVersion: '9.9.9', updateAvailable: true),
        checking: true,
        failed: true,
        installing: true,
        installDone: true,
        installFailed: true,
        releasesPageUrl: 'https://x.invalid',
      );
      expect(OasisUpdateSnapshot.fromJson(snap.toJson()), snap);
      expect(
        OasisUpdateSnapshot.fromJson(
          OasisUpdateSnapshot().toJson(),
        ),
        const OasisUpdateSnapshot(),
      );
      expect(snap.hashCode, isNot(0));
      expect(snap == snap, isTrue);
      expect(snap == const OasisUpdateSnapshot(), isFalse);
    });
  });

  group('dbus transport', () {
    test('session link owns its client', () async {
      final bus = DBusServer();
      final dir = await Directory.systemTemp.createTemp('oasis-host-test');
      final address = await bus.listenAddress(
        DBusAddress('unix:path=${dir.path}/bus'),
      );
      var created = 0;
      final link = await OasisHostDbusLink.session(
        connect: () {
          created++;
          return DBusClient(address);
        },
      );
      expect(created, 1);
      await link.close();
      await bus.close();
      await dir.delete(recursive: true);
    });

    test('object is introspectable and rejects foreign calls', () async {
      final r = await _dbusRig();
      final object = DBusRemoteObject(
        r.clientBus!,
        name: kOasisHostBusName,
        path: DBusObjectPath(kOasisHostPath),
      );
      final xml = await object.callMethod(
        'org.freedesktop.DBus.Introspectable',
        'Introspect',
        const [],
        replySignature: DBusSignature('s'),
      );
      expect(xml.returnValues.single.asString(), contains('dev.oasis.Host'));
      await expectLater(
        object.callMethod('com.example.Other', 'Call', const [
          DBusString('getState'),
          DBusString('{}'),
        ]),
        throwsA(anything),
      );
      await r.close();
    });
  });

  testWidgets('RemoteOasisHost rebuilds on locale change', (tester) async {
    await tester.runAsync(() async {
      final r = await _localRig();
      Locale? seen;
      await tester.pumpWidget(
        RemoteOasisHost(
          connection: r.client,
          child: Builder(
            builder: (context) {
              seen = OasisHost.of(context).locale;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, const Locale('en'));
      r.server.locale.value = const Locale('ru');
      await _until(() => r.client.locale.value == const Locale('ru'));
      await tester.pump();
      expect(seen, const Locale('ru'));
      await r.close();
    });
  });

  group('failed links', () {
    test('send failures are swallowed and logged', () async {
      final link = _FailLink();
      final appearance = RemoteOasisAppearance(link)
        ..themeMode = OasisThemeMode.dark
        ..accent = const Color(0xFF0000FF);
      expect(appearance.themeMode, OasisThemeMode.dark);
      sendHostRequest(link, 'openUrl', {'url': 'x'});
      await link.close();
    });
  });

  testWidgets('shell exports the host service', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final bus = DBusServer();
      final dir = await Directory.systemTemp.createTemp('oasis-host-test');
      final address = await bus.listenAddress(
        DBusAddress('unix:path=${dir.path}/bus'),
      );
      final serverBus = DBusClient(address);
      final clientBus = DBusClient(address);
      final appearance = OasisAppearance();
      await tester.pumpWidget(
        OasisDesktopApp(
          version: '1.0.0',
          appearance: appearance,
          backend: const NoopSystemBackend(),
          exportHostService: true,
          hostServerFactory: (endpoint) => OasisHostDbusServer(
            endpoint,
            connect: () => serverBus,
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final conn = await _connect(OasisHostDbusLink(clientBus));
      expect(conn.appearance.themeMode, OasisThemeMode.light);
      appearance.themeMode = OasisThemeMode.dark;
      await _until(
        () => conn.appearance.themeMode == OasisThemeMode.dark,
      );
      await conn.close();
      await clientBus.close();
      await serverBus.close();
      await bus.close();
      await dir.delete(recursive: true);
    });
  });

  testWidgets('host serve failure is logged not fatal', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        version: '1.0.0',
        backend: const NoopSystemBackend(),
        exportHostService: true,
        hostServerFactory: (endpoint) => OasisHostDbusServer(
          endpoint,
          connect: () => throw StateError('no bus'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OasisDesktopApp), findsOneWidget);
  });

  testWidgets('settings app runs on a remote host', (tester) async {
    await tester.runAsync(() async {
      final r = await _localRig();
      await tester.pumpWidget(OasisSettingsApp(host: r.client));
      await tester.pump();
      expect(find.byType(OasisSettingsApp), findsOneWidget);
      r.server.appearance.themeMode = OasisThemeMode.dark;
      await _until(
        () => r.client.appearance.themeMode == OasisThemeMode.dark,
      );
      await tester.pump();
      expect(
        (tester.widget<MaterialApp>(find.byType(MaterialApp)).theme)!
            .brightness,
        Brightness.dark,
      );
      await r.close();
    });
  });

  test('every protocol member is exercised', () {
    expect(_covered, containsAll({...kOasisHostMethods, ...kOasisHostEvents}));
  });
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_landing/landing_app.dart';
import 'package:oasis_landing/services/release_client.dart';
import 'package:oasis_landing/views/landing_page.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'dart:convert';

import 'helpers/test_app.dart';

class _NeverChecker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String v) => Completer<AppUpdate>().future;
}

class _FixedChecker extends UpdateChecker {
  _FixedChecker(this.result);
  final AppUpdate result;
  @override
  Future<AppUpdate> check(String v) async => result;
}

final _png = MemoryImage(Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')));

ReleaseClient _client(String body, [int status = 200]) => ReleaseClient(
    client: MockClient((_) async => http.Response(body, status)),
    host: 'gitlab.test',
    projectPath: 'x/y');

void main() {
  test('AppUpdate equality and hashCode', () {
    const a = AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '1.2.0',
        updateAvailable: true,
        releaseUrl: 'r');
    const b = AppUpdate(
        currentVersion: '1.0.0',
        latestVersion: '1.2.0',
        updateAvailable: true,
        releaseUrl: 'r');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const AppUpdate(), isFalse);
    expect(a == Object(), isFalse);
  });

  test('ReleaseClient releasesUrl', () {
    expect(_client('[]').releasesUrl,
        'https://gitlab.test/x/y/-/releases');
    expect(ReleaseClient().releasesUrl,
        'https://gitlab.com/HttpAnimations/oasis-de/-/releases');
  });

  testWidgets('appearance.themeFor resolves context brightness',
      (tester) async {
    final a = OasisAppearance(themeMode: OasisThemeMode.system);
    await pumpOasis(tester, Builder(builder: (context) {
      return Text(a.themeFor(context).brightness.name);
    }), platformDark: true);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('OasisButton tap cancel clears pressed', (tester) async {
    await pumpOasis(
        tester,
        OasisButton(
            label: 'b',
            variant: OasisButtonVariant.primary,
            onPressed: () {}));
    final g = await tester.startGesture(
        tester.getCenter(find.text('b')));
    await tester.pump();
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.up();
    await tester.pump();
  });

  testWidgets('search field dark + wallpaper non-const + slider pan',
      (tester) async {
    await pumpOasis(
        tester,
        const Column(children: [
          SizedBox(height: 60, child: Scaffold(body: OasisSearchField(hint: 'h'))),
          SizedBox(height: 8),
          Expanded(child: OasisWallpaper()),
        ]),
        theme: OasisThemeMode.dark);
    expect(find.byType(OasisSearchField), findsOneWidget);

    var v = 0.0;
    await pumpOasis(
        tester,
        SizedBox(
            width: 200,
            child: StatefulBuilder(
                builder: (c, set) =>
                    OasisSlider(value: v, onChanged: (x) => set(() => v = x)))),
        size: const Size(300, 100));
    await tester.drag(find.byType(OasisSlider), const Offset(150, 0));
    expect(v, greaterThan(0.5));
  });

  testWidgets('traffic lights hover exit', (tester) async {
    await pumpOasis(tester, const OasisTrafficLights());
    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(tester.getCenter(find.byType(OasisTrafficLights)));
    await tester.pump();
    await m.moveTo(const Offset(600, 600));
    await tester.pump();
  });

  testWidgets('update tile checking state shows spinner',
      (tester) async {
    final service = UpdateService(checker: _NeverChecker());
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        updates: service,
        setLocale: (_) {},
        child: Builder(builder: (context) {
          return UpdateCheckTile(service: service);
        }),
      ),
    );
    service.check();
    await tester.pump();
    expect(find.text('Checking for updates…'), findsOneWidget);
  });

  testWidgets('landing wide showcase row + get started + source',
      (tester) async {
    final opened = <String>[];
    await pumpOasis(
      tester,
      LandingPage(
        client: _client('[]'),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        onOpenUrl: opened.add,
        showcaseImages: [_png, _png],
      ),
      size: const Size(1200, 2600),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    await tester.ensureVisible(find.text('Download'));
    await tester.tap(find.text('Download'));
    expect(opened.last, 'https://gitlab.test/x/y/-/releases');
  });

  testWidgets('landing app theme listener fires', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modes = <OasisThemeMode>[];
    await tester.pumpWidget(LandingApp(
        client: _client('[]'),
        onOpenUrl: (_) {},
        onThemeChanged: modes.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<OasisThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(modes, contains(OasisThemeMode.light));
  });

  testWidgets('settings standalone check + openUrl', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(OasisSettingsApp(
      updateChecker: _FixedChecker(const AppUpdate(
          latestVersion: '9.0.0',
          updateAvailable: true,
          releaseUrl: 'https://rel/9')),
      openUrl: opened.add,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View release'));
    expect(opened, contains('https://rel/9'));
  });

  testWidgets('settings standalone setLocale + wifi toggle',
      (tester) async {
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

  testWidgets('landing narrow showcase column', (tester) async {
    await pumpOasis(
      tester,
      LandingPage(
        client: _client('[]'),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        showcaseImages: [_png],
      ),
      size: const Size(480, 3200),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('landing setLocale closure', (tester) async {
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        updates: UpdateService(),
        setLocale: (_) {},
        child: Builder(builder: (context) {
          return const SizedBox();
        }),
      ),
    );
    final element = tester.element(find.byType(SizedBox).last);
    OasisHost.of(element).setLocale.call(const Locale('ru'));
  });

  testWidgets('landing app setLocale via host', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LandingApp(
        client: _client('[]'), onOpenUrl: (_) {}));
    await tester.pumpAndSettle();
    tester
        .widget<OasisHost>(find.byType(OasisHost))
        .setLocale(const Locale('ru'));
  });
}

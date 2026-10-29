import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_landing/landing_app.dart';
import 'package:oasis_landing/services/release_client.dart';
import 'package:oasis_landing/views/landing_page.dart';
import 'package:oasis_landing/widgets/desktop_preview.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

ReleaseClient _client({int status = 200, String body = '[]'}) => ReleaseClient(
  client: MockClient((_) async => http.Response(body, status)),
  host: 'gitlab.test',
  projectPath: 'x/y',
);

final _releases = jsonEncode([
  {
    'tag_name': 'v1.2.0',
    'name': 'Oasis 1.2.0',
    'assets': {
      'links': [
        {'name': 'oasis-amd64.deb', 'direct_asset_url': 'https://dl/deb'},
        {'name': 'oasis.tar.gz', 'direct_asset_url': 'https://dl/tgz'},
      ],
    },
  },
]);

void main() {
  testWidgets('landing page shows all releases states', (tester) async {
    final opened = <String>[];
    await pumpOasis(
      tester,
      LandingPage(
        client: _client(body: _releases),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        onOpenUrl: opened.add,
      ),
      size: const Size(1100, 2400),
    );
    await tester.pumpAndSettle();
    expect(find.text('oasis-amd64.deb'), findsOneWidget);
    await tester.tap(find.text('oasis-amd64.deb'));
    expect(opened, contains('https://dl/deb'));
    await tester.tap(find.text('All releases on GitLab'));
    expect(opened, contains('https://gitlab.test/x/y/-/releases'));
    expect(find.text('v1.2.0'), findsOneWidget);

    await pumpOasis(
      tester,
      LandingPage(
        key: const ValueKey('empty'),
        client: _client(body: '[]'),
        appUrl: 'app/',
        repoUrl: 'https://repo',
      ),
      size: const Size(1100, 2400),
    );
    await tester.pumpAndSettle();
    expect(find.text('No releases yet'), findsOneWidget);

    await pumpOasis(
      tester,
      LandingPage(
        key: const ValueKey('error'),
        client: _client(status: 500),
        appUrl: 'app/',
        repoUrl: 'https://repo',
      ),
      size: const Size(1100, 2400),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load releases"), findsOneWidget);
  });

  testWidgets('landing page narrow layout and showcase images', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await pumpOasis(
      tester,
      LandingPage(
        client: _client(body: _releases),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        showcaseImages: [MemoryImage(Uint8List.fromList(png))],
      ),
      size: const Size(480, 3200),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('landing page links and theme menu', (tester) async {
    final opened = <String>[];
    final appearance = OasisAppearance();
    await pumpOasis(
      tester,
      OasisHost(
        appearance: appearance,
        updates: UpdateService(),
        setLocale: (_) {},
        child: LandingPage(
          client: _client(body: _releases),
          appUrl: 'https://app',
          repoUrl: 'https://repo',
          onOpenUrl: opened.add,
        ),
      ),
      size: const Size(1100, 2400),
    );
    await tester.tap(find.text('Launch web app').first);
    expect(opened, contains('https://app'));
    await tester.tap(find.text('Source code'));
    expect(opened, contains('https://repo'));

    await tester.tap(find.byType(PopupMenuButton<OasisThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(appearance.themeMode, OasisThemeMode.dark);

    await tester.tap(find.byType(PopupMenuButton<OasisThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OLED').last);
    await tester.pumpAndSettle();
    expect(appearance.themeMode, OasisThemeMode.oled);
  });

  testWidgets('landing app boots with injected client', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final modes = <OasisThemeMode>[];
    await tester.pumpWidget(
      LandingApp(
        client: _client(body: _releases),
        onOpenUrl: (_) {},
        onThemeChanged: modes.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your desktop, distilled.'), findsOneWidget);
  });

  testWidgets('downloads section and preview paint', (tester) async {
    await pumpOasis(
      tester,
      const Padding(padding: EdgeInsets.all(20), child: DesktopPreview()),
      theme: OasisThemeMode.dark,
      size: const Size(900, 700),
    );
    expect(find.byType(DesktopPreview), findsOneWidget);
  });

  testWidgets('landing wide showcase row, get started and source', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final opened = <String>[];
    await pumpOasis(
      tester,
      LandingPage(
        client: _client(),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        onOpenUrl: opened.add,
        showcaseImages: [
          MemoryImage(Uint8List.fromList(png)),
          MemoryImage(Uint8List.fromList(png)),
        ],
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
    await tester.pumpWidget(
      LandingApp(
        client: _client(),
        onOpenUrl: (_) {},
        onThemeChanged: modes.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<OasisThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(modes, contains(OasisThemeMode.light));
  });

  testWidgets('landing narrow showcase column', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await pumpOasis(
      tester,
      LandingPage(
        client: _client(),
        appUrl: 'app/',
        repoUrl: 'https://repo',
        showcaseImages: [MemoryImage(Uint8List.fromList(png))],
      ),
      size: const Size(480, 3200),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('landing app setLocale via host', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LandingApp(client: _client(), onOpenUrl: (_) {}));
    await tester.pumpAndSettle();
    tester
        .widget<OasisHost>(find.byType(OasisHost))
        .setLocale(const Locale('ru'));
    await tester.pump();
    expect(find.byType(OasisHost), findsOneWidget);
  });
}

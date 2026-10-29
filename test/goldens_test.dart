import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_landing/landing_app.dart';
import 'package:oasis_landing/services/release_client.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeChecker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String currentVersion) async => const AppUpdate();
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ReleaseClient _releases() => ReleaseClient(
  client: MockClient(
    (_) async => http.Response(
      jsonEncode([
        {
          'tag_name': 'v1.0.0',
          'name': 'Oasis 1.0.0',
          'assets': {
            'links': [
              {'name': 'oasis-amd64.deb', 'direct_asset_url': 'https://dl/deb'},
              {
                'name': 'oasis-arm64.AppImage',
                'direct_asset_url': 'https://dl/appimage',
              },
            ],
          },
        },
      ]),
      200,
    ),
  ),
  host: 'gitlab.test',
  projectPath: 'x/y',
);

void main() {
  setUpAll(loadOasisFonts);

  testWidgets('desktop light', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/desktop_light.png'),
      );
    });
  });

  testWidgets('desktop dark with windows', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.dark),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/desktop_dark_settings.png'),
      );
    });
  });

  testWidgets('desktop genie minimise', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_note).first);
      await tester.pumpAndSettle();
      final light = tester
          .getRect(find.byType(OasisTrafficLights).first)
          .centerLeft;
      await tester.tapAt(light + const Offset(26, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/genie_minimise.png'),
      );
    });
  });

  testWidgets('desktop launcher', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 's');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/launcher.png'),
      );
    });
  });

  testWidgets('desktop launch pad', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.rocket_launch));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/launch_pad.png'),
      );
    });
  });

  testWidgets('desktop control center', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/control_center.png'),
      );
    });
  });

  for (final mode in [OasisThemeMode.dark, OasisThemeMode.oled]) {
    testWidgets('desktop launcher ${mode.name}', (tester) async {
      await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
        await _size(tester, const Size(1280, 800));
        await tester.pumpWidget(
          OasisDesktopApp(
            backend: const NoopSystemBackend(),
            version: '1.0.0',
            appearance: OasisAppearance(themeMode: mode),
            updateChecker: _FakeChecker(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search).first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 's');
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/launcher_${mode.name}.png'),
        );
      });
    });

    testWidgets('desktop launch pad ${mode.name}', (tester) async {
      await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
        await _size(tester, const Size(1280, 800));
        await tester.pumpWidget(
          OasisDesktopApp(
            backend: const NoopSystemBackend(),
            version: '1.0.0',
            appearance: OasisAppearance(themeMode: mode),
            updateChecker: _FakeChecker(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.rocket_launch));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/launch_pad_${mode.name}.png'),
        );
      });
    });

    testWidgets('desktop control center ${mode.name}', (tester) async {
      await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
        await _size(tester, const Size(1280, 800));
        await tester.pumpWidget(
          OasisDesktopApp(
            backend: const NoopSystemBackend(),
            version: '1.0.0',
            appearance: OasisAppearance(themeMode: mode),
            updateChecker: _FakeChecker(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/control_center_${mode.name}.png'),
        );
      });
    });
  }

  testWidgets('settings standalone', (tester) async {
    await _size(tester, const Size(1000, 700));
    await tester.pumpWidget(
      OasisSettingsApp(
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        updateChecker: _FakeChecker(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_light.png'),
    );
  });

  testWidgets('settings dark', (tester) async {
    await _size(tester, const Size(1000, 700));
    await tester.pumpWidget(
      OasisSettingsApp(
        appearance: OasisAppearance(themeMode: OasisThemeMode.dark),
        updateChecker: _FakeChecker(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_dark.png'),
    );
  });

  for (final mode in [
    OasisThemeMode.light,
    OasisThemeMode.dark,
    OasisThemeMode.oled,
  ]) {
    testWidgets('landing ${mode.name}', (tester) async {
      await _size(tester, const Size(1100, 2400));
      await tester.pumpWidget(
        LandingApp(
          appearance: OasisAppearance(themeMode: mode),
          client: _releases(),
          onOpenUrl: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/landing_${mode.name}.png'),
      );
    });
  }
}

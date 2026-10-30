import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/services/notifications.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_files/oasis_files.dart';
import 'package:oasis_landing/landing_app.dart';
import 'package:oasis_landing/services/release_client.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _InfoBackend extends NoopSystemBackend {
  const _InfoBackend();

  @override
  Future<OasisSystemInfo> systemInfo() async => const OasisSystemInfo(
    deviceName: 'oasis-box',
    osName: 'Oasis Linux 1.0',
    kernel: 'Linux version 6.8.1',
    cpu: 'Virtual Core 8c',
    memory: '16.0 GB',
    disk: '512G (120G used)',
    gpu: 'virtio-gpu',
  );
}

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

  testWidgets('desktop zh', (tester) async {
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await _size(tester, const Size(1280, 800));
      await tester.pumpWidget(
        OasisDesktopApp(
          backend: const NoopSystemBackend(),
          version: '1.0.0',
          locale: const Locale('zh'),
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/desktop_zh.png'),
      );
    });
  });

  testWidgets('desktop context menu', (tester) async {
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
      await tester.tapAt(
        const Offset(640, 400),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/desktop_context_menu.png'),
      );
    });
  });

  testWidgets('window context menu', (tester) async {
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
      final bar = tester
          .getRect(find.byType(OasisTrafficLights).first)
          .centerRight;
      await tester.tapAt(
        bar + const Offset(60, 0),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/window_context_menu.png'),
      );
    });
  });

  testWidgets('window switcher', (tester) async {
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
      await tester.tap(find.byIcon(Icons.calculate).first);
      await tester.pumpAndSettle();
      final dynamic st = tester.state(find.byType(OasisDesktopApp));
      (st.controller as ShellController).cycleWindows();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/window_switcher.png'),
      );
    });
  });

  testWidgets('notification center', (tester) async {
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
      final dynamic st = tester.state(find.byType(OasisDesktopApp));
      final controller = st.controller as ShellController;
      controller.pushNotification(
        OasisNotification(
          id: 1,
          appName: 'Files',
          summary: 'Download finished',
          body: '3 items saved to Downloads',
          timestamp: DateTime(2025, 6, 10, 9, 40),
          expireTimeout: 0,
        ),
      );
      controller.dismissBanner();
      controller.toggleNotificationCenter();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/notification_center.png'),
      );
    });
  });

  testWidgets('launcher empty', (tester) async {
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
      await tester.enterText(find.byType(TextField).first, 'zzzzqq');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/launcher_empty.png'),
      );
    });
  });

  for (final pane in [
    SettingsPane.wallpaper,
    SettingsPane.general,
    SettingsPane.about,
  ]) {
    testWidgets('settings ${pane.name}', (tester) async {
      await _size(tester, const Size(1000, 700));
      final s = SettingsState(backend: const _InfoBackend())
        ..selectPane(pane);
      await tester.pumpWidget(
        OasisSettingsApp(
          state: s,
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_${pane.name}.png'),
      );
    });
  }

  for (final locale in const [
    Locale('zh'),
    Locale('ru'),
    Locale('ga'),
  ]) {
    testWidgets('settings about ${locale.languageCode}', (tester) async {
      await _size(tester, const Size(1000, 700));
      final s = SettingsState(backend: const _InfoBackend())
        ..selectPane(SettingsPane.about);
      await tester.pumpWidget(
        OasisSettingsApp(
          state: s,
          locale: locale,
          appearance: OasisAppearance(themeMode: OasisThemeMode.light),
          updateChecker: _FakeChecker(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/settings_about_${locale.languageCode}.png',
        ),
      );
    });
  }

  testWidgets('settings oled', (tester) async {
    await _size(tester, const Size(1000, 700));
    await tester.pumpWidget(
      OasisSettingsApp(
        appearance: OasisAppearance(themeMode: OasisThemeMode.oled),
        updateChecker: _FakeChecker(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_oled.png'),
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

  testWidgets('landing releases error', (tester) async {
    await _size(tester, const Size(1100, 2400));
    await tester.pumpWidget(
      LandingApp(
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        client: ReleaseClient(
          client: MockClient((_) async => http.Response('nope', 500)),
          host: 'gitlab.test',
          projectPath: 'x/y',
        ),
        onOpenUrl: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/landing_error.png'),
    );
  });

  testWidgets('files light', (tester) async {
    final when = DateTime(2024, 3, 2, 14, 30);
    final s = FilesState(
      backend: _FilesBackend({
        '/home/u': [
          FileItem(
            path: '/home/u/docs',
            name: 'docs',
            isDir: true,
            modified: when,
          ),
          FileItem(
            path: '/home/u/report.pdf',
            name: 'report.pdf',
            isDir: false,
            size: 42000,
            modified: when,
          ),
          FileItem(
            path: '/home/u/photo.png',
            name: 'photo.png',
            isDir: false,
            size: 3000000,
            modified: when,
          ),
          FileItem(
            path: '/home/u/song.mp3',
            name: 'song.mp3',
            isDir: false,
            size: 7000000,
            modified: when,
          ),
        ],
      }),
    );
    await _size(tester, const Size(900, 600));
    await tester.pumpWidget(
      wrapOasis(
        FilesHome(state: s, startDir: '/home/u'),
        theme: OasisThemeMode.light,
        size: const Size(900, 600),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/files_light.png'),
    );
  });
}

class _FilesBackend extends FilesBackend {
  _FilesBackend(this.tree);

  final Map<String, List<FileItem>> tree;

  @override
  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async =>
      tree[dir] ?? [];

  @override
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  }) async =>
      [];

  @override
  Future<List<FileBookmark>> bookmarks() async => const [
        FileBookmark(kind: BookmarkKind.home, path: '/home/u'),
        FileBookmark(kind: BookmarkKind.documents, path: '/home/u/docs'),
        FileBookmark(kind: BookmarkKind.downloads, path: '/home/u/dl'),
        FileBookmark(kind: BookmarkKind.trash, path: '/trash'),
        FileBookmark(kind: BookmarkKind.root, path: '/'),
      ];

  @override
  Future<void> mkdir(String parent, String name) async {}

  @override
  Future<void> rename(String path, String newName) async {}

  @override
  Future<void> paste(
    List<String> paths,
    String destDir, {
    required bool move,
  }) async {}

  @override
  Future<void> trash(List<String> paths) async {}

  @override
  Future<void> open(String path) async {}
}

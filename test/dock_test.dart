import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/dock.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeChecker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String currentVersion) async => const AppUpdate();
}

OasisApp _app(String id) => OasisApp(
  id: id,
  name: 'App $id',
  icon: Icons.circle,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  builder: (_) => const SizedBox(),
);

Future<void> _pumpDesktop(WidgetTester tester, {OasisStore? store}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    OasisDesktopApp(
      store: store,
      backend: const NoopSystemBackend(),
      version: '1.0.0',
      appearance: OasisAppearance(),
      updateChecker: _FakeChecker(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('OasisDockSettings defaults to push, bottom, medium', () {
    final d = OasisDockSettings();
    expect(d.mode, OasisDockMode.push);
    expect(d.position, OasisDockPosition.bottom);
    expect(d.size, OasisDockSize.medium);
    expect(d.iconSize, kDockIconSizeMedium);
    expect(dockReservedExtent(d), kDockIconSizeMedium + 37);
    d.dispose();
  });

  test('OasisDockSettings persists and restores', () {
    final store = MemoryOasisStore();
    final d = OasisDockSettings(store: store);
    var notified = 0;
    d.addListener(() => notified++);
    d.mode = OasisDockMode.autoHide;
    d.position = OasisDockPosition.left;
    d.size = OasisDockSize.custom;
    d.customSize = 80;
    expect(notified, 4);
    expect(store.read('shell.dock.mode'), 'autoHide');
    expect(store.read('shell.dock.position'), 'left');
    expect(store.read('shell.dock.size'), 'custom');
    expect(store.read('shell.dock.customSize'), '80.0');
    expect(d.iconSize, 80);
    expect(dockReservedExtent(d), 0);

    d.customSize = 200;
    expect(d.customSize, kDockCustomSizeMax);
    d.customSize = kDockCustomSizeMax;
    d.mode = OasisDockMode.autoHide;

    final restored = OasisDockSettings(store: store);
    expect(restored.mode, OasisDockMode.autoHide);
    expect(restored.position, OasisDockPosition.left);
    expect(restored.size, OasisDockSize.custom);
    expect(restored.customSize, kDockCustomSizeMax);
    d.dispose();
    restored.dispose();
  });

  test('OasisDockSettings icon sizes and extent per position', () {
    final d = OasisDockSettings();
    d.size = OasisDockSize.small;
    expect(d.iconSize, kDockIconSizeSmall);
    d.size = OasisDockSize.large;
    expect(d.iconSize, kDockIconSizeLarge);
    d.size = OasisDockSize.custom;
    expect(d.iconSize, d.customSize);
    d.position = OasisDockPosition.left;
    d.size = OasisDockSize.large;
    expect(dockReservedExtent(d), kDockIconSizeLarge + 37);
    d.dispose();
  });

  testWidgets('dock pane edits settings through the shared model', (
    tester,
  ) async {
    final store = MemoryOasisStore();
    final s = SettingsState(store: store)..selectPane(SettingsPane.dock);
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        setLocale: (_) {},
        child: SettingsHome(state: s),
      ),
      size: const Size(900, 620),
    );
    expect(find.text('Dock'), findsWidgets);
    expect(find.text('Mode'), findsOneWidget);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-hide').last);
    await tester.pumpAndSettle();
    expect(s.dock.mode, OasisDockMode.autoHide);
    expect(store.read('shell.dock.mode'), 'autoHide');

    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left').last);
    await tester.pumpAndSettle();
    expect(s.dock.position, OasisDockPosition.left);

    expect(find.byType(OasisSlider), findsNothing);
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    expect(s.dock.size, OasisDockSize.custom);
    final slider = find.byType(OasisSlider);
    expect(slider, findsOneWidget);
    await tester.tapAt(tester.getCenter(slider) + const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(s.dock.customSize, isNot(64.0));
    s.dispose();
  });

  testWidgets('dock hides entirely in off mode', (tester) async {
    final store = MemoryOasisStore();
    await store.write('shell.dock.mode', 'off');
    await _pumpDesktop(tester, store: store);
    expect(find.byType(ShellDock), findsNothing);
  });

  testWidgets('auto-hide reveals the dock at the screen edge', (tester) async {
    final dock = OasisDockSettings()..mode = OasisDockMode.autoHide;
    addTearDown(dock.dispose);
    final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dock: dock,
          menusBuilder: () => const [],
        ),
      ),
    );
    final hidden = tester.getRect(find.byType(ShellDock));
    expect(hidden.top, greaterThanOrEqualTo(780));

    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(const Offset(640, 799));
    await tester.pumpAndSettle();
    final shown = tester.getRect(find.byType(ShellDock));
    expect(shown.bottom, lessThanOrEqualTo(800));
    expect(shown.top, lessThan(hidden.top));

    await m.moveTo(const Offset(640, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ShellDock)).top,
      greaterThanOrEqualTo(780),
    );
  });

  testWidgets('auto-hide tracks the left and right screen edges', (
    tester,
  ) async {
    for (final position in [OasisDockPosition.left, OasisDockPosition.right]) {
      final dock = OasisDockSettings()
        ..mode = OasisDockMode.autoHide
        ..position = position;
      addTearDown(dock.dispose);
      final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
      addTearDown(c.dispose);
      await pumpOasis(
        tester,
        Scaffold(
          body: DesktopShell(
            controller: c,
            dock: dock,
            menusBuilder: () => const [],
          ),
        ),
      );
      final hidden = tester.getRect(find.byType(ShellDock));

      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: Offset.zero);
      await m.moveTo(
        position == OasisDockPosition.left
            ? const Offset(1, 400)
            : const Offset(1279, 400),
      );
      await tester.pumpAndSettle();
      final shown = tester.getRect(find.byType(ShellDock));
      if (position == OasisDockPosition.left) {
        expect(shown.left, greaterThan(hidden.left));
        expect(shown.left, greaterThanOrEqualTo(0));
      } else {
        expect(shown.right, lessThan(hidden.right));
        expect(shown.right, lessThanOrEqualTo(1280));
      }

      await m.moveTo(const Offset(640, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ShellDock)), hidden);
      await m.removePointer();
    }
  });

  testWidgets('leaving auto-hide clears the revealed state', (tester) async {
    final dock = OasisDockSettings()..mode = OasisDockMode.autoHide;
    addTearDown(dock.dispose);
    final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dock: dock,
          menusBuilder: () => const [],
        ),
      ),
    );

    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(const Offset(640, 799));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ShellDock)).top, lessThan(780));

    dock.mode = OasisDockMode.push;
    await tester.pumpAndSettle();
    await m.moveTo(const Offset(640, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ShellDock)).bottom,
      lessThanOrEqualTo(800),
    );
  });

  testWidgets('left and right positions render a vertical dock', (
    tester,
  ) async {
    for (final position in [OasisDockPosition.left, OasisDockPosition.right]) {
      final dock = OasisDockSettings()..position = position;
      addTearDown(dock.dispose);
      final c = ShellController(
        batteryPollInterval: null,
        apps: [_app('a'), _app('b')],
      );
      addTearDown(c.dispose);
      c.pinned.addAll(c.apps);
      await pumpOasis(
        tester,
        Scaffold(
          body: DesktopShell(
            controller: c,
            dock: dock,
            menusBuilder: () => const [],
          ),
        ),
      );
      final r = tester.getRect(find.byType(ShellDock));
      if (position == OasisDockPosition.left) {
        expect(r.left, lessThan(60));
      } else {
        expect(r.right, greaterThan(1220));
      }

      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: Offset.zero);
      await m.moveTo(tester.getCenter(find.byType(OasisAppIcon).first));
      await tester.pump();
      await m.moveTo(Offset.zero);
      await tester.pump();
      await m.removePointer();
    }
  });

  testWidgets('zoomed window clears a left dock but not a hidden one', (
    tester,
  ) async {
    for (final (mode, left) in [
      (OasisDockMode.push, kDockIconSizeMedium + 37),
      (OasisDockMode.autoHide, 0.0),
    ]) {
      final dock = OasisDockSettings()
        ..mode = mode
        ..position = OasisDockPosition.left;
      addTearDown(dock.dispose);
      final c = ShellController(
        batteryPollInterval: null,
        apps: [_app('a')],
        dock: dock,
      );
      addTearDown(c.dispose);
      await pumpOasis(
        tester,
        Scaffold(
          body: DesktopShell(
            controller: c,
            dock: dock,
            menusBuilder: () => const [],
          ),
        ),
      );
      c.openApp(c.apps.first);
      c.toggleZoom(c.windows.single.id);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(OasisWindow)).left,
        moreOrLessEquals(left, epsilon: 0.01),
      );
    }
  });

  testWidgets('zoomed window clears a right dock', (tester) async {
    final dock = OasisDockSettings()..position = OasisDockPosition.right;
    addTearDown(dock.dispose);
    final c = ShellController(
      batteryPollInterval: null,
      apps: [_app('a')],
      dock: dock,
    );
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dock: dock,
          menusBuilder: () => const [],
        ),
      ),
    );
    c.openApp(c.apps.first);
    c.toggleZoom(c.windows.single.id);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(OasisWindow)).right,
      moreOrLessEquals(1280 - (kDockIconSizeMedium + 37), epsilon: 0.01),
    );
  });

  test('half snap respects the dock edge', () {
    final app = _app('a');
    const screen = Size(1280, 800);
    ShellWindowData snap(OasisDockSettings dock, Offset pointer) {
      final c = ShellController(
        batteryPollInterval: null,
        apps: [app],
        dock: dock,
      );
      addTearDown(c.dispose);
      c.openApp(app);
      c.dragWindow(c.windows.single.id, const Offset(10, 0), screen);
      c.endSurfaceGesture(pointer, screen);
      return c.windows.single;
    }

    final leftDock = OasisDockSettings()..position = OasisDockPosition.left;
    var w = snap(leftDock, const Offset(0, 400));
    expect(w.position.dx, kDockIconSizeMedium + 37);
    expect(w.size!.width, 1280 / 2 - (kDockIconSizeMedium + 37));
    w = snap(leftDock, const Offset(1279, 400));
    expect(w.position.dx, 640);
    expect(w.size!.width, 640);

    final rightDock = OasisDockSettings()..position = OasisDockPosition.right;
    w = snap(rightDock, const Offset(1279, 400));
    expect(w.size!.width, 640 - (kDockIconSizeMedium + 37));

    final hidden = OasisDockSettings()..mode = OasisDockMode.autoHide;
    w = snap(hidden, const Offset(0, 400));
    expect(w.size!.height, 800 - 30 - 8);

    final bottom = OasisDockSettings();
    w = snap(bottom, const Offset(0, 400));
    expect(w.size!.height, 800 - 30 - 8 - (kDockIconSizeMedium + 37));
    leftDock.dispose();
    rightDock.dispose();
    hidden.dispose();
    bottom.dispose();
  });
}

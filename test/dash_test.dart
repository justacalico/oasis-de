import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/dash.dart';
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
  test('OasisDashSettings defaults to push, bottom, medium', () {
    final d = OasisDashSettings();
    expect(d.mode, OasisDashMode.push);
    expect(d.position, OasisDashPosition.bottom);
    expect(d.size, OasisDashSize.medium);
    expect(d.iconSize, kDashIconSizeMedium);
    expect(dashReservedExtent(d), kDashIconSizeMedium + 24);
    d.dispose();
  });

  test('OasisDashSettings persists and restores', () {
    final store = MemoryOasisStore();
    final d = OasisDashSettings(store: store);
    var notified = 0;
    d.addListener(() => notified++);
    d.mode = OasisDashMode.autoHide;
    d.position = OasisDashPosition.left;
    d.size = OasisDashSize.custom;
    d.customSize = 80;
    expect(notified, 4);
    expect(store.read('shell.dock.mode'), 'autoHide');
    expect(store.read('shell.dock.position'), 'left');
    expect(store.read('shell.dock.size'), 'custom');
    expect(store.read('shell.dock.customSize'), '80.0');
    expect(d.iconSize, 80);
    expect(dashReservedExtent(d), 0);

    d.customSize = 200;
    expect(d.customSize, kDashCustomSizeMax);
    d.customSize = kDashCustomSizeMax;
    d.mode = OasisDashMode.autoHide;

    final restored = OasisDashSettings(store: store);
    expect(restored.mode, OasisDashMode.autoHide);
    expect(restored.position, OasisDashPosition.left);
    expect(restored.size, OasisDashSize.custom);
    expect(restored.customSize, kDashCustomSizeMax);
    d.dispose();
    restored.dispose();
  });

  test('OasisDashSettings icon sizes and extent per position', () {
    final d = OasisDashSettings();
    d.size = OasisDashSize.small;
    expect(d.iconSize, kDashIconSizeSmall);
    d.size = OasisDashSize.large;
    expect(d.iconSize, kDashIconSizeLarge);
    d.size = OasisDashSize.custom;
    expect(d.iconSize, d.customSize);
    d.position = OasisDashPosition.left;
    d.size = OasisDashSize.large;
    expect(dashReservedExtent(d), kDashIconSizeLarge + 24);
    d.dispose();
  });

  testWidgets('dash pane edits settings through the shared model', (
    tester,
  ) async {
    final store = MemoryOasisStore();
    final s = SettingsState(store: store)..selectPane(SettingsPane.dash);
    await pumpOasis(
      tester,
      OasisHost(
        appearance: OasisAppearance(),
        setLocale: (_) {},
        child: SettingsHome(state: s),
      ),
      size: const Size(900, 620),
    );
    expect(find.text('Dash'), findsWidgets);
    expect(find.text('Mode'), findsOneWidget);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-hide').last);
    await tester.pumpAndSettle();
    expect(s.dash.mode, OasisDashMode.autoHide);
    expect(store.read('shell.dock.mode'), 'autoHide');

    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left').last);
    await tester.pumpAndSettle();
    expect(s.dash.position, OasisDashPosition.left);

    expect(find.byType(OasisSlider), findsNothing);
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    expect(s.dash.size, OasisDashSize.custom);
    final slider = find.byType(OasisSlider);
    expect(slider, findsOneWidget);
    await tester.tapAt(tester.getCenter(slider) + const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(s.dash.customSize, isNot(64.0));
    s.dispose();
  });

  testWidgets('dash hides entirely in off mode', (tester) async {
    final store = MemoryOasisStore();
    await store.write('shell.dock.mode', 'off');
    await _pumpDesktop(tester, store: store);
    expect(find.byType(ShellDash), findsNothing);
  });

  testWidgets('auto-hide reveals the dash at the screen edge', (tester) async {
    final dash = OasisDashSettings()..mode = OasisDashMode.autoHide;
    addTearDown(dash.dispose);
    final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dash: dash,
          menusBuilder: () => const [],
        ),
      ),
    );
    final hidden = tester.getRect(find.byType(ShellDash));
    expect(hidden.top, greaterThanOrEqualTo(780));

    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(const Offset(640, 799));
    await tester.pumpAndSettle();
    final shown = tester.getRect(find.byType(ShellDash));
    expect(shown.bottom, lessThanOrEqualTo(800));
    expect(shown.top, lessThan(hidden.top));

    await m.moveTo(const Offset(640, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ShellDash)).top,
      greaterThanOrEqualTo(780),
    );
  });

  testWidgets('auto-hide tracks the left and right screen edges', (
    tester,
  ) async {
    for (final position in [OasisDashPosition.left, OasisDashPosition.right]) {
      final dash = OasisDashSettings()
        ..mode = OasisDashMode.autoHide
        ..position = position;
      addTearDown(dash.dispose);
      final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
      addTearDown(c.dispose);
      await pumpOasis(
        tester,
        Scaffold(
          body: DesktopShell(
            controller: c,
            dash: dash,
            menusBuilder: () => const [],
          ),
        ),
      );
      final hidden = tester.getRect(find.byType(ShellDash));

      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: Offset.zero);
      await m.moveTo(
        position == OasisDashPosition.left
            ? const Offset(1, 400)
            : const Offset(1279, 400),
      );
      await tester.pumpAndSettle();
      final shown = tester.getRect(find.byType(ShellDash));
      if (position == OasisDashPosition.left) {
        expect(shown.left, greaterThan(hidden.left));
        expect(shown.left, greaterThanOrEqualTo(0));
      } else {
        expect(shown.right, lessThan(hidden.right));
        expect(shown.right, lessThanOrEqualTo(1280));
      }

      await m.moveTo(const Offset(640, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ShellDash)), hidden);
      await m.removePointer();
    }
  });

  testWidgets('leaving auto-hide clears the revealed state', (tester) async {
    final dash = OasisDashSettings()..mode = OasisDashMode.autoHide;
    addTearDown(dash.dispose);
    final c = ShellController(batteryPollInterval: null, apps: [_app('a')]);
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dash: dash,
          menusBuilder: () => const [],
        ),
      ),
    );

    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(const Offset(640, 799));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ShellDash)).top, lessThan(780));

    dash.mode = OasisDashMode.push;
    await tester.pumpAndSettle();
    await m.moveTo(const Offset(640, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(ShellDash)).bottom,
      lessThanOrEqualTo(800),
    );
  });

  testWidgets('left and right positions render a vertical dash', (
    tester,
  ) async {
    for (final position in [OasisDashPosition.left, OasisDashPosition.right]) {
      final dash = OasisDashSettings()..position = position;
      addTearDown(dash.dispose);
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
            dash: dash,
            menusBuilder: () => const [],
          ),
        ),
      );
      final r = tester.getRect(find.byType(ShellDash));
      if (position == OasisDashPosition.left) {
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

  testWidgets('zoomed window clears a left dash but not a hidden one', (
    tester,
  ) async {
    for (final (mode, left) in [
      (OasisDashMode.push, kDashIconSizeMedium + 24),
      (OasisDashMode.autoHide, 0.0),
    ]) {
      final dash = OasisDashSettings()
        ..mode = mode
        ..position = OasisDashPosition.left;
      addTearDown(dash.dispose);
      final c = ShellController(
        batteryPollInterval: null,
        apps: [_app('a')],
        dash: dash,
      );
      addTearDown(c.dispose);
      await pumpOasis(
        tester,
        Scaffold(
          body: DesktopShell(
            controller: c,
            dash: dash,
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

  testWidgets('zoomed window clears a right dash', (tester) async {
    final dash = OasisDashSettings()..position = OasisDashPosition.right;
    addTearDown(dash.dispose);
    final c = ShellController(
      batteryPollInterval: null,
      apps: [_app('a')],
      dash: dash,
    );
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: DesktopShell(
          controller: c,
          dash: dash,
          menusBuilder: () => const [],
        ),
      ),
    );
    c.openApp(c.apps.first);
    c.toggleZoom(c.windows.single.id);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(OasisWindow)).right,
      moreOrLessEquals(1280 - (kDashIconSizeMedium + 24), epsilon: 0.01),
    );
  });

  test('half snap respects the dash edge', () {
    final app = _app('a');
    const screen = Size(1280, 800);
    ShellWindowData snap(OasisDashSettings dash, Offset pointer) {
      final c = ShellController(
        batteryPollInterval: null,
        apps: [app],
        dash: dash,
      );
      addTearDown(c.dispose);
      c.openApp(app);
      c.dragWindow(c.windows.single.id, const Offset(10, 0), screen);
      c.endSurfaceGesture(pointer, screen);
      return c.windows.single;
    }

    final leftDash = OasisDashSettings()..position = OasisDashPosition.left;
    var w = snap(leftDash, const Offset(0, 400));
    expect(w.position.dx, kDashIconSizeMedium + 24);
    expect(w.size!.width, 1280 / 2 - (kDashIconSizeMedium + 24));
    w = snap(leftDash, const Offset(1279, 400));
    expect(w.position.dx, 640);
    expect(w.size!.width, 640);

    final rightDash = OasisDashSettings()..position = OasisDashPosition.right;
    w = snap(rightDash, const Offset(1279, 400));
    expect(w.size!.width, 640 - (kDashIconSizeMedium + 24));

    final hidden = OasisDashSettings()..mode = OasisDashMode.autoHide;
    w = snap(hidden, const Offset(0, 400));
    expect(w.size!.height, 800 - 30 - 8);

    final bottom = OasisDashSettings();
    w = snap(bottom, const Offset(0, 400));
    expect(w.size!.height, 800 - 30 - 8 - (kDashIconSizeMedium + 24));
    leftDash.dispose();
    rightDash.dispose();
    hidden.dispose();
    bottom.dispose();
  });
}

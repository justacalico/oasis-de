import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/shell/shell_menus.dart';
import 'package:oasis_ui/oasis_ui.dart';

OasisApp _app(String id) => OasisApp(
  id: id,
  name: 'App $id',
  icon: Icons.circle,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  builder: (_) => const SizedBox(),
);

ShellController _controller() =>
    ShellController(apps: [_app('a'), _app('b'), _app('notes')]);

void main() {
  test('openApp creates, focuses and stacks windows', () {
    final c = _controller();
    final apps = c.apps;
    c.openApp(apps[0]);
    c.openApp(apps[1]);
    expect(c.windows.length, 2);
    expect(c.focusedId, c.windows.last.id);
    expect(
      c.windows.last.position.dx,
      greaterThan(c.windows.first.position.dx),
    );
    c.dispose();
  });

  test('openApp on existing window restores and refocuses', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    final id = c.windows.first.id;
    c.minimizeWindow(id);
    expect(c.windows.first.minimized, isTrue);
    expect(c.focusedId, isNull);
    c.openApp(c.apps[0]);
    expect(c.windows.length, 1);
    expect(c.windows.first.minimized, isFalse);
    expect(c.windows.first.transition, ShellWindowTransition.restoring);
    expect(c.focusedId, id);
    c.dispose();
  });

  test('closeWindow removes the window and clears focus', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    final id = c.windows.first.id;
    c.closeWindow(id);
    expect(c.windows, isEmpty);
    expect(c.focusedId, isNull);
    c.dispose();
  });

  test('focusWindow reorders stacking', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    c.openApp(c.apps[1]);
    final first = c.windows.first.id;
    c.focusWindow(first);
    expect(c.windows.last.id, first);
    expect(c.focusedId, first);
    c.dispose();
  });

  test('restoreWindow, toggleZoom and dragWindow mutate state', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    final w = c.windows.first;
    c.dragWindow(w.id, const Offset(10, 20), const Size(1280, 800));
    expect(w.position, const Offset(66, 72));
    c.toggleZoom(w.id);
    expect(w.zoomed, isTrue);
    c.dragWindow(w.id, const Offset(5, 5), const Size(1280, 800));
    expect(w.position, const Offset(66, 72));
    c.toggleZoom(w.id);
    c.minimizeWindow(w.id);
    expect(c.focusedWindow, isNull);
    c.restoreWindow(w.id);
    expect(c.focusedWindow?.id, w.id);
    c.dispose();
  });

  test('minimize and restore run through a transition', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    final w = c.windows.first;
    c.restoreWindow(w.id);
    expect(w.transition, ShellWindowTransition.none);
    c.minimizeWindow(w.id);
    expect(w.minimized, isTrue);
    expect(w.transition, ShellWindowTransition.minimizing);
    c.minimizeWindow(w.id);
    expect(c.windows.length, 1);
    c.dragWindow(w.id, const Offset(9, 9), const Size(1280, 800));
    expect(w.position, const Offset(56, 52));
    c.finishTransition(w.id);
    expect(w.transition, ShellWindowTransition.none);
    c.restoreWindow(w.id);
    expect(w.minimized, isFalse);
    expect(w.transition, ShellWindowTransition.restoring);
    c.dragWindow(w.id, const Offset(9, 9), const Size(1280, 800));
    expect(w.position, const Offset(56, 52));
    c.finishTransition(w.id);
    expect(w.transition, ShellWindowTransition.none);
    c.dispose();
  });

  test('closing or minimizing the focused window promotes the next', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    c.openApp(c.apps[1]);
    final first = c.windows[0].id;
    final second = c.windows[1].id;
    c.minimizeWindow(second);
    expect(c.focusedId, first);
    c.focusWindow(second);
    c.closeWindow(second);
    expect(c.focusedId, first);
    c.minimizeWindow(first);
    expect(c.focusedId, isNull);
    c.dispose();
  });

  test('battery level polls on an interval', () {
    fakeAsync((async) {
      final backend = _BatteryBackend();
      final c = ShellController(
        apps: const [],
        backend: backend,
        batteryPollInterval: const Duration(seconds: 1),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(backend.calls, greaterThanOrEqualTo(4));
      expect(c.batteryLevel, 0.5);
      c.dispose();
    });
  });

  test('showDesktop toggles minimize and restore', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    c.openApp(c.apps[1]);
    c.showDesktop();
    expect(c.windows.every((w) => w.minimized), isTrue);
    c.showDesktop();
    expect(c.windows.every((w) => !w.minimized), isTrue);

    c.showDesktop();
    c.restoreWindow(c.windows.first.id);
    c.showDesktop();
    expect(c.windows.every((w) => !w.minimized), isTrue);
    c.dispose();
  });

  test('resizeWindow sizes, moves and clamps windows', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    final w = c.windows.first;
    const fallback = Size(800, 600);

    c.resizeWindow(
      w.id,
      const Offset(40, 30),
      OasisResizeEdge.bottomRight,
      fallback,
    );
    expect(w.size, const Size(840, 630));
    expect(w.position, const Offset(56, 52));

    c.resizeWindow(
      w.id,
      const Offset(10, 12),
      OasisResizeEdge.topLeft,
      fallback,
    );
    expect(w.size, const Size(830, 618));
    expect(w.position, const Offset(66, 64));

    c.resizeWindow(
      w.id,
      const Offset(-2000, -2000),
      OasisResizeEdge.bottomRight,
      fallback,
    );
    expect(w.size, const Size(kMinWindowWidth, kMinWindowHeight));
    expect(w.position, const Offset(66, 64));

    c.resizeWindow(
      w.id,
      const Offset(470, 330),
      OasisResizeEdge.bottomRight,
      fallback,
    );
    expect(w.size, const Size(830, 630));

    c.resizeWindow(w.id, const Offset(600, 0), OasisResizeEdge.left, fallback);
    expect(w.size, const Size(kMinWindowWidth, 630));
    expect(w.position, Offset(66 + 830 - kMinWindowWidth, 64));

    c.toggleZoom(w.id);
    c.resizeWindow(
      w.id,
      const Offset(5, 5),
      OasisResizeEdge.bottomRight,
      fallback,
    );
    expect(w.size, const Size(kMinWindowWidth, 630));
    c.toggleZoom(w.id);

    w.transition = ShellWindowTransition.restoring;
    c.resizeWindow(
      w.id,
      const Offset(5, 5),
      OasisResizeEdge.bottomRight,
      fallback,
    );
    expect(w.size, const Size(kMinWindowWidth, 630));
    c.dispose();
  });

  test('dragWindow clamps to screen and snap zones apply', () {
    final c = _controller();
    c.openApp(c.apps.first);
    final w = c.windows.single;
    w.size = const Size(500, 400);
    const screen = Size(1280, 800);
    c.dragWindow(w.id, const Offset(-2000, -500), screen);
    expect(w.position.dx, greaterThan(-w.size!.width));
    expect(w.position.dy, greaterThanOrEqualTo(0));
    c.dragWindow(w.id, const Offset(4000, 3000), screen);
    expect(w.position.dx, lessThanOrEqualTo(screen.width - 64));
    expect(w.position.dy, lessThanOrEqualTo(screen.height - 24));
    c.endSurfaceGesture(const Offset(640, 10), screen);
    expect(w.zoomed, isTrue);
    c.dragWindow(w.id, const Offset(1, 1), screen);
    expect(w.position.dx, w.position.dx);

    w.zoomed = false;
    c.dragWindow(w.id, const Offset(5, 5), screen);
    c.endSurfaceGesture(const Offset(4, 400), screen);
    expect(w.size!.width, screen.width / 2);
    expect(w.position.dx, 0);
    c.dragWindow(w.id, const Offset(5, 5), screen);
    c.endSurfaceGesture(const Offset(1279, 400), screen);
    expect(w.position.dx, screen.width / 2);
    c.dragWindow(w.id, const Offset(5, 5), screen);
    c.endSurfaceGesture(const Offset(640, 400), screen);
    c.dispose();
  });

  test('mutating a missing window is a no-op', () {
    final c = _controller();
    c.minimizeWindow(999);
    c.restoreWindow(999);
    c.finishTransition(999);
    c.toggleZoom(999);
    c.dragWindow(999, const Offset(1, 1), const Size(1280, 800));
    c.resizeWindow(
      999,
      const Offset(1, 1),
      OasisResizeEdge.bottomRight,
      const Size(800, 600),
    );
    expect(c.windows, isEmpty);
    c.dispose();
  });

  test('pinApp, unpinApp and movePinned mutate pinned list', () {
    final c = _controller();
    c.unpinApp('a');
    expect(c.pinned, isEmpty);
    c.pinned.add(c.apps.first);
    c.unpinApp('a');
    expect(c.pinned, isEmpty);
    c.pinApp('missing');
    c.pinApp('a');
    c.pinApp('a');
    c.pinApp('b');
    expect([for (final a in c.pinned) a.id], ['a', 'b']);
    c.movePinned('b', 'a');
    expect([for (final a in c.pinned) a.id], ['b', 'a']);
    c.movePinned('a', 'a');
    c.movePinned('x', 'a');
    expect(c.pinned.first.id, 'b');
    c.dispose();
  });

  test('toggles notify the system backend and reconcile', () async {
    final calls = <String>[];
    final c = ShellController(
      apps: const [],
      backend: _RecordingBackend(calls),
    );
    c.wifiOnValue = false;
    c.bluetoothOnValue = false;
    c.brightnessValue = 0.5;
    c.volumeValue = 0.5;
    expect(calls, ['wifi', 'bluetooth', 'brightness', 'volume']);
    await pumpEventQueue();
    c.dispose();
  });

  test('cycleWindows focuses next visible window', () {
    final c = _controller();
    c.cycleWindows();
    c.openApp(c.apps[0]);
    c.openApp(c.apps[1]);
    final w1 = c.windows[0];
    final w2 = c.windows[1];
    c.cycleWindows();
    expect(c.focusedId, w1.id);
    c.cycleWindows();
    expect(c.focusedId, w2.id);
    w1.minimized = true;
    c.cycleWindows();
    expect(c.focusedId, w2.id);
    c.dispose();
  });

  test('workspaces switch and move windows', () {
    final c = _controller();
    c.openApp(c.apps.first);
    final w = c.windows.single;
    expect(w.workspace, 0);
    c.setWorkspace(0);
    c.setWorkspace(9);
    c.setWorkspace(-1);
    expect(c.activeWorkspace, 0);
    c.setWorkspace(2);
    expect(c.activeWorkspace, 2);
    expect(c.focusedId, isNull);
    c.moveWindowToWorkspace(w.id, 2);
    expect(w.workspace, 2);
    c.moveWindowToWorkspace(w.id, 2);
    c.setWorkspace(0);
    expect(c.focusedId, isNull);
    c.setWorkspace(2);
    expect(c.focusedId, w.id);
    c.dispose();
  });

  test('menus and overlays are mutually exclusive', () {
    final c = _controller();
    c.selectMenu('File');
    expect(c.openMenu, 'File');
    c.toggleLauncher();
    expect(c.launcherOpen, isTrue);
    expect(c.openMenu, isNull);
    c.toggleControlCenter();
    expect(c.controlCenterOpen, isTrue);
    expect(c.launcherOpen, isFalse);
    c.selectMenu('Edit');
    c.closeOverlays();
    expect(c.controlCenterOpen, isFalse);
    expect(c.openMenu, isNull);
    c.toggleControlCenter();
    c.toggleControlCenter();
    expect(c.controlCenterOpen, isFalse);
    c.toggleLauncher();
    c.toggleLauncher();
    expect(c.launcherOpen, isFalse);
    c.dispose();
  });

  test('demo toggles notify', () {
    final c = _controller();
    var notified = 0;
    c.addListener(() => notified++);
    c.wifiOnValue = false;
    c.bluetoothOnValue = false;
    c.focusOnValue = true;
    c.nightLightOnValue = true;
    c.brightnessValue = 0.4;
    c.volumeValue = 0.2;
    expect(c.wifiOn, isFalse);
    expect(c.bluetoothOn, isFalse);
    expect(c.focusOn, isTrue);
    expect(c.nightLightOn, isTrue);
    expect(c.brightness, 0.4);
    expect(c.volume, 0.2);
    expect(notified, 6);
    c.dispose();
  });

  test('filterApps matches case-insensitively', () {
    final c = _controller();
    expect(c.filterApps(''), c.apps);
    expect(c.filterApps('  '), c.apps);
    expect(c.filterApps('app a').single.id, 'a');
    expect(c.filterApps('NOTES').single.id, 'notes');
    expect(c.filterApps('zzz'), isEmpty);
    c.dispose();
  });

  test('filterApps ranks prefix, keyword, fuzzy and recency', () {
    OasisApp app(
      String id,
      String name, {
      List<String> kw = const [],
      String? gen,
    }) => OasisApp(
      id: id,
      name: name,
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000)],
      keywords: kw,
      genericName: gen,
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(
      apps: [
        app('exact', 'Settings'),
        app('sub', 'Sunset Settings'),
        app('kw', 'Other', kw: const ['settings prefs']),
        app('fz', 'SrEtTuS'),
        app('gen', 'Editor', gen: 'Set text'),
        app('oth', 'Settings Tool'),
      ],
    );
    addTearDown(c.dispose);
    final ranked = c.filterApps('sett');
    expect(ranked.first.id, 'exact');
    expect(ranked.map((a) => a.id), containsAll(['sub', 'kw', 'fz', 'gen']));
    c.launchCounts['oth'] = 5;
    final ids = [for (final a in c.filterApps('sett')) a.id];
    expect(ids.indexOf('oth'), lessThan(ids.indexOf('sub')));
    expect(c.filterApps('nada'), isEmpty);
  });

  test('syncApps refreshes app refs on open windows', () {
    final c = _controller();
    c.openApp(c.apps.first);
    final fresh = [_app('a'), _app('b')];
    c.syncApps(fresh);
    expect(c.apps, fresh);
    expect(identical(c.windows.first.app, fresh.first), isTrue);
    c.dispose();
  });
  test('shell menus reflect and drive window state', () {
    final l10n = lookupOasisLocalizations(const Locale('en'));
    OasisApp app(String id) => OasisApp(
      id: id,
      name: 'App $id',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(
      apps: [app('notes'), app('about'), app('settings')],
    );
    c.openApp(c.apps.first);
    final ctx = _Ctx();
    final apps = {'about': c.apps[1], 'settings': c.apps[2]};
    final menus = buildShellMenus(l10n, c, 'Oasis', apps);
    expect(menus.length, 5);
    for (final menu in menus) {
      c.openApp(c.apps.first);
      c.focusWindow(c.windows.last.id);
      for (final item in menu.items(ctx)) {
        if (item.enabled && item.action != null) {
          item.action!(ctx);
        }
        if (c.windows.isEmpty) c.openApp(c.apps.first);
        c.focusWindow(c.windows.last.id);
      }
    }
    c.dispose();
  });

  test('menus minimise and restore windows from the list', () {
    final l10n = lookupOasisLocalizations(const Locale('en'));
    OasisApp app(String id) => OasisApp(
      id: id,
      name: 'App $id',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(apps: [app('a'), app('b')]);
    c.openApp(c.apps[0]);
    c.openApp(c.apps[1]);
    final ctx = _Ctx();
    final windowMenu = buildShellMenus(
      l10n,
      c,
      'Oasis',
      {},
    ).firstWhere((m) => m.label == l10n.menuWindow);
    final items = windowMenu.items(ctx);
    expect(items.length, greaterThanOrEqualTo(4));
    final minimised = c.windows.first;
    minimised.minimized = true;
    final entries = windowMenu.items(ctx);
    for (final item in entries) {
      if (item.checked) expect(item.label, isNotEmpty);
      item.action?.call(ctx);
    }
    expect(minimised.minimized, isFalse);
    c.dispose();
  });

  test('session lock and suspend engage lock, unlock verifies', () async {
    final calls = <String>[];
    final backend = _RecordingBackend(calls);
    final c = ShellController(
      apps: const [],
      backend: backend,
      batteryPollInterval: null,
    );
    addTearDown(c.dispose);
    expect(c.locked, isFalse);
    c.session(OasisSessionAction.lock);
    expect(c.locked, isTrue);
    expect(backend.calls, ['session']);
    c.session(OasisSessionAction.suspend);
    expect(c.locked, isTrue);
    expect(backend.calls, ['session', 'session', 'session']);
    expect(await c.tryUnlock('pw'), isTrue);
    expect(c.locked, isFalse);
  });

  test('tryUnlock rejects when backend denies', () async {
    final c = ShellController(
      apps: const [],
      backend: const _DenyBackend(),
      batteryPollInterval: null,
    );
    addTearDown(c.dispose);
    c.session(OasisSessionAction.lock);
    expect(await c.tryUnlock('bad'), isFalse);
    expect(c.locked, isTrue);
  });
}

class _DenyBackend extends NoopSystemBackend {
  const _DenyBackend();

  @override
  Future<bool> verifyPassword(String password) async => false;
}

class _Ctx extends Fake implements BuildContext {
  @override
  InheritedElement? getElementForInheritedWidgetOfExactType<
      T extends InheritedWidget>() => null;
}

class _BatteryBackend implements OasisSystemBackend {
  var calls = 0;

  @override
  Future<OasisBattery> battery() async {
    calls++;
    return const OasisBattery(level: 0.5, charging: false);
  }

  @override
  Future<OasisSystemState> read() async => const OasisSystemState();

  @override
  Future<void> wifi(bool enabled) async {}

  @override
  Future<void> bluetooth(bool enabled) async {}

  @override
  Future<void> brightness(double level) async {}

  @override
  Future<void> volume(double level) async {}

  @override
  Future<void> nightLight(bool enabled) async {}

  @override
  void session(OasisSessionAction action) {}

  @override
  Future<bool> verifyPassword(String password) async => true;
}

class _RecordingBackend implements OasisSystemBackend {
  _RecordingBackend(this.calls);

  final List<String> calls;

  @override
  Future<void> wifi(bool enabled) async => calls.add('wifi');

  @override
  Future<void> bluetooth(bool enabled) async => calls.add('bluetooth');

  @override
  Future<void> brightness(double level) async => calls.add('brightness');

  @override
  Future<void> volume(double level) async => calls.add('volume');

  @override
  Future<void> nightLight(bool enabled) async => calls.add('nightLight');

  @override
  Future<OasisSystemState> read() async => const OasisSystemState();

  @override
  Future<OasisBattery> battery() async =>
      const OasisBattery(level: null, charging: false);

  @override
  void session(OasisSessionAction action) => calls.add('session');

  @override
  Future<bool> verifyPassword(String password) async => true;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/shell/shell_controller.dart';
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
    expect(c.windows.last.position.dx,
        greaterThan(c.windows.first.position.dx));
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
    c.dragWindow(w.id, const Offset(10, 20));
    expect(w.position, const Offset(66, 72));
    c.toggleZoom(w.id);
    expect(w.zoomed, isTrue);
    c.dragWindow(w.id, const Offset(5, 5));
    expect(w.position, const Offset(66, 72));
    c.toggleZoom(w.id);
    c.minimizeWindow(w.id);
    expect(c.focusedWindow, isNull);
    c.restoreWindow(w.id);
    expect(c.focusedWindow?.id, w.id);
    c.dispose();
  });

  test('mutating a missing window is a no-op', () {
    final c = _controller();
    c.minimizeWindow(999);
    c.restoreWindow(999);
    c.toggleZoom(999);
    c.dragWindow(999, const Offset(1, 1));
    expect(c.windows, isEmpty);
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
    c.brightnessValue = 0.4;
    c.volumeValue = 0.2;
    expect(c.wifiOn, isFalse);
    expect(c.bluetoothOn, isFalse);
    expect(c.focusOn, isTrue);
    expect(c.brightness, 0.4);
    expect(c.volume, 0.2);
    expect(notified, 5);
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

  test('syncApps refreshes app refs on open windows', () {
    final c = _controller();
    c.openApp(c.apps.first);
    final fresh = [_app('a'), _app('b')];
    c.syncApps(fresh);
    expect(c.apps, fresh);
    expect(identical(c.windows.first.app, fresh.first), isTrue);
    c.dispose();
  });
}

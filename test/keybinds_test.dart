import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'desktop_shell_test.dart' show pumpDesktop;
import 'helpers/test_app.dart';
import 'wayland_test.dart' show FakeWaylandHost;

OasisApp _app(String id) => OasisApp(
  id: id,
  name: 'App $id',
  icon: Icons.circle,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  builder: (_) => const SizedBox(),
);

ShellController _controller({
  WaylandService? wayland,
  OasisKeybindsService? keybinds,
}) => ShellController(
  apps: [_app('a'), _app('b'), _app('notes')],
  wayland: wayland,
  keybinds: keybinds,
  batteryPollInterval: null,
);

void main() {
  test('defaults cover every builtin action', () {
    final s = OasisKeybindsService();
    for (final action in OasisKeybindsService.builtinActions) {
      expect(s.comboFor(action), isNotNull);
    }
    expect(
      s.comboFor(OasisKeybindsService.actionLauncher),
      const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
    );
    expect(
      s.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    expect(s.comboFor('nope'), isNull);
    expect(s.activators.length, OasisKeybindsService.builtinActions.length);
    s.dispose();
  });

  test('combo label, encode and decode', () {
    const combo = OasisKeyCombo(
      key: LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
    );
    expect(combo.label, 'Ctrl+Shift+K');
    expect(
      const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true).label,
      'Super+Space',
    );
    expect(const OasisKeyCombo(key: LogicalKeyboardKey.f1).label, 'F1');
    expect(const OasisKeyCombo(key: LogicalKeyboardKey.escape).label, 'Esc');

    final round = OasisKeyCombo.decode(combo.encode());
    expect(round, combo);
    expect(round.hashCode, combo.hashCode);
    expect(round == combo, isTrue);
    expect(round == const OasisKeyCombo(key: LogicalKeyboardKey.keyK), isFalse);

    expect(OasisKeyCombo.decode(42), isNull);
    expect(OasisKeyCombo.decode('nocolon'), isNull);
    expect(OasisKeyCombo.decode('abc:m'), isNull);
    expect(OasisKeyCombo.decode('99999999999999:m'), isNull);
    expect(OasisKeyCombo.decode(''), isNull);
    // A modifier saved as the trigger key is dropped instead of firing on its
    // own press.
    expect(
      OasisKeyCombo.decode('${LogicalKeyboardKey.superKey.keyId}:'),
      isNull,
    );

    final activator = combo.activator;
    expect(activator.trigger, LogicalKeyboardKey.keyK);
    expect(activator.control, isTrue);
    expect(activator.shift, isTrue);
    expect(activator.alt, isFalse);
    expect(activator.meta, isFalse);
  });

  testWidgets('combo fromKeyDown reads held modifiers', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final down = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyQ,
      logicalKey: LogicalKeyboardKey.keyQ,
      timeStamp: Duration.zero,
    );
    expect(
      OasisKeyCombo.fromKeyDown(down),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    final modDown = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.metaLeft,
      logicalKey: LogicalKeyboardKey.metaLeft,
      timeStamp: Duration.zero,
    );
    expect(OasisKeyCombo.fromKeyDown(modDown), isNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    // Linux delivers the command key as superKey, which Flutter doesn't
    // include in isMetaPressed — it must still count as meta and must not be
    // recorded as the trigger itself.
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    expect(
      OasisKeyCombo.fromKeyDown(down),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    final superDown = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.superKey,
      logicalKey: LogicalKeyboardKey.superKey,
      timeStamp: Duration.zero,
    );
    expect(OasisKeyCombo.fromKeyDown(superDown), isNull);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
  });

  test('rebind steals combos and notifies', () {
    final store = MemoryOasisStore();
    final s = OasisKeybindsService(store: store);
    var notified = 0;
    s.addListener(() => notified++);

    const combo = OasisKeyCombo(key: LogicalKeyboardKey.keyJ, meta: true);
    s.rebind(OasisKeybindsService.actionQuit, combo);
    expect(s.comboFor(OasisKeybindsService.actionQuit), combo);
    expect(notified, 1);
    expect(store.read(OasisKeybindsService.storeKey), isNotNull);

    // Stealing: rebinding the launcher's combo leaves it unbound.
    s.rebind(
      OasisKeybindsService.actionQuit,
      const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
    );
    expect(s.comboFor(OasisKeybindsService.actionLauncher), isNull);
    expect(
      s.actionForCombo(
        const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
      ),
      OasisKeybindsService.actionQuit,
    );
    expect(s.actionForCombo(combo), isNull);

    // Unknown actions are ignored without notifying.
    s.rebind('bogus', combo);
    expect(notified, 2);

    s.resetDefaults();
    expect(
      s.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    s.dispose();
  });

  test('custom keybinds add, rebind, steal and remove', () {
    final s = OasisKeybindsService();
    const combo = OasisKeyCombo(key: LogicalKeyboardKey.keyT, alt: true);
    final id = s.addCustom(combo: combo, command: 'xterm -e top');
    expect(s.custom, hasLength(1));
    expect(s.customById(id)?.command, 'xterm -e top');
    expect(s.comboFor(id), combo);
    expect(s.actionForCombo(combo), id);
    expect(s.activators.values, contains(id));
    expect(s.customById('custom:999'), isNull);

    const other = OasisKeyCombo(key: LogicalKeyboardKey.keyU, alt: true);
    s.rebind(id, other);
    expect(s.comboFor(id), other);

    // Stealing a custom combo unbinds it instead of deleting the entry.
    s.rebind(OasisKeybindsService.actionQuit, other);
    expect(s.customById(id)?.combo, isNull);
    expect(s.actionForCombo(other), OasisKeybindsService.actionQuit);

    s.removeCustom(id);
    expect(s.custom, isEmpty);
    expect(s.comboFor(id), isNull);
    s.removeCustom('custom:missing');
    s.dispose();
  });

  test('persisted keybinds restore into a fresh service', () {
    final store = MemoryOasisStore();
    final s = OasisKeybindsService(store: store);
    s.rebind(
      OasisKeybindsService.actionQuit,
      const OasisKeyCombo(key: LogicalKeyboardKey.keyW, meta: true),
    );
    s.addCustom(
      combo: const OasisKeyCombo(key: LogicalKeyboardKey.keyT, alt: true),
      command: 'xterm',
    );

    final s2 = OasisKeybindsService(store: store);
    expect(
      s2.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyW, meta: true),
    );
    expect(s2.custom, hasLength(1));
    expect(s2.custom.first.command, 'xterm');
    final id2 = s2.addCustom(
      combo: const OasisKeyCombo(key: LogicalKeyboardKey.keyY, alt: true),
      command: 'foo',
    );
    expect(id2, 'custom:2');
    s.dispose();
    s2.dispose();
  });

  test('restore tolerates malformed payloads', () {
    final store = MemoryOasisStore();
    store.write(OasisKeybindsService.storeKey, 'not json');
    var s = OasisKeybindsService(store: store);
    expect(s.custom, isEmpty);

    store.write(OasisKeybindsService.storeKey, '[]');
    s.dispose();
    s = OasisKeybindsService(store: store);
    expect(s.custom, isEmpty);

    store.write(
      OasisKeybindsService.storeKey,
      jsonEncode({
        'bindings': {
          'shell.quit': 'bad',
          'bogus.action': '1:m',
          'shell.zoom': '${LogicalKeyboardKey.keyG.keyId}:m',
        },
        'custom': [
          'junk',
          {'id': 3, 'command': 'x'},
          {'id': 'custom:7'},
          {'id': 'custom:7', 'command': 'ok', 'combo': 'bad'},
        ],
      }),
    );
    s.dispose();
    s = OasisKeybindsService(store: store);
    expect(
      s.comboFor(OasisKeybindsService.actionZoom),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyG, meta: true),
    );
    expect(
      s.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    expect(s.custom, hasLength(1));
    expect(s.custom.first.combo, isNull);
    final next = s.addCustom(
      combo: const OasisKeyCombo(key: LogicalKeyboardKey.keyY, alt: true),
      command: 'y',
    );
    expect(next, 'custom:2');
    s.dispose();
  });

  test('quitFocusedApp closes every window of the app', () {
    final c = _controller();
    c.openApp(c.apps[0]);
    c.openApp(c.apps[0], newWindow: true);
    c.openApp(c.apps[1]);
    c.focusWindow(c.windows[1].id);
    expect(c.focusedWindow?.app.id, 'a');
    c.runKeybindAction(OasisKeybindsService.actionQuit);
    expect(c.windows.map((w) => w.app.id), ['b']);
    c.runKeybindAction(OasisKeybindsService.actionQuit);
    expect(c.windows, isEmpty);
    c.runKeybindAction(OasisKeybindsService.actionQuit);
    c.dispose();
  });

  test('quitFocusedApp groups wayland surfaces by app id', () async {
    final host = FakeWaylandHost();
    final wayland = WaylandService(host: host);
    await wayland.start();
    final c = _controller(wayland: wayland);
    host.emit({
      'event': 'toplevel',
      'id': 1,
      'textureId': 11,
      'title': 'One',
      'appId': 'org.foo',
      'parent': -1,
    });
    host.emit({
      'event': 'toplevel',
      'id': 2,
      'textureId': 12,
      'title': 'Two',
      'appId': 'org.foo',
      'parent': -1,
    });
    await pumpEventQueue();
    c.runKeybindAction(OasisKeybindsService.actionQuit);
    expect(host.calls, containsAllInOrder(['close:1', 'close:2']));
    c.dispose();
    wayland.dispose();
  });

  test('runKeybindAction covers every builtin and custom commands', () async {
    final host = FakeWaylandHost();
    final wayland = WaylandService(host: host);
    await wayland.start();
    final keybinds = OasisKeybindsService();
    final c = _controller(wayland: wayland, keybinds: keybinds);
    c.openApp(c.apps[0]);

    c.runKeybindAction(OasisKeybindsService.actionLauncher);
    expect(c.launcherOpen, isTrue);
    c.runKeybindAction(OasisKeybindsService.actionLaunchpad);
    expect(c.launchPadOpen, isTrue);
    expect(c.launcherOpen, isFalse);

    c.runKeybindAction(OasisKeybindsService.actionCycleWindows);
    expect(c.switcherIndex, isNotNull);
    c.runKeybindAction(OasisKeybindsService.actionCycleWindowsBack);
    c.runKeybindAction(OasisKeybindsService.actionDismiss);
    expect(c.switcherIndex, isNull);
    expect(c.launchPadOpen, isFalse);

    c.runKeybindAction(OasisKeybindsService.actionShowDesktop);
    expect(c.windows.every((w) => w.minimized), isTrue);
    c.runKeybindAction(OasisKeybindsService.actionShowDesktop);
    expect(c.windows.every((w) => !w.minimized), isTrue);

    c.runKeybindAction(OasisKeybindsService.actionZoom);
    expect(c.focusedWindow?.zoomed, isTrue);

    final id = keybinds.addCustom(
      combo: const OasisKeyCombo(key: LogicalKeyboardKey.keyR, meta: true),
      command: 'run "two words" \'x y\' last',
    );
    c.runKeybindAction(id);
    final empty = keybinds.addCustom(
      combo: const OasisKeyCombo(key: LogicalKeyboardKey.keyE, meta: true),
      command: '   ',
    );
    c.runKeybindAction(empty);
    c.runKeybindAction('custom:missing');
    c.runKeybindAction('completely.unknown');
    await pumpEventQueue();
    expect(host.calls, contains('launch:run two words x y last'));
    c.dispose();
    wayland.dispose();
  });

  Future<void> sendCombo(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('super+space opens the searcher and super+q quits', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await sendCombo(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.space,
    );
    expect(find.text('Search apps'), findsOneWidget);

    await sendCombo(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.space,
    );
    expect(find.text('Search apps'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await sendCombo(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyQ,
    );
    expect(find.byType(TextField), findsNothing);
  });

  Future<void> sendSuperCombo(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    // GTK reports the command key as superKey; fuchsia's test keymap is the
    // only simulated one that produces that logical key.
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('linux super key opens the searcher and quits apps', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await sendSuperCombo(tester, LogicalKeyboardKey.space);
    expect(find.text('Search apps'), findsOneWidget);

    await sendSuperCombo(tester, LogicalKeyboardKey.space);
    expect(find.text('Search apps'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await sendSuperCombo(tester, LogicalKeyboardKey.keyQ);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('rebound shortcuts drive the shell', (tester) async {
    final store = MemoryOasisStore();
    final keybinds = OasisKeybindsService(store: store);
    keybinds.rebind(
      OasisKeybindsService.actionLauncher,
      const OasisKeyCombo(key: LogicalKeyboardKey.f4),
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        backend: const NoopSystemBackend(),
        version: '1.0.0',
        keybinds: keybinds,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await sendCombo(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.space,
    );
    expect(find.text('Search apps'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pumpAndSettle();
    expect(find.text('Search apps'), findsOneWidget);
  });

  testWidgets('keyboard pane records and resets bindings', (tester) async {
    final keybinds = OasisKeybindsService();
    final state = SettingsState(keybinds: keybinds)
      ..selectPane(SettingsPane.keyboard);
    await pumpOasis(
      tester,
      Scaffold(body: SettingsHome(state: state)),
      size: const Size(900, 620),
    );

    expect(find.text('Shortcuts'), findsOneWidget);
    expect(find.text('App search'), findsOneWidget);
    expect(find.text('Super+Space'), findsWidgets);
    expect(find.text('Add shortcut'), findsOneWidget);

    // Tapping the chip itself starts a capture; Escape cancels it.
    await tester.tap(find.text('Super+Space'));
    await tester.pumpAndSettle();
    expect(find.text('Type shortcut…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Type shortcut…'), findsNothing);
    expect(
      keybinds.comboFor(OasisKeybindsService.actionLauncher),
      const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
    );

    // Tap to record, then a bare modifier keeps recording.
    await tester.tap(find.text('Quit app'));
    await tester.pumpAndSettle();
    expect(find.text('Type shortcut…'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.text('Type shortcut…'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      keybinds.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyW, meta: true),
    );
    expect(find.text('Super+W'), findsOneWidget);

    // Recording with the Linux super key keeps it as a modifier too.
    await tester.tap(find.text('Quit app'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    await tester.pump();
    expect(find.text('Type shortcut…'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    await tester.pumpAndSettle();
    expect(
      keybinds.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
    expect(find.text('Super+Q'), findsOneWidget);

    // Escape cancels a capture.
    await tester.tap(find.text('Next window'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      keybinds.comboFor(OasisKeybindsService.actionCycleWindows),
      const OasisKeyCombo(key: LogicalKeyboardKey.tab, alt: true),
    );

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(
      keybinds.comboFor(OasisKeybindsService.actionQuit),
      const OasisKeyCombo(key: LogicalKeyboardKey.keyQ, meta: true),
    );
  });

  testWidgets('keyboard pane manages custom shortcuts', (tester) async {
    final store = MemoryOasisStore();
    final keybinds = OasisKeybindsService(store: store);
    // Steal the launcher combo so its row falls back to "Not set".
    keybinds.rebind(
      OasisKeybindsService.actionQuit,
      const OasisKeyCombo(key: LogicalKeyboardKey.space, meta: true),
    );
    final state = SettingsState(keybinds: keybinds)
      ..selectPane(SettingsPane.keyboard);
    await pumpOasis(
      tester,
      Scaffold(body: SettingsHome(state: state)),
      size: const Size(900, 620),
    );
    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(find.text('Super+Space'), findsWidgets);

    await tester.tap(find.text('Add shortcut'));
    await tester.pumpAndSettle();
    expect(find.text('Command to run'), findsOneWidget);

    // Escape dismisses an in-dialog capture without adding anything.
    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(keybinds.custom, isEmpty);

    await tester.tap(find.text('Add shortcut'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'xterm -e top');
    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OasisButton, 'Add shortcut').last);
    await tester.pumpAndSettle();

    expect(keybinds.custom, hasLength(1));
    expect(keybinds.custom.first.command, 'xterm -e top');
    expect(
      keybinds.custom.first.combo,
      const OasisKeyCombo(key: LogicalKeyboardKey.keyT, control: true),
    );
    expect(find.text('xterm -e top'), findsOneWidget);
    expect(find.text('Ctrl+T'), findsWidgets);

    // Tapping the custom row captures too; Escape leaves the combo alone.
    await tester.tap(find.text('xterm -e top'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      keybinds.custom.first.combo,
      const OasisKeyCombo(key: LogicalKeyboardKey.keyT, control: true),
    );

    // Re-record the custom combo through its chip.
    await tester.tap(find.text('Ctrl+T'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      keybinds.custom.first.combo,
      const OasisKeyCombo(key: LogicalKeyboardKey.keyU, alt: true),
    );

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(keybinds.custom, isEmpty);
    expect(find.text('xterm -e top'), findsNothing);
  });

  testWidgets('keyboard pane falls back to an ephemeral service', (
    tester,
  ) async {
    final state = SettingsState()..selectPane(SettingsPane.keyboard);
    await pumpOasis(
      tester,
      Scaffold(body: SettingsHome(state: state)),
      size: const Size(900, 620),
    );
    expect(find.text('Keyboard'), findsWidgets);
    expect(find.text('Super+Space'), findsWidgets);
    state.dispose();
  });
}

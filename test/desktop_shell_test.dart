import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/dock.dart';
import 'package:oasis_de/shell/genie_window.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeChecker extends UpdateChecker {
  _FakeChecker(this.result);

  final AppUpdate result;

  @override
  Future<AppUpdate> check(String currentVersion) async => result;
}

Future<void> pumpDesktop(
  WidgetTester tester, {
  OasisThemeMode mode = OasisThemeMode.light,
  OasisAppearance? appearance,
  Locale? platformLocale,
  UpdateChecker? updateChecker,
  List<String>? opened,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    OasisDesktopApp(
      version: '1.0.0',
      appearance: appearance ?? OasisAppearance(themeMode: mode),
      updateChecker: updateChecker ?? _FakeChecker(const AppUpdate()),
      openUrl: (u) => opened?.add(u),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop renders bar, dock and wallpaper', (tester) async {
    await pumpDesktop(tester);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    expect(find.byType(OasisAppIcon), findsWidgets);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('opening the app menu shows items and opens about', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.text('Oasis'));
    await tester.pumpAndSettle();
    expect(find.text('About Oasis'), findsWidgets);
    expect(find.text('Quit Oasis'), findsOneWidget);
    await tester.tap(find.text('About Oasis').last);
    await tester.pumpAndSettle();
    expect(
      find.text('A calm, glassy desktop environment for Linux.'),
      findsOneWidget,
    );
  });

  testWidgets('menu hover switches the open menu', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Close Window'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('View')));
    await tester.pumpAndSettle();
    expect(find.text('Enter Full Screen'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('Window')));
    await tester.pumpAndSettle();
    expect(find.text('Minimise'), findsOneWidget);
    await tester.tapAt(const Offset(640, 400));
    await tester.pumpAndSettle();
    expect(find.text('Minimise'), findsNothing);
  });

  testWidgets('dock opens a window and traffic lights control it', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);

    Offset light(int i) =>
        tester.getRect(find.byType(OasisTrafficLights).first).centerLeft +
        Offset(6 + i * 20.0, 0);

    await tester.tapAt(light(0));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tapAt(light(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Notes').first, const Offset(30, 20));
    await tester.pumpAndSettle();
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await tester.tapAt(light(2));
      await tester.pump();
      await tester.tapAt(light(2));
    });
    await tester.pumpAndSettle();
  });

  testWidgets('dragging a window corner resizes it', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byType(OasisWindow));
    final br = tester.getRect(find.byType(OasisWindow)).bottomRight;
    final gesture = await tester.startGesture(br - const Offset(4, 4));
    await gesture.moveBy(const Offset(40, 25));
    await gesture.up();
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byType(OasisWindow));
    expect(after.width, before.width + 40);
    expect(after.height, before.height + 25);
  });

  testWidgets('launcher filters and opens apps', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    expect(find.text('Search apps'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'sett');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('launcher keyboard navigation and no results', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'notes');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Search apps'), findsNothing);
  });

  testWidgets('control center toggles and sliders work', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();

    final slider = find.byType(OasisSlider).first;
    await tester.tapAt(tester.getCenter(slider) - const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(640, 500));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsNothing);
  });

  testWidgets('settings window navigates panes and picks theme', (
    tester,
  ) async {
    final appearance = OasisAppearance();
    await pumpDesktop(tester, appearance: appearance);
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('Traditional English'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.text('通用'), findsWidgets);

    await tester.tap(find.text('外观').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(appearance.themeMode, OasisThemeMode.dark);

    await tester.tap(find.text('关于').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('无线局域网').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('蓝牙').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OasisToggle).first);
    await tester.pumpAndSettle();
  });

  testWidgets('dark and oled modes render', (tester) async {
    await pumpDesktop(tester, mode: OasisThemeMode.dark);
    expect(find.text('File'), findsOneWidget);
    await pumpDesktop(
      tester,
      appearance: OasisAppearance(themeMode: OasisThemeMode.oled),
    );
    expect(find.text('File'), findsOneWidget);
  });

  testWidgets('status icons open launcher and control center', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.battery_full));
    await tester.tap(find.byIcon(Icons.wifi).first);
    await tester.pumpAndSettle();
    expect(find.text('Brightness'), findsOneWidget);
  });

  testWidgets('window genies into the dock and back out', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);

    final light = tester
        .getRect(find.byType(OasisTrafficLights).first)
        .centerLeft;
    await tester.tapAt(light + const Offset(26, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Notes'), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_note).last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);
  });

  testWidgets('tapping the dock icon mid-genie pulls the window back', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    final light = tester
        .getRect(find.byType(OasisTrafficLights).first)
        .centerLeft;
    await tester.tapAt(light + const Offset(26, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.edit_note).last);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);
  });

  testWidgets('genie falls back when the dock icon is unmounted', (
    tester,
  ) async {
    final window = ShellWindowData(
      id: 1,
      app: OasisApp(
        id: 'x',
        name: 'X',
        icon: Icons.circle,
        iconColors: const [Color(0xFF000000), Color(0xFF111111)],
        builder: (_) => const SizedBox(),
      ),
      position: Offset.zero,
    )..transition = ShellWindowTransition.minimizing;
    await tester.pumpWidget(
      MaterialApp(
        home: GenieWindow(
          window: window,
          rect: const Rect.fromLTWH(40, 40, 400, 300),
          onEnd: () {},
          child: const SizedBox(width: 400, height: 300),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('menu actions: settings, close, minimise, zoom, about', (
    tester,
  ) async {
    await pumpDesktop(tester);

    await tester.tap(find.text('Oasis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Window'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_note).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Window'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimise'));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsNothing);

    final icons = find.byIcon(Icons.edit_note);
    await tester.tap(icons.last);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);

    await tester.tap(find.text('Window'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Oasis').last);
    await tester.pumpAndSettle();
    expect(
      find.text('A calm, glassy desktop environment for Linux.'),
      findsWidgets,
    );

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Full Screen'), findsOneWidget);
    await tester.tapAt(const Offset(640, 500));
    await tester.pumpAndSettle();
  });

  testWidgets('control center workspace pager switches', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ws1')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ws0')).first);
    await tester.pumpAndSettle();
  });

  testWidgets('control center bluetooth and volume slider', (tester) async {
    await pumpDesktop(
      tester,
      updateChecker: _FakeChecker(
        const AppUpdate(
          latestVersion: '2.0.0',
          updateAvailable: true,
          releaseUrl: 'https://rel/2',
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bluetooth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night Light'));
    await tester.pumpAndSettle();
    final sliders = find.byType(OasisSlider);
    await tester.tapAt(tester.getCenter(sliders.at(1)) + const Offset(40, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    expect(find.text('Version 2.0.0 is available'), findsOneWidget);
  });

  testWidgets('dock magnification on hover and entry hover', (tester) async {
    await pumpDesktop(tester);
    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: Offset.zero);
    addTearDown(m.removePointer);
    await m.moveTo(const Offset(640, 780));
    await tester.pumpAndSettle();
    await m.moveTo(const Offset(700, 780));
    await tester.pumpAndSettle();
    await m.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await m.moveTo(tester.getCenter(find.text('Close Window')));
    await tester.pump();
    await m.moveTo(tester.getCenter(find.text('New Window')));
    await tester.pump();
    await m.moveTo(const Offset(640, 500));
    await tester.pump();
    await tester.tapAt(const Offset(640, 500));
    await tester.pumpAndSettle();
  });

  testWidgets('launcher panel tap, submit and clock tick', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    final panelGd = find.ancestor(
      of: find.byType(EditableText),
      matching: find.byType(GestureDetector),
    );
    final r = tester.getRect(panelGd.first);
    await tester.tapAt(r.topCenter + const Offset(0, 6));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, 'notes');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
  });

  testWidgets('unpinned minimized window gets a dock entry', (tester) async {
    final app = OasisApp(
      id: 'extra',
      name: 'Extra',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(apps: [app]);
    addTearDown(c.dispose);
    c.openApp(app);
    final w = c.windows.single;
    c.minimizeWindow(w.id);
    c.finishTransition(w.id);

    await pumpOasis(
      tester,
      Scaffold(
        body: Center(child: ShellDock(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final icon = find.byKey(w.dockIconKey);
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    expect(w.minimized, isFalse);
  });

  testWidgets('dock icons pin via context menu', (tester) async {
    OasisApp mk(String id) => OasisApp(
      id: id,
      name: 'App $id',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(apps: [mk('a'), mk('b'), mk('ext')]);
    addTearDown(c.dispose);
    c.pinned.addAll([c.apps[0], c.apps[1]]);
    c.openApp(c.apps[2]);
    final w = c.windows.single;
    c.minimizeWindow(w.id);
    c.finishTransition(w.id);
    await pumpOasis(
      tester,
      Scaffold(
        body: Center(child: ShellDock(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(OasisAppIcon).last,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin to Dock'));
    await tester.pumpAndSettle();
    expect(c.pinned.map((a) => a.id), contains('ext'));
  });

  testWidgets('dock unpin via context menu', (tester) async {
    OasisApp mk(String id) => OasisApp(
      id: id,
      name: 'App $id',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(apps: [mk('a'), mk('b')]);
    addTearDown(c.dispose);
    c.pinned.addAll(c.apps);
    await pumpOasis(
      tester,
      Scaffold(
        body: Center(child: ShellDock(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(OasisAppIcon).at(2),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();
    expect(c.pinned.map((a) => a.id), isNot(contains('b')));
  });
  testWidgets('pinned icons reorder by drag', (tester) async {
    OasisApp mk(String id) => OasisApp(
      id: id,
      name: 'App $id',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c = ShellController(apps: [mk('a'), mk('b')]);
    addTearDown(c.dispose);
    c.pinned.addAll(c.apps);
    await pumpOasis(
      tester,
      Scaffold(
        body: Center(child: ShellDock(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final icons = find.byType(OasisAppIcon);
    final from = tester.getCenter(icons.at(1));
    final to = tester.getCenter(icons.at(2));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.pinned.first.id, 'b');
  });
}

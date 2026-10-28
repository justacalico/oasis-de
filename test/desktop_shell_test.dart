import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_ui/oasis_ui.dart';


class _FakeChecker extends UpdateChecker {
  _FakeChecker(this.result);

  final AppUpdate result;

  @override
  Future<AppUpdate> check(String currentVersion) async => result;
}

Future<void> pumpDesktop(WidgetTester tester,
    {OasisThemeMode mode = OasisThemeMode.light,
    OasisAppearance? appearance,
    Locale? platformLocale,
    List<String>? opened}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(OasisDesktopApp(
    version: '1.0.0',
    appearance: appearance ?? OasisAppearance(themeMode: mode),
    updateChecker: _FakeChecker(const AppUpdate()),
    openUrl: (u) => opened?.add(u),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop renders bar, dock and wallpaper', (tester) async {
    await pumpDesktop(tester);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(OasisAppIcon), findsWidgets);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('opening the app menu shows items and opens about',
      (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.text('Oasis'));
    await tester.pumpAndSettle();
    expect(find.text('About Oasis'), findsWidgets);
    expect(find.text('Quit Oasis'), findsOneWidget);
    await tester.tap(find.text('About Oasis').last);
    await tester.pumpAndSettle();
    expect(find.text('A calm, glassy desktop environment for Linux.'),
        findsOneWidget);
  });

  testWidgets('menu hover switches the open menu', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Close Window'), findsOneWidget);

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Edit')));
    await tester.pumpAndSettle();
    expect(find.text('Select All'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('Window')));
    await tester.pumpAndSettle();
    expect(find.text('Minimise'), findsOneWidget);
    await tester.tapAt(const Offset(640, 400));
    await tester.pumpAndSettle();
    expect(find.text('Minimise'), findsNothing);
  });

  testWidgets('dock opens a window and traffic lights control it',
      (tester) async {
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

    await tester.drag(
        find.text('Notes').first, const Offset(30, 20));
    await tester.pumpAndSettle();
    await withClock(Clock.fixed(DateTime(2025, 6, 10, 9, 41)), () async {
      await tester.tapAt(light(2));
      await tester.pump();
      await tester.tapAt(light(2));
    });
    await tester.pumpAndSettle();
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

  testWidgets('launcher keyboard navigation and no results',
      (tester) async {
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

  testWidgets('control center toggles and sliders work',
      (tester) async {
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
    await tester.tapAt(
        tester.getCenter(slider) - const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(640, 500));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi'), findsNothing);
  });

  testWidgets('settings window navigates panes and picks theme',
      (tester) async {
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
    await pumpDesktop(tester,
        appearance: OasisAppearance(themeMode: OasisThemeMode.oled));
    expect(find.text('File'), findsOneWidget);
  });

  testWidgets('status icons open launcher and control center',
      (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.battery_full));
    await tester.tap(find.byIcon(Icons.wifi).first);
    await tester.pumpAndSettle();
    expect(find.text('Brightness'), findsOneWidget);
  });
}

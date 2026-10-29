import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_ui/oasis_ui.dart';


class _Checker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String v) async => const AppUpdate(
      latestVersion: '2.0.0',
      updateAvailable: true,
      releaseUrl: 'https://rel/2');
}

Future<void> pumpDesktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(OasisDesktopApp(
      version: '1.0.0',
      appearance: OasisAppearance(themeMode: OasisThemeMode.light),
      updateChecker: _Checker(),
      openUrl: (_) {}));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu actions: settings, close, minimise, zoom, about',
      (tester) async {
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
    expect(find.text('A calm, glassy desktop environment for Linux.'),
        findsWidgets);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Full Screen'), findsOneWidget);
    await tester.tapAt(const Offset(640, 500));
    await tester.pumpAndSettle();
  });

  testWidgets('control center bluetooth and volume slider',
      (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bluetooth'));
    await tester.pumpAndSettle();
    final sliders = find.byType(OasisSlider);
    await tester.tapAt(tester.getCenter(sliders.at(1)) +
        const Offset(40, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for Updates').last);
    await tester.pumpAndSettle();
    expect(find.text('Version 2.0.0 is available'), findsOneWidget);
  });

  testWidgets('dock magnification on hover and entry hover',
      (tester) async {
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

  testWidgets('launcher panel tap, submit and clock tick',
      (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    final panelGd = find.ancestor(
        of: find.byType(EditableText),
        matching: find.byType(GestureDetector));
    final r = tester.getRect(panelGd.first);
    await tester.tapAt(r.topCenter + const Offset(0, 6));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, 'notes');
    await tester.pumpAndSettle();
    await tester.testTextInput
        .receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
  });
}

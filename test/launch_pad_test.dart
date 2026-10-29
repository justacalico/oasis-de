import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/dock.dart';
import 'package:oasis_de/shell/launch_pad.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeChecker extends UpdateChecker {
  @override
  Future<AppUpdate> check(String currentVersion) async => const AppUpdate();
}

Future<void> pumpDesktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    OasisDesktopApp(
      version: '1.0.0',
      appearance: OasisAppearance(themeMode: OasisThemeMode.light),
      updateChecker: _FakeChecker(),
    ),
  );
  await tester.pumpAndSettle();
}

OasisApp _app(String id) => OasisApp(
  id: id,
  name: 'App $id',
  icon: Icons.circle,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  builder: (_) => const SizedBox(),
);

void main() {
  testWidgets('launch pad dock entry is not a windowed app', (tester) async {
    await pumpDesktop(tester);
    final context = tester.element(find.byType(Scaffold));
    final entry = launchPadEntry(
      lookupOasisLocalizations(const Locale('en', 'GB')),
      OasisPalette.light,
    );
    expect(entry.name, 'Launch Pad');
    expect(entry.isExternal, isFalse);
    expect(entry.builder(context), isA<SizedBox>());
  });

  testWidgets('dock rocket toggles the launch pad', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsNothing);
  });

  testWidgets('typing filters the grid and tapping an icon opens the app', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sett');
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsNothing);
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('empty search shows no results and escape closes', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsNothing);
  });

  testWidgets('keyboard navigation selects and opens apps', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);
    expect(find.byType(ShellLaunchPad), findsNothing);

    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets);
    expect(find.byType(ShellLaunchPad), findsNothing);
  });

  testWidgets('tapping the backdrop closes the pad', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(30, 400));
    await tester.pumpAndSettle();
    expect(find.byType(ShellLaunchPad), findsNothing);
  });

  testWidgets('paged grid swipes, dots and key jumps navigate', (tester) async {
    final controller = ShellController(
      apps: [for (var i = 0; i < 45; i++) _app('$i')],
    );
    addTearDown(controller.dispose);
    await pumpOasis(
      tester,
      Scaffold(body: ShellLaunchPad(controller: controller)),
    );
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('App 0'), findsOneWidget);
    expect(find.text('App 40'), findsNothing);

    final dots = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    );
    expect(dots, findsNWidgets(2));

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('App 40'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('App 40'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('App 40'), findsNothing);

    await tester.tap(dots.last);
    await tester.pumpAndSettle();
    expect(find.text('App 44'), findsOneWidget);
  });
}

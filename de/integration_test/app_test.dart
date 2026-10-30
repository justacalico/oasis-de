import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_ui/oasis_ui.dart';

void main() {
  testWidgets('desktop boots to menu bar and dock', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const OasisDesktopApp(
        backend: NoopSystemBackend(),
        version: '0.0.0',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/shell/context_menu.dart';

void main() {
  testWidgets('confirmShellAction does nothing without an Overlay', (
    tester,
  ) async {
    var confirmed = false;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: Key('host')),
      ),
    );
    confirmShellAction(
      tester.element(find.byKey(const Key('host'))),
      message: 'Sure?',
      cancelLabel: 'Cancel',
      confirmLabel: 'OK',
      onConfirm: () => confirmed = true,
    );
    expect(confirmed, isFalse);
  });
}

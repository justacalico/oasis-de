import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_ui/oasis_ui.dart';

Future<void> loadOasisFonts() async {
  final loader = FontLoader('packages/oasis_ui/Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
        rootBundle.load('packages/oasis_ui/fonts/Inter-$w.ttf'));
  }
  await loader.load();
}

Widget wrapOasis(
  Widget home, {
  OasisThemeMode theme = OasisThemeMode.light,
  bool platformDark = false,
  Locale? locale,
  Size size = const Size(1280, 800),
}) {
  return MediaQuery(
    data: MediaQueryData(
        size: size,
        platformBrightness:
            platformDark ? Brightness.dark : Brightness.light),
    child: MaterialApp(
      theme: OasisTheme.resolve(theme, platformDark: platformDark),
      locale: locale,
      supportedLocales: OasisLocalizations.supportedLocales,
      localizationsDelegates: const [
        OasisLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<void> pumpOasis(
  WidgetTester tester,
  Widget home, {
  OasisThemeMode theme = OasisThemeMode.light,
  bool platformDark = false,
  Locale? locale,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrapOasis(
    home,
    theme: theme,
    platformDark: platformDark,
    locale: locale,
    size: size,
  ));
  await tester.pumpAndSettle();
}

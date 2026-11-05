import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_files/oasis_files.dart';
import 'package:oasis_ui/oasis_ui.dart';

class FakeFilesBackend extends FilesBackend {
  FakeFilesBackend(this.items);

  final List<FileItem> items;

  @override
  Future<List<FileItem>> list(String dir, {bool showHidden = false}) async =>
      items;

  @override
  Future<List<FileItem>> search(
    String root,
    String query, {
    int limit = 200,
  }) async =>
      [];

  @override
  Future<List<FileBookmark>> bookmarks() async => const [];

  @override
  Future<void> mkdir(String parent, String name) async {}

  @override
  Future<void> rename(String path, String newName) async {}

  @override
  Future<void> paste(
    List<String> paths,
    String destDir, {
    required bool move,
  }) async {}

  @override
  Future<void> trash(List<String> paths) async {}

  @override
  Future<void> open(String path) async {}
}

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
  Locale? locale,
  Size size = const Size(1280, 800),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: OasisTheme.resolve(theme),
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
  Locale? locale,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrapOasis(
    home,
    theme: theme,
    locale: locale,
    size: size,
  ));
  await tester.pumpAndSettle();
}

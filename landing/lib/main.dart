import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'landing_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  final appearance = OasisAppearance();
  final saved = prefs.getString('theme');
  if (saved != null) {
    for (final mode in OasisThemeMode.values) {
      if (mode.name == saved) appearance.themeMode = mode;
    }
  }
  runApp(LandingApp(
    appearance: appearance,
    onThemeChanged: (mode) => prefs.setString('theme', mode.name),
    appUrl: 'app/',
    onOpenUrl: (url) async {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri);
    },
    showcaseImages: const [
      AssetImage('assets/showcase/desktop.png'),
      AssetImage('assets/showcase/settings.png'),
      AssetImage('assets/showcase/dark.png'),
    ],
  ));
}

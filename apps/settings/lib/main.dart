import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_app.dart';
import 'state/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  final store = PrefsOasisStore(prefs);
  runApp(OasisSettingsApp(
    wallpaper: OasisWallpaperService(store: store),
    state: SettingsState(store: store, backend: const CliSystemBackend()),
    openUrl: (url) async {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri);
    },
  ));
}

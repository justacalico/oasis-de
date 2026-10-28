import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  runApp(OasisSettingsApp(
    openUrl: (url) async {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri);
    },
  ));
}

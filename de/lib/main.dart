import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

const kInterfaceMode = bool.fromEnvironment(
  'OASIS_INTERFACE',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final info = await PackageInfo.fromPlatform();
  final prefs = await SharedPreferences.getInstance();

  if (!kIsWeb && Platform.isLinux) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0x00000000),
    );
    unawaited(
      windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
        if (kInterfaceMode ||
            Platform.environment['OASIS_SESSION'] == '1') {
          await windowManager.setFullScreen(true);
        }
      }),
    );
  }

  runApp(
    OasisDesktopApp(
      version: info.version,
      wallpaper: OasisWallpaperService(store: PrefsOasisStore(prefs)),
      store: PrefsOasisStore(prefs),
      openUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri);
      },
    ),
  );
}

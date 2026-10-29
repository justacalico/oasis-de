import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'views/settings_home.dart';

class OasisSettingsApp extends StatefulWidget {
  const OasisSettingsApp({
    super.key,
    this.version = '0.1.0',
    this.updateChecker,
    this.openUrl,
    this.appearance,
    this.wallpaper,
  });

  final String version;
  final UpdateChecker? updateChecker;
  final ValueChanged<String>? openUrl;
  final OasisAppearance? appearance;
  final OasisWallpaperService? wallpaper;

  @override
  State<OasisSettingsApp> createState() => _OasisSettingsAppState();
}

class _OasisSettingsAppState extends State<OasisSettingsApp> {
  late final OasisAppearance _appearance;
  late final OasisWallpaperService _wallpaper;
  late final UpdateService _updates;
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    _wallpaper = widget.wallpaper ?? OasisWallpaperService();
    _updates = UpdateService(
      checker: widget.updateChecker,
      currentVersion: () async => widget.version,
    );
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platformDark =
        View.of(context).platformDispatcher.platformBrightness ==
            Brightness.dark;
    return AnimatedBuilder(
      animation: _appearance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) =>
              OasisLocalizations.of(context).settingsTitle,
          theme: _appearance.themeForBrightness(platformDark),
          locale: _locale,
          supportedLocales: OasisLocalizations.supportedLocales,
          localizationsDelegates: const [
            OasisLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OasisHost(
            appearance: _appearance,
            updates: _updates,
            setLocale: (l) => setState(() => _locale = l),
            locale: _locale,
            openUrl: widget.openUrl,
            child: Scaffold(
              body: SafeArea(
                child: SettingsHome(
                  version: widget.version,
                  wallpaper: _wallpaper,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

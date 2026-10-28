import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'apps/shell_apps.dart';
import 'shell/desktop_shell.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_menus.dart';

class OasisDesktopApp extends StatefulWidget {
  const OasisDesktopApp({
    super.key,
    this.version = '0.1.0',
    this.updateChecker,
    this.openUrl,
    this.appearance,
  });

  final String version;
  final UpdateChecker? updateChecker;
  final ValueChanged<String>? openUrl;
  final OasisAppearance? appearance;

  @override
  State<OasisDesktopApp> createState() => _OasisDesktopAppState();
}

class _OasisDesktopAppState extends State<OasisDesktopApp> {
  late final OasisAppearance _appearance;
  late final UpdateService _updates;
  late final ShellController _controller;
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    _updates = UpdateService(
      checker: widget.updateChecker,
      currentVersion: () async => widget.version,
    );
    _controller = ShellController(apps: const []);
  }

  @override
  void dispose() {
    _controller.dispose();
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
              OasisLocalizations.of(context).appName,
          theme: _appearance.themeForBrightness(platformDark),
          locale: _locale,
          supportedLocales: OasisLocalizations.supportedLocales,
          localizationsDelegates: const [
            OasisLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              final l10n = OasisLocalizations.of(context);
              final apps = buildShellApps(
                l10n,
                version: widget.version,
                appearance: _appearance,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
              );
              _controller.syncApps(apps);
              final appsById = {for (final a in apps) a.id: a};
              return OasisHost(
                appearance: _appearance,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
                child: Scaffold(
                  body: DesktopShell(
                    controller: _controller,
                    menusBuilder: () => buildShellMenus(
                      l10n,
                      _controller,
                      _focusedAppName(l10n),
                      appsById,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _setLocale(Locale? locale) {
    setState(() => _locale = locale);
  }

  String _focusedAppName(OasisLocalizations l10n) {
    final focused = _controller.focusedWindow;
    return focused?.app.name ?? l10n.appName;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'apps/shell_apps.dart';
import 'shell/desktop_shell.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_menus.dart';
import 'wayland/desktop_entries.dart';
import 'wayland/wayland_service.dart';

Future<List<OasisApp>> loadExternalApps() async {
  final entries = kIsWeb
      ? const <DesktopAppEntry>[]
      : await loadDesktopEntries();
  return [for (final e in entries) desktopAppToOasis(e)];
}

class OasisDesktopApp extends StatefulWidget {
  const OasisDesktopApp({
    super.key,
    this.version = '0.1.0',
    this.updateChecker,
    this.openUrl,
    this.appearance,
    this.wayland,
    this.externalAppsLoader = loadExternalApps,
  });

  final String version;
  final UpdateChecker? updateChecker;
  final ValueChanged<String>? openUrl;
  final OasisAppearance? appearance;
  final WaylandService? wayland;
  final Future<List<OasisApp>> Function() externalAppsLoader;

  @override
  State<OasisDesktopApp> createState() => _OasisDesktopAppState();
}

class _OasisDesktopAppState extends State<OasisDesktopApp> {
  late final OasisAppearance _appearance;
  late final UpdateService _updates;
  late final ShellController _controller;
  late final WaylandService _wayland;
  List<OasisApp> _externalApps = const [];
  Locale? _locale;

  ShellController get controller => _controller;
  WaylandService get wayland => _wayland;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    _updates = UpdateService(
      checker: widget.updateChecker,
      currentVersion: () async => widget.version,
    );
    _wayland = widget.wayland ?? WaylandService();
    _controller =
        ShellController(apps: const [], wayland: _wayland);
    unawaited(_init());
  }

  Future<void> _init() async {
    await _wayland.start();
    if (!mounted || !_wayland.available) return;
    final apps = await widget.externalAppsLoader();
    if (mounted) setState(() => _externalApps = apps);
  }

  @override
  void dispose() {
    _controller.dispose();
    _wayland.dispose();
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
              final builtins = buildShellApps(
                l10n,
                version: widget.version,
                appearance: _appearance,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
              );
              final apps = [...builtins, ..._externalApps];
              _controller.syncApps(apps, pinned: builtins);
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
    return focused?.displayTitle ?? l10n.appName;
  }
}

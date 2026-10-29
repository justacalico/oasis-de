import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'apps/shell_apps.dart';
import 'services/notifications.dart';
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
    this.wallpaper,
    this.wayland,
    this.externalAppsLoader = loadExternalApps,
    this.notificationDaemon,
    this.appDirWatcher,
    this.store,
    this.backend,
  });

  final String version;
  final UpdateChecker? updateChecker;
  final ValueChanged<String>? openUrl;
  final OasisAppearance? appearance;
  final OasisWallpaperService? wallpaper;
  final WaylandService? wayland;
  final Future<List<OasisApp>> Function() externalAppsLoader;
  final NotificationDaemon? notificationDaemon;
  final Stream<void> Function()? appDirWatcher;
  final OasisStore? store;
  final OasisSystemBackend? backend;

  @override
  State<OasisDesktopApp> createState() => _OasisDesktopAppState();
}

class _OasisDesktopAppState extends State<OasisDesktopApp> {
  late final OasisAppearance _appearance;
  late final OasisWallpaperService _wallpaper;
  late final UpdateService _updates;
  late final ShellController _controller;
  late final WaylandService _wayland;
  List<OasisApp> _externalApps = const [];
  late final String? _savedPins = widget.store?.read('shell.pinned');
  Locale? _locale;
  StreamSubscription<void>? _appDirWatch;

  ShellController get controller => _controller;
  WaylandService get wayland => _wayland;

  @override
  void initState() {
    super.initState();
    _appearance = widget.appearance ?? OasisAppearance();
    _wallpaper = widget.wallpaper ?? OasisWallpaperService();
    _updates = UpdateService(
      checker: widget.updateChecker,
      currentVersion: () async => widget.version,
    );
    _wayland = widget.wayland ?? WaylandService();
    _controller = ShellController(
      apps: const [],
      wayland: _wayland,
      backend: widget.backend ?? const CliSystemBackend(),
    );
    _controller.unknownAppName = () =>
        lookupOasisLocalizations(_locale ?? const Locale('en')).appUnknown;
    _controller.launchFailedMessage = (app) =>
        lookupOasisLocalizations(_locale ?? const Locale('en'))
            .launchFailed(app);
    _restoreState();
    _appearance.addListener(_persistState);
    _controller.addListener(_persistState);
    unawaited(_init());
  }

  void _restoreState() {
    final s = widget.store;
    if (s == null) return;
    final c = _controller;
    final mode = OasisThemeMode.values.asNameMap()[s.read('shell.themeMode')];
    if (mode != null) _appearance.themeMode = mode;
    final accent = int.tryParse(s.read('shell.accent') ?? '');
    if (accent != null) _appearance.accent = Color(accent);
    final locale = s.read('shell.locale');
    if (locale != null) {
      _locale = locale.isEmpty ? null : _localeFromTag(locale);
    }
    c.wifiOn = s.read('shell.wifi') != '0';
    c.bluetoothOn = s.read('shell.bluetooth') != '0';
    c.focusOn = s.read('shell.focus') == '1';
    c.nightLightOn = s.read('shell.nightLight') == '1';
    final b = double.tryParse(s.read('shell.brightness') ?? '');
    if (b != null) c.brightness = b;
    final v = double.tryParse(s.read('shell.volume') ?? '');
    if (v != null) c.volume = v;
  }

  final Map<String, String> _persisted = {};

  void _persistState() {
    final s = widget.store;
    if (s == null) return;
    final c = _controller;
    final next = <String, String>{
      'shell.themeMode': _appearance.themeMode.name,
      'shell.accent': '${_appearance.accent?.toARGB32() ?? ''}',
      'shell.locale': _locale?.toLanguageTag() ?? '',
      'shell.wifi': c.wifiOn ? '1' : '0',
      'shell.bluetooth': c.bluetoothOn ? '1' : '0',
      'shell.focus': c.focusOn ? '1' : '0',
      'shell.nightLight': c.nightLightOn ? '1' : '0',
      'shell.brightness': '${c.brightness}',
      'shell.volume': '${c.volume}',
      'shell.pinned': [for (final a in c.pinned) a.id].join(','),
    };
    for (final e in next.entries) {
      if (_persisted[e.key] != e.value) {
        _persisted[e.key] = e.value;
        s.write(e.key, e.value);
      }
    }
  }

  Future<void> _init() async {
    unawaited(
      widget.notificationDaemon?.start(
            onNotify: _controller.pushNotification,
            onClose: _controller.dismissNotification,
          ) ??
          Future.value(),
    );
    await _wayland.start();
    if (!mounted || !_wayland.available) return;
    Future<void> reload() async {
      final apps = await widget.externalAppsLoader();
      if (mounted) setState(() => _externalApps = apps);
    }

    await reload();
    final watcher = widget.appDirWatcher;
    if (watcher != null) {
      _appDirWatch = watcher().listen((_) => reload());
    }
  }

  @override
  void dispose() {
    unawaited(widget.notificationDaemon?.stop() ?? Future.value());
    _appDirWatch?.cancel();
    _appearance.removeListener(_persistState);
    _controller.removeListener(_persistState);
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
          onGenerateTitle: (context) => OasisLocalizations.of(context).appName,
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
                wallpaper: _wallpaper,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
              );
              final apps = [...builtins, ..._externalApps];
              final appsById = {for (final a in apps) a.id: a};
              final savedPins = _savedPins;
              _controller.syncApps(
                apps,
                pinnedIds: savedPins?.split(','),
                fallback: builtins,
              );
              return OasisHost(
                appearance: _appearance,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
                child: Scaffold(
                  body: DesktopShell(
                    controller: _controller,
                    wallpaper: _wallpaper,
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
    _persistState();
  }

  String _focusedAppName(OasisLocalizations l10n) {
    final focused = _controller.focusedWindow;
    return focused?.displayTitle ?? l10n.appName;
  }
}

Locale _localeFromTag(String tag) {
  final parts = tag.split(RegExp('[-_]'));
  String? script;
  String? country;
  for (var i = 1; i < parts.length; i++) {
    final p = parts[i];
    if (script == null && p.length == 4) {
      script = p;
    } else {
      country ??= p;
    }
  }
  return Locale.fromSubtags(
      languageCode: parts[0], scriptCode: script, countryCode: country);
}

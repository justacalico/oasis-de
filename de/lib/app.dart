import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'apps/shell_apps.dart';
import 'services/mpris.dart';
import 'services/notifications.dart';
import 'services/power.dart';
import 'shell/desktop_shell.dart';
import 'services/displays.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_menus.dart';
import 'shell/view_scale.dart';
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
    this.mpris,
    this.appDirWatcher,
    this.store,
    this.backend,
    this.locale,
    this.keybinds,
    this.mouse,
    this.trackpad,
  });

  final String version;
  final UpdateChecker? updateChecker;
  final ValueChanged<String>? openUrl;
  final OasisAppearance? appearance;
  final OasisWallpaperService? wallpaper;
  final WaylandService? wayland;
  final Future<List<OasisApp>> Function() externalAppsLoader;
  final NotificationDaemon? notificationDaemon;
  final MprisService? mpris;
  final Stream<void> Function()? appDirWatcher;
  final OasisStore? store;
  final OasisSystemBackend? backend;
  final Locale? locale;
  final OasisKeybindsService? keybinds;
  final OasisMouseSettings? mouse;
  final OasisTrackpadSettings? trackpad;

  @override
  State<OasisDesktopApp> createState() => _OasisDesktopAppState();
}

class _OasisDesktopAppState extends State<OasisDesktopApp> {
  late final OasisAppearance _appearance;
  late final OasisDockSettings _dock;
  late final OasisWallpaperService _wallpaper;
  late final UpdateService _updates;
  late final ShellController _controller;
  late final WaylandService _wayland;
  late final OasisSystemBackend _backend;
  late final WaylandPowerBackend _powerBackend;
  late final WaylandDisplayBackend _displayBackend;
  late final DisplaysDaemon _displaysDaemon;
  late final MprisService _mpris;
  late final OasisKeybindsService _keybinds;
  late final OasisMouseSettings _mouse;
  late final OasisTrackpadSettings _trackpad;
  var _waylandWasUp = false;
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
    _dock = OasisDockSettings(store: widget.store);
    _wallpaper = widget.wallpaper ?? OasisWallpaperService();
    _updates = UpdateService(
      checker: widget.updateChecker,
      currentVersion: () async => widget.version,
    );
    _wayland = widget.wayland ?? WaylandService();
    _powerBackend = WaylandPowerBackend(_wayland, store: widget.store);
    _mpris = widget.mpris ?? MprisService();
    _backend = widget.backend ?? const CliSystemBackend();
    _keybinds =
        widget.keybinds ?? OasisKeybindsService(store: widget.store);
    _mouse = widget.mouse ?? OasisMouseSettings(store: widget.store);
    _trackpad =
        widget.trackpad ?? OasisTrackpadSettings(store: widget.store);
    _mouse.addListener(_pushPointerConfig);
    _trackpad.addListener(_pushPointerConfig);
    _wayland.addListener(_onWaylandChanged);
    _controller = ShellController(
      apps: const [],
      wayland: _wayland,
      backend: _backend,
      mpris: _mpris,
      dock: _dock,
      keybinds: _keybinds,
    );
    _controller.unknownAppName = () =>
        lookupOasisLocalizations(_locale ?? const Locale('en')).appUnknown;
    _controller.launchFailedMessage = (app) =>
        lookupOasisLocalizations(_locale ?? const Locale('en'))
            .launchFailed(app);
    _locale = widget.locale;
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
    final backend = c.backend;
    final wifi = s.read('shell.wifi');
    if (wifi != null) {
      c.wifiOn = wifi != '0';
      backend.wifi(c.wifiOn);
    }
    final bluetooth = s.read('shell.bluetooth');
    if (bluetooth != null) {
      c.bluetoothOn = bluetooth != '0';
      backend.bluetooth(c.bluetoothOn);
    }
    c.focusOn = s.read('shell.focus') == '1';
    final nightLight = s.read('shell.nightLight');
    if (nightLight != null) {
      c.nightLightOn = nightLight == '1';
      backend.nightLight(c.nightLightOn);
    }
    final b = double.tryParse(s.read('shell.brightness') ?? '');
    if (b != null) {
      c.brightness = b;
      backend.brightness(b);
    }
    final v = double.tryParse(s.read('shell.volume') ?? '');
    if (v != null) {
      c.volume = v;
      backend.volume(v);
    }
    final counts = s.read('shell.launchCounts');
    if (counts != null) {
      for (final part in counts.split(',')) {
        final sep = part.lastIndexOf(':');
        if (sep <= 0) continue;
        final n = int.tryParse(part.substring(sep + 1));
        if (n != null) c.launchCounts[part.substring(0, sep)] = n;
      }
    }
    _powerBackend.restore();
  }

  void _onWaylandChanged() {
    final up = _wayland.available;
    if (up != _waylandWasUp) {
      _waylandWasUp = up;
      _pushPointerConfig();
    }
  }

  void _pushPointerConfig() {
    if (!_wayland.available) return;
    unawaited(_wayland.inputConfig({
      'device': 'mouse',
      'pointerSpeed': _mouse.pointerSpeed,
      'scrollSpeed': _mouse.scrollSpeed,
      'naturalScrolling': _mouse.naturalScrolling,
      'leftHanded': _mouse.primaryButton == OasisPrimaryButton.right,
    }));
    unawaited(_wayland.inputConfig({
      'device': 'trackpad',
      'pointerSpeed': _trackpad.pointerSpeed,
      'scrollSpeed': _trackpad.scrollSpeed,
      'naturalScrolling': _trackpad.naturalScrolling,
      'tapToClick': _trackpad.tapToClick,
      'twoFingerScrolling': _trackpad.twoFingerScrolling,
    }));
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
      'shell.launchCounts': [
        for (final e in c.launchCounts.entries) '${e.key}:${e.value}',
      ].join(','),
    };
    for (final e in next.entries) {
      if (_persisted[e.key] != e.value) {
        _persisted[e.key] = e.value;
        s.write(e.key, e.value);
      }
    }
  }

  Future<void> _init() async {
    _controller.notificationActionHandler = (id, action) => unawaited(
          widget.notificationDaemon?.invokeAction(id, action) ??
              Future.value(),
        );
    _controller.notificationClosedHandler = (id, reason) => unawaited(
          widget.notificationDaemon?.notifyClosed(id, reason) ??
              Future.value(),
        );
    unawaited(
      widget.notificationDaemon?.start(
            onNotify: _controller.pushNotification,
            onClose: (id) => _controller.dismissNotification(id, reason: 3),
          ) ??
          Future.value(),
    );
    unawaited(_wayland.start());
    _displayBackend = WaylandDisplayBackend(
      _wayland,
      store: widget.store,
      onIdentify: _controller.identifyOutputs,
    );
    _displayBackend.restore();
    _displaysDaemon = DisplaysDaemon(
      _displayBackend,
      onIdentify: _controller.identifyOutputs,
    );
    unawaited(_displaysDaemon.start());
    unawaited(_mpris.start());
    if (!mounted) return;
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
    unawaited(_displaysDaemon.stop());
    unawaited(widget.notificationDaemon?.stop() ?? Future.value());
    _appDirWatch?.cancel();
    _appearance.removeListener(_persistState);
    _controller.removeListener(_persistState);
    _mouse.removeListener(_pushPointerConfig);
    _trackpad.removeListener(_pushPointerConfig);
    _wayland.removeListener(_onWaylandChanged);
    _controller.dispose();
    _wayland.dispose();
    _mpris.dispose();
    _keybinds.dispose();
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => OasisLocalizations.of(context).appName,
          theme: _appearance.theme,
          builder: (context, child) => ShellViewScaler(
            wayland: _wayland,
            child: child ?? const SizedBox.shrink(),
          ),
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
                store: widget.store,
                backend: _backend,
                displayBackend: _displayBackend,
                powerBackend: _powerBackend,
                keybinds: _keybinds,
                dock: _dock,
                mouse: _mouse,
                trackpad: _trackpad,
              );
              final apps = [...builtins, ..._externalApps];
              final appsById = {for (final a in apps) a.id: a};
              final savedPins = _savedPins;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _controller.syncApps(
                  apps,
                  pinnedIds: savedPins == null
                      ? null
                      : [
                          for (final p in savedPins.split(','))
                            if (p.isNotEmpty) p,
                        ],
                  fallback: builtins,
                );
              });
              return OasisHost(
                appearance: _appearance,
                updates: _updates,
                setLocale: _setLocale,
                locale: _locale,
                openUrl: widget.openUrl,
                child: Scaffold(
                  body: DesktopShell(
                    controller: _controller,
                    dock: _dock,
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

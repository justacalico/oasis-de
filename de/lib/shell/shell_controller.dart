import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';

export 'shell_constants.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import '../services/mpris.dart';
import '../services/notifications.dart';

import '../wayland/wayland_service.dart';
import 'shell_constants.dart';

enum ShellWindowTransition { none, minimizing, restoring }


const _waylandResizeEdges = {
  1: OasisResizeEdge.top,
  2: OasisResizeEdge.bottom,
  4: OasisResizeEdge.left,
  5: OasisResizeEdge.topLeft,
  6: OasisResizeEdge.bottomLeft,
  8: OasisResizeEdge.right,
  9: OasisResizeEdge.topRight,
  10: OasisResizeEdge.bottomRight,
};

class ShellWindowData {
  ShellWindowData({
    required this.id,
    required this.app,
    required this.position,
    this.workspace = 0,
  });

  final int id;
  OasisApp app;
  Offset position;
  Size? size;
  Size? adoptedSize;
  final dockIconKey = GlobalKey();
  var minimized = false;
  var zoomed = false;
  var fullscreen = false;
  Rect? preSnapRect;
  var workspace = 0;
  var transition = ShellWindowTransition.none;
  var animateGeom = false;
  WaylandSurface? surface;
  var launching = false;
  Timer? launchTimer;

  String get displayTitle =>
      surface != null && surface!.title.isNotEmpty ? surface!.title : app.name;

  bool get clientDecorated => surface?.clientDecorated ?? false;

  double get titleBarHeight =>
      clientDecorated ? 0 : kOasisWindowTitleBarHeight;
}

typedef ShellMenuItem = OasisMenuItem;

typedef ShellMenuAction = void Function(BuildContext context);

class ShellMenu {
  const ShellMenu({required this.label, required this.items});

  final String label;
  final List<ShellMenuItem> Function(BuildContext context) items;
}

class ShellController extends ChangeNotifier {
  ShellController({
    required List<OasisApp> apps,
    this.wayland,
    this.backend = const NoopSystemBackend(),
    this.mpris,
    this.dock,
    OasisKeybindsService? keybinds,
    this.batteryPollInterval = const Duration(seconds: 60),
  })  : apps = List.of(apps),
        keybinds = keybinds ?? OasisKeybindsService() {
    wayland?.addListener(_syncSurfaces);
    wayland?.onIdleSuspend = idleSuspend;
    mpris?.addListener(notifyListeners);
    _requestSub = wayland?.requests.listen(_onWaylandRequest);
    _refreshSystemState();
    if (batteryPollInterval != null) {
      _batteryTimer = Timer.periodic(
        batteryPollInterval!,
        (_) => unawaited(pollBattery()),
      );
    }
  }

  Future<void> pollBattery() async {
    OasisBattery b;
    try {
      b = await backend.battery();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    if (b.level == batteryLevel && b.charging == batteryCharging) return;
    batteryLevel = b.level;
    batteryCharging = b.charging;
    notifyListeners();
  }

  Future<void> _refreshSystemState() async {
    unawaited(pollBattery());
    OasisSystemState s;
    try {
      s = await backend.read();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    if (s.wifi != null) wifiOn = s.wifi!;
    if (s.bluetooth != null) bluetoothOn = s.bluetooth!;
    if (s.brightness != null) brightness = s.brightness!;
    if (s.volume != null) volume = s.volume!;
    if (s.nightLight != null) nightLightOn = s.nightLight!;
    notifyListeners();
  }

  final List<OasisApp> apps;
  final List<OasisApp> pinned = [];
  final List<ShellWindowData> windows = [];
  final WaylandService? wayland;
  final MprisService? mpris;
  final OasisDockSettings? dock;
  final OasisKeybindsService keybinds;
  final Duration? batteryPollInterval;

  String Function() unknownAppName =
      () => lookupOasisLocalizations(const Locale('en')).appUnknown;

  String Function(String) launchFailedMessage = (app) =>
      lookupOasisLocalizations(const Locale('en')).launchFailed(app);

  var _localNotificationId = 0;

  double? batteryLevel;
  bool batteryCharging = false;
  Timer? _batteryTimer;

  final List<OasisNotification> notifications = [];
  OasisNotification? bannerNotification;
  var notificationCenterOpen = false;
  Timer? _bannerTimer;

  void Function(int id, String action)? notificationActionHandler;
  void Function(int id, int reason)? notificationClosedHandler;

  var identifyActive = false;
  var lastPointerPosition = Offset.zero;
  Timer? _identifyTimer;

  void identifyOutputs() {
    _identifyTimer?.cancel();
    identifyActive = true;
    notifyListeners();
    _identifyTimer = Timer(const Duration(seconds: 3), () {
      identifyActive = false;
      notifyListeners();
    });
  }

  final _reportedOutputs = <int, List<int>>{};

  @override
  void notifyListeners() {
    _syncSurfaceOutputs();
    super.notifyListeners();
  }

  void _syncSurfaceOutputs() {
    final wl = wayland;
    if (wl == null || _disposed) return;
    for (final w in windows) {
      final s = w.surface;
      if (s == null || w.workspace != activeWorkspace) continue;
      var rect = w.position & (w.size ?? s.size);
      if (w.zoomed || w.fullscreen) {
        final head = wl.outputAt(rect.center) ?? wl.primaryOutput;
        if (head != null) rect = head.rect;
      }
      final ids = wl
          .outputsFor(rect)
          .map((o) => o.id)
          .toList()
        ..sort();
      if (!listEquals(ids, _reportedOutputs[s.id])) {
        _reportedOutputs[s.id] = ids;
        unawaited(wl.surfaceOutputs(s.id, ids));
      }
    }
  }

  Offset get _spawnOrigin {
    final wl = wayland;
    final o = wl == null
        ? null
        : (wl.outputAt(lastPointerPosition) ?? wl.primaryOutput);
    return o?.rect.topLeft ?? Offset.zero;
  }

  ShellWindowData _spawnWindow(OasisApp app) => ShellWindowData(
        id: _nextId++,
        app: app,
        workspace: activeWorkspace,
        position: _spawnOrigin +
            Offset(
              56 + _cascadeCount * 28.0,
              52 + _cascadeCount * 24.0,
            ),
      );

  void pushNotification(OasisNotification n) {
    if (!n.transient) {
      notifications.removeWhere((o) => o.id == n.id);
      notifications.insert(0, n);
      if (notifications.length > 50) notifications.length = 50;
    }
    if (!focusOn) {
      bannerNotification = n;
      _scheduleBannerDismiss();
    }
    notifyListeners();
  }

  Duration? get _bannerTimeout {
    final n = bannerNotification;
    if (n == null) return null;
    if (n.expireTimeout == 0 || n.urgency >= 2) return null;
    if (n.expireTimeout > 0) {
      return Duration(milliseconds: n.expireTimeout);
    }
    return const Duration(seconds: 5);
  }

  void _scheduleBannerDismiss() {
    _bannerTimer?.cancel();
    final timeout = _bannerTimeout;
    if (timeout == null) return;
    _bannerTimer = Timer(timeout, () {
      if (_disposed) return;
      bannerNotification = null;
      notifyListeners();
    });
  }

  void pauseBannerDismiss() => _bannerTimer?.cancel();

  void resumeBannerDismiss() => _scheduleBannerDismiss();

  void dismissBanner() {
    bannerNotification = null;
    _bannerTimer?.cancel();
    notifyListeners();
  }

  void dismissNotification(int id, {int reason = 2}) {
    if (bannerNotification?.id == id) bannerNotification = null;
    notifications.removeWhere((n) => n.id == id);
    notificationClosedHandler?.call(id, reason);
    notifyListeners();
  }

  void invokeNotificationAction(OasisNotification n, String action) {
    notificationActionHandler?.call(n.id, action);
    dismissNotification(n.id);
  }

  void clearNotifications() {
    final closed = notificationClosedHandler;
    if (closed != null) {
      for (final n in notifications) {
        closed(n.id, 2);
      }
    }
    notifications.clear();
    bannerNotification = null;
    notifyListeners();
  }

  void toggleNotificationCenter() {
    notificationCenterOpen = !notificationCenterOpen;
    if (notificationCenterOpen) {
      launcherOpen = false;
      launchPadOpen = false;
      controlCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  StreamSubscription<WaylandRequest>? _requestSub;
  int _nextId = 1;
  int? _focusedId;
  String? _openMenu;

  /// Logical rect of the menubar label that opened [_openMenu], used to
  /// position the dropdown under the correct output.
  Rect? menuAnchor;
  int? _surfaceDragId;
  ({int id, OasisResizeEdge edge})? _surfaceResize;
  var launcherOpen = false;
  var launchPadOpen = false;
  var controlCenterOpen = false;
  var activeWorkspace = 0;
  var wifiOn = true;
  List<OasisWifiNetwork> wifiNetworks = const [];
  var wifiScanning = false;
  var bluetoothOn = true;
  var focusOn = false;
  var nightLightOn = false;
  var brightness = 0.8;
  var volume = 0.6;
  var _appliedBrightnessPct = -1;
  var _appliedVolumePct = -1;

  int? get focusedId => _focusedId;
  String? get openMenu => _openMenu;
  int? get surfaceDragWindowId => _surfaceDragId;
  ({int id, OasisResizeEdge edge})? get surfaceResize => _surfaceResize;

  var _pinsLoaded = false;
  final List<String> _pendingPinIds = [];

  void syncApps(
    List<OasisApp> fresh, {
    List<String>? pinnedIds,
    List<OasisApp>? fallback,
  }) {
    apps
      ..clear()
      ..addAll(fresh);
    final byId = {for (final a in fresh) a.id: a};
    if (!_pinsLoaded) {
      _pinsLoaded = true;
      if (pinnedIds == null) {
        pinned.addAll(fallback ?? fresh);
      } else {
        for (final id in pinnedIds) {
          final a = byId[id];
          if (a != null) {
            pinned.add(a);
          } else {
            _pendingPinIds.add(id);
          }
        }
      }
    }
    for (var i = _pendingPinIds.length - 1; i >= 0; i--) {
      final a = byId[_pendingPinIds[i]];
      if (a != null) {
        pinned.add(a);
        _pendingPinIds.removeAt(i);
      }
    }
    for (var i = 0; i < pinned.length; i++) {
      final updated = byId[pinned[i].id];
      if (updated != null) pinned[i] = updated;
    }
    for (final w in windows) {
      final updated = byId[w.app.id];
      if (updated != null) w.app = updated;
    }
  }

  ShellWindowData? get focusedWindow {
    final id = _focusedId;
    if (id == null) return null;
    for (final w in windows) {
      if (w.id == id && !w.minimized) return w;
    }
    return null;
  }

  /// Whether an unminimized fullscreen window covers the active
  /// workspace, in which case chrome (menu bar, dock, banner)
  /// stays hidden.
  bool get fullscreenOnActiveWorkspace => windows.any(
        (w) =>
            w.fullscreen &&
            !w.minimized &&
            w.workspace == activeWorkspace,
      );

  final Map<String, int> launchCounts = {};
  String? launchError;

  List<OasisApp> filterApps(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final order = {for (var i = 0; i < apps.length; i++) apps[i].id: i};
      final sorted = [...apps]..sort((a, b) {
          final byCount = (launchCounts[b.id] ?? 0)
              .compareTo(launchCounts[a.id] ?? 0);
          return byCount != 0 ? byCount : order[a.id]! - order[b.id]!;
        });
      return sorted;
    }
    bool fuzzy(String field) {
      var i = 0;
      for (final ch in field.codeUnits) {
        if (i < q.length && ch == q.codeUnitAt(i)) i++;
      }
      return i == q.length;
    }

    int score(OasisApp a) {
      var best = 0;
      final fields = [a.name, ?a.genericName, ...a.keywords];
      for (var i = 0; i < fields.length; i++) {
        final f = fields[i].toLowerCase();
        final tier = f.startsWith(q)
            ? 3
            : f.contains(q)
            ? 2
            : fuzzy(f)
            ? 1
            : 0;
        if (tier == 0) continue;
        final s = tier * 2 + (i == 0 ? 1 : 0);
        if (s > best) best = s;
      }
      return best;
    }

    final scored = <(OasisApp, int)>[];
    for (final a in apps) {
      final s = score(a);
      if (s > 0) scored.add((a, s));
    }
    scored.sort((x, y) {
      final byScore = y.$2.compareTo(x.$2);
      if (byScore != 0) return byScore;
      final byRecency = (launchCounts[y.$1.id] ?? 0).compareTo(
        launchCounts[x.$1.id] ?? 0,
      );
      if (byRecency != 0) return byRecency;
      return x.$1.name.compareTo(y.$1.name);
    });
    return [for (final s in scored) s.$1];
  }

  void openApp(OasisApp app, {bool newWindow = false}) {
    for (final w in windows) {
      if (newWindow) break;
      if (w.app.id == app.id) {
        for (final m in [w, ...transientFamily(w)]) {
          if (m.minimized) {
            m.minimized = false;
            m.transition = ShellWindowTransition.restoring;
          }
        }
        _focus(w.id);
        closeOverlays();
        return;
      }
    }
    ShellWindowData? window;
    if (app.isExternal) {
      final service = wayland;
      if (service == null || !service.available) {
        closeOverlays();
        return;
      }
      window = _spawnWindow(app);
      unawaited(
        service.launch(app.exec!).catchError((Object e) {
          _failLaunch(window!);
        }),
      );
      window.launchTimer = Timer(const Duration(seconds: 8), () {
        if (window!.launching) _failLaunch(window);
      });
    }
    launchCounts[app.id] = (launchCounts[app.id] ?? 0) + 1;
    final w = window ?? _spawnWindow(app);
    w.launching = app.isExternal;
    windows.add(w);
    _focus(w.id);
    closeOverlays();
  }

  void launchAction(List<String> argv) {
    final service = wayland;
    if (service == null) return;
    unawaited(service.launch(argv).catchError((Object _) {}));
  }

  void closeWindow(int id) {
    final window = _byId(id);
    final surface = window?.surface;
    if (surface != null) {
      wayland?.close(surface.id);
    } else {
      windows.removeWhere((w) => w.id == id);
      if (_focusedId == id) {
        _focusedId = null;
        _promoteFocus();
      }
    }
    _pushWaylandFocus();
    notifyListeners();
  }

  void _promoteFocus() {
    if (_focusedId != null) return;
    for (var i = windows.length - 1; i >= 0; i--) {
      final w = windows[i];
      if (!w.minimized && !w.launching && w.workspace == activeWorkspace) {
        _focusedId = w.id;
        return;
      }
    }
  }

  List<ShellWindowData> transientFamily(ShellWindowData root) {
    final out = <ShellWindowData>[];
    void collect(ShellWindowData parent) {
      final pid = parent.surface?.id;
      if (pid == null) return;
      for (final w in windows) {
        if (w.surface?.transientParentId == pid && !out.contains(w)) {
          out.add(w);
          collect(w);
        }
      }
    }

    collect(root);
    return out;
  }

  void _raiseTransients() {
    var moved = true;
    var passes = 0;
    while (moved && passes < windows.length) {
      moved = false;
      passes++;
      for (final w in List.of(windows)) {
        final pid = w.surface?.transientParentId;
        if (pid == null) continue;
        final parent = windowForSurface(pid);
        if (parent == null) continue;
        if (windows.indexOf(w) < windows.indexOf(parent)) {
          windows
            ..remove(w)
            ..add(w);
          moved = true;
        }
      }
    }
  }

  void minimizeWindow(int id) {
    final window = _byId(id);
    if (window == null || window.minimized) return;
    final family = [window, ...transientFamily(window)];
    for (final w in family) {
      w.minimized = true;
      w.transition = ShellWindowTransition.minimizing;
    }
    if (family.any((w) => w.id == _focusedId)) {
      _focusedId = null;
      _promoteFocus();
    }
    _pushWaylandFocus();
    notifyListeners();
  }

  void restoreWindow(int id) {
    final window = _byId(id);
    if (window == null || !window.minimized) return;
    for (final w in [window, ...transientFamily(window)]) {
      w.minimized = false;
      w.transition = ShellWindowTransition.restoring;
    }
    _focus(id);
  }

  void finishTransition(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.transition = ShellWindowTransition.none;
    notifyListeners();
  }

  void toggleFullscreen(int id) {
    final w = _byId(id);
    if (w == null) return;
    w.fullscreen = !w.fullscreen;
    w.adoptedSize = w.surface?.size;
    w.animateGeom = true;
    notifyListeners();
  }

  void toggleZoom(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.zoomed = !window.zoomed;
    window.adoptedSize = window.surface?.size;
    window.animateGeom = true;
    notifyListeners();
  }

  void focusWindow(int id) => _focus(id);

  void _pushWaylandFocus() {
    wayland?.focus(focusedWindow?.surface?.id);
  }

  void _focus(int id) {
    if (_focusedId == id) return;
    final window = _byId(id);
    if (window == null) return;
    _focusedId = id;
    windows.remove(window);
    windows.add(window);
    _raiseTransients();
    _pushWaylandFocus();
    notifyListeners();
  }

  int? _dragWindowId;

  void dragWindow(int id, Offset delta, Size screen) {
    final window = _byId(id);
    if (window == null ||
        window.fullscreen ||
        window.transition != ShellWindowTransition.none) {
      return;
    }
    window.animateGeom = false;
    if (window.zoomed) {
      window.zoomed = false;
      window.position = Offset(
        (screen.width - (window.size?.width ?? 480)) / 2,
        kMenuBarHeight + 4,
      );
      _dragWindowId = id;
      notifyListeners();
      return;
    }
    if (window.preSnapRect != null) {
      window.size = window.preSnapRect!.size;
      window.position = window.preSnapRect!.topLeft;
      window.preSnapRect = null;
    }
    final w = window.size?.width ?? 480;
    window.position = Offset(
      (window.position.dx + delta.dx).clamp(-w + 64, screen.width - 64),
      (window.position.dy + delta.dy)
          .clamp(kMenuBarHeight + 4, screen.height - 24),
    );
    _dragWindowId = id;
    notifyListeners();
  }

  void resizeWindow(int id, Offset delta, OasisResizeEdge edge, Size fallback) {
    final window = _byId(id);
    if (window == null ||
        window.zoomed ||
        window.fullscreen ||
        window.transition != ShellWindowTransition.none) {
      return;
    }
    window.animateGeom = false;
    var minW = kMinWindowWidth;
    var minH = kMinWindowHeight;
    var maxW = double.infinity;
    var maxH = double.infinity;
    final s = window.surface;
    if (s != null) {
      if (s.minSize.width > 0 && s.minSize.height > 0) {
        minW = math.max(minW, s.minSize.width);
        minH = math.max(minH, s.minSize.height + window.titleBarHeight);
      } else if (!s.size.isEmpty) {
        minW = math.min(minW, s.size.width);
        minH = math.min(minH, s.size.height + window.titleBarHeight);
      }
      if (s.maxSize.width > 0 && s.maxSize.height > 0) {
        maxW = s.maxSize.width;
        maxH = s.maxSize.height + window.titleBarHeight;
      }
    }
    final base = window.size ?? fallback;
    final size = Size(
      math.max(minW, math.min(maxW, base.width + delta.dx * edge.dx)),
      math.max(minH, math.min(maxH, base.height + delta.dy * edge.dy)),
    );
    window.position = Offset(
      edge.dx < 0
          ? window.position.dx + base.width - size.width
          : window.position.dx,
      edge.dy < 0
          ? window.position.dy + base.height - size.height
          : window.position.dy,
    );
    window.size = size;
    window.adoptedSize = s?.size;
    notifyListeners();
  }

  void endSurfaceGesture([Offset? pointer, Size? screen]) {
    _surfaceDragId = null;
    _surfaceResize = null;
    final wid = _dragWindowId;
    _dragWindowId = null;
    final w = wid == null ? null : _byId(wid);
    if (w == null || pointer == null || screen == null) return;
    if (pointer.dy <= kMenuBarHeight + 4) {
      if (!w.zoomed) {
        w.zoomed = true;
        w.adoptedSize = w.surface?.size;
        w.animateGeom = true;
        notifyListeners();
      }
    } else if (pointer.dx <= 8 || pointer.dx >= screen.width - 8) {
      final left = pointer.dx <= 8;
      final cur = w.size ?? w.adoptedSize ?? const Size(480, 360);
      var x = left ? 0.0 : screen.width / 2;
      var width = screen.width / 2;
      var height = screen.height - kMenuBarHeight - 8;
      final d = dock;
      if (d == null) {
        height -= kDockHeight;
      } else {
        final inset = dockReservedExtent(d);
        switch (d.position) {
          case OasisDockPosition.bottom:
            height -= inset;
          case OasisDockPosition.left:
            if (left) {
              x += inset;
              width -= inset;
            }
          case OasisDockPosition.right:
            if (!left) width -= inset;
        }
      }
      w
        ..preSnapRect = Rect.fromLTWH(
          w.position.dx,
          w.position.dy,
          cur.width,
          cur.height,
        )
        ..zoomed = false
        ..fullscreen = false
        ..size = Size(width, height)
        ..position = Offset(x, kMenuBarHeight + 4)
        ..adoptedSize = w.surface?.size
        ..animateGeom = true;
      notifyListeners();
    }
  }

  ShellWindowData? windowForSurface(int surfaceId) {
    for (final w in windows) {
      if (w.surface?.id == surfaceId) return w;
    }
    return null;
  }

  ShellWindowData? _byId(int id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  OasisApp _appForSurface(WaylandSurface surface) {
    for (final a in apps) {
      if (a.isExternal &&
          (a.id == 'desktop:${surface.appId}' ||
              a.id == 'desktop:${surface.appId}.desktop')) {
        return a;
      }
    }
    final label = surface.title.isNotEmpty
        ? surface.title
        : (surface.appId.isNotEmpty ? surface.appId : unknownAppName());
    return OasisApp(
      id: 'external:${surface.id}',
      name: label,
      icon: Icons.apps,
      iconColors: const [Color(0xFF8E8E93), Color(0xFF48484A)],
      builder: (_) => const SizedBox.shrink(),
    );
  }

  void _failLaunch(ShellWindowData window) {
    if (!window.launching) return;
    window.launchTimer?.cancel();
    launchError = window.app.name;
    windows.remove(window);
    pushNotification(
      OasisNotification(
        id: --_localNotificationId,
        appName: window.app.name,
        summary: window.app.name,
        body: launchFailedMessage(window.app.name),
        timestamp: clock.now(),
      ),
    );
  }

  void _syncSurfaces() {
    final service = wayland;
    if (service == null) return;
    var changed = false;
    for (var i = windows.length - 1; i >= 0; i--) {
      final w = windows[i];
      final s = w.surface;
      if (s != null && !service.surfaces.containsKey(s.id)) {
        windows.removeAt(i);
        if (_focusedId == w.id) {
          _focusedId = null;
          _promoteFocus();
        }
        changed = true;
      }
    }
    final bound = <int>{
      for (final w in windows)
        if (w.surface != null) w.surface!.id,
    };
    final launching = [
      for (final w in windows)
        if (w.launching) w,
    ];
    for (final s in service.toplevels) {
      if (bound.contains(s.id)) continue;
      ShellWindowData? target;
      if (s.appId.isNotEmpty) {
        final match = _appForSurface(s);
        for (final w in launching) {
          if (w.app.id == match.id) {
            target = w;
            break;
          }
        }
      }
      target ??= launching.isEmpty ? null : launching.first;
      if (target == null) {
        target = _spawnWindow(_appForSurface(s));
        windows.add(target);
      } else {
        launching.remove(target);
      }
      target
        ..surface = s
        ..launching = false
        ..launchTimer?.cancel();
      bound.add(s.id);
      _focus(target.id);
      changed = true;
    }
    for (final w in windows) {
      final s = w.surface;
      if (s != null && s.appId.isNotEmpty && !w.app.isExternal) {
        final match = _appForSurface(s);
        if (match.isExternal) w.app = match;
      }
    }
    for (final w in windows) {
      final s = w.surface;
      if (s == null || w.zoomed || s.size.isEmpty) continue;
      if (s.size == w.adoptedSize) continue;
      w.adoptedSize = s.size;
      final fit = Size(
        s.size.width,
        s.size.height + w.titleBarHeight,
      );
      if (w.size == fit) continue;
      w.size = fit;
      changed = true;
    }
    _raiseTransients();
    final orphanIds = <int>[];
    for (final p in service.popups) {
      var parent = service.surfaces[p.parentId];
      while (parent != null && parent.isPopup) {
        parent = service.surfaces[parent.parentId];
      }
      if (parent == null) orphanIds.add(p.id);
    }
    if (orphanIds.isNotEmpty) {
      scheduleMicrotask(() {
        for (final id in orphanIds) {
          service.close(id);
        }
      });
    }
    if (changed) {
      _pushWaylandFocus();
      notifyListeners();
    }
  }

  void _onWaylandRequest(WaylandRequest request) {
    final w = windowForSurface(request.id);
    if (w == null) return;
    switch (request.type) {
      case WaylandRequestType.move:
        _surfaceDragId = w.id;
      case WaylandRequestType.maximize:
        if (w.zoomed != request.on) {
          w.zoomed = request.on;
          w.adoptedSize = w.surface?.size;
          notifyListeners();
        }
      case WaylandRequestType.fullscreen:
        if (w.fullscreen != request.on) {
          w.fullscreen = request.on;
          w.adoptedSize = w.surface?.size;
          notifyListeners();
        }
      case WaylandRequestType.minimize:
        minimizeWindow(w.id);
      case WaylandRequestType.activate:
        if (w.minimized) restoreWindow(w.id);
        _focus(w.id);
      case WaylandRequestType.resize:
        final edge = _waylandResizeEdges[request.edges];
        if (edge != null) {
          _surfaceResize = (id: w.id, edge: edge);
        }
      case WaylandRequestType.windowMenu:
    }
  }

  void pinApp(String appId) {
    if (pinned.any((a) => a.id == appId)) return;
    for (final a in apps) {
      if (a.id == appId) {
        pinned.add(a);
        notifyListeners();
        return;
      }
    }
  }

  void unpinApp(String appId) {
    if (pinned.isEmpty) return;
    pinned.removeWhere((a) => a.id == appId);
    notifyListeners();
  }

  void movePinned(String dragId, String overId) {
    final from = pinned.indexWhere((a) => a.id == dragId);
    final to = pinned.indexWhere((a) => a.id == overId);
    if (from < 0 || to < 0 || from == to) return;
    pinned.insert(to, pinned.removeAt(from));
    notifyListeners();
  }

  static const workspaceCount = 4;

  void setWorkspace(int i) {
    if (i == activeWorkspace || i < 0 || i >= workspaceCount) {
      return;
    }
    activeWorkspace = i;
    _focusedId = null;
    final visible = [
      for (final w in windows)
        if (w.workspace == i && !w.minimized) w,
    ];
    if (visible.isNotEmpty) _focus(visible.last.id);
    notifyListeners();
  }

  void moveWindowToWorkspace(int id, int i) {
    final w = _byId(id);
    if (w == null || i == w.workspace) return;
    final family = [w, ...transientFamily(w)];
    for (final m in family) {
      m.workspace = i;
    }
    if (family.any((m) => m.id == _focusedId)) _focusedId = null;
    notifyListeners();
  }

  int? _switcherIndex;
  List<ShellWindowData>? _switcherList;
  int? get switcherIndex => _switcherIndex;

  int get _cascadeCount => windows
      .where((w) => w.workspace == activeWorkspace && !w.minimized)
      .length;

  List<ShellWindowData> get switcherWindows {
    final src = _switcherList ?? windows;
    return [
      for (final w in src.reversed)
        if (w.workspace == activeWorkspace && !w.minimized) w,
    ];
  }

  void cycleWindows({bool backwards = false}) {
    _switcherList ??= [...windows];
    _switcherList!.removeWhere((w) => !windows.contains(w));
    final visible = switcherWindows;
    if (visible.isEmpty) {
      closeSwitcher();
      return;
    }
    var idx = _switcherIndex;
    if (idx == null) {
      final cur = visible.indexWhere((w) => w.id == _focusedId);
      idx = backwards ? cur - 1 : cur + 1;
    } else {
      idx += backwards ? -1 : 1;
    }
    _switcherIndex =
        ((idx % visible.length) + visible.length) % visible.length;
    notifyListeners();
  }

  void commitSwitcher() {
    final visible = switcherWindows;
    final idx = _switcherIndex;
    if (idx != null && idx < visible.length) {
      focusWindow(visible[idx].id);
    }
    closeSwitcher();
  }

  void closeSwitcher() {
    if (_switcherIndex == null && _switcherList == null) return;
    _switcherIndex = null;
    _switcherList = null;
    notifyListeners();
  }

  void selectSwitcherWindow(int id) {
    focusWindow(id);
    closeSwitcher();
  }

  void toggleZoomFocused() {
    final w = focusedWindow;
    if (w == null) return;
    w.zoomed = !w.zoomed;
    notifyListeners();
  }

  void quitFocusedApp() {
    final focused = focusedWindow;
    if (focused == null) return;
    final appId = focused.app.id;
    final surfaceAppId = focused.surface?.appId;
    for (final w in List.of(windows)) {
      if (w.app.id == appId ||
          (surfaceAppId != null &&
              surfaceAppId.isNotEmpty &&
              w.surface?.appId == surfaceAppId)) {
        closeWindow(w.id);
      }
    }
  }

  void runKeybindAction(String action) {
    switch (action) {
      case OasisKeybindsService.actionLauncher:
        toggleLauncher();
      case OasisKeybindsService.actionLaunchpad:
        toggleLaunchPad();
      case OasisKeybindsService.actionCycleWindows:
        cycleWindows();
      case OasisKeybindsService.actionCycleWindowsBack:
        cycleWindows(backwards: true);
      case OasisKeybindsService.actionDismiss:
        closeSwitcher();
        closeOverlays();
      case OasisKeybindsService.actionShowDesktop:
        showDesktop();
      case OasisKeybindsService.actionZoom:
        toggleZoomFocused();
      case OasisKeybindsService.actionQuit:
        quitFocusedApp();
      default:
        final command = keybinds.customById(action)?.command;
        if (command != null) {
          final argv = _splitArgv(command);
          if (argv.isNotEmpty) launchAction(argv);
        }
    }
  }

  static List<String> _splitArgv(String command) {
    final argv = <String>[];
    final buf = StringBuffer();
    String? quote;
    for (var i = 0; i < command.length; i++) {
      final ch = command[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buf.write(ch);
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == ' ' || ch == '\t') {
        if (buf.isNotEmpty) {
          argv.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) argv.add(buf.toString());
    return argv;
  }

  final Set<int> _desktopHiddenIds = {};

  void showDesktop() {
    _desktopHiddenIds.removeWhere((id) {
      final w = _byId(id);
      return w == null || !w.minimized;
    });
    if (_desktopHiddenIds.isNotEmpty) {
      for (final id in _desktopHiddenIds.toList()) {
        restoreWindow(id);
      }
      _desktopHiddenIds.clear();
      return;
    }
    for (final w in switcherWindows) {
      if (!w.minimized) {
        _desktopHiddenIds.add(w.id);
        minimizeWindow(w.id);
      }
    }
  }

  void selectMenu(String? label, {Rect? anchor}) {
    if (anchor != null) menuAnchor = anchor;
    if (_openMenu == label) return;
    _openMenu = label;
    if (label != null) {
      launcherOpen = false;
      launchPadOpen = false;
      controlCenterOpen = false;
      notificationCenterOpen = false;
    }
    notifyListeners();
  }

  void toggleLauncher() {
    launcherOpen = !launcherOpen;
    if (launcherOpen) {
      launchPadOpen = false;
      controlCenterOpen = false;
      notificationCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void toggleLaunchPad() {
    launchPadOpen = !launchPadOpen;
    if (launchPadOpen) {
      launcherOpen = false;
      controlCenterOpen = false;
      notificationCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void toggleControlCenter() {
    controlCenterOpen = !controlCenterOpen;
    if (controlCenterOpen) {
      launcherOpen = false;
      launchPadOpen = false;
      notificationCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void closeOverlays() {
    launcherOpen = false;
    launchPadOpen = false;
    controlCenterOpen = false;
    notificationCenterOpen = false;
    _openMenu = null;
    notifyListeners();
  }

  Future<void> refreshWifiNetworks() async {
    if (!wifiOn) {
      if (wifiNetworks.isNotEmpty) {
        wifiNetworks = const [];
        notifyListeners();
      }
      return;
    }
    wifiScanning = true;
    notifyListeners();
    List<OasisWifiNetwork> found;
    try {
      found = await backend.wifiNetworks();
    } catch (_) {
      found = const [];
    }
    if (_disposed) return;
    wifiNetworks = wifiOn ? found : const [];
    wifiScanning = false;
    notifyListeners();
  }

  Future<void> connectWifiNetwork(String ssid) async {
    await backend.connectWifi(ssid);
    if (_disposed) return;
    unawaited(refreshWifiNetworks());
  }

  set wifiOnValue(bool v) => _set(() => wifiOn = v, () => backend.wifi(v));
  set bluetoothOnValue(bool v) =>
      _set(() => bluetoothOn = v, () => backend.bluetooth(v));
  set focusOnValue(bool v) => _set(() => focusOn = v);
  set nightLightOnValue(bool v) =>
      _set(() => nightLightOn = v, () => backend.nightLight(v));

  int _percent(double v) => (v.clamp(0.0, 1.0) * 100).round();

  set brightnessValue(double v) {
    _appliedBrightnessPct = _percent(v);
    _set(() => brightness = v, () => backend.brightness(v));
  }

  set volumeValue(double v) {
    _appliedVolumePct = _percent(v);
    _set(() => volume = v, () => backend.volume(v));
  }

  set brightnessPreview(double v) {
    _set(() => brightness = v);
    final pct = _percent(v);
    if (pct == _appliedBrightnessPct) return;
    _appliedBrightnessPct = pct;
    unawaited(backend.brightness(v));
  }

  set volumePreview(double v) {
    _set(() => volume = v);
    final pct = _percent(v);
    if (pct == _appliedVolumePct) return;
    _appliedVolumePct = pct;
    unawaited(backend.volume(v));
  }

  final OasisSystemBackend backend;

  var locked = false;

  void idleSuspend() => session(OasisSessionAction.suspend);

  void session(OasisSessionAction action) {
    if (action == OasisSessionAction.lock ||
        action == OasisSessionAction.suspend) {
      locked = true;
      if (action == OasisSessionAction.suspend) {
        backend.session(OasisSessionAction.lock);
      }
    }
    backend.session(action);
    notifyListeners();
  }

  int _failedUnlocks = 0;
  DateTime? _unlockLockedUntil;

  Future<bool> tryUnlock(String password) async {
    final until = _unlockLockedUntil;
    if (until != null) {
      final wait = until.difference(clock.now());
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    if (await backend.verifyPassword(password)) {
      locked = false;
      _failedUnlocks = 0;
      await wayland?.sessionUnlock();
      notifyListeners();
      return true;
    }
    _failedUnlocks++;
    _unlockLockedUntil = clock.now().add(
      Duration(milliseconds: 500 * _failedUnlocks),
    );
    return false;
  }

  void _set(void Function() apply, [Future<void> Function()? after]) {
    apply();
    final done = after?.call();
    if (done != null) {
      unawaited(done.then((_) => _refreshSystemState()));
    }
    notifyListeners();
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _bannerTimer?.cancel();
    _batteryTimer?.cancel();
    for (final w in windows) {
      w.launchTimer?.cancel();
    }
    _requestSub?.cancel();
    _identifyTimer?.cancel();
    wayland?.onIdleSuspend = null;
    wayland?.removeListener(_syncSurfaces);
    mpris?.removeListener(notifyListeners);
    super.dispose();
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import '../services/notifications.dart';

import '../wayland/wayland_service.dart';
import 'menu_bar.dart';

enum ShellWindowTransition { none, minimizing, restoring }

const kMinWindowWidth = 360.0;
const kMinWindowHeight = 300.0;

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
  var workspace = 0;
  var transition = ShellWindowTransition.none;
  WaylandSurface? surface;
  var launching = false;
  Timer? launchTimer;

  String get displayTitle =>
      surface != null && surface!.title.isNotEmpty ? surface!.title : app.name;
}

class ShellMenuItem {
  const ShellMenuItem({
    required this.label,
    this.enabled = true,
    this.separatorAfter = false,
    this.checked = false,
    this.action,
  });

  final String label;
  final bool enabled;
  final bool separatorAfter;
  final bool checked;
  final void Function(BuildContext context)? action;
}

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
    this.batteryPollInterval = const Duration(seconds: 60),
  }) : apps = List.of(apps) {
    wayland?.addListener(_syncSurfaces);
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
    final b = await backend.battery();
    if (_disposed) return;
    if (b.level == batteryLevel && b.charging == batteryCharging) return;
    batteryLevel = b.level;
    batteryCharging = b.charging;
    notifyListeners();
  }

  Future<void> _refreshSystemState() async {
    pollBattery();
    final s = await backend.read();
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

  void pushNotification(OasisNotification n) {
    notifications.insert(0, n);
    if (!focusOn) {
      bannerNotification = n;
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 5), () {
        if (_disposed) return;
        bannerNotification = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void dismissNotification(int id) {
    if (bannerNotification?.id == id) bannerNotification = null;
    notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearNotifications() {
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
  int? _surfaceDragId;
  ({int id, OasisResizeEdge edge})? _surfaceResize;
  var launcherOpen = false;
  var launchPadOpen = false;
  var controlCenterOpen = false;
  var activeWorkspace = 0;
  var wifiOn = true;
  var bluetoothOn = true;
  var focusOn = false;
  var nightLightOn = false;
  var brightness = 0.8;
  var volume = 0.6;

  int? get focusedId => _focusedId;
  String? get openMenu => _openMenu;
  int? get surfaceDragWindowId => _surfaceDragId;
  ({int id, OasisResizeEdge edge})? get surfaceResize => _surfaceResize;

  void syncApps(
    List<OasisApp> fresh, {
    List<String>? pinnedIds,
    List<OasisApp>? fallback,
  }) {
    apps
      ..clear()
      ..addAll(fresh);
    final byId = {for (final a in fresh) a.id: a};
    pinned
      ..clear()
      ..addAll(
        pinnedIds == null
            ? fallback ?? fresh
            : [
                for (final id in pinnedIds)
                  if (byId[id] != null) byId[id]!,
              ],
      );
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

  final Map<String, int> launchCounts = {};
  String? launchError;

  List<OasisApp> filterApps(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return apps;
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

    final scored = [
      for (final a in apps)
        if (score(a) > 0) (a, score(a)),
    ];
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
      window = ShellWindowData(
        id: _nextId++,
        app: app,
        position: Offset(
          56 + windows.length * 28.0,
          52 + windows.length * 24.0,
        ),
      );
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
    final w =
        window ??
        ShellWindowData(
          id: _nextId++,
          app: app,
          position: Offset(
            56 + windows.length * 28.0,
            52 + windows.length * 24.0,
          ),
        );
    w.launching = app.isExternal;
    windows.add(w);
    _focus(w.id);
    closeOverlays();
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
    notifyListeners();
  }

  void toggleZoom(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.zoomed = !window.zoomed;
    window.adoptedSize = window.surface?.size;
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
        window.zoomed ||
        window.transition != ShellWindowTransition.none) {
      return;
    }
    final w = window.size?.width ?? 480;
    window.position = Offset(
      (window.position.dx + delta.dx).clamp(-w + 64, screen.width - 64),
      (window.position.dy + delta.dy).clamp(0.0, screen.height - 24),
    );
    _dragWindowId = id;
    notifyListeners();
  }

  void resizeWindow(int id, Offset delta, OasisResizeEdge edge, Size fallback) {
    final window = _byId(id);
    if (window == null ||
        window.zoomed ||
        window.transition != ShellWindowTransition.none) {
      return;
    }
    var minW = kMinWindowWidth;
    var minH = kMinWindowHeight;
    var maxW = double.infinity;
    var maxH = double.infinity;
    final s = window.surface;
    if (s != null) {
      if (s.minSize.width > 0 && s.minSize.height > 0) {
        minW = math.max(minW, s.minSize.width);
        minH = math.max(minH, s.minSize.height + kOasisWindowTitleBarHeight);
      } else if (!s.size.isEmpty) {
        minW = math.min(minW, s.size.width);
        minH = math.min(minH, s.size.height + kOasisWindowTitleBarHeight);
      }
      if (s.maxSize.width > 0 && s.maxSize.height > 0) {
        maxW = s.maxSize.width;
        maxH = s.maxSize.height + kOasisWindowTitleBarHeight;
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
        notifyListeners();
      }
    } else if (pointer.dx <= 8 || pointer.dx >= screen.width - 8) {
      final left = pointer.dx <= 8;
      w
        ..zoomed = false
        ..size = Size(screen.width / 2, screen.height - kMenuBarHeight - 8)
        ..position = Offset(left ? 0 : screen.width / 2, kMenuBarHeight + 4)
        ..adoptedSize = w.surface?.size;
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
        timestamp: DateTime.now(),
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
    for (final s in service.toplevels) {
      if (bound.contains(s.id)) continue;
      ShellWindowData? target;
      final launching = [
        for (final w in windows)
          if (w.launching) w,
      ];
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
      target ??= () {
        final w = ShellWindowData(
          id: _nextId++,
          app: _appForSurface(s),
          position: Offset(
            56 + windows.length * 28.0,
            52 + windows.length * 24.0,
          ),
        );
        windows.add(w);
        return w;
      }();
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
        s.size.height + kOasisWindowTitleBarHeight,
      );
      if (w.size == fit) continue;
      w.size = fit;
      changed = true;
    }
    _raiseTransients();
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
        if (w.workspace == i) w,
    ];
    if (visible.isNotEmpty) _focus(visible.last.id);
    notifyListeners();
  }

  void moveWindowToWorkspace(int id, int i) {
    final w = _byId(id);
    if (w == null || i == w.workspace) return;
    w.workspace = i;
    if (_focusedId == id) _focusedId = null;
    notifyListeners();
  }

  int? _switcherIndex;
  List<ShellWindowData>? _switcherList;
  int? get switcherIndex => _switcherIndex;

  List<ShellWindowData> get switcherWindows {
    final src = _switcherList ?? windows;
    return [
      for (final w in src)
        if (w.workspace == activeWorkspace && !w.minimized) w,
    ];
  }

  void cycleWindows({bool backwards = false}) {
    _switcherList ??= [...windows];
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
    _focus(visible[_switcherIndex!].id);
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

  void selectMenu(String? label) {
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

  set wifiOnValue(bool v) => _set(() => wifiOn = v, () => backend.wifi(v));
  set bluetoothOnValue(bool v) =>
      _set(() => bluetoothOn = v, () => backend.bluetooth(v));
  set focusOnValue(bool v) => _set(() => focusOn = v);
  set nightLightOnValue(bool v) =>
      _set(() => nightLightOn = v, () => backend.nightLight(v));
  set brightnessValue(double v) =>
      _set(() => brightness = v, () => backend.brightness(v));
  set volumeValue(double v) => _set(() => volume = v, () => backend.volume(v));

  final OasisSystemBackend backend;

  var locked = false;

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

  Future<bool> tryUnlock(String password) async {
    if (await backend.verifyPassword(password)) {
      locked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  void _set(void Function() apply, [void Function()? after]) {
    apply();
    after?.call();
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
    wayland?.removeListener(_syncSurfaces);
    super.dispose();
  }
}

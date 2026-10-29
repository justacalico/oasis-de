import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import '../wayland/wayland_service.dart';

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
  });

  final int id;
  OasisApp app;
  Offset position;
  Size? size;
  Size? adoptedSize;
  final dockIconKey = GlobalKey();
  var minimized = false;
  var zoomed = false;
  var transition = ShellWindowTransition.none;
  WaylandSurface? surface;
  var launching = false;

  String get displayTitle =>
      surface != null && surface!.title.isNotEmpty ? surface!.title : app.name;
}

class ShellMenuItem {
  const ShellMenuItem({
    required this.label,
    this.enabled = true,
    this.separatorAfter = false,
    this.action,
  });

  final String label;
  final bool enabled;
  final bool separatorAfter;
  final void Function(BuildContext context)? action;
}

typedef ShellMenuAction = void Function(BuildContext context);

class ShellMenu {
  const ShellMenu({required this.label, required this.items});

  final String label;
  final List<ShellMenuItem> Function(BuildContext context) items;
}

class ShellController extends ChangeNotifier {
  ShellController({required List<OasisApp> apps, this.wayland})
    : apps = List.of(apps) {
    wayland?.addListener(_syncSurfaces);
    _requestSub = wayland?.requests.listen(_onWaylandRequest);
  }

  final List<OasisApp> apps;
  final List<OasisApp> pinned = [];
  final List<ShellWindowData> windows = [];
  final WaylandService? wayland;

  StreamSubscription<WaylandRequest>? _requestSub;
  int _nextId = 1;
  int? _focusedId;
  String? _openMenu;
  int? _surfaceDragId;
  ({int id, OasisResizeEdge edge})? _surfaceResize;
  var launcherOpen = false;
  var launchPadOpen = false;
  var controlCenterOpen = false;
  var wifiOn = true;
  var bluetoothOn = true;
  var focusOn = false;
  var nightLightOn = false;
  var brightness = 0.8;
  var volume = 0.6;
  var batteryPercent = 100;

  int? get focusedId => _focusedId;
  String? get openMenu => _openMenu;
  int? get surfaceDragWindowId => _surfaceDragId;
  ({int id, OasisResizeEdge edge})? get surfaceResize => _surfaceResize;

  void syncApps(List<OasisApp> fresh, {List<OasisApp>? pinned}) {
    apps
      ..clear()
      ..addAll(fresh);
    this.pinned
      ..clear()
      ..addAll(pinned ?? fresh);
    final byId = {for (final a in fresh) a.id: a};
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
      for (final field in [a.name, ?a.genericName, ...a.keywords]) {
        final f = field.toLowerCase();
        final s = f.startsWith(q)
            ? 3
            : f.contains(q)
            ? 2
            : fuzzy(f)
            ? 1
            : 0;
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

  void openApp(OasisApp app) {
    for (final w in windows) {
      if (w.app.id == app.id) {
        if (w.minimized) w.transition = ShellWindowTransition.restoring;
        w.minimized = false;
        _focus(w.id);
        closeOverlays();
        return;
      }
    }
    if (app.isExternal) {
      final service = wayland;
      if (service == null || !service.available) {
        closeOverlays();
        return;
      }
      unawaited(service.launch(app.exec!));
    }
    launchCounts[app.id] = (launchCounts[app.id] ?? 0) + 1;
    final window = ShellWindowData(
      id: _nextId++,
      app: app,
      position: Offset(56 + windows.length * 28.0, 52 + windows.length * 24.0),
    );
    window.launching = app.isExternal;
    windows.add(window);
    _focus(window.id);
    closeOverlays();
  }

  void closeWindow(int id) {
    final window = _byId(id);
    final surface = window?.surface;
    if (surface != null) {
      wayland?.close(surface.id);
    } else {
      windows.removeWhere((w) => w.id == id);
      if (_focusedId == id) _focusedId = null;
    }
    _pushWaylandFocus();
    notifyListeners();
  }

  void minimizeWindow(int id) {
    final window = _byId(id);
    if (window == null || window.minimized) return;
    window.minimized = true;
    window.transition = ShellWindowTransition.minimizing;
    if (_focusedId == id) _focusedId = null;
    _pushWaylandFocus();
    notifyListeners();
  }

  void restoreWindow(int id) {
    final window = _byId(id);
    if (window == null || !window.minimized) return;
    window.minimized = false;
    window.transition = ShellWindowTransition.restoring;
    _focus(id);
  }

  void finishTransition(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.transition = ShellWindowTransition.none;
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
    _pushWaylandFocus();
    notifyListeners();
  }

  void dragWindow(int id, Offset delta) {
    final window = _byId(id);
    if (window == null ||
        window.zoomed ||
        window.transition != ShellWindowTransition.none) {
      return;
    }
    window.position += delta;
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

  void endSurfaceGesture() {
    _surfaceDragId = null;
    _surfaceResize = null;
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
        : (surface.appId.isNotEmpty ? surface.appId : 'Application');
    return OasisApp(
      id: 'external:${surface.id}',
      name: label,
      icon: Icons.apps,
      iconColors: const [Color(0xFF8E8E93), Color(0xFF48484A)],
      builder: (_) => const SizedBox.shrink(),
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
        if (_focusedId == w.id) _focusedId = null;
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
      for (final w in windows) {
        if (w.launching) {
          target = w;
          break;
        }
      }
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
        ..launching = false;
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
      case WaylandRequestType.fullscreen:
        if (w.zoomed != request.on) {
          w.zoomed = request.on;
          w.adoptedSize = w.surface?.size;
          notifyListeners();
        }
      case WaylandRequestType.minimize:
        minimizeWindow(w.id);
      case WaylandRequestType.resize:
        final edge = _waylandResizeEdges[request.edges];
        if (edge != null) {
          _surfaceResize = (id: w.id, edge: edge);
        }
    }
  }

  void selectMenu(String? label) {
    if (_openMenu == label) return;
    _openMenu = label;
    notifyListeners();
  }

  void toggleLauncher() {
    launcherOpen = !launcherOpen;
    if (launcherOpen) {
      launchPadOpen = false;
      controlCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void toggleLaunchPad() {
    launchPadOpen = !launchPadOpen;
    if (launchPadOpen) {
      launcherOpen = false;
      controlCenterOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void toggleControlCenter() {
    controlCenterOpen = !controlCenterOpen;
    if (controlCenterOpen) {
      launcherOpen = false;
      launchPadOpen = false;
      _openMenu = null;
    }
    notifyListeners();
  }

  void closeOverlays() {
    launcherOpen = false;
    launchPadOpen = false;
    controlCenterOpen = false;
    _openMenu = null;
    notifyListeners();
  }

  set wifiOnValue(bool v) => _set(() => wifiOn = v);
  set bluetoothOnValue(bool v) => _set(() => bluetoothOn = v);
  set focusOnValue(bool v) => _set(() => focusOn = v);
  set nightLightOnValue(bool v) => _set(() => nightLightOn = v);
  set brightnessValue(double v) => _set(() => brightness = v);
  set volumeValue(double v) => _set(() => volume = v);

  void _set(void Function() apply) {
    apply();
    notifyListeners();
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    wayland?.removeListener(_syncSurfaces);
    super.dispose();
  }
}

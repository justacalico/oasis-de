import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';

export 'shell_constants.dart';
export 'shell_window.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:oasis_ui/oasis_ui.dart';

import '../services/mpris.dart';
import '../services/notifications.dart';
import '../services/screenshot.dart';

import '../wayland/wayland_service.dart';
import 'shell_constants.dart';
import 'shell_notifications.dart';
import 'shell_window.dart';
import 'system_status.dart';

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
    OasisSystemBackend backend = const NoopSystemBackend(),
    this.mpris,
    this.dock,
    OasisKeybindsService? keybinds,
    ScreenshotService? screenshots,
    Duration? batteryPollInterval = const Duration(seconds: 60),
  }) : apps = List.of(apps),
       keybinds = keybinds ?? OasisKeybindsService(),
       screenshots = screenshots ?? ScreenshotService(wayland: wayland) {
    _status = SystemStatus(
      backend: backend,
      onChanged: notifyListeners,
      onUnlocked: () async {
        await wayland?.sessionUnlock();
      },
      batteryPollInterval: batteryPollInterval,
    );
    _notifications = ShellNotifications(
      onChanged: notifyListeners,
      isFocusOn: () => _status.focusOn,
      onAction: (id, action) => notificationActionHandler?.call(id, action),
      onClosed: (id, reason) => notificationClosedHandler?.call(id, reason),
    );
    wayland?.addListener(_syncSurfaces);
    wayland?.onIdleSuspend = idleSuspend;
    mpris?.addListener(notifyListeners);
    _requestSub = wayland?.requests.listen(_onWaylandRequest);
  }

  final List<OasisApp> apps;
  final List<OasisApp> pinned = [];
  final List<ShellWindowData> windows = [];
  final WaylandService? wayland;
  final MprisService? mpris;
  final OasisDockSettings? dock;
  final OasisKeybindsService keybinds;
  final ScreenshotService screenshots;

  late final SystemStatus _status;
  late final ShellNotifications _notifications;

  String Function() unknownAppName = () =>
      lookupOasisLocalizations(const Locale('en')).appUnknown;

  String Function(String) launchFailedMessage = (app) =>
      lookupOasisLocalizations(const Locale('en')).launchFailed(app);

  String Function() screenshotAppName = () =>
      lookupOasisLocalizations(const Locale('en')).appScreenshot;

  String Function() screenshotSavedTitle = () =>
      lookupOasisLocalizations(const Locale('en')).screenshotSavedTitle;

  String Function() screenshotFailedMessage = () =>
      lookupOasisLocalizations(const Locale('en')).screenshotFailed;

  void Function(int id, String action)? notificationActionHandler;
  void Function(int id, int reason)? notificationClosedHandler;

  var identifyActive = false;
  var lastPointerPosition = Offset.zero;
  Timer? _identifyTimer;

  void identifyOutputs() {
    _identifyTimer?.cancel();
    identifyActive = true;
    notifyListeners();
    _identifyTimer = Timer(kIdentifyDuration, () {
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
      final ids = wl.outputsFor(rect).map((o) => o.id).toList()..sort();
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
    position:
        _spawnOrigin +
        Offset(
          kWindowSpawnX + _cascadeCount * kWindowCascadeX,
          kWindowSpawnY + _cascadeCount * kWindowCascadeY,
        ),
  );

  List<OasisNotification> get notifications => _notifications.items;
  OasisNotification? get bannerNotification => _notifications.banner;

  void pushNotification(OasisNotification n) => _notifications.push(n);

  void dismissBanner() => _notifications.dismissBanner();

  void dismissNotification(int id, {int reason = 2}) =>
      _notifications.dismiss(id, reason: reason);

  void invokeNotificationAction(OasisNotification n, String action) =>
      _notifications.invokeAction(n, action);

  void clearNotifications() => _notifications.clear();

  void pauseBannerDismiss() => _notifications.pauseDismiss();

  void resumeBannerDismiss() => _notifications.resumeDismiss();

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
  ({int id, OasisResizeEdge edge})? _resizeGesture;
  var launcherOpen = false;
  var launchPadOpen = false;
  var controlCenterOpen = false;
  var notificationCenterOpen = false;
  var activeWorkspace = 0;

  int? get focusedId => _focusedId;
  String? get openMenu => _openMenu;
  int? get surfaceDragWindowId => _surfaceDragId;

  /// Active interactive resize grab, whether started by a client's
  /// xdg resize request or by a shell resize grabber.
  ({int id, OasisResizeEdge edge})? get resizeGesture => _resizeGesture;

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
    (w) => w.fullscreen && !w.minimized && w.workspace == activeWorkspace,
  );

  final Map<String, int> launchCounts = {};
  String? launchError;

  List<OasisApp> filterApps(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final order = {for (var i = 0; i < apps.length; i++) apps[i].id: i};
      final sorted = [...apps]
        ..sort((a, b) {
          final byCount = (launchCounts[b.id] ?? 0).compareTo(
            launchCounts[a.id] ?? 0,
          );
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
          if (m.minimized) m.markRestoring();
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
          debugPrint('Oasis: launch of ${app.exec} failed: $e');
          _failLaunch(window!);
        }),
      );
      window.beginLaunch(
        Timer(kLaunchTimeout, () {
          if (window!.launching) _failLaunch(window);
        }),
      );
    }
    launchCounts[app.id] = (launchCounts[app.id] ?? 0) + 1;
    final w = window ?? _spawnWindow(app);
    windows.add(w);
    _focus(w.id);
    closeOverlays();
  }

  void launchAction(List<String> argv) {
    final service = wayland;
    if (service == null) return;
    unawaited(
      service.launch(argv).catchError((Object e) {
        debugPrint('Oasis: launch action failed: $e');
      }),
    );
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
      w.markMinimizing();
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
      w.markRestoring();
    }
    _focus(id);
  }

  void finishTransition(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.finishTransition();
    notifyListeners();
  }

  void toggleFullscreen(int id) {
    final w = _byId(id);
    if (w == null) return;
    w.setFullscreen(!w.fullscreen);
    notifyListeners();
  }

  void toggleZoom(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.setZoomed(!window.zoomed);
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
      window.unzoomTo(
        Offset(
          (screen.width - (window.size?.width ?? kDefaultWindowWidth)) / 2,
          kWindowEdgeTop,
        ),
      );
      _dragWindowId = id;
      notifyListeners();
      return;
    }
    final preSnap = window.takePreSnap();
    if (preSnap != null) {
      window.size = preSnap.size;
      window.position = preSnap.topLeft;
    }
    final w = window.size?.width ?? kDefaultWindowWidth;
    window.position = Offset(
      (window.position.dx + delta.dx).clamp(
        -w + kWindowEdgeMargin,
        screen.width - kWindowEdgeMargin,
      ),
      (window.position.dy + delta.dy).clamp(
        kWindowEdgeTop,
        screen.height - kWindowBottomMargin,
      ),
    );
    _dragWindowId = id;
    notifyListeners();
  }

  void beginResize(int id, OasisResizeEdge edge) {
    if (_byId(id) == null || _resizeGesture == (id: id, edge: edge)) {
      return;
    }
    _resizeGesture = (id: id, edge: edge);
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
    final wasResizing = _resizeGesture != null;
    _surfaceDragId = null;
    _resizeGesture = null;
    if (wasResizing) notifyListeners();
    final wid = _dragWindowId;
    _dragWindowId = null;
    final w = wid == null ? null : _byId(wid);
    if (w == null || pointer == null || screen == null) return;
    if (pointer.dy <= kWindowEdgeTop) {
      if (!w.zoomed) {
        w.setZoomed(true);
        notifyListeners();
      }
    } else if (pointer.dx <= kSnapEdgeWidth ||
        pointer.dx >= screen.width - kSnapEdgeWidth) {
      final left = pointer.dx <= kSnapEdgeWidth;
      final cur =
          w.size ??
          w.adoptedSize ??
          const Size(kDefaultWindowWidth, kDefaultWindowHeight);
      var x = left ? 0.0 : screen.width / 2;
      var width = screen.width / 2;
      var height = screen.height - kMenuBarHeight - kSnapBottomMargin;
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
      w.snapTo(
        preSnap: Rect.fromLTWH(
          w.position.dx,
          w.position.dy,
          cur.width,
          cur.height,
        ),
        position: Offset(x, kWindowEdgeTop),
        size: Size(width, height),
      );
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
    window.cancelLaunch();
    launchError = window.app.name;
    windows.remove(window);
    pushNotification(
      OasisNotification(
        id: _notifications.nextLocalId(),
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
        if (_resizeGesture?.id == w.id) _resizeGesture = null;
        if (_surfaceDragId == w.id) _surfaceDragId = null;
        if (_dragWindowId == w.id) _dragWindowId = null;
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
      target.bindSurface(s);
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
      if (s == null || w.zoomed || w.fullscreen || s.size.isEmpty) {
        continue;
      }
      if (_resizeGesture?.id == w.id) continue;
      if (s.size == w.adoptedSize) continue;
      w.adoptedSize = s.size;
      var fit = Size(s.size.width, s.size.height + w.titleBarHeight);
      final bound = _workAreaSize(w);
      if (bound != null) {
        fit = Size(
          math.min(fit.width, bound.width),
          math.min(fit.height, bound.height),
        );
      }
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

  /// Work area available to a floating window on the head [w] sits on:
  /// output rect minus menu bar, layer-exclusive insets and, on the
  /// primary head, the dock. Client-chosen sizes are clamped to this so
  /// a window can never map bigger than the screen.
  Size? _workAreaSize(ShellWindowData w) {
    final wl = wayland;
    final center = w.position + (w.size ?? Size.zero).center(Offset.zero);
    final head = (wl?.outputAt(center) ?? wl?.primaryOutput)?.rect;
    if (wl == null || head == null) return null;
    final insets = wl.exclusiveInsets;
    var width = head.width - insets.horizontal;
    var height = head.height - kMenuBarHeight - 8 - insets.vertical;
    if (head == wl.primaryOutput?.rect) {
      final d = dock;
      if (d == null) {
        height -= kDockHeight;
      } else {
        final extent = dockReservedExtent(d);
        switch (d.position) {
          case OasisDockPosition.left:
          case OasisDockPosition.right:
            width -= extent;
          case OasisDockPosition.bottom:
            height -= extent;
        }
      }
    }
    return Size(width, height);
  }

  void _onWaylandRequest(WaylandRequest request) {
    final w = windowForSurface(request.id);
    if (w == null) return;
    switch (request.type) {
      case WaylandRequestType.move:
        _surfaceDragId = w.id;
      case WaylandRequestType.maximize:
        if (w.zoomed != request.on) {
          w.setZoomed(request.on, animate: false);
          notifyListeners();
        }
      case WaylandRequestType.fullscreen:
        if (w.fullscreen != request.on) {
          w.setFullscreen(request.on, animate: false);
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
          beginResize(w.id, edge);
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
    if (family.any((m) => m.id == _focusedId)) {
      _focusedId = null;
      _promoteFocus();
      _pushWaylandFocus();
    }
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
      var cur = visible.indexWhere((w) => w.id == _focusedId);
      if (cur < 0) cur = backwards ? visible.length : -1;
      idx = backwards ? cur - 1 : cur + 1;
    } else {
      idx += backwards ? -1 : 1;
    }
    _switcherIndex = ((idx % visible.length) + visible.length) % visible.length;
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
    w.setZoomed(!w.zoomed, animate: false);
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

  /// Whether the snip overlay is up waiting for a region drag.
  var snipActive = false;
  Timer? _snipDelay;
  var _snipInFlight = false;

  /// Entry point for the Screenshot window: parks the app's own
  /// windows so they don't land in the frame, then starts the chosen
  /// capture flow.
  void requestScreenshot(ScreenshotMode mode, {int delaySeconds = 0}) {
    for (final w in windows) {
      if (w.app.id == kScreenshotAppId && !w.minimized) {
        minimizeWindow(w.id);
      }
    }
    if (mode == ScreenshotMode.fullscreen) {
      captureFullscreen(delaySeconds: delaySeconds);
    } else {
      beginSnip(delaySeconds: delaySeconds);
    }
  }

  void beginSnip({int delaySeconds = 0}) {
    _snipDelay?.cancel();
    if (delaySeconds > 0) {
      _snipDelay = Timer(Duration(seconds: delaySeconds), () {
        _snipDelay = null;
        _armSnip();
      });
      return;
    }
    _armSnip();
  }

  void _armSnip() {
    closeOverlays();
    snipActive = true;
    notifyListeners();
  }

  void cancelSnip() {
    _snipDelay?.cancel();
    _snipDelay = null;
    if (!snipActive) return;
    snipActive = false;
    _restoreScreenshotWindows();
    notifyListeners();
  }

  /// Called by the snip overlay once the user lets go of a selection.
  void completeSnip(Rect region) => unawaited(_capture(region));

  void captureFullscreen({int delaySeconds = 0}) {
    _snipDelay?.cancel();
    _snipDelay = Timer(Duration(seconds: delaySeconds), () {
      _snipDelay = null;
      unawaited(_capture(_fullRegion()));
    });
  }

  Rect? _fullRegion() {
    Rect? bounds;
    for (final o in wayland?.outputs ?? const <OasisOutput>[]) {
      if (!o.enabled) continue;
      bounds = bounds?.expandToInclude(o.rect) ?? o.rect;
    }
    return bounds;
  }

  Future<void> _capture(Rect? region) async {
    if (_snipInFlight) return;
    _snipInFlight = true;
    snipActive = false;
    notifyListeners();
    // The overlay is drawn by the shell itself, so it has to be gone
    // from the framebuffer before pixels are read back.
    await Future<void>.delayed(kScreenshotSettle);
    String? path;
    if (region != null) path = await screenshots.captureRegion(region);
    _snipInFlight = false;
    // Restoring the app's windows animates them through the dock, which
    // trips over a notification banner appearing in the same layout
    // pass — let it land a frame later instead.
    WidgetsBinding.instance
      ..scheduleFrame()
      ..addPostFrameCallback((_) {
        if (!_disposed) _restoreScreenshotWindows();
      });
    pushNotification(
      OasisNotification(
        id: _notifications.nextLocalId(),
        appName: screenshotAppName(),
        summary: path == null
            ? screenshotFailedMessage()
            : screenshotSavedTitle(),
        body: path ?? '',
        timestamp: clock.now(),
      ),
    );
  }

  void _restoreScreenshotWindows() {
    for (final w in windows) {
      if (w.app.id == kScreenshotAppId && w.minimized) {
        restoreWindow(w.id);
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
      case OasisKeybindsService.actionScreenshot:
        beginSnip();
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
    cancelSnip();
    launcherOpen = false;
    launchPadOpen = false;
    controlCenterOpen = false;
    notificationCenterOpen = false;
    _openMenu = null;
    notifyListeners();
  }

  OasisSystemBackend get backend => _status.backend;
  double? get batteryLevel => _status.batteryLevel;
  bool get batteryCharging => _status.batteryCharging;
  Future<void> pollBattery() => _status.pollBattery();

  List<OasisWifiNetwork> get wifiNetworks => _status.wifiNetworks;
  bool get wifiScanning => _status.wifiScanning;
  bool get wifiOn => _status.wifiOn;
  set wifiOn(bool v) => _status.wifiOn = v;
  bool get bluetoothOn => _status.bluetoothOn;
  set bluetoothOn(bool v) => _status.bluetoothOn = v;
  bool get focusOn => _status.focusOn;
  set focusOn(bool v) => _status.focusOn = v;
  bool get nightLightOn => _status.nightLightOn;
  set nightLightOn(bool v) => _status.nightLightOn = v;
  double get brightness => _status.brightness;
  set brightness(double v) => _status.brightness = v;
  double get volume => _status.volume;
  set volume(double v) => _status.volume = v;

  set wifiOnValue(bool v) => _status.wifiOnValue = v;
  set bluetoothOnValue(bool v) => _status.bluetoothOnValue = v;
  set focusOnValue(bool v) => _status.focusOnValue = v;
  set nightLightOnValue(bool v) => _status.nightLightOnValue = v;
  set brightnessValue(double v) => _status.brightnessValue = v;
  set volumeValue(double v) => _status.volumeValue = v;
  set brightnessPreview(double v) => _status.brightnessPreview = v;
  set volumePreview(double v) => _status.volumePreview = v;

  Future<void> refreshWifiNetworks() => _status.refreshWifiNetworks();

  Future<void> connectWifiNetwork(String ssid) =>
      _status.connectWifiNetwork(ssid);

  bool get locked => _status.locked;

  void idleSuspend() => _status.idleSuspend();

  void session(OasisSessionAction action) => _status.session(action);

  Future<bool> tryUnlock(String password) => _status.tryUnlock(password);

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _notifications.dispose();
    _status.dispose();
    for (final w in windows) {
      w.cancelLaunch();
    }
    _requestSub?.cancel();
    _identifyTimer?.cancel();
    _snipDelay?.cancel();
    screenshots.dispose();
    wayland?.onIdleSuspend = null;
    wayland?.removeListener(_syncSurfaces);
    mpris?.removeListener(notifyListeners);
    super.dispose();
  }
}

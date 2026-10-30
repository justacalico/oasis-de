import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wayland_host.dart';

class WaylandSurface {
  WaylandSurface({
    required this.id,
    this.textureId = -1,
    this.parentId,
    this.isSub = false,
    this.title = '',
    this.appId = '',
    this.offset = Offset.zero,
    this.size = Size.zero,
  });

  final int id;
  int textureId;
  final int? parentId;
  int? transientParentId;
  final bool isSub;
  final List<int> children = [];
  String title;
  String appId;
  Offset offset;
  Size size;
  Size bufferSize = Size.zero;
  Offset geoOffset = Offset.zero;
  double scale = 1;
  int transform = 0;
  List<Rect>? inputRegion;
  bool idleInhibit = false;
  Size minSize = Size.zero;
  Size maxSize = Size.zero;

  bool get isPopup => parentId != null && !isSub;
}

enum WaylandRequestType {
  move,
  resize,
  maximize,
  fullscreen,
  minimize,
  windowMenu,
  activate,
}

class WaylandRequest {
  const WaylandRequest(
    this.type,
    this.id, {
    this.on = false,
    this.edges = 0,
    this.x = 0,
    this.y = 0,
  });

  final WaylandRequestType type;
  final int id;
  final bool on;
  final int edges;
  final double x;
  final double y;
}

class WaylandCursor {
  const WaylandCursor({
    required this.textureId,
    required this.size,
    required this.hotspot,
  });

  final int textureId;
  final Size size;
  final Offset hotspot;
}

class WaylandService extends ChangeNotifier {
  WaylandService({WaylandHost? host})
    : _host = host ?? const ChannelWaylandHost();

  final WaylandHost _host;
  final Map<int, WaylandSurface> surfaces = {};
  final Map<int, List<int>> _pendingSubs = {};
  final _requests = StreamController<WaylandRequest>.broadcast();
  StreamSubscription<Map<String, Object?>>? _sub;
  WaylandCursor? cursor;
  int cursorShape = 0;

  var socket = '';
  var started = false;

  Stream<WaylandRequest> get requests => _requests.stream;
  bool get available => socket.isNotEmpty;

  Future<void> start() async {
    if (started) return;
    started = true;
    String? name;
    try {
      name = await _host.start();
    } on MissingPluginException {
      name = null;
    } on PlatformException {
      name = null;
    }
    socket = name ?? '';
    if (available) {
      _sub = _host.events.listen(_onEvent);
    }
    notifyListeners();
  }

  List<WaylandSurface> get toplevels => surfaces.values
      .where((s) => !s.isPopup && !s.isSub)
      .toList(growable: false);

  List<WaylandSurface> get popups =>
      surfaces.values.where((s) => s.isPopup).toList(growable: false);

  void _onEvent(Map<String, Object?> e) {
    final id = (e['id'] as num?)?.toInt() ?? -1;
    switch (e['event']) {
      case 'toplevel':
        final parentId = (e['parent'] as num?)?.toInt() ?? -1;
        surfaces[id] = WaylandSurface(
          id: id,
          textureId: (e['textureId'] as num?)?.toInt() ?? -1,
          title: e['title'] as String? ?? '',
          appId: e['appId'] as String? ?? '',
        )..transientParentId = parentId >= 0 ? parentId : null;
        final adoptees = _pendingSubs.remove(id);
        if (adoptees != null) surfaces[id]!.children.addAll(adoptees);
      case 'toplevelParent':
        final parentId = (e['parent'] as num?)?.toInt() ?? -1;
        surfaces[id]?.transientParentId = parentId >= 0 ? parentId : null;
      case 'toplevelClosed':
        surfaces.remove(id);
      case 'title':
        surfaces[id]?.title = e['title'] as String? ?? '';
      case 'appId':
        surfaces[id]?.appId = e['appId'] as String? ?? '';
      case 'size':
        final s = surfaces[id];
        if (s != null) {
          s.size = Size((e['w'] as num).toDouble(), (e['h'] as num).toDouble());
          s.bufferSize = Size(
            (e['bw'] as num?)?.toDouble() ?? s.size.width,
            (e['bh'] as num?)?.toDouble() ?? s.size.height,
          );
          s.geoOffset = Offset(
            (e['gx'] as num?)?.toDouble() ?? 0,
            (e['gy'] as num?)?.toDouble() ?? 0,
          );
          final scale = (e['scale'] as num?)?.toDouble();
          if (scale != null && scale > 0) s.scale = scale;
          s.transform = (e['transform'] as num?)?.toInt() ?? 0;
        }
      case 'cursor':
        final tex = (e['texture'] as num?)?.toInt() ?? -1;
        cursor = id != 0 && tex >= 0
            ? WaylandCursor(
                textureId: tex,
                size: Size(
                  (e['w'] as num).toDouble(),
                  (e['h'] as num).toDouble(),
                ),
                hotspot: Offset(
                  (e['hx'] as num).toDouble(),
                  (e['hy'] as num).toDouble(),
                ),
              )
            : null;
      case 'cursorShape':
        cursorShape = (e['shape'] as num?)?.toInt() ?? 0;
      case 'idleInhibit':
        final s = surfaces[id];
        if (s != null) s.idleInhibit = e['on'] == true;
      case 'inputRegion':
        final s = surfaces[id];
        final rects = e['rects'] as List<Object?>?;
        if (s != null) {
          s.inputRegion = rects == null
              ? null
              : [
                  for (var i = 0; i + 3 < rects.length; i += 4)
                    Rect.fromLTWH(
                      (rects[i] as num).toDouble(),
                      (rects[i + 1] as num).toDouble(),
                      (rects[i + 2] as num).toDouble(),
                      (rects[i + 3] as num).toDouble(),
                    ),
                ];
        }
      case 'minSize':
        final s = surfaces[id];
        if (s != null) {
          s.minSize = Size(
            (e['w'] as num).toDouble(),
            (e['h'] as num).toDouble(),
          );
        }
      case 'maxSize':
        final s = surfaces[id];
        if (s != null) {
          s.maxSize = Size(
            (e['w'] as num).toDouble(),
            (e['h'] as num).toDouble(),
          );
        }
      case 'popup':
        surfaces[id] = WaylandSurface(
          id: id,
          textureId: (e['textureId'] as num?)?.toInt() ?? -1,
          parentId: (e['parent'] as num).toInt(),
          offset: Offset(
            (e['x'] as num).toDouble(),
            (e['y'] as num).toDouble(),
          ),
        );
        final adoptees = _pendingSubs.remove(id);
        if (adoptees != null) surfaces[id]!.children.addAll(adoptees);
      case 'popupMoved':
      case 'subsurfaceMoved':
        final s = surfaces[id];
        if (s != null) {
          s.offset = Offset(
            (e['x'] as num).toDouble(),
            (e['y'] as num).toDouble(),
          );
        }
      case 'popupClosed':
        surfaces.remove(id);
      case 'subsurface':
        final sub = WaylandSurface(
          id: id,
          parentId: (e['parent'] as num).toInt(),
          isSub: true,
          offset: Offset(
            (e['x'] as num).toDouble(),
            (e['y'] as num).toDouble(),
          ),
        );
        surfaces[id] = sub;
        final parent = surfaces[sub.parentId];
        if (parent != null) {
          parent.children.add(id);
        } else {
          (_pendingSubs[sub.parentId!] ??= []).add(id);
        }
        final adoptees = _pendingSubs.remove(id);
        if (adoptees != null) surfaces[id]!.children.addAll(adoptees);
      case 'childrenReordered':
        final s = surfaces[id];
        final order = e['children'] as List<Object?>?;
        if (s != null && order != null) {
          s.children
            ..clear()
            ..addAll(order.map((v) => (v as num).toInt()));
        }
      case 'subsurfaceClosed':
        final s = surfaces.remove(id);
        if (s?.parentId != null) {
          surfaces[s!.parentId]?.children.remove(id);
        }
        for (final pending in _pendingSubs.values) {
          pending.remove(id);
        }
      case 'texture':
        surfaces[id]?.textureId = (e['textureId'] as num?)?.toInt() ?? -1;
      case 'move':
        _requests.add(WaylandRequest(WaylandRequestType.move, id));
      case 'resize':
        _requests.add(
          WaylandRequest(
            WaylandRequestType.resize,
            id,
            edges: (e['edges'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'maximize':
        _requests.add(
          WaylandRequest(WaylandRequestType.maximize, id, on: e['on'] == true),
        );
      case 'fullscreen':
        _requests.add(
          WaylandRequest(
            WaylandRequestType.fullscreen,
            id,
            on: e['on'] == true,
          ),
        );
      case 'minimize':
        _requests.add(WaylandRequest(WaylandRequestType.minimize, id));
      case 'activate':
        _requests.add(WaylandRequest(WaylandRequestType.activate, id));
      case 'windowMenu':
        _requests.add(
          WaylandRequest(
            WaylandRequestType.windowMenu,
            id,
            x: (e['x'] as num?)?.toDouble() ?? 0,
            y: (e['y'] as num?)?.toDouble() ?? 0,
          ),
        );
    }
    notifyListeners();
  }

  Future<void> launch(List<String> argv) =>
      available ? _host.launch(argv) : Future.value();

  Future<void> configure(
    int id,
    int width,
    int height, {
    bool maximized = false,
    bool fullscreen = false,
    bool resizing = false,
  }) => available
      ? _host.configure(
          id,
          width,
          height,
          maximized: maximized,
          fullscreen: fullscreen,
          resizing: resizing,
        )
      : Future.value();

  Future<void> close(int id) => available ? _host.close(id) : Future.value();

  Future<void> focus(int? id) => available ? _host.focus(id) : Future.value();

  Future<void> pointerMotion(int id, double x, double y) =>
      available ? _host.pointerMotion(id, x, y) : Future.value();

  Future<void> pointerExit(int id) =>
      available ? _host.pointerExit(id) : Future.value();

  Future<void> pointerButton(int button, bool pressed) =>
      available ? _host.pointerButton(button, pressed) : Future.value();

  Future<void> pointerAxis(double dx, double dy) =>
      available ? _host.pointerAxis(dx, dy) : Future.value();

  Future<void> key(int code, bool pressed) =>
      available ? _host.key(code, pressed) : Future.value();

  @override
  void dispose() {
    _sub?.cancel();
    _requests.close();
    super.dispose();
  }
}

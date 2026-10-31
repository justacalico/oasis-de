import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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
  Rect? vpSrc;
  int ackedSerial = 0;
  double scale = 1;
  int transform = 0;
  List<Rect>? inputRegion;
  bool idleInhibit = false;
  bool shortcutsInhibited = false;
  Size minSize = Size.zero;
  Size maxSize = Size.zero;

  bool isLayer = false;
  bool isLock = false;
  int layerIndex = 0;
  String layerNamespace = '';
  int layerAnchor = 0;
  int layerExclusive = 0;
  int layerExclusiveEdge = 0;
  EdgeInsets layerMargins = EdgeInsets.zero;
  int layerKeyboard = 0;
  Size layerDesired = Size.zero;
  int outputId = -1;
  Rect? layerRect;

  bool get isPopup => parentId != null && !isSub && !isLayer && !isLock;
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

class OasisOutputMode {
  const OasisOutputMode({
    required this.width,
    required this.height,
    required this.refreshMhz,
    this.preferred = false,
  });

  final int width;
  final int height;
  final int refreshMhz;
  final bool preferred;

  String get label => '${width}x$height';
}

class OasisOutput {
  const OasisOutput({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.primary = false,
    this.powered = true,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.scale = 1,
    this.refreshMhz = 60000,
    this.transform = 0,
    this.physWidthMm = 0,
    this.physHeightMm = 0,
    this.modes = const [],
  });

  final int id;
  final String name;
  final String description;
  final bool enabled;
  final bool primary;
  final bool powered;
  final int x;
  final int y;
  final int width;
  final int height;
  final double scale;
  final int refreshMhz;
  final int transform;
  final int physWidthMm;
  final int physHeightMm;
  final List<OasisOutputMode> modes;

  Rect get rect =>
      Rect.fromLTWH(x.toDouble(), y.toDouble(),
          width.toDouble(), height.toDouble());

  bool contains(Offset point) => rect.contains(point);
}

class WaylandService extends ChangeNotifier {
  WaylandService({WaylandHost? host})
    : _host = host ?? const ChannelWaylandHost();

  final WaylandHost _host;
  final Map<int, WaylandSurface> surfaces = {};
  final Map<int, List<int>> _pendingSubs = {};
  bool _notifyQueued = false;
  bool _disposed = false;

  void _queueNotify() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }
  final _requests = StreamController<WaylandRequest>.broadcast();
  StreamSubscription<Map<String, Object?>>? _sub;
  WaylandCursor? cursor;
  int cursorShape = 0;
  bool pointerOverClient = false;
  bool pointerLocked = false;

  var socket = '';
  var started = false;
  List<OasisOutput> outputs = const [];
  bool _starting = false;
  Timer? _retryTimer;
  Completer<void>? _retryWait;
  int? _idleOffMs;
  int? _idleSuspendMs;

  /// Fired when the compositor's idle suspend timer expires.
  void Function()? onIdleSuspend;

  Stream<WaylandRequest> get requests => _requests.stream;
  bool get available => socket.isNotEmpty;

  Future<void> start() async {
    if (started || _starting) return;
    _starting = true;
    try {
      for (var attempt = 0; attempt < 5 && !_disposed; attempt++) {
        String? name;
        try {
          name = await _host.start();
        } on MissingPluginException {
          name = null;
        } on PlatformException {
          name = null;
        }
        if (name != null && name.isNotEmpty) {
          socket = name;
          started = true;
          _sub = _host.events.listen(_onEvent);
          final off = _idleOffMs;
          if (off != null) {
            unawaited(
              _host.setIdleTimeouts(off, _idleSuspendMs ?? 0),
            );
          }
          notifyListeners();
          return;
        }
        _retryWait = Completer<void>();
        _retryTimer = Timer(
          Duration(milliseconds: 400 * (attempt + 1)),
          () => _retryWait?.complete(),
        );
        await _retryWait!.future;
        _retryTimer = null;
        _retryWait = null;
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (available) await _host.stop();
    socket = '';
    started = false;
    if (!_disposed) notifyListeners();
  }

  List<WaylandSurface> get toplevels => surfaces.values
      .where((s) => !s.isPopup && !s.isSub && !s.isLayer && !s.isLock)
      .toList(growable: false);

  List<WaylandSurface> get popups =>
      surfaces.values.where((s) => s.isPopup).toList(growable: false);

  List<WaylandSurface> layerSurfaces(int layer) => surfaces.values
      .where((s) => s.isLayer && s.layerIndex == layer)
      .toList(growable: false);

  List<WaylandSurface> get lockSurfaces => surfaces.values
      .where((s) => s.isLock)
      .toList(growable: false);

  bool sessionLocked = false;
  bool displayOff = false;

  OasisOutput? get primaryOutput {
    for (final o in outputs) {
      if (o.enabled && o.primary) return o;
    }
    for (final o in outputs) {
      if (o.enabled) return o;
    }
    return outputs.isEmpty ? null : outputs.first;
  }

  OasisOutput? outputAt(Offset point, {Size? size}) {
    Rect? area;
    if (size != null) {
      area = point & size;
    }
    for (final o in outputs) {
      if (!o.enabled) continue;
      if (area != null) {
        if (o.rect.overlaps(area)) return o;
      } else if (o.contains(point)) {
        return o;
      }
    }
    return primaryOutput;
  }

  List<OasisOutput> outputsFor(Rect rect) => [
        for (final o in outputs)
          if (o.enabled && o.rect.overlaps(rect)) o,
      ];

  EdgeInsets get exclusiveInsets => exclusiveInsetsFor(-1);

  EdgeInsets exclusiveInsetsFor(int outputId) {
    var left = 0.0, top = 0.0, right = 0.0, bottom = 0.0;
    for (final s in surfaces.values) {
      if (outputId >= 0 && s.outputId >= 0 && s.outputId != outputId) {
        continue;
      }
      if (!s.isLayer || s.layerExclusive <= 0 || s.size.isEmpty) {
        continue;
      }
      final edge = s.layerExclusiveEdge != 0
          ? s.layerExclusiveEdge
          : s.layerAnchor;
      final zone = s.layerExclusive.toDouble();
      if (edge == 1) {
        top = zone > top ? zone : top;
      } else if (edge == 2) {
        bottom = zone > bottom ? zone : bottom;
      } else if (edge == 4) {
        left = zone > left ? zone : left;
      } else if (edge == 8) {
        right = zone > right ? zone : right;
      }
    }
    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }

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
          final vsw = (e['vsw'] as num?)?.toDouble() ?? -1;
          final vsh = (e['vsh'] as num?)?.toDouble() ?? -1;
          s.vpSrc = vsw > 0 && vsh > 0
              ? Rect.fromLTWH(
                  (e['vsx'] as num?)?.toDouble() ?? 0,
                  (e['vsy'] as num?)?.toDouble() ?? 0,
                  vsw,
                  vsh,
                )
              : null;
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
      case 'shortcutsInhibit':
        surfaces[id]?.shortcutsInhibited = e['on'] == true;
      case 'pointerLock':
        pointerLocked = e['on'] == true;
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
      case 'layer':
        final s = surfaces.putIfAbsent(id, () => WaylandSurface(id: id))
          ..isLayer = true;
        s.textureId = (e['textureId'] as num?)?.toInt() ?? s.textureId;
        s.layerNamespace = e['ns'] as String? ?? '';
        s.layerIndex = (e['layer'] as num?)?.toInt() ?? 0;
        s.layerAnchor = (e['anchor'] as num?)?.toInt() ?? 0;
        s.layerExclusive = (e['exclusive'] as num?)?.toInt() ?? 0;
        s.layerExclusiveEdge = (e['edge'] as num?)?.toInt() ?? 0;
        s.layerKeyboard = (e['kb'] as num?)?.toInt() ?? 0;
        s.layerMargins = EdgeInsets.fromLTRB(
          (e['ml'] as num?)?.toDouble() ?? 0,
          (e['mt'] as num?)?.toDouble() ?? 0,
          (e['mr'] as num?)?.toDouble() ?? 0,
          (e['mb'] as num?)?.toDouble() ?? 0,
        );
        s.layerDesired = Size(
          (e['dw'] as num?)?.toDouble() ?? 0,
          (e['dh'] as num?)?.toDouble() ?? 0,
        );
        s.outputId = (e['output'] as num?)?.toInt() ?? -1;
      case 'layerClosed':
        surfaces.remove(id);
      case 'lockSurface':
        surfaces[id] = WaylandSurface(
          id: id,
          textureId: (e['textureId'] as num?)?.toInt() ?? -1,
        )..isLock = true;
      case 'lockSurfaceClosed':
        surfaces.remove(id);
      case 'sessionLock':
        sessionLocked = true;
      case 'sessionUnlock':
        sessionLocked = false;
      case 'outputPower':
        displayOff = e['on'] == false;
      case 'idleSuspend':
        onIdleSuspend?.call();
      case 'outputs':
        final list = e['list'] as List<Object?>? ?? const [];
        outputs = [
          for (final raw in list)
            if (raw is Map)
              OasisOutput(
                id: (raw['id'] as num?)?.toInt() ?? 0,
                name: raw['name'] as String? ?? '',
                description: raw['desc'] as String? ?? '',
                enabled: raw['enabled'] != false,
                primary: raw['primary'] == true,
                powered: raw['powered'] != false,
                x: (raw['x'] as num?)?.toInt() ?? 0,
                y: (raw['y'] as num?)?.toInt() ?? 0,
                width: (raw['w'] as num?)?.toInt() ?? 0,
                height: (raw['h'] as num?)?.toInt() ?? 0,
                scale: (raw['scale'] as num?)?.toDouble() ?? 1,
                refreshMhz: (raw['refresh'] as num?)?.toInt() ?? 0,
                transform: (raw['transform'] as num?)?.toInt() ?? 0,
                physWidthMm: (raw['physW'] as num?)?.toInt() ?? 0,
                physHeightMm: (raw['physH'] as num?)?.toInt() ?? 0,
                modes: [
                  for (final m
                      in (raw['modes'] as List<Object?>? ?? const []))
                    if (m is Map)
                      OasisOutputMode(
                        width: (m['w'] as num?)?.toInt() ?? 0,
                        height: (m['h'] as num?)?.toInt() ?? 0,
                        refreshMhz:
                            (m['refresh'] as num?)?.toInt() ?? 0,
                        preferred: m['preferred'] == true,
                      ),
                ],
              ),
        ];
      case 'configureAcked':
        surfaces[id]?.ackedSerial =
            (e['serial'] as num?)?.toInt() ?? 0;
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
    _queueNotify();
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

  Future<void> configureLayer(int id, int width, int height) => available
      ? _host.configureLayer(id, width, height)
      : Future.value();

  Future<void> surfaceOutputs(int id, List<int> outputs) => available
      ? _host.surfaceOutputs(id, outputs)
      : Future.value();

  Future<void> configureOutput(
    String name, {
    int? x,
    int? y,
    int? width,
    int? height,
    int? refreshMhz,
    double? scale,
    int? transform,
    bool? enabled,
  }) =>
        available
            ? _host.configureOutput(
                name,
                x: x,
                y: y,
                width: width,
                height: height,
                refreshMhz: refreshMhz,
                scale: scale,
                transform: transform,
                enabled: enabled,
              )
            : Future.value();

  Future<void> close(int id) => available ? _host.close(id) : Future.value();

  Future<void> sessionUnlock() =>
      available ? _host.sessionUnlock() : Future.value();

  Future<void> activity() =>
      available ? _host.activity() : Future.value();

  Future<void> setIdleTimeouts(int displayOffMs, int suspendMs) {
    _idleOffMs = displayOffMs;
    _idleSuspendMs = suspendMs;
    return available
        ? _host.setIdleTimeouts(displayOffMs, suspendMs)
        : Future.value();
  }

  Future<void> focus(int? id) => available ? _host.focus(id) : Future.value();

  Future<void> pointerMotion(int id, double x, double y) {
    pointerOverClient = true;
    return available ? _host.pointerMotion(id, x, y) : Future.value();
  }

  Future<void> pointerExit(int id) {
    pointerOverClient = false;
    return available ? _host.pointerExit(id) : Future.value();
  }

  Future<void> pointerButton(int button, bool pressed) =>
      available ? _host.pointerButton(button, pressed) : Future.value();

  Future<void> pointerAxis(
    double dx,
    double dy, {
    int source = 0,
    int discrete = 0,
  }) => available
      ? _host.pointerAxis(dx, dy, source: source, discrete: discrete)
      : Future.value();

  Future<void> pointerAxisStop() =>
      available ? _host.pointerAxisStop() : Future.value();

  Future<void> touchDown(int id, int tid, double x, double y) =>
      available ? _host.touchDown(id, tid, x, y) : Future.value();

  Future<void> touchMotion(int tid, double x, double y) =>
      available ? _host.touchMotion(tid, x, y) : Future.value();

  Future<void> touchUp(int tid) =>
      available ? _host.touchUp(tid) : Future.value();

  Future<void> key(int code, bool pressed) =>
      available ? _host.key(code, pressed) : Future.value();

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    if (_retryWait != null && !_retryWait!.isCompleted) {
      _retryWait!.complete();
    }
    _sub?.cancel();
    _requests.close();
    super.dispose();
  }
}

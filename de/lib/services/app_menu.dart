import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import '../wayland/wayland_service.dart';

/// A location on the session bus holding a com.canonical.dbusmenu tree.
class AppMenuAddress {
  const AppMenuAddress(this.service, this.path);

  final String service;
  final String path;
}

/// One com.canonical.dbusmenu item. Root-level menus are the children
/// of layout id 0.
class AppMenuNode {
  AppMenuNode({
    required this.id,
    this.label = '',
    this.enabled = true,
    this.separator = false,
    this.checked = false,
    this.shortcut = '',
    List<AppMenuNode>? children,
  }) : children = children ?? [];

  final int id;
  int parent = -1;
  String label;
  bool enabled;
  bool separator;
  bool checked;
  String shortcut;
  List<AppMenuNode> children;
}

/// Strips the `_` mnemonics dbusmenu puts in labels (`__` is a literal
/// underscore).
String appMenuLabel(String raw) {
  if (!raw.contains('_')) return raw;
  final b = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == '_' && i + 1 < raw.length) {
      if (raw[i + 1] == '_') {
        b.write('_');
        i++;
      }
    } else {
      b.write(raw[i]);
    }
  }
  return b.toString();
}

String _shortcutLabel(DBusValue? value) {
  if (value is DBusVariant) value = value.value;
  if (value is! DBusArray || value.children.isEmpty) return '';
  final combo = value.children.first;
  if (combo is! DBusArray) return '';
  return [
    for (final k in combo.children)
      if (k is DBusString) k.value == 'Control' ? 'Ctrl' : k.value,
  ].join('+');
}

bool _propBool(DBusDict props, String key, bool fallback) {
  final v = props.children[DBusString(key)];
  if (v is! DBusVariant || v.value is! DBusBoolean) return fallback;
  return (v.value as DBusBoolean).value;
}

String _propString(DBusDict props, String key) {
  final v = props.children[DBusString(key)];
  if (v is! DBusVariant || v.value is! DBusString) return '';
  return (v.value as DBusString).value;
}

AppMenuNode? _parseNode(DBusValue value) {
  if (value is DBusVariant) value = value.value;
  if (value is! DBusStruct || value.children.length < 3) return null;
  final idValue = value.children[0];
  final props = value.children[1];
  final children = value.children[2];
  if (idValue is! DBusInt32 || props is! DBusDict || children is! DBusArray) {
    return null;
  }
  if (!_propBool(props, 'visible', true)) return null;
  final node = AppMenuNode(
    id: idValue.value,
    label: appMenuLabel(_propString(props, 'label')),
    enabled:
        _propBool(props, 'enabled', true) &&
        _propString(props, 'disposition') != 'informative',
    separator: _propString(props, 'type') == 'separator',
    checked:
        const {
          'checkmark',
          'radio',
        }.contains(_propString(props, 'toggle-type')) &&
        _propState(props),
    shortcut: _shortcutLabel(props.children[const DBusString('shortcut')]),
  );
  node.children = [for (final c in children.children) ?_parseNode(c)];
  return node;
}

bool _propState(DBusDict props) {
  final v = props.children[const DBusString('toggle-state')];
  if (v is! DBusVariant || v.value is! DBusInt32) return false;
  return (v.value as DBusInt32).value == 1;
}

/// com.canonical.AppMenu.Registrar implementation: apps report their
/// exported menu object paths here. On Wayland the window id is only
/// meaningful for XWayland clients, so matching falls back to the
/// registering connection's pid.
class AppMenuRegistrar extends DBusObject {
  AppMenuRegistrar({this.onRegistered, this.onUnregistered, this.onChanged})
    : super(DBusObjectPath('/com/canonical/AppMenu/Registrar'));

  final Map<int, AppMenuAddress> windows = {};
  final void Function(int windowId, AppMenuAddress address)? onRegistered;
  final void Function(int windowId)? onUnregistered;
  final VoidCallback? onChanged;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.name) {
      case 'RegisterWindow':
        if (methodCall.values.length != 2 ||
            methodCall.values[0] is! DBusUint32 ||
            methodCall.values[1] is! DBusObjectPath) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final id = (methodCall.values[0] as DBusUint32).value;
        final address = AppMenuAddress(
          methodCall.sender ?? '',
          (methodCall.values[1] as DBusObjectPath).value,
        );
        windows[id] = address;
        onRegistered?.call(id, address);
        onChanged?.call();
        return DBusMethodSuccessResponse();
      case 'UnregisterWindow':
        if (methodCall.values.length != 1 ||
            methodCall.values[0] is! DBusUint32) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final id = (methodCall.values[0] as DBusUint32).value;
        windows.remove(id);
        onUnregistered?.call(id);
        onChanged?.call();
        return DBusMethodSuccessResponse();
      case 'GetMenuForWindow':
        if (methodCall.values.length != 1 ||
            methodCall.values[0] is! DBusUint32) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final address =
            windows[(methodCall.values[0] as DBusUint32).value] ??
            const AppMenuAddress('', '/');
        return DBusMethodSuccessResponse([
          DBusString(address.service),
          DBusObjectPath(address.path),
        ]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

/// Resolves the focused window to an exported com.canonical.dbusmenu
/// tree and drives it: layout fetches, AboutToShow refreshes and the
/// opened/closed/hovered/clicked events. Apps attach their menus either
/// through the org_kde_kwin_appmenu protocol (KDE/Qt on Wayland) or by
/// calling RegisterWindow on the registrar (GTK appmenu, XWayland).
class AppMenuService extends ChangeNotifier {
  AppMenuService({
    DBusClient Function()? connect,
    this.signalStream = platformSignalStream,
  }) : _connect = connect ?? DBusClient.session;

  final DBusClient Function() _connect;
  final Stream<DBusSignal> Function(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  })
  signalStream;

  static Stream<DBusSignal> platformSignalStream(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  }) => DBusSignalStream(
    bus,
    sender: sender,
    interface: interface,
    name: name,
    path: path,
  );

  /// Called when the app asks for a top-level menu to be shown, e.g.
  /// from a global accelerator (ItemActivationRequested).
  void Function(AppMenuNode node)? onItemActivation;

  /// Root-level menus of the focused window's dbusmenu tree; empty
  /// while the focused app exports nothing.
  List<AppMenuNode> menus = const [];

  var started = false;
  var registrarReady = false;

  DBusClient? _bus;
  AppMenuRegistrar? _registrar;
  StreamSubscription<DBusSignal>? _layoutSub;
  StreamSubscription<DBusSignal>? _ownerSub;

  WaylandSurface? _tracked;
  String _trackedService = '';
  String _trackedPath = '';
  var _registryVersion = 0;
  var _trackedVersion = -1;

  AppMenuAddress? _bound;
  DBusRemoteObject? _menu;
  final Map<int, AppMenuNode> _nodes = {};
  final Map<String, int> _servicePids = {};

  Future<void> start() async {
    final bus = _connect();
    try {
      _bus = bus;
      final registrar = AppMenuRegistrar(
        onRegistered: _emitRegistered,
        onUnregistered: _emitUnregistered,
        onChanged: _onRegistryChanged,
      );
      await bus.registerObject(registrar);
      _registrar = registrar;
      final reply = await bus.requestName('com.canonical.AppMenu.Registrar');
      registrarReady = reply == DBusRequestNameReply.primaryOwner;
      if (!registrarReady) {
        debugPrint('Oasis: appmenu registrar name not owned ($reply)');
      }
      _ownerSub = signalStream(
        bus,
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
      ).listen(_onOwnerChanged, onError: (_) {});
      started = true;
    } catch (e) {
      debugPrint('Oasis: appmenu service failed to start: $e');
      await bus.close();
      _bus = null;
    }
  }

  void _emitRegistered(int windowId, AppMenuAddress address) {
    unawaited(
      _bus
          ?.emitSignal(
            path: DBusObjectPath('/com/canonical/AppMenu/Registrar'),
            interface: 'com.canonical.AppMenu.Registrar',
            name: 'WindowRegistered',
            values: [
              DBusUint32(windowId),
              DBusString(address.service),
              DBusObjectPath(address.path),
            ],
          )
          .catchError((Object _) {}),
    );
  }

  void _emitUnregistered(int windowId) {
    unawaited(
      _bus
          ?.emitSignal(
            path: DBusObjectPath('/com/canonical/AppMenu/Registrar'),
            interface: 'com.canonical.AppMenu.Registrar',
            name: 'WindowUnregistered',
            values: [DBusUint32(windowId)],
          )
          .catchError((Object _) {}),
    );
  }

  /// Point the service at the currently focused surface. Idempotent:
  /// it only re-resolves when the surface, its exported menu address or
  /// the registrar's window list changed.
  void track(WaylandSurface? surface) {
    final service = surface?.appMenuService ?? '';
    final path = surface?.appMenuPath ?? '';
    if (identical(surface, _tracked) &&
        _trackedVersion == _registryVersion &&
        service == _trackedService &&
        path == _trackedPath) {
      return;
    }
    _tracked = surface;
    _trackedService = service;
    _trackedPath = path;
    _trackedVersion = _registryVersion;
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final s = _tracked;
    AppMenuAddress? address;
    if (s != null) {
      if (s.appMenuService.isNotEmpty && s.appMenuPath.isNotEmpty) {
        address = AppMenuAddress(s.appMenuService, s.appMenuPath);
      } else {
        address = _registrar?.windows[s.xid] ?? await _byPid(s.pid);
      }
    }
    if (!identical(s, _tracked)) return;
    if (address == null) {
      _unbind();
      return;
    }
    if (address.service == _bound?.service && address.path == _bound?.path) {
      return;
    }
    await _bind(address);
  }

  Future<AppMenuAddress?> _byPid(int pid) async {
    if (pid <= 0) return null;
    final registrar = _registrar;
    if (registrar == null) return null;
    final services = {for (final a in registrar.windows.values) a.service};
    for (final name in services) {
      if (await _pidOf(name) == pid) {
        for (final a in registrar.windows.values) {
          if (a.service == name) return a;
        }
      }
    }
    return null;
  }

  Future<int> _pidOf(String name) async {
    final cached = _servicePids[name];
    if (cached != null) return cached;
    final bus = _bus;
    if (bus == null) return -1;
    try {
      final res =
          await DBusRemoteObject(
            bus,
            name: 'org.freedesktop.DBus',
            path: DBusObjectPath('/org/freedesktop/DBus'),
          ).callMethod('org.freedesktop.DBus', 'GetConnectionUnixProcessID', [
            DBusString(name),
          ]);
      final pid = (res.returnValues.first as DBusUint32).value;
      _servicePids[name] = pid;
      return pid;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _bind(AppMenuAddress address) async {
    _unbind();
    _bound = address;
    final bus = _bus;
    if (bus == null) return;
    _menu = DBusRemoteObject(
      bus,
      name: address.service,
      path: DBusObjectPath(address.path),
    );
    _layoutSub = signalStream(
      bus,
      sender: address.service,
      interface: 'com.canonical.dbusmenu',
    ).listen(_onMenuSignal, onError: (_) {});
    await _load();
  }

  void _unbind() {
    unawaited(_layoutSub?.cancel() ?? Future.value());
    _layoutSub = null;
    _menu = null;
    _bound = null;
    _nodes.clear();
    if (menus.isNotEmpty) {
      menus = const [];
      notifyListeners();
    }
  }

  void _index(AppMenuNode node) {
    _nodes[node.id] = node;
    for (final c in node.children) {
      c.parent = node.id;
      _index(c);
    }
  }

  Future<void> _load() async {
    final menu = _menu;
    if (menu == null) return;
    try {
      final res = await menu.callMethod('com.canonical.dbusmenu', 'GetLayout', [
        const DBusInt32(0),
        const DBusInt32(-1),
        DBusArray.string(const []),
      ], replySignature: DBusSignature('u(ia{sv}av)'));
      if (!identical(menu, _menu)) return;
      _nodes.clear();
      final root = _parseNode(res.returnValues[1]) ?? AppMenuNode(id: 0);
      _index(root);
      menus = [
        for (final c in root.children)
          if (!c.separator && c.label.isNotEmpty) c,
      ];
      notifyListeners();
    } catch (_) {}
  }

  void _onMenuSignal(DBusSignal signal) {
    switch (signal.name) {
      case 'LayoutUpdated':
      case 'ItemsPropertiesUpdated':
        unawaited(_load());
      case 'ItemActivationRequested':
        final id = signal.values.firstOrNull;
        if (id is! DBusInt32) return;
        var node = _nodes[id.value];
        while (node != null && node.parent > 0) {
          node = _nodes[node.parent];
        }
        if (node != null) onItemActivation?.call(node);
    }
  }

  void _onOwnerChanged(DBusSignal signal) {
    if (signal.values.length < 3) return;
    final name = (signal.values[0] as DBusString).value;
    final newOwner = (signal.values[2] as DBusString).value;
    if (newOwner.isNotEmpty) return;
    _servicePids.remove(name);
    final registrar = _registrar;
    if (registrar != null &&
        registrar.windows.values.any((a) => a.service == name)) {
      registrar.windows.removeWhere((_, a) => a.service == name);
      _registryVersion++;
      track(_tracked);
    }
    if (_bound?.service == name) _unbind();
  }

  Future<void> _sendEvent(int id, String kind) async {
    final menu = _menu;
    if (menu == null) return;
    try {
      await menu.callMethod('com.canonical.dbusmenu', 'Event', [
        DBusInt32(id),
        DBusString(kind),
        const DBusVariant(DBusString('')),
        DBusUint32(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ], noReplyExpected: true);
    } catch (_) {}
  }

  Future<void> activate(AppMenuNode node) => _sendEvent(node.id, 'clicked');

  Future<void> hoverItem(AppMenuNode node) => _sendEvent(node.id, 'hovered');

  Future<void> closeMenu(AppMenuNode node) => _sendEvent(node.id, 'closed');

  /// Sends AboutToShow followed by the opened event; apps may rebuild
  /// the submenu in response, in which case the node's children get
  /// re-fetched before the flyout renders.
  Future<void> openMenu(AppMenuNode node) async {
    final menu = _menu;
    if (menu == null) return;
    var needsUpdate = false;
    try {
      final res = await menu.callMethod(
        'com.canonical.dbusmenu',
        'AboutToShow',
        [DBusInt32(node.id)],
        replySignature: DBusSignature('b'),
      );
      needsUpdate = (res.returnValues.first as DBusBoolean).value;
    } catch (_) {}
    if (!identical(menu, _menu)) return;
    if (needsUpdate) await _refresh(node);
    await _sendEvent(node.id, 'opened');
  }

  Future<void> _refresh(AppMenuNode node) async {
    final menu = _menu;
    if (menu == null) return;
    try {
      final res = await menu.callMethod('com.canonical.dbusmenu', 'GetGroup', [
        DBusArray.int32([node.id]),
        DBusArray.string(const []),
      ], replySignature: DBusSignature('a(ia{sv}av)'));
      if (!identical(menu, _menu)) return;
      final items = res.returnValues.first as DBusArray;
      for (final raw in items.children) {
        final parsed = _parseNode(raw);
        if (parsed == null || parsed.id != node.id) continue;
        for (final c in _nodes[node.id]?.children ?? const <AppMenuNode>[]) {
          _dropIndex(c);
        }
        node.children = parsed.children;
        for (final c in node.children) {
          c.parent = node.id;
          _index(c);
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void _dropIndex(AppMenuNode node) {
    _nodes.remove(node.id);
    for (final c in node.children) {
      _dropIndex(c);
    }
  }

  void _onRegistryChanged() {
    _registryVersion++;
    track(_tracked);
  }

  Future<void> stop() async {
    unawaited(_layoutSub?.cancel() ?? Future.value());
    unawaited(_ownerSub?.cancel() ?? Future.value());
    _layoutSub = null;
    _ownerSub = null;
    final registrar = _registrar;
    if (registrarReady) {
      await _bus?.releaseName('com.canonical.AppMenu.Registrar');
    }
    if (registrar != null) await _bus?.unregisterObject(registrar);
    await _bus?.close();
    _bus = null;
    _registrar = null;
    _tracked = null;
    _menu = null;
    _bound = null;
    _nodes.clear();
    _servicePids.clear();
    menus = const [];
    started = false;
    registrarReady = false;
  }
}

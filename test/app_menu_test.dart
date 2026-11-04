import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/services/app_menu.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/shell/shell_menus.dart';
import 'package:oasis_de/shell/top_bar.dart';
import 'package:oasis_de/wayland/wayland_host.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class _FakeHost extends WaylandHost {
  final _events = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void emit(Map<String, Object?> event) => _events.add(event);

  @override
  Future<String?> start() async => 'wayland-1';

  @override
  Future<void> stop() async {}

  @override
  Future<void> launch(List<String> argv) async {}

  @override
  Future<void> configure(
    int id,
    int width,
    int height, {
    bool maximized = false,
    bool fullscreen = false,
    bool resizing = false,
  }) async {}

  @override
  Future<void> configureLayer(int id, int width, int height) async {}

  @override
  Future<void> surfaceOutputs(int id, List<int> outputs) async {}

  @override
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
  }) async {}

  @override
  Future<void> close(int id) async {}

  @override
  Future<void> sessionUnlock() async {}

  @override
  Future<void> activity() async {}

  @override
  Future<void> setIdleTimeouts(int displayOffMs, int suspendMs) async {}

  @override
  Future<void> focus(int? id) async {}

  @override
  Future<void> pointerMotion(int id, double x, double y) async {}

  @override
  Future<void> pointerExit(int id) async {}

  @override
  Future<void> pointerButton(int button, bool pressed) async {}

  @override
  Future<void> pointerAxis(
    double dx,
    double dy, {
    int source = 0,
    int discrete = 0,
  }) async {}

  @override
  Future<void> pointerAxisStop() async {}

  @override
  Future<void> inputConfig(Map<String, Object?> config) async {}

  @override
  Future<void> touchDown(int id, int tid, double x, double y) async {}

  @override
  Future<void> touchMotion(int tid, double x, double y) async {}

  @override
  Future<void> touchUp(int tid) async {}

  @override
  Future<void> key(int code, bool pressed) async {}

  @override
  Future<Map<String, Object?>?> capture(int x, int y, int w, int h) async =>
      null;
}

class _FakeBus extends Fake implements DBusClient {
  var registered = false;
  var released = false;
  var unregistered = false;
  var closed = false;
  var owner = DBusRequestNameReply.primaryOwner;
  var failRequest = false;
  var failEmit = false;
  var failCalls = false;
  DBusObject? object;
  final calls = <String>[];
  final emitted = <String>[];
  final pids = <String, int>{};
  FutureOr<DBusMethodSuccessResponse> Function(
    String? destination,
    String name,
    Iterable<DBusValue> values,
  )?
  onCall;

  @override
  Future<void> registerObject(DBusObject object) async {
    registered = true;
    this.object = object;
  }

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    if (failRequest) throw StateError('bus down');
    return owner;
  }

  @override
  Future<DBusReleaseNameReply> releaseName(String name) async {
    released = true;
    return DBusReleaseNameReply.released;
  }

  @override
  Future<void> unregisterObject(DBusObject object) async {
    unregistered = true;
  }

  @override
  Future<void> emitSignal({
    required DBusObjectPath path,
    required String interface,
    required String name,
    Iterable<DBusValue> values = const [],
    String? destination,
  }) async {
    if (failEmit) throw StateError('emit down');
    emitted.add(name);
  }

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
    Duration? timeout,
    bool requiresPrivilegedSocket = false,
  }) async {
    calls.add('${destination ?? ''}:$interface.$name');
    if (failCalls) throw StateError('bus down');
    if (name == 'GetConnectionUnixProcessID') {
      final n = (values.first as DBusString).value;
      final pid = pids[n];
      if (pid == null) throw StateError('unknown name');
      return DBusMethodSuccessResponse([DBusUint32(pid)]);
    }
    final handler = onCall;
    if (handler != null) {
      return await handler(destination, name, values);
    }
    return DBusMethodSuccessResponse(const []);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

DBusStruct _node(
  int id,
  Map<String, DBusValue> props, [
  List<DBusStruct> children = const [],
]) => DBusStruct([
  DBusInt32(id),
  DBusDict.stringVariant(props),
  DBusArray(DBusSignature('v'), [for (final c in children) DBusVariant(c)]),
]);

DBusMethodSuccessResponse _layout(DBusStruct root) =>
    DBusMethodSuccessResponse([const DBusUint32(1), root]);

DBusSignal _ownerChanged(String name, String newOwner) => DBusSignal(
  sender: 'org.freedesktop.DBus',
  path: DBusObjectPath('/org/freedesktop/DBus'),
  interface: 'org.freedesktop.DBus',
  name: 'NameOwnerChanged',
  values: [DBusString(name), DBusString('x'), DBusString(newOwner)],
);

DBusSignal _menuSignal(
  String name,
  List<DBusValue> values, {
  String sender = ':1.5',
}) => DBusSignal(
  sender: sender,
  path: DBusObjectPath('/MenuBar'),
  interface: 'com.canonical.dbusmenu',
  name: name,
  values: values,
);

AppMenuService _service(_FakeBus bus, StreamController<DBusSignal> signals) =>
    AppMenuService(
      connect: () => bus,
      signalStream:
          (
            DBusClient bus, {
            String? sender,
            String? interface,
            String? name,
            DBusObjectPath? path,
          }) => signals.stream,
    );

DBusMethodCall _call(
  String name,
  List<DBusValue> values, {
  String sender = ':1.5',
}) => DBusMethodCall(sender: sender, name: name, values: values);

void main() {
  test('registrar registers, unregisters and serves lookups', () async {
    final registered = <int>[];
    final unregistered = <int>[];
    var changes = 0;
    final r = AppMenuRegistrar(
      onRegistered: (id, _) => registered.add(id),
      onUnregistered: unregistered.add,
      onChanged: () => changes++,
    );
    final ok = await r.handleMethodCall(
      _call('RegisterWindow', [
        const DBusUint32(7),
        DBusObjectPath('/MenuBar'),
      ]),
    );
    expect(ok, isA<DBusMethodSuccessResponse>());
    expect(r.windows[7]!.service, ':1.5');
    expect(r.windows[7]!.path, '/MenuBar');
    expect(registered, [7]);
    expect(changes, 1);

    final got =
        await r.handleMethodCall(
              _call('GetMenuForWindow', [const DBusUint32(7)]),
            )
            as DBusMethodSuccessResponse;
    expect((got.returnValues[0] as DBusString).value, ':1.5');
    expect((got.returnValues[1] as DBusObjectPath).value, '/MenuBar');

    final missing =
        await r.handleMethodCall(
              _call('GetMenuForWindow', [const DBusUint32(9)]),
            )
            as DBusMethodSuccessResponse;
    expect((missing.returnValues[0] as DBusString).value, '');
    expect((missing.returnValues[1] as DBusObjectPath).value, '/');

    final gone = await r.handleMethodCall(
      _call('UnregisterWindow', [const DBusUint32(7)]),
    );
    expect(gone, isA<DBusMethodSuccessResponse>());
    expect(r.windows, isEmpty);
    expect(unregistered, [7]);
    expect(changes, 2);
  });

  test('registrar rejects malformed calls and unknown methods', () async {
    final r = AppMenuRegistrar();
    expect(
      await r.handleMethodCall(_call('RegisterWindow', [DBusString('x')])),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await r.handleMethodCall(
        _call('RegisterWindow', [DBusUint32(1), DBusString('/x')]),
      ),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await r.handleMethodCall(_call('UnregisterWindow', [])),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await r.handleMethodCall(_call('UnregisterWindow', [DBusString('x')])),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await r.handleMethodCall(_call('GetMenuForWindow', [])),
      isA<DBusMethodErrorResponse>(),
    );
    expect(
      await r.handleMethodCall(_call('Nope', [])),
      isA<DBusMethodErrorResponse>(),
    );
  });

  test('platform signal stream wraps DBusSignalStream', () {
    final stream = AppMenuService.platformSignalStream(
      _FakeBus(),
      sender: ':1.5',
      interface: 'com.canonical.dbusmenu',
      name: 'LayoutUpdated',
      path: DBusObjectPath('/MenuBar'),
    );
    expect(stream, isA<Stream<DBusSignal>>());
  });

  test('appMenuLabel strips mnemonics', () {
    expect(appMenuLabel('File'), 'File');
    expect(appMenuLabel('_File'), 'File');
    expect(appMenuLabel('Save _As'), 'Save As');
    expect(appMenuLabel('A__b'), 'A_b');
    expect(appMenuLabel('trail_'), 'trail_');
  });

  group('service', () {
    late _FakeBus bus;
    late StreamController<DBusSignal> signals;
    late AppMenuService service;

    setUp(() {
      bus = _FakeBus();
      signals = StreamController<DBusSignal>.broadcast();
      service = _service(bus, signals);
    });

    tearDown(() async {
      await service.stop();
      unawaited(signals.close());
    });

    WaylandSurface surface({
      int id = 1,
      int pid = -1,
      int xid = 0,
      String menuService = '',
      String menuPath = '',
    }) => WaylandSurface(id: id)
      ..pid = pid
      ..xid = xid
      ..appMenuService = menuService
      ..appMenuPath = menuPath;

    test('start registers the object and requests the name', () async {
      await service.start();
      expect(service.started, isTrue);
      expect(service.registrarReady, isTrue);
      expect(bus.registered, isTrue);
      expect(bus.object, isA<AppMenuRegistrar>());
    });

    test('start without the name still tracks menus', () async {
      bus.owner = DBusRequestNameReply.exists;
      await service.start();
      expect(service.started, isTrue);
      expect(service.registrarReady, isFalse);
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('File')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'File');
      await service.stop();
      expect(bus.released, isFalse);
      expect(bus.unregistered, isTrue);
      expect(bus.closed, isTrue);
      expect(service.menus, isEmpty);
      expect(service.started, isFalse);
    });

    test('start failure closes the bus', () async {
      bus.failRequest = true;
      await service.start();
      expect(service.started, isFalse);
      expect(bus.closed, isTrue);
    });

    test('registrar signals are emitted on registration', () async {
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      await registrar.handleMethodCall(
        _call('RegisterWindow', [const DBusUint32(4), DBusObjectPath('/M')]),
      );
      await registrar.handleMethodCall(
        _call('UnregisterWindow', [const DBusUint32(4)]),
      );
      expect(bus.emitted, ['WindowRegistered', 'WindowUnregistered']);
    });

    test('registrar emit failures are swallowed', () async {
      await service.start();
      bus.failEmit = true;
      final registrar = bus.object! as AppMenuRegistrar;
      await registrar.handleMethodCall(
        _call('RegisterWindow', [const DBusUint32(4), DBusObjectPath('/M')]),
      );
      await registrar.handleMethodCall(
        _call('UnregisterWindow', [const DBusUint32(4)]),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('direct surface address binds the layout', () async {
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('_File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(10, {
                    'label': DBusString('_Quit'),
                    'shortcut': DBusArray(DBusSignature('as'), [
                      DBusArray.string(['Control', 'Q']),
                    ]),
                  }),
                  _node(11, {'type': DBusString('separator')}),
                  _node(12, {
                    'label': DBusString('Off'),
                    'enabled': DBusBoolean(false),
                  }),
                  _node(13, {
                    'label': DBusString('Check'),
                    'toggle-type': DBusString('checkmark'),
                    'toggle-state': DBusInt32(1),
                  }),
                  _node(14, {
                    'label': DBusString('RadioOff'),
                    'toggle-type': DBusString('radio'),
                    'toggle-state': DBusInt32(0),
                  }),
                  _node(15, {
                    'label': DBusString('Info'),
                    'disposition': DBusString('informative'),
                  }),
                  _node(16, {
                    'label': DBusString('Hidden'),
                    'visible': DBusBoolean(false),
                  }),
                  _node(17, {'label': DBusString('')}),
                ],
              ),
              _node(2, {'label': DBusString('Edit')}),
              _node(3, {'type': DBusString('separator')}),
              _node(4, {'label': DBusString('')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.map((m) => m.label), ['File', 'Edit']);
      final file = service.menus.first;
      final quit = file.children[0];
      expect(quit.shortcut, 'Ctrl+Q');
      expect(file.children[2].enabled, isFalse);
      expect(file.children[3].checked, isTrue);
      expect(file.children[4].checked, isFalse);
      expect(file.children[5].enabled, isFalse);
      expect(file.children.map((n) => n.label), isNot(contains('Hidden')));
      expect(file.children.where((n) => n.separator).length, 1);
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      service.track(null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
      expect(bus.calls.where((c) => c.contains('GetLayout')).length, 1);
    });

    test('same address re-resolve does not refetch', () async {
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('F')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      service.track(surface(id: 2, menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      expect(bus.calls.where((c) => c.contains('GetLayout')).length, 1);
    });

    test('xid match binds via registrar', () async {
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('G')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await registrar.handleMethodCall(
        _call('RegisterWindow', [
          const DBusUint32(88),
          DBusObjectPath('/MenuBar'),
        ], sender: ':1.9'),
      );
      service.track(surface(xid: 88));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'G');
      expect(bus.calls.any((c) => c.startsWith(':1.9:')), isTrue);
    });

    test('pid match falls back to the registrar owner pid', () async {
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      bus.pids[':1.9'] = 4242;
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('P')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await registrar.handleMethodCall(
        _call('RegisterWindow', [
          const DBusUint32(88),
          DBusObjectPath('/MenuBar'),
        ], sender: ':1.9'),
      );
      service.track(surface(pid: 4242));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'P');
      // cached pid answer skips a second lookup
      service.track(surface(pid: 4242, menuService: ':1.9', menuPath: '/x'));
      await Future<void>.delayed(Duration.zero);
    });

    test('unknown pid and dead services yield no menu', () async {
      await service.start();
      service.track(surface(pid: 7));
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
    });

    test('pid lookup failure leaves no menu', () async {
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      await registrar.handleMethodCall(
        _call('RegisterWindow', [
          const DBusUint32(1),
          DBusObjectPath('/M'),
        ], sender: ':1.9'),
      );
      service.track(surface(pid: 5));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
    });

    test('track before start resolves to nothing', () async {
      service.track(surface(pid: 5, xid: 1));
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
    });

    test('pid lookup without a bus resolves to nothing', () async {
      bus.failRequest = true;
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      await registrar.handleMethodCall(
        _call('RegisterWindow', [
          const DBusUint32(1),
          DBusObjectPath('/M'),
        ], sender: ':1.9'),
      );
      service.track(surface(pid: 5));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
    });

    test('layout updates refetch the tree', () async {
      var version = 0;
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          version++;
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('M$version')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'M1');
      signals.add(_menuSignal('LayoutUpdated', [DBusUint32(2), DBusInt32(0)]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'M2');
      signals.add(
        _menuSignal('ItemsPropertiesUpdated', [
          DBusArray(DBusSignature('(ia{sv}av)'), const []),
          DBusArray(DBusSignature('(ia{sv}as)'), const []),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'M3');
    });

    test('item activation resolves to the top-level menu', () async {
      AppMenuNode? activated;
      service.onItemActivation = (n) => activated = n;
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(
                    10,
                    {
                      'label': DBusString('Recent'),
                      'children-display': DBusString('submenu'),
                    },
                    [
                      _node(20, {'label': DBusString('Doc')}),
                    ],
                  ),
                ],
              ),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      signals.add(
        _menuSignal('ItemActivationRequested', [
          const DBusInt32(20),
          const DBusUint32(0),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(activated?.label, 'File');
      signals.add(_menuSignal('ItemActivationRequested', const []));
      signals.add(_menuSignal('ItemActivationRequested', [DBusString('x')]));
      signals.add(_menuSignal('ItemActivationRequested', [DBusInt32(999)]));
      expect(activated?.label, 'File');
    });

    test('events and about-to-show drive the menu', () async {
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(
                    10,
                    {'label': DBusString('Old')},
                    [
                      _node(20, {'label': DBusString('Deep')}),
                    ],
                  ),
                ],
              ),
            ]),
          );
        }
        if (name == 'AboutToShow') {
          return DBusMethodSuccessResponse(const [DBusBoolean(true)]);
        }
        if (name == 'GetGroup') {
          return DBusMethodSuccessResponse([
            DBusArray(DBusSignature('(ia{sv}av)'), [
              _node(1, {}, [
                _node(10, {'label': DBusString('New')}),
                _node(11, {
                  'label': DBusString('Skip'),
                  'visible': DBusBoolean(false),
                }),
                _node(12, {'label': DBusString('Other')}),
              ]),
              _node(99, {}, [
                _node(98, {'label': DBusString('X')}),
              ]),
            ]),
          ]);
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final file = service.menus.single;
      expect(file.children.single.label, 'Old');
      expect(file.children.single.children.single.label, 'Deep');
      await service.openMenu(file);
      expect(file.children.map((n) => n.label), ['New', 'Other']);
      expect(bus.calls.where((c) => c.contains('AboutToShow')).length, 1);
      expect(
        bus.calls.where((c) => c.contains('.Event')).length,
        greaterThanOrEqualTo(1),
      );
      await service.activate(file);
      await service.hoverItem(file);
      await service.closeMenu(file);
      expect(bus.calls.where((c) => c.contains('.Event')).length, 4);
      bus.failCalls = true;
      await service.openMenu(file);
      await service.activate(file);
    });

    test('about-to-show returning false skips the refresh', () async {
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('F')}),
            ]),
          );
        }
        if (name == 'AboutToShow') {
          return DBusMethodSuccessResponse(const [DBusBoolean(false)]);
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await service.openMenu(service.menus.single);
      expect(bus.calls.any((c) => c.contains('GetGroup')), isFalse);
    });

    test('menu calls before binding are no-ops', () async {
      final node = AppMenuNode(id: 1);
      await service.openMenu(node);
      await service.activate(node);
      await service.hoverItem(node);
      await service.closeMenu(node);
      expect(bus.calls, isEmpty);
    });

    test('losing the menu service clears the tree', () async {
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('F')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isNotEmpty);
      signals.add(_ownerChanged(':1.5', ''));
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
      signals.add(_ownerChanged(':1.5', ':1.5'));
      signals.add(
        DBusSignal(
          sender: 'org.freedesktop.DBus',
          path: DBusObjectPath('/org/freedesktop/DBus'),
          interface: 'org.freedesktop.DBus',
          name: 'NameOwnerChanged',
          values: [DBusString('x')],
        ),
      );
      expect(service.menus, isEmpty);
    });

    test('losing a registered service prunes its windows', () async {
      await service.start();
      final registrar = bus.object! as AppMenuRegistrar;
      await registrar.handleMethodCall(
        _call('RegisterWindow', [
          const DBusUint32(3),
          DBusObjectPath('/M'),
        ], sender: ':1.7'),
      );
      bus.pids[':1.7'] = 9;
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('F')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      service.track(surface(pid: 9));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus.single.label, 'F');
      signals.add(_ownerChanged(':1.7', ''));
      await Future<void>.delayed(Duration.zero);
      expect(registrar.windows, isEmpty);
      expect(service.menus, isEmpty);
    });

    test('stale surface switch during resolve is ignored', () async {
      final gate = Completer<DBusMethodSuccessResponse>();
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') return gate.future;
        if (name == 'GetConnectionUnixProcessID') {
          return DBusMethodSuccessResponse([DBusUint32(1)]);
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      service.track(null);
      gate.complete(
        _layout(
          _node(0, {}, [
            _node(1, {'label': DBusString('X')}),
          ]),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(service.menus, isEmpty);
    });

    test('stale bind during about-to-show is ignored', () async {
      final gate = Completer<DBusMethodSuccessResponse>();
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(1, {'label': DBusString('F')}),
            ]),
          );
        }
        if (name == 'AboutToShow') return gate.future;
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      service.track(surface(menuService: ':1.5', menuPath: '/MenuBar'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final pending = service.openMenu(service.menus.single);
      await Future<void>.delayed(Duration.zero);
      service.track(null);
      await Future<void>.delayed(Duration.zero);
      gate.complete(DBusMethodSuccessResponse(const [DBusBoolean(true)]));
      await pending;
      expect(service.menus, isEmpty);
    });
  });

  group('wayland', () {
    test('toplevel and appMenu events populate the surface', () async {
      final host = _FakeHost();
      final wl = WaylandService(host: host);
      await wl.start();
      host.emit({
        'event': 'toplevel',
        'id': 1,
        'textureId': 3,
        'title': 'Kate',
        'appId': 'org.kde.kate',
        'pid': 4242,
        'xid': 77,
        'menuService': ':1.5',
        'menuPath': '/MenuBar',
      });
      await Future<void>.delayed(Duration.zero);
      final s = wl.surfaces[1]!;
      expect(s.pid, 4242);
      expect(s.xid, 77);
      expect(s.appMenuService, ':1.5');
      expect(s.appMenuPath, '/MenuBar');
      host.emit({
        'event': 'appMenu',
        'id': 1,
        'service': ':1.8',
        'path': '/Menu/Bar',
      });
      await Future<void>.delayed(Duration.zero);
      expect(s.appMenuService, ':1.8');
      expect(s.appMenuPath, '/Menu/Bar');
      host.emit({'event': 'appMenu', 'id': 99, 'service': ':1.9', 'path': '/'});
      await Future<void>.delayed(Duration.zero);
      expect(wl.surfaces[99], isNull);
      wl.dispose();
    });
  });

  group('shell menus', () {
    final l10n = lookupOasisLocalizations(const Locale('en'));

    testWidgets('exported menus replace the static set', (tester) async {
      final bus = _FakeBus();
      final signals = StreamController<DBusSignal>.broadcast();
      addTearDown(signals.close);
      final service = _service(bus, signals);
      final host = _FakeHost();
      final wl = WaylandService(host: host);
      await wl.start();
      addTearDown(wl.dispose);
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wl,
        appMenu: service,
      );
      addTearDown(c.dispose);
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(10, {'label': DBusString('Open')}),
                  _node(11, {'type': DBusString('separator')}),
                  _node(12, {'type': DBusString('separator')}),
                  _node(13, {'label': DBusString('')}),
                  _node(
                    14,
                    {
                      'label': DBusString('Recent'),
                      'children-display': DBusString('submenu'),
                    },
                    [
                      _node(15, {'label': DBusString('Doc')}),
                    ],
                  ),
                ],
              ),
              _node(2, {'label': DBusString('Edit')}),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      await pumpOasis(tester, const SizedBox.shrink());
      host.emit({
        'event': 'toplevel',
        'id': 1,
        'textureId': 3,
        'title': 'Kate',
        'appId': 'kate',
        'menuService': ':1.5',
        'menuPath': '/MenuBar',
      });
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(service.menus.length, 2);
      final menus = buildShellMenus(l10n, c, 'Kate', {});
      expect(menus.length, 3);
      expect(menus[0].label, 'Kate');
      expect(menus[1].label, 'File');
      expect(menus[2].label, 'Edit');
      final ctx = tester.element(find.byType(Directionality).first);
      final items = menus[1].items(ctx);
      expect(items.length, 2);
      expect(items[0].label, 'Open');
      expect(items[0].separatorAfter, isTrue);
      expect(items[1].label, 'Recent');
      expect(items[1].children, isNotNull);
      expect(items[1].children!().single.label, 'Doc');
      items[0].action?.call(ctx);
      items[1].onOpen?.call();
      items[1].onClose?.call();
      items[1].onHover?.call();
      await tester.pump();
      expect(
        bus.calls.where((c) => c.contains('.Event')).length,
        greaterThanOrEqualTo(3),
      );
      menus[1].onOpen?.call();
      menus[1].onClose?.call();
      await tester.pump();
      expect(bus.calls.any((c) => c.contains('AboutToShow')), isTrue);
      await service.stop();
    });

    testWidgets('top bar renders app menus and fires dbus events', (
      tester,
    ) async {
      final bus = _FakeBus();
      final signals = StreamController<DBusSignal>.broadcast();
      addTearDown(signals.close);
      final service = _service(bus, signals);
      final host = _FakeHost();
      final wl = WaylandService(host: host);
      await wl.start();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wl,
        appMenu: service,
      );
      addTearDown(c.dispose);
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(10, {'label': DBusString('Quit')}),
                  _node(
                    11,
                    {
                      'label': DBusString('Recent'),
                      'children-display': DBusString('submenu'),
                    },
                    [
                      _node(12, {'label': DBusString('Doc')}),
                    ],
                  ),
                ],
              ),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      host.emit({
        'event': 'toplevel',
        'id': 1,
        'textureId': 4,
        'title': 'Kate',
        'appId': 'org.kde.kate',
        'pid': 5,
        'menuService': ':1.5',
        'menuPath': '/MenuBar',
      });
      final l10n = lookupOasisLocalizations(const Locale('en'));
      await pumpOasis(
        tester,
        DesktopShell(
          controller: c,
          menusBuilder: () => buildShellMenus(l10n, c, 'Kate', {}),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(service.menus.single.label, 'File');
      await tester.tap(find.text('File'));
      await tester.pump();
      expect(c.openMenu, 'File');
      expect(find.text('Quit'), findsOneWidget);
      final quitEntry = tester.widget<OasisMenuEntry>(
        find.ancestor(
          of: find.text('Quit'),
          matching: find.byType(OasisMenuEntry),
        ),
      );
      quitEntry.item.onHover?.call();
      await tester.tap(find.text('Quit'));
      await tester.pump();
      expect(c.openMenu, isNull);
      expect(bus.calls.any((c) => c.contains('.Event')), isTrue);
      await service.stop();
    });

    testWidgets('dropdown opens submenu and closes it on leaf select', (
      tester,
    ) async {
      final bus = _FakeBus();
      final signals = StreamController<DBusSignal>.broadcast();
      addTearDown(signals.close);
      final service = _service(bus, signals);
      final host = _FakeHost();
      final wl = WaylandService(host: host);
      await wl.start();
      addTearDown(wl.dispose);
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wl,
        appMenu: service,
      );
      addTearDown(c.dispose);
      bus.onCall = (destination, name, values) {
        if (name == 'GetLayout') {
          return _layout(
            _node(0, {}, [
              _node(
                1,
                {
                  'label': DBusString('File'),
                  'children-display': DBusString('submenu'),
                },
                [
                  _node(
                    10,
                    {
                      'label': DBusString('Recent'),
                      'children-display': DBusString('submenu'),
                    },
                    [
                      _node(11, {'label': DBusString('Doc')}),
                    ],
                  ),
                  _node(12, {'label': DBusString('Plain')}),
                ],
              ),
            ]),
          );
        }
        return DBusMethodSuccessResponse(const []);
      };
      await service.start();
      host.emit({
        'event': 'toplevel',
        'id': 1,
        'textureId': 3,
        'title': 'Kate',
        'appId': 'kate',
        'menuService': ':1.5',
        'menuPath': '/MenuBar',
      });
      await tester.pump();
      await tester.pump();
      final l10n = lookupOasisLocalizations(const Locale('en'));
      await pumpOasis(
        tester,
        DesktopShell(
          controller: c,
          menusBuilder: () => buildShellMenus(l10n, c, 'Kate', {}),
        ),
      );
      await tester.tap(find.text('File'));
      await tester.pump();
      expect(find.text('Doc'), findsNothing);
      await tester.ensureVisible(find.text('Recent'));
      final recent = find.ancestor(
        of: find.text('Recent'),
        matching: find.byType(OasisMenuEntry),
      );
      final center = tester.getCenter(recent);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.moveTo(center);
      await tester.pump();
      expect(find.text('Doc'), findsOneWidget);
      expect(bus.calls.any((c) => c.contains('AboutToShow')), isTrue);
      // hovering the sibling collapses the flyout
      final plain = find.ancestor(
        of: find.text('Plain'),
        matching: find.byType(OasisMenuEntry),
      );
      await gesture.moveTo(tester.getCenter(plain));
      await tester.pump();
      expect(find.text('Doc'), findsNothing);
      await gesture.moveTo(tester.getCenter(recent));
      await tester.pump();
      expect(find.text('Doc'), findsOneWidget);
      await tester.tap(find.text('Doc'));
      await tester.pump();
      expect(c.openMenu, isNull);
      await gesture.removePointer();
      await service.stop();
    });

    testWidgets('submenu flyouts flip at screen edges', (tester) async {
      OasisMenuCascade? cascade;
      await pumpOasis(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              GestureDetector(
                onTap: () {
                  cascade = OasisMenuCascade(Overlay.of(context));
                  cascade!.open(
                    1,
                    const Rect.fromLTWH(290, 200, 8, 30),
                    const OasisMenuItem(label: 'root'),
                    const [OasisMenuItem(label: 'Fly A')],
                    () {},
                  );
                },
                child: const Text('a'),
              ),
              GestureDetector(
                onTap: () {
                  cascade!.open(
                    2,
                    const Rect.fromLTWH(2, 50, 8, 30),
                    const OasisMenuItem(label: 'root2'),
                    const [OasisMenuItem(label: 'Fly B')],
                    () {},
                  );
                  cascade!.open(
                    3,
                    const Rect.fromLTWH(2, 220, 8, 30),
                    const OasisMenuItem(label: 'root3'),
                    [
                      for (var i = 0; i < 12; i++)
                        OasisMenuItem(label: 'Fly C$i'),
                    ],
                    () {},
                  );
                },
                child: const Text('b'),
              ),
            ],
          ),
        ),
        size: const Size(300, 250),
      );
      await tester.tap(find.text('a'));
      await tester.pump();
      expect(find.text('Fly A'), findsOneWidget);
      await tester.tap(find.text('b'));
      await tester.pump();
      expect(find.text('Fly B'), findsOneWidget);
      expect(find.text('Fly C0'), findsOneWidget);
      cascade?.close();
      await tester.pump();
      expect(find.text('Fly A'), findsNothing);
    });

    testWidgets('tapping a submenu item opens its flyout', (tester) async {
      final opened = <String>[];
      await pumpOasis(
        tester,
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => showOasisMenu(context, const Offset(20, 20), [
              OasisMenuItem(
                label: 'Sub',
                children: () => const [OasisMenuItem(label: 'Leaf')],
                onOpen: () => opened.add('Sub'),
              ),
              const OasisMenuItem(label: 'Solo'),
            ]),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.text('Sub'));
      await tester.pump();
      expect(opened, ['Sub']);
      expect(find.text('Leaf'), findsOneWidget);
      await tester.tap(find.text('Leaf'));
      await tester.pump();
      expect(find.text('Leaf'), findsNothing);
    });

    testWidgets('menu dropdown lifecycle drives open/close hooks', (
      tester,
    ) async {
      final opened = <String>[];
      final closed = <String>[];
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      ShellMenu make(String label) => ShellMenu(
        label: label,
        onOpen: () => opened.add(label),
        onClose: () => closed.add(label),
        items: (_) => [ShellMenuItem(label: '$label item')],
      );
      await pumpOasis(
        tester,
        MenuDropdown(menuIndex: 0, menus: [make('File')], controller: c),
      );
      expect(opened, ['File']);
      await tester.pumpWidget(
        wrapOasis(
          MenuDropdown(
            menuIndex: 1,
            menus: [make('File'), make('Edit')],
            controller: c,
          ),
        ),
      );
      await tester.pump();
      expect(closed, ['File']);
      expect(opened, ['File', 'Edit']);
      await tester.pumpWidget(wrapOasis(const SizedBox.shrink()));
      await tester.pump();
      expect(closed, ['File', 'Edit']);
    });
  });

  group('app wiring', () {
    testWidgets('OasisDesktopApp starts the app menu service', (tester) async {
      final bus = _FakeBus();
      final signals = StreamController<DBusSignal>.broadcast();
      addTearDown(signals.close);
      final service = _service(bus, signals);
      await pumpOasis(
        tester,
        OasisDesktopApp(
          appMenu: service,
          externalAppsLoader: () async => const [],
        ),
      );
      expect(service.started, isTrue);
    });
  });
}

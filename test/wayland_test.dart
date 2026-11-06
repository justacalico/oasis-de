import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/wayland/desktop_entries.dart';
import 'package:oasis_de/wayland/keymap.dart';
import 'package:oasis_de/wayland/layer_surface_view.dart';
import 'package:oasis_de/wayland/wayland_host.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_de/wayland/wayland_surface_view.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';

class FakeWaylandHost extends WaylandHost {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final calls = <String>[];
  String? socket = 'wayland-9';
  Object? startError;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void emit(Map<String, Object?> event) => _events.add(event);

  @override
  Future<String?> start() async {
    if (startError != null) throw startError!;
    return socket;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> launch(List<String> argv) async {
    calls.add('launch:${argv.join(' ')}');
  }

  @override
  Future<void> configure(
    int id,
    int width,
    int height, {
    bool maximized = false,
    bool fullscreen = false,
    bool resizing = false,
  }) async {
    calls.add(
      'configure:$id:${width}x$height:$maximized:$fullscreen'
      '${resizing ? ':resizing' : ''}',
    );
  }

  @override
  Future<void> configureLayer(int id, int width, int height) async {
    calls.add('configureLayer:$id:${width}x$height');
  }

  @override
  Future<void> surfaceOutputs(int id, List<int> outputs) async {
    calls.add('surfaceOutputs:$id:${outputs.join('+')}');
  }

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
  }) async {
    calls.add('configureOutput:$name:${x ?? -1}:${y ?? -1}:$enabled');
  }

  @override
  Future<void> close(int id) async {
    calls.add('close:$id');
  }

  @override
  Future<void> sessionUnlock() async {
    calls.add('sessionUnlock');
  }

  @override
  Future<void> activity() async {
    calls.add('activity');
  }

  @override
  Future<void> setIdleTimeouts(int displayOffMs, int suspendMs) async {
    calls.add('idleTimeouts:$displayOffMs:$suspendMs');
  }

  @override
  Future<void> focus(int? id) async {
    calls.add('focus:$id');
  }

  @override
  Future<void> pointerMotion(int id, double x, double y) async {
    calls.add('motion:$id:$x:$y');
  }

  @override
  Future<void> pointerExit(int id) async {
    calls.add('exit:$id');
  }

  @override
  Future<void> pointerButton(int button, bool pressed) async {
    calls.add('button:$button:$pressed');
  }

  @override
  Future<void> pointerAxis(
    double dx,
    double dy, {
    int source = 0,
    int discrete = 0,
  }) async {
    calls.add('axis:$dx:$dy');
  }

  @override
  Future<void> pointerAxisStop() async {}

  @override
  Future<void> inputConfig(Map<String, Object?> config) async {
    calls.add('inputConfig:${config['device']}');
  }

  @override
  Future<void> touchDown(int id, int tid, double x, double y) async {}

  @override
  Future<void> touchMotion(int tid, double x, double y) async {}

  @override
  Future<void> touchUp(int tid) async {}

  @override
  Future<void> key(int code, bool pressed) async {
    calls.add('key:$code:$pressed');
  }

  /// Frame handed back by [capture]; null reports capture failure.
  Uint8List? captureRgba;
  int captureWidth = 0;
  int captureHeight = 0;

  @override
  Future<Map<String, Object?>?> capture(int x, int y, int w, int h) async {
    calls.add('capture:$x:$y:${w}x$h');
    final rgba = captureRgba;
    if (rgba == null) return null;
    return {'w': captureWidth, 'h': captureHeight, 'rgba': rgba};
  }
}

void main() {
  surfaceViewCoverage();
  layerViewCoverage();
  test('service forwards input config when available', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.inputConfig({'device': 'mouse'});
    expect(host.calls, isNot(contains('inputConfig:mouse')));
    await service.start();
    await service.inputConfig({'device': 'mouse'});
    expect(host.calls, contains('inputConfig:mouse'));
  });

  test('service starts and handles surface events', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();
    expect(service.available, isTrue);
    expect(service.socket, 'wayland-9');
    await service.start();

    host.emit({
      'event': 'toplevel',
      'id': 1,
      'textureId': 10,
      'title': 'Editor',
      'appId': 'editor',
    });
    await pumpEventQueue();
    expect(service.toplevels.single.id, 1);
    expect(service.popups, isEmpty);

    host.emit({'event': 'title', 'id': 1, 'title': 'New'});
    host.emit({'event': 'appId', 'id': 1, 'appId': 'org.x'});
    host.emit({'event': 'size', 'id': 1, 'w': 640, 'h': 480});
    host.emit({'event': 'minSize', 'id': 1, 'w': 320, 'h': 240});
    host.emit({'event': 'maxSize', 'id': 1, 'w': 1280, 'h': 960});
    host.emit({'event': 'minSize', 'id': 99, 'w': 1, 'h': 1});
    await pumpEventQueue();
    final s = service.surfaces[1]!;
    expect(s.title, 'New');
    expect(s.appId, 'org.x');
    expect(s.size, const Size(640, 480));
    expect(s.minSize, const Size(320, 240));
    expect(s.maxSize, const Size(1280, 960));

    host.emit({
      'event': 'popup',
      'id': 2,
      'parent': 1,
      'textureId': 11,
      'x': 10,
      'y': 20,
    });
    await pumpEventQueue();
    expect(service.popups.single.isPopup, isTrue);
    expect(service.surfaces[2]!.offset, const Offset(10, 20));

    host.emit({'event': 'popupMoved', 'id': 2, 'x': 5, 'y': 6});
    await pumpEventQueue();
    expect(service.surfaces[2]!.offset, const Offset(5, 6));

    host.emit({'event': 'popupClosed', 'id': 2});
    host.emit({'event': 'toplevelClosed', 'id': 1});
    host.emit({'event': 'mystery', 'id': 99});
    await pumpEventQueue();
    expect(service.surfaces, isEmpty);
    service.dispose();
  });

  test('service drops malformed surface events', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'size', 'id': 1, 'w': 'oops', 'h': 480});
    host.emit({'event': 'size', 'id': 1, 'w': 640});
    host.emit({'event': 'minSize', 'id': 1, 'w': 'x', 'h': 1});
    host.emit({'event': 'maxSize', 'id': 1, 'w': 1});
    host.emit({'event': 'cursor', 'id': 1, 'texture': 5});
    host.emit({
      'event': 'inputRegion',
      'id': 1,
      'rects': [0, 0, 'x', 8],
    });
    host.emit({'event': 'popup', 'id': 2, 'x': 1, 'y': 2});
    host.emit({'event': 'popup', 'id': 3, 'parent': 1});
    host.emit({'event': 'subsurface', 'id': 4, 'parent': 1});
    host.emit({'event': 'subsurface', 'id': 5, 'x': 1, 'y': 1});
    host.emit({'event': 'popupMoved', 'id': 2, 'x': 'a'});
    host.emit({
      'event': 'childrenReordered',
      'id': 1,
      'children': [1, 'x'],
    });
    await pumpEventQueue();
    final s = service.surfaces[1]!;
    expect(s.size, Size.zero);
    expect(s.minSize, Size.zero);
    expect(s.maxSize, Size.zero);
    expect(s.inputRegion, isNull);
    expect(service.cursor, isNull);
    expect(service.surfaces.containsKey(2), isFalse);
    expect(service.surfaces.containsKey(3), isFalse);
    expect(service.surfaces.containsKey(4), isFalse);
    expect(service.surfaces.containsKey(5), isFalse);
    expect(s.children, isEmpty);

    host.emit({'event': 'inputRegion', 'id': 1, 'rects': [0, 0, 4, 4]});
    host.emit({'event': 'subsurface', 'id': 6, 'parent': 1, 'x': 1, 'y': 1});
    host.emit({
      'event': 'childrenReordered',
      'id': 1,
      'children': [6],
    });
    await pumpEventQueue();
    expect(s.inputRegion!.single.width, 4);
    expect(s.children, [6]);

    host.emit({'event': 'inputRegion', 'id': 1});
    await pumpEventQueue();
    expect(s.inputRegion, isNull);
    service.dispose();
  });

  test('service tracks subsurface layers and textures', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();

    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'texture', 'id': 1, 'textureId': 7});
    host.emit({'event': 'subsurface', 'id': 5, 'parent': 1, 'x': 10, 'y': 20});
    host.emit({'event': 'subsurface', 'id': 6, 'parent': 999, 'x': 0, 'y': 0});
    host.emit({'event': 'subsurfaceMoved', 'id': 5, 'x': 1, 'y': 2});
    host.emit({'event': 'texture', 'id': 5, 'textureId': 8});
    await pumpEventQueue();

    final top = service.surfaces[1]!;
    expect(top.textureId, 7);
    expect(top.children, [5]);
    final sub = service.surfaces[5]!;
    expect(sub.isSub, isTrue);
    expect(sub.isPopup, isFalse);
    expect(sub.offset, const Offset(1, 2));
    expect(sub.textureId, 8);
    expect(service.surfaces[6]!.isSub, isTrue);
    expect(service.toplevels.single.id, 1);

    host.emit({'event': 'subsurfaceClosed', 'id': 5});
    host.emit({'event': 'subsurfaceClosed', 'id': 99});
    await pumpEventQueue();
    expect(top.children, isEmpty);
    expect(service.surfaces.containsKey(5), isFalse);
    service.dispose();
  });

  test('service forwards window requests', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    final requests = <WaylandRequest>[];
    service.requests.listen(requests.add);
    await service.start();
    host.emit({
      'event': 'toplevel',
      'id': 1,
      'textureId': 10,
      'title': '',
      'appId': '',
    });
    await pumpEventQueue();
    host.emit({'event': 'move', 'id': 1});
    host.emit({'event': 'resize', 'id': 1, 'edges': 5});
    host.emit({'event': 'maximize', 'id': 1, 'on': true});
    host.emit({'event': 'fullscreen', 'id': 1, 'on': true});
    host.emit({'event': 'minimize', 'id': 1});
    await pumpEventQueue();
    expect(requests.map((r) => r.type), [
      WaylandRequestType.move,
      WaylandRequestType.resize,
      WaylandRequestType.maximize,
      WaylandRequestType.fullscreen,
      WaylandRequestType.minimize,
    ]);
    expect(requests[1].edges, 5);
    expect(requests[2].on, isTrue);
    service.dispose();
  });

  test('service tracks negotiated decoration mode', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'decoration', 'id': 9, 'mode': 1});
    await pumpEventQueue();
    final s = service.surfaces[1]!;
    expect(s.decorationMode, 2);
    expect(s.clientDecorated, isFalse);

    host.emit({'event': 'decoration', 'id': 1, 'mode': 1});
    await pumpEventQueue();
    expect(s.decorationMode, 1);
    expect(s.clientDecorated, isTrue);

    host.emit({'event': 'decoration', 'id': 1});
    await pumpEventQueue();
    expect(s.clientDecorated, isFalse);
    service.dispose();
  });

  test('self-decorating app id overrides negotiated mode', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(
      host: host,
      selfDecoratedAppIds: {'gitlab.openlyst.devinorium'},
    );
    await service.start();
    host.emit({
      'event': 'toplevel',
      'id': 1,
      'appId': 'gitlab.openlyst.devinorium',
    });
    host.emit({'event': 'decoration', 'id': 1, 'mode': 2});
    host.emit({'event': 'toplevel', 'id': 2});
    host.emit({
      'event': 'appId',
      'id': 2,
      'appId': 'gitlab.openlyst.devinorium',
    });
    await pumpEventQueue();
    final s = service.surfaces[1]!;
    expect(s.decorationMode, 2);
    expect(s.clientDecorated, isTrue);
    expect(service.surfaces[2]!.clientDecorated, isTrue);
    service.dispose();
  });

  test('service tracks shortcut inhibit and pointer lock', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'shortcutsInhibit', 'id': 1, 'on': true});
    host.emit({'event': 'shortcutsInhibit', 'id': 9, 'on': true});
    host.emit({'event': 'pointerLock', 'id': 1, 'on': true});
    await pumpEventQueue();
    expect(service.surfaces[1]!.shortcutsInhibited, isTrue);
    expect(service.pointerLocked, isTrue);
    host.emit({'event': 'shortcutsInhibit', 'id': 1, 'on': false});
    host.emit({'event': 'pointerLock', 'id': 1, 'on': false});
    await pumpEventQueue();
    expect(service.surfaces[1]!.shortcutsInhibited, isFalse);
    expect(service.pointerLocked, isFalse);
  });

  test('service adopts pending subsurfaces and stops', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();

    host.emit({'event': 'subsurface', 'id': 8, 'parent': 7, 'x': 0, 'y': 0});
    host.emit({'event': 'subsurface', 'id': 7, 'parent': 9, 'x': 0, 'y': 0});
    host.emit({'event': 'subsurface', 'id': 5, 'parent': 1, 'x': 0, 'y': 0});
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'popup', 'id': 9, 'parent': 1, 'x': 0, 'y': 0});
    host.emit({
      'event': 'childrenReordered',
      'id': 1,
      'children': [9, 5],
    });
    host.emit({
      'event': 'size',
      'id': 1,
      'w': 100,
      'h': 100,
      'vsx': 1,
      'vsy': 2,
      'vsw': 50,
      'vsh': 40,
    });
    host.emit({'event': 'configureAcked', 'id': 1, 'serial': 7});
    await pumpEventQueue();

    expect(service.surfaces[7]!.children, [8]);
    expect(service.surfaces[1]!.children, [9, 5]);
    expect(service.surfaces[9]!.children, [7]);
    expect(service.surfaces[1]!.vpSrc, const Rect.fromLTWH(1, 2, 50, 40));
    expect(service.surfaces[1]!.ackedSerial, 7);

    await service.pointerAxisStop();
    await service.stop();
    expect(service.available, isFalse);
    expect(service.started, isFalse);
    service.dispose();
  });

  test('service wraps host calls', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();
    await service.launch(['foo', '--bar']);
    await service.configure(1, 800, 600, maximized: true);
    await service.close(1);
    await service.focus(1);
    await service.focus(null);
    await service.pointerMotion(1, 3, 4);
    await service.pointerExit(1);
    await service.pointerButton(0x110, true);
    await service.pointerAxis(1, 2);
    await service.key(30, true);
    expect(host.calls, [
      'launch:foo --bar',
      'configure:1:800x600:true:false',
      'close:1',
      'focus:1',
      'focus:null',
      'motion:1:3.0:4.0',
      'exit:1',
      'button:272:true',
      'axis:1.0:2.0',
      'key:30:true',
    ]);
    service.dispose();
  });

  test('service handles missing plugin and errors', () async {
    final missing = FakeWaylandHost()
      ..startError = MissingPluginException('no plugin');
    final s1 = WaylandService(host: missing);
    await s1.start();
    expect(s1.available, isFalse);

    final failing = FakeWaylandHost()
      ..startError = PlatformException(code: 'x');
    final s2 = WaylandService(host: failing);
    await s2.start();
    expect(s2.available, isFalse);

    final nosocket = FakeWaylandHost()..socket = null;
    final s3 = WaylandService(host: nosocket);
    await s3.start();
    expect(s3.available, isFalse);
  });

  test('channel host invokes method channel', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('oasis/wayland');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'start') return {'socket': 'wayland-3'};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const host = ChannelWaylandHost();
    expect(await host.start(), 'wayland-3');
    await host.launch(['a']);
    await host.configure(1, 2, 3, maximized: true);
    await host.configureLayer(4, 5, 6);
    await host.close(1);
    await host.sessionUnlock();
    await host.activity();
    await host.setIdleTimeouts(60000, 900000);
    await host.focus(2);
    await host.focus(null);
    await host.pointerMotion(1, 1, 2);
    await host.pointerExit(1);
    await host.pointerButton(272, false);
    await host.pointerAxis(0, 1);
    await host.pointerAxisStop();
    await host.inputConfig({'device': 'mouse'});
    await host.touchDown(1, 2, 3, 4);
    await host.touchMotion(2, 5, 6);
    await host.touchUp(2);
    await host.key(30, true);
    await host.stop();
    host.events;
    expect(calls.map((c) => c.method), [
      'start',
      'launch',
      'configure',
      'configureLayer',
      'close',
      'sessionUnlock',
      'activity',
      'idleTimeouts',
      'focus',
      'focus',
      'pointerMotion',
      'pointerExit',
      'pointerButton',
      'pointerAxis',
      'pointerAxisStop',
      'inputConfig',
      'touchDown',
      'touchMotion',
      'touchUp',
      'key',
      'stop',
    ]);
    expect(calls[2].arguments['maximized'], 1);
    expect(calls[3].arguments['w'], 5);
    expect(calls[7].arguments['displayOff'], 60000);
    expect(calls[7].arguments['suspend'], 900000);
    expect(calls[9].arguments['id'], -1);
  });

  test('channel host decodes events', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const methods = MethodChannel('oasis/wayland/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
    const host = ChannelWaylandHost();
    final first = host.events.first;
    await messenger.handlePlatformMessage(
      'oasis/wayland/events',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'event': 'title',
        'id': 4,
        'title': 'Hi',
      }),
      (_) {},
    );
    final event = await first;
    expect(event['id'], 4);
    expect(event['title'], 'Hi');
  });

  test('unavailable service no-ops host calls', () async {
    final host = FakeWaylandHost()..socket = null;
    final service = WaylandService(host: host);
    await service.start();
    await service.launch(['x']);
    await service.configure(1, 1, 1, maximized: true);
    await service.close(1);
    await service.focus(1);
    await service.pointerMotion(1, 0, 0);
    await service.pointerExit(1);
    await service.pointerButton(0x110, true);
    await service.pointerAxis(0, 1);
    await service.activity();
    await service.key(30, true);
    await service.surfaceOutputs(1, const [1]);
    await service.configureOutput('eDP-1', enabled: true);
    expect(host.calls, isEmpty);
    service.dispose();
  });

  test('loadExternalApps scans the system', () async {
    final apps = await loadExternalApps();
    expect(apps, isA<List<OasisApp>>());
  });

  test('keymap covers mapped keys', () {
    expect(evdevCodeFor(PhysicalKeyboardKey.keyA), 30);
    expect(evdevCodeFor(PhysicalKeyboardKey.enter), 28);
    expect(evdevCodeFor(PhysicalKeyboardKey.space), 57);
    expect(evdevCodeFor(PhysicalKeyboardKey.arrowLeft), 105);
    expect(evdevCodeFor(PhysicalKeyboardKey.f12), 88);
    expect(evdevCodeFor(PhysicalKeyboardKey.controlLeft), 29);
    expect(evdevCodeFor(PhysicalKeyboardKey.mediaPlayPause), 164);
    expect(evdevCodeFor(const PhysicalKeyboardKey(0x000e0026)), 30);
    for (var u = 0; u <= 0xFF; u++) {
      evdevCodeFor(PhysicalKeyboardKey(u | 0x70000));
    }
  });

  test('parseExecLine handles quotes and field codes', () {
    expect(parseExecLine('foo --bar %f %u %i %c %k', 'App', 'ic'), [
      'foo',
      '--bar',
      '--icon',
      'ic',
      'App',
    ]);
    expect(parseExecLine('run "a b" %U', 'App', null), ['run', 'a b']);
    expect(parseExecLine('', 'App', null), isEmpty);
  });

  test('parseDesktopEntry variants', () {
    const valid = '''
[Desktop Entry]
Type=Application
Name=Editor
Exec=edit %f
Icon=editor
''';
    final e = parseDesktopEntry(
      'edit',
      valid,
      resolveIcon: (icon) => '/icons/$icon.png',
    );
    expect(e!.id, 'edit');
    expect(e.name, 'Editor');
    expect(e.argv, ['edit']);
    expect(e.iconPath, '/icons/editor.png');

    expect(
      parseDesktopEntry('x', valid.replaceAll('Type=Application', 'Type=Link')),
      isNull,
    );
    expect(parseDesktopEntry('x', '$valid\nNoDisplay=true'), isNull);
    expect(parseDesktopEntry('x', '$valid\nHidden=true'), isNull);
    final term = parseDesktopEntry(
      'x',
      '$valid\nTerminal=true',
      resolveIcon: (_) => null,
    );
    expect(term!.terminal, isTrue);
    expect(parseDesktopEntry('x', valid.replaceAll('Name=Editor', '')), isNull);
    expect(
      parseDesktopEntry('x', valid.replaceAll('Exec=edit %f', 'Exec=')),
      isNull,
    );
    expect(
      parseDesktopEntry(
        'x',
        '[Desktop Entry]\nType=Application\nName=N\nExec=%f\n',
      ),
      isNull,
    );

    const misc = '''
# comment
[Other]
Type=Link
Name=Hidden Name
[Desktop Entry]
Type=Application
Name=First
Name=Second
Exec=prog
Icon=
broken line
''';
    final m = parseDesktopEntry('misc', misc, resolveIcon: (_) => null);
    expect(m!.name, 'Second');
    expect(m.argv, ['prog']);
    expect(m.iconPath, isNull);
  });

  test('desktop entry spec details', () {
    const full = """
[Desktop Entry]
Type=Application
Name=Browser
Name[de]=BrowserDE
GenericName=Web
Keywords=web;net;
Categories=Network;WebBrowser;
Exec=firefox %u
Icon=ff
TryExec=/bin/sh
StartupWMClass=firefox
StartupNotify=true
Actions=new-private;missing;broken;
[Desktop Action new-private]
Name=New Private Window
Exec=firefox --private-window
Icon=ffp
[Desktop Action broken]
Exec=firefox --x
""";
    final e = parseDesktopEntry(
      'ff',
      full,
      resolveIcon: (i) => '/i/$i.png',
      executableExists: (_) => true,
    );
    expect(e!.name, 'Browser');
    expect(e.genericName, 'Web');
    expect(e.keywords, ['web', 'net']);
    expect(e.categories, ['Network', 'WebBrowser']);
    expect(e.startupWmClass, 'firefox');
    expect(e.startupNotify, isTrue);
    expect(e.actions.single.id, 'new-private');
    expect(e.actions.single.name, 'New Private Window');
    expect(e.actions.single.argv, ['firefox', '--private-window']);
    expect(e.actions.single.iconPath, '/i/ffp.png');

    final de = parseDesktopEntry(
      'ff',
      full,
      locale: 'de_DE',
      resolveIcon: (_) => null,
      executableExists: (_) => true,
    );
    expect(de!.name, 'BrowserDE');

    final oa = desktopAppToOasis(e);
    expect(oa.actions.single.name, 'New Private Window');
    expect(oa.actions.single.exec, ['firefox', '--private-window']);

    expect(
      parseDesktopEntry('ff', '$full\n', executableExists: (_) => false),
      isNull,
    );
    expect(
      parseDesktopEntry(
        'x',
        full.replaceAll('StartupWMClass=firefox', 'OnlyShowIn=GNOME'),
        desktop: 'Oasis',
        resolveIcon: (_) => null,
        executableExists: (_) => true,
      ),
      isNull,
    );
  });

  test('desktop entry OnlyShowIn NotShowIn and Terminal exec', () {
    const base = """
[Desktop Entry]
Type=Application
Name=T
Exec=t
""";
    expect(
      parseDesktopEntry(
        't',
        '$base\nOnlyShowIn=GNOME;KDE;',
        desktop: 'KDE',
        resolveIcon: (_) => null,
      ),
      isNotNull,
    );
    expect(
      parseDesktopEntry(
        't',
        '$base\nOnlyShowIn=GNOME;',
        desktop: 'Oasis',
        resolveIcon: (_) => null,
      ),
      isNull,
    );
    expect(
      parseDesktopEntry(
        't',
        '$base\nNotShowIn=Oasis;',
        desktop: 'Oasis',
        resolveIcon: (_) => null,
      ),
      isNull,
    );
    expect(
      parseDesktopEntry(
        't',
        '$base\nNotShowIn=GNOME;',
        desktop: 'Oasis',
        resolveIcon: (_) => null,
      ),
      isNotNull,
    );

    final term = parseDesktopEntry(
      't',
      '$base\nTerminal=true',
      resolveIcon: (_) => null,
    )!;
    final app = desktopAppToOasis(
      term,
      environment: const {},
      which: (_) => null,
    );
    expect(app.exec, contains('-e'));
    expect(app.exec!.last, 't');

    expect(
      desktopAppToOasis(term, environment: const {'TERMINAL': 'foot'}).exec,
      ['foot', 't'],
    );
    expect(
      desktopAppToOasis(
        term,
        environment: const {'TERMINAL': 'wezterm'},
      ).exec,
      ['wezterm', 'start', '--', 't'],
    );
    expect(
      desktopAppToOasis(
        term,
        environment: const {'TERMINAL': '/opt/kitty'},
      ).exec,
      ['/opt/kitty', 't'],
    );
    expect(
      desktopAppToOasis(
        term,
        environment: const {'TERMINAL': 'oddterm'},
      ).exec,
      ['oddterm', '-e', 't'],
    );
    expect(
      desktopAppToOasis(
        term,
        which: (name) => name == 'alacritty' ? name : null,
      ).exec,
      ['alacritty', '-e', 't'],
    );
    expect(desktopAppToOasis(term, which: (_) => null).exec, [
      'x-terminal-emulator',
      '-e',
      't',
    ]);
  });

  test('parseExecLine unescapes sequences', () {
    expect(parseExecLine('run "a\\"b" x\\sy', 'N', null), [
      'run',
      'a"b',
      'x y',
    ]);
    expect(parseExecLine('run a\\tb c\\nd e\\rf', 'N', null), [
      'run',
      'a\tb',
      'c\nd',
      'e\rf',
    ]);
    expect(parseExecLine('app 100%%', 'N', null), ['app', '100%']);
    expect(parseExecLine('app %% %F', 'N', null), ['app', '%']);
  });

  test('default executableExists honours TryExec', () {
    const contents = """
[Desktop Entry]
Type=Application
Name=S
Exec=s
TryExec=/bin/sh
""";
    expect(
      parseDesktopEntry('s', contents, resolveIcon: (_) => null),
      isNotNull,
    );
    expect(
      parseDesktopEntry(
        's',
        contents.replaceAll('/bin/sh', '/nonexistent-tool-xyz'),
        resolveIcon: (_) => null,
      ),
      isNull,
    );
    expect(
      parseDesktopEntry(
        's',
        contents.replaceAll('/bin/sh', 'sh'),
        resolveIcon: (_) => null,
      ),
      isNotNull,
    );
    expect(
      parseDesktopEntry(
        's',
        contents.replaceAll('/bin/sh', 'definitely-missing-binary-xyz'),
        resolveIcon: (_) => null,
      ),
      isNull,
    );
  });

  test('findIconPath resolves files', () {
    expect(findIconPath(''), isNull);
    expect(findIconPath('no-such-oasis-icon-xyz-123'), isNull);
    expect(findIconPath('/no/such/icon.png'), isNull);
    final dir = _tmpDir('icons');
    final png = File('${dir.path}/i.png');
    png.writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    expect(findIconPath(png.path), png.path);
    for (final size in [
      '256x256',
      '128x128',
      '96x96',
      '64x64',
      '48x48',
      '32x32',
      '24x24',
      '16x16',
    ]) {
      final themed = File('${dir.path}/hicolor/$size/apps/themed.png')
        ..createSync(recursive: true);
      themed.writeAsBytesSync(const [0x89]);
      expect(findIconPath('themed', roots: [dir.path]), themed.path);
      themed.deleteSync();
    }
    final pix = File('${dir.path}/pix.png')..writeAsBytesSync(const [0x89]);
    expect(findIconPath('pix', roots: [dir.path]), pix.path);
    expect(findIconPath('pix.png', roots: [dir.path]), pix.path);
  });

  test('findIconPath honours gtk icon theme from settings', () {
    final home = _tmpDir('home');
    File('${home.path}/.config/gtk-3.0/settings.ini')
      ..createSync(recursive: true)
      ..writeAsStringSync('[Settings]\ngtk-icon-theme-name=Custom\n');
    final dir = _tmpDir('icons2');
    final themed = File('${dir.path}/Custom/48x48/apps/x.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [0x89]);
    expect(
      findIconPath('x', roots: [dir.path], environment: {'HOME': home.path}),
      themed.path,
    );
  });

  test('findIconPath honours index.theme', () {
    final dir = _tmpDir('themeicons');
    void png(String rel) {
      File('${dir.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [0x89]);
    }

    File('${dir.path}/adwaita/index.theme')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[Icon Theme]
Directories=16x16/apps,48x48/apps,scalable/apps,64x64/apps
ScaledDirectories=48x48/apps@2
Inherits=base-theme,other-theme
[16x16/apps]
Size=16
Type=Fixed
[48x48/apps]
Size=48
Type=Fixed
[scalable/apps]
Type=Scalable
MinSize=24
MaxSize=256
[64x64/apps]
Size=64
Type=Threshold
Threshold=4
''');
    File('${dir.path}/base-theme/index.theme')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[Icon Theme]
Directories=32x32/apps
[32x32/apps]
Size=32
''');
    png('adwaita/48x48/apps/exact.png');
    png('adwaita/scalable/apps/scaled.svg');
    png('adwaita/64x64/apps/near.png');
    png('base-theme/32x32/apps/inherited.png');
    png('adwaita/scalable/apps/second.svg');
    png('adwaita/64x64/apps/second.png');
    png('adwaita/48x48/apps@2/retina.png');
    png('other-theme/32x32/apps/fallback.png');

    expect(
      findIconPath('exact', roots: [dir.path], theme: 'adwaita'),
      endsWith('48x48/apps/exact.png'),
    );
    expect(
      findIconPath('scaled', roots: [dir.path], theme: 'adwaita'),
      endsWith('scalable/apps/scaled.svg'),
    );
    expect(
      findIconPath('near', roots: [dir.path], theme: 'adwaita'),
      endsWith('64x64/apps/near.png'),
    );
    expect(
      findIconPath('inherited', roots: [dir.path], theme: 'adwaita'),
      endsWith('32x32/apps/inherited.png'),
    );
    expect(
      findIconPath('fallback', roots: [dir.path], theme: 'adwaita'),
      endsWith('32x32/apps/fallback.png'),
    );
    expect(
      findIconPath('retina', roots: [dir.path], theme: 'adwaita'),
      endsWith('48x48/apps@2/retina.png'),
    );
    expect(
      findIconPath('second', roots: [dir.path], theme: 'adwaita'),
      endsWith('scalable/apps/second.svg'),
    );
    expect(
      findIconPath('scaled', roots: [dir.path], theme: 'adwaita', size: 16),
      endsWith('scalable/apps/scaled.svg'),
    );
    expect(
      findIconPath('scaled', roots: [dir.path], theme: 'adwaita', size: 300),
      endsWith('scalable/apps/scaled.svg'),
    );
    expect(
      findIconPath('near', roots: [dir.path], theme: 'adwaita', size: 62),
      endsWith('64x64/apps/near.png'),
    );
    expect(
      findIconPath('missing-xyz', roots: [dir.path], theme: 'adwaita'),
      isNull,
    );
  });

  test('watchDesktopDirs emits on change', () async {
    final dir = _tmpDir('watch');
    final events = watchDesktopDirs(
      dirs: [dir.path],
      debounce: const Duration(milliseconds: 10),
    ).first;
    File('${dir.path}/x.desktop').writeAsStringSync('x');
    await events.timeout(const Duration(seconds: 5));

    final child = '${dir.path}/nope';
    var fired = 0;
    final sub = watchDesktopDirs(
      dirs: [child],
      debounce: const Duration(milliseconds: 10),
    ).listen((_) => fired++);
    Directory(child).createSync();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fired, greaterThan(0));
    await sub.cancel();

    final gone = watchDesktopDirs(
      dirs: ['${dir.path}/missing/nested'],
      debounce: const Duration(milliseconds: 10),
    ).listen((_) {});
    await gone.cancel();
  });

  test('loadDesktopEntries scans directories', () async {
    final dir = _tmpDir('apps');
    File('${dir.path}/good.desktop').writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Good
Exec=good
Icon=good
''');
    File('${dir.path}/hidden.desktop').writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Bad
Exec=bad
NoDisplay=true
''');
    File('${dir.path}/notes.txt').writeAsStringSync('nope');
    Directory('${dir.path}/nested/deep').createSync(recursive: true);
    File('${dir.path}/nested/deep/tool.desktop').writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Tool
Exec=tool
''');
    Link('${dir.path}/loop').createSync(dir.path);
    File('${dir.path}/odd.desktop.bak.desktop').writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Odd
Exec=odd
''');
    final entries = await loadDesktopEntries(
      dirs: [dir.path, '${dir.path}/missing'],
    );
    expect(
      {for (final e in entries) e.name},
      containsAll(['Good', 'Tool', 'Odd']),
    );
    expect(
      entries.firstWhere((e) => e.name == 'Tool').id,
      'nested-deep-tool',
    );
    expect(entries.firstWhere((e) => e.name == 'Odd').id, 'odd.desktop.bak');
    final all = await loadDesktopEntries();
    expect(all, isA<List<DesktopAppEntry>>());
    expect(desktopSearchDirs().first.endsWith('applications'), isTrue);
    final app = desktopAppToOasis(
      entries.firstWhere((e) => e.name == 'Good'),
    );
    expect(app.isExternal, isTrue);
    expect(app.exec, ['good']);
    expect(app.builder(_StubContext()), isNotNull);
  });
}

void surfaceViewCoverage() {
  testWidgets('surface view releases pressed keys on focus loss', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final other = FocusNode();
    addTearDown(other.dispose);
    await pumpOasis(
      tester,
      Row(
        children: [
          Expanded(
            child: WaylandSurfaceView(
              surface: WaylandSurface(id: 1),
              service: service,
              focused: true,
              maximized: false,
            ),
          ),
          Focus(focusNode: other, child: const SizedBox(width: 10)),
        ],
      ),
      size: const Size(400, 300),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(host.calls, contains('key:29:true'));
    other.requestFocus();
    await tester.pump();
    expect(host.calls, contains('key:29:false'));
  });

  testWidgets('inhibited surface forwards shell chords', (tester) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final surface = WaylandSurface(id: 1);
    service.surfaces[1] = surface;
    await pumpOasis(
      tester,
      WaylandSurfaceView(
        surface: surface,
        service: service,
        focused: true,
        maximized: false,
      ),
      size: const Size(400, 300),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    expect(host.calls, isNot(contains('key:15:true')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    surface.shortcutsInhibited = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(host.calls, contains('key:56:true'));
    expect(host.calls, contains('key:15:true'));
    expect(host.calls, contains('key:15:false'));

    // The Linux super key also keeps shell chords away from the client.
    surface.shortcutsInhibited = false;
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    expect(host.calls, isNot(contains('key:32:true')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.superKey,
      physicalKey: PhysicalKeyboardKey.superKey,
      platform: 'fuchsia',
    );

    // A bare space goes through to the client.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(host.calls, contains('key:57:true'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });

  testWidgets('surface view handles cancel and trackpad gestures', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({'event': 'size', 'id': 1, 'w': 400, 'h': 300});
    await tester.pump();
    await pumpOasis(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          height: 150,
          child: WaylandSurfaceView(
            surface: service.surfaces[1]!,
            service: service,
            focused: false,
            maximized: false,
          ),
        ),
      ),
      size: const Size(400, 300),
    );
    final center = tester.getCenter(find.byType(WaylandSurfaceView));

    final touch = await tester.startGesture(
      center,
      kind: PointerDeviceKind.touch,
    );
    await touch.cancel();
    await tester.pump();

    final mouse = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.cancel();
    await tester.pump();

    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, pan: const Offset(4, 5));
    await pad.panZoomEnd();
    await tester.pump();
    expect(host.calls, contains('axis:4.0:5.0'));
  });

  testWidgets('popup view hits subsurfaces and handles cancel', (tester) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final popup = WaylandSurface(
      id: 9,
      parentId: 1,
      textureId: 100,
      size: const Size(100, 100),
    );
    final sub = WaylandSurface(
      id: 7,
      parentId: 9,
      isSub: true,
      offset: const Offset(10, 10),
      size: const Size(30, 30),
    );
    popup.children.addAll([7, 8]);
    service.surfaces[7] = sub;
    await pumpOasis(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: WaylandPopupView(surface: popup, service: service),
      ),
      size: const Size(400, 300),
    );
    final gesture = await tester.startGesture(const Offset(15, 15));
    await gesture.up();
    await tester.pump();
    expect(host.calls, contains('motion:7:5.0:5.0'));

    sub.inputRegion = [const Rect.fromLTWH(0, 0, 5, 5)];
    final second = await tester.startGesture(const Offset(25, 25));
    await second.up();
    await tester.pump();
    expect(host.calls, contains('motion:9:25.0:25.0'));

    final third = await tester.startGesture(const Offset(15, 15));
    await third.cancel();
    await tester.pump();
  });
}

class _StubContext extends Fake implements BuildContext {}

Directory _tmpDir(String name) {
  final dir = Directory('${Directory.systemTemp.path}/oasis_test_$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

void layerViewCoverage() {
  test('service handles layer lock and power events', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    host.emit({
      'event': 'layer',
      'id': 5,
      'textureId': 7,
      'ns': 'panel',
      'layer': 2,
      'anchor': 5,
      'exclusive': 30,
      'edge': 4,
      'kb': 1,
      'ml': 1,
      'mt': 2,
      'mr': 3,
      'mb': 4,
      'dw': 400,
      'dh': 40,
    });
    host.emit({'event': 'size', 'id': 5, 'w': 400, 'h': 40});
    host.emit({
      'event': 'layer',
      'id': 8,
      'anchor': 1,
      'exclusive': 20,
      'edge': 1,
    });
    host.emit({'event': 'size', 'id': 8, 'w': 100, 'h': 20});
    host.emit({
      'event': 'layer',
      'id': 9,
      'anchor': 2,
      'exclusive': 10,
      'edge': 0,
    });
    host.emit({'event': 'size', 'id': 9, 'w': 100, 'h': 10});
    host.emit({
      'event': 'layer',
      'id': 10,
      'anchor': 8,
      'exclusive': 15,
      'edge': 0,
    });
    host.emit({'event': 'size', 'id': 10, 'w': 15, 'h': 100});
    host.emit({'event': 'lockSurface', 'id': 6, 'textureId': 9});
    host.emit({'event': 'sessionLock'});
    host.emit({'event': 'outputPower', 'on': false});
    await Future<void>.delayed(Duration.zero);
    final s = service.surfaces[5]!;
    expect(s.isLayer, isTrue);
    expect(s.layerNamespace, 'panel');
    expect(s.layerIndex, 2);
    expect(s.layerAnchor, 5);
    expect(s.layerExclusive, 30);
    expect(s.layerExclusiveEdge, 4);
    expect(s.layerKeyboard, 1);
    expect(s.layerMargins, const EdgeInsets.fromLTRB(1, 2, 3, 4));
    expect(s.layerDesired, const Size(400, 40));
    expect(s.isPopup, isFalse);
    expect(service.toplevels, isEmpty);
    expect(service.layerSurfaces(2), contains(s));
    expect(service.lockSurfaces.single.id, 6);
    expect(service.sessionLocked, isTrue);
    expect(service.displayOff, isTrue);
    expect(service.exclusiveInsets, const EdgeInsets.fromLTRB(30, 20, 15, 10));
    await service.configureLayer(5, 400, 40);
    await service.sessionUnlock();
    expect(host.calls, contains('configureLayer:5:400x40'));
    expect(host.calls, contains('sessionUnlock'));
    host.emit({'event': 'sessionUnlock'});
    host.emit({'event': 'outputPower', 'on': true});
    host.emit({'event': 'layerClosed', 'id': 5});
    host.emit({'event': 'lockSurfaceClosed', 'id': 6});
    await Future<void>.delayed(Duration.zero);
    expect(service.sessionLocked, isFalse);
    expect(service.displayOff, isFalse);
    expect(service.surfaces.containsKey(5), isFalse);
    expect(service.surfaces.containsKey(6), isFalse);
    expect(
      service.exclusiveInsets,
      const EdgeInsets.only(top: 20, right: 15, bottom: 10),
    );
    final dead = WaylandService(host: FakeWaylandHost()..socket = null);
    addTearDown(dead.dispose);
    await dead.configureLayer(5, 1, 1);
    await dead.sessionUnlock();
    await dead.activity();
  });

  test('layerSurfaceRect resolves anchors and margins', () {
    const output = Size(800, 600);
    final s = WaylandSurface(id: 1)..layerDesired = const Size(100, 50);
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(350, 275, 100, 50));
    s.layerAnchor = 1;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(350, 0, 100, 50));
    s.layerAnchor = 2;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(350, 550, 100, 50));
    s.layerAnchor = 4;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(0, 275, 100, 50));
    s.layerAnchor = 8;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(700, 275, 100, 50));
    s.layerAnchor = 1 | 4 | 8;
    s.layerMargins = const EdgeInsets.fromLTRB(10, 5, 20, 0);
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(10, 5, 770, 50));
    s.layerAnchor = 2 | 4 | 8;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(10, 550, 770, 50));
    s.layerAnchor = 4 | 1 | 2;
    s.layerDesired = const Size(100, 50);
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(10, 5, 100, 595));
    s.layerAnchor = 8 | 1 | 2;
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(680, 5, 100, 595));
    s.layerAnchor = 0;
    s.layerDesired = Size.zero;
    s.size = const Size(60, 30);
    expect(layerSurfaceRect(s, output), const Rect.fromLTWH(370, 285, 60, 30));
  });

  test('surfaceCoordsAt and subSurfaceHit resolve layers', () {
    final service = WaylandService(host: FakeWaylandHost());
    addTearDown(service.dispose);
    final root = WaylandSurface(id: 1, size: const Size(400, 40));
    final sub = WaylandSurface(
      id: 7,
      parentId: 1,
      isSub: true,
      offset: const Offset(10, 10),
      size: const Size(30, 30),
    );
    root.children.add(7);
    service.surfaces[7] = sub;
    expect(
      surfaceCoordsAt(root, const Offset(30, 225), const Size(800, 600)),
      const Offset(15, 15),
    );
    final hit = subSurfaceHit(service, root, const Offset(15, 15));
    expect(hit?.$1.id, 7);
    expect(hit?.$2, const Offset(5, 5));
    expect(subSurfaceHit(service, root, const Offset(300, 5)), isNull);
    sub.inputRegion = [const Rect.fromLTWH(0, 0, 2, 2)];
    expect(subSurfaceHit(service, root, const Offset(15, 15)), isNull);
    final pressed = <int>{};
    expect(
      waylandKeyEvent(
        service,
        pressed,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
      ),
      KeyEventResult.handled,
    );
    expect(pressed, contains(30));
    expect(
      waylandKeyEvent(
        service,
        pressed,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        escReserved: true,
      ),
      KeyEventResult.ignored,
    );
  });

  testWidgets('layer surface view configures and forwards input', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final s = WaylandSurface(id: 5, textureId: 7)
      ..isLayer = true
      ..layerKeyboard = 2
      ..size = const Size(790, 600);
    service.surfaces[5] = s;
    final other = FocusNode();
    addTearDown(other.dispose);
    await pumpOasis(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            Expanded(
              child: LayerSurfaceView(surface: s, service: service),
            ),
            Focus(focusNode: other, child: const SizedBox(width: 10)),
          ],
        ),
      ),
      size: const Size(800, 600),
    );
    await tester.pump();
    expect(host.calls, contains('configureLayer:5:790x600'));
    s.children.add(7);
    service.surfaces[7] = WaylandSurface(
      id: 7,
      parentId: 5,
      isSub: true,
      offset: const Offset(10, 10),
      size: const Size(30, 30),
    );
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        position: Offset(100, 300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(host.calls, contains('motion:5:100.0:300.0'));
    await tester.sendEventToBinding(
      const PointerHoverEvent(
        position: Offset(795, 300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(host.calls, contains('exit:5'));
    final drag = await tester.startGesture(const Offset(15, 15));
    await drag.moveTo(const Offset(100, 300));
    await drag.up();
    await tester.pump();
    final subTap = await tester.startGesture(const Offset(15, 15));
    await subTap.up();
    await tester.pump();
    expect(host.calls, contains('motion:7:5.0:5.0'));
    final gesture = await tester.startGesture(const Offset(15, 15));
    await gesture.up();
    await tester.pump();
    expect(host.calls, contains('focus:5'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(host.calls, contains('key:29:true'));
    other.requestFocus();
    await tester.pump();
    expect(host.calls, contains('key:29:false'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(15, 15),
        scrollDelta: const Offset(0, -40),
      ),
    );
    await tester.pump();
    expect(host.calls.where((c) => c.startsWith('axis:')), isNotEmpty);
    final cancel = await tester.startGesture(const Offset(15, 15));
    await cancel.cancel();
    await tester.pump();
    expect(host.calls, contains('button:272:true'));
    expect(host.calls, contains('button:272:false'));
  });

  testWidgets('layer surface view without interactivity skips focus', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final s = WaylandSurface(id: 5)
      ..isLayer = true
      ..size = const Size(100, 100);
    service.surfaces[5] = s;
    await pumpOasis(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: LayerSurfaceView(surface: s, service: service),
      ),
      size: const Size(800, 600),
    );
    final gesture = await tester.startGesture(const Offset(15, 15));
    await gesture.up();
    await tester.pump();
    expect(host.calls, isNot(contains('focus:5')));
  });

  testWidgets('lock surface view grabs focus and forwards keys', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final s = WaylandSurface(id: 6, textureId: 9)..isLock = true;
    service.surfaces[6] = s;
    final other = FocusNode();
    addTearDown(other.dispose);
    await pumpOasis(
      tester,
      Row(
        children: [
          Expanded(
            child: LockSurfaceView(surface: s, service: service),
          ),
          Focus(focusNode: other, child: const SizedBox(width: 10)),
        ],
      ),
      size: const Size(800, 600),
    );
    await tester.pump();
    expect(host.calls, contains('focus:6'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    expect(host.calls, contains('key:30:true'));
    other.requestFocus();
    await tester.pump();
    expect(host.calls, contains('key:30:false'));
  });
}

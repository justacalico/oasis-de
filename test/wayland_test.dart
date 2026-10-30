import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/wayland/desktop_entries.dart';
import 'package:oasis_de/wayland/keymap.dart';
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
    calls.add('configure:$id:${width}x$height:$maximized:$fullscreen');
  }

  @override
  Future<void> close(int id) async {
    calls.add('close:$id');
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
  Future<void> touchDown(int id, int tid, double x, double y) async {}

  @override
  Future<void> touchMotion(int tid, double x, double y) async {}

  @override
  Future<void> touchUp(int tid) async {}

  @override
  Future<void> key(int code, bool pressed) async {
    calls.add('key:$code:$pressed');
  }
}

void main() {
  surfaceViewCoverage();
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

  test('service adopts pending subsurfaces and stops', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();

    host.emit({'event': 'subsurface', 'id': 8, 'parent': 7, 'x': 0, 'y': 0});
    host.emit({'event': 'subsurface', 'id': 7, 'parent': 9, 'x': 0, 'y': 0});
    host.emit({'event': 'subsurface', 'id': 5, 'parent': 1, 'x': 0, 'y': 0});
    host.emit({'event': 'toplevel', 'id': 1});
    host.emit({
      'event': 'popup',
      'id': 9,
      'parent': 1,
      'x': 0,
      'y': 0,
    });
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
    await host.close(1);
    await host.focus(2);
    await host.focus(null);
    await host.pointerMotion(1, 1, 2);
    await host.pointerExit(1);
    await host.pointerButton(272, false);
    await host.pointerAxis(0, 1);
    await host.pointerAxisStop();
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
      'close',
      'focus',
      'focus',
      'pointerMotion',
      'pointerExit',
      'pointerButton',
      'pointerAxis',
      'pointerAxisStop',
      'touchDown',
      'touchMotion',
      'touchUp',
      'key',
      'stop',
    ]);
    expect(calls[2].arguments['maximized'], 1);
    expect(calls[5].arguments['id'], -1);
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
    await service.key(30, true);
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
    expect(m!.name, 'First');
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
    final app = desktopAppToOasis(term);
    expect(app.exec, contains('-e'));
    expect(app.exec!.last, 't');

    expect(
      desktopAppToOasis(
        term,
        environment: const {'TERMINAL': 'foot'},
      ).exec,
      ['foot', '-e', 't'],
    );
    expect(
      desktopAppToOasis(
        term,
        which: (name) => name == 'alacritty' ? name : null,
      ).exec,
      ['alacritty', '-e', 't'],
    );
    expect(
      desktopAppToOasis(term, which: (_) => null).exec,
      ['x-terminal-emulator', '-e', 't'],
    );
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
      findIconPath(
        'x',
        roots: [dir.path],
        environment: {'HOME': home.path},
      ),
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
    final entries = await loadDesktopEntries(
      dirs: [dir.path, '${dir.path}/missing'],
    );
    expect(entries.single.name, 'Good');
    final all = await loadDesktopEntries();
    expect(all, isA<List<DesktopAppEntry>>());
    expect(desktopSearchDirs().first.endsWith('applications'), isTrue);
    final app = desktopAppToOasis(entries.single);
    expect(app.isExternal, isTrue);
    expect(app.exec, ['good']);
    expect(app.builder(_StubContext()), isNotNull);
  });
}

void surfaceViewCoverage() {
  testWidgets('surface view releases pressed keys on focus loss',
      (tester) async {
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

  testWidgets('surface view handles cancel and trackpad gestures',
      (tester) async {
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

    final pad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, pan: const Offset(4, 5));
    await pad.panZoomEnd();
    await tester.pump();
    expect(host.calls, contains('axis:4.0:5.0'));
  });

  testWidgets('popup view hits subsurfaces and handles cancel',
      (tester) async {
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

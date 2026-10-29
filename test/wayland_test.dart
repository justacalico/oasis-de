import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/wayland/desktop_entries.dart';
import 'package:oasis_de/wayland/keymap.dart';
import 'package:oasis_de/wayland/wayland_host.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_ui/oasis_ui.dart';

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
  Future<void> launch(List<String> argv) async {
    calls.add('launch:${argv.join(' ')}');
  }

  @override
  Future<void> configure(
      int id, int width, int height, bool maximized) async {
    calls.add('configure:$id:${width}x$height:$maximized');
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
  Future<void> pointerAxis(double dx, double dy) async {
    calls.add('axis:$dx:$dy');
  }

  @override
  Future<void> key(int code, bool pressed) async {
    calls.add('key:$code:$pressed');
  }
}

void main() {
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
    await pumpEventQueue();
    final s = service.surfaces[1]!;
    expect(s.title, 'New');
    expect(s.appId, 'org.x');
    expect(s.size, const Size(640, 480));

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

  test('service wraps host calls', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    await service.start();
    await service.launch(['foo', '--bar']);
    await service.configure(1, 800, 600, true);
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
      'configure:1:800x600:true',
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
      ..startError =
          MissingPluginException('no plugin');
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
    addTearDown(
        () => messenger.setMockMethodCallHandler(channel, null));

    const host = ChannelWaylandHost();
    expect(await host.start(), 'wayland-3');
    await host.launch(['a']);
    await host.configure(1, 2, 3, true);
    await host.close(1);
    await host.focus(2);
    await host.focus(null);
    await host.pointerMotion(1, 1, 2);
    await host.pointerExit(1);
    await host.pointerButton(272, false);
    await host.pointerAxis(0, 1);
    await host.key(30, true);
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
      'key',
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
    addTearDown(
        () => messenger.setMockMethodCallHandler(methods, null));
    const host = ChannelWaylandHost();
    final first = host.events.first;
    await messenger.handlePlatformMessage(
      'oasis/wayland/events',
      const StandardMethodCodec().encodeSuccessEnvelope(
          {'event': 'title', 'id': 4, 'title': 'Hi'}),
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
    await service.configure(1, 1, 1, true);
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
    expect(evdevCodeFor(PhysicalKeyboardKey.mediaPlayPause),
        isNull);
    for (var u = 0; u <= 0xFF; u++) {
      evdevCodeFor(PhysicalKeyboardKey(u | 0x70000));
    }
  });

  test('parseExecLine handles quotes and field codes', () {
    expect(parseExecLine('foo --bar %f %u %i %c %k', 'App', 'ic'),
        ['foo', '--bar', '--icon', 'ic', 'App']);
    expect(parseExecLine('run "a b" %U', 'App', null),
        ['run', 'a b']);
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
    final e = parseDesktopEntry('edit', valid,
        resolveIcon: (icon) => '/icons/$icon.png');
    expect(e!.id, 'edit');
    expect(e.name, 'Editor');
    expect(e.argv, ['edit']);
    expect(e.iconPath, '/icons/editor.png');

    expect(
        parseDesktopEntry('x', valid.replaceAll(
            'Type=Application', 'Type=Link')),
        isNull);
    expect(parseDesktopEntry('x', '$valid\nNoDisplay=true'),
        isNull);
    expect(parseDesktopEntry('x', '$valid\nHidden=true'), isNull);
    expect(
        parseDesktopEntry('x', '$valid\nTerminal=true'), isNull);
    expect(parseDesktopEntry('x', valid.replaceAll(
        'Name=Editor', '')), isNull);
    expect(parseDesktopEntry('x', valid.replaceAll(
        'Exec=edit %f', 'Exec=')), isNull);
    expect(parseDesktopEntry('x', '[Desktop Entry]\nType=Application\nName=N\nExec=%f\n'), isNull);

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
    final m = parseDesktopEntry('misc', misc,
        resolveIcon: (_) => null);
    expect(m!.name, 'First');
    expect(m.argv, ['prog']);
    expect(m.iconPath, isNull);
  });

  test('findIconPath resolves files', () {
    expect(findIconPath(''), isNull);
    expect(
        findIconPath(
            'no-such-oasis-icon-xyz-123'),
        isNull);
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
      final themed = File(
          '${dir.path}/hicolor/$size/apps/themed.png')
        ..createSync(recursive: true);
      themed.writeAsBytesSync(const [0x89]);
      expect(
          findIconPath('themed', roots: [dir.path]),
          themed.path);
      themed.deleteSync();
    }
    final pix = File('${dir.path}/pix.png')
      ..writeAsBytesSync(const [0x89]);
    expect(findIconPath('pix', roots: [dir.path]), pix.path);
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
    final entries =
        await loadDesktopEntries(dirs: [dir.path, '${dir.path}/missing']);
    expect(entries.single.name, 'Good');
    final all = await loadDesktopEntries();
    expect(all, isA<List<DesktopAppEntry>>());
    expect(desktopSearchDirs().first.endsWith('applications'),
        isTrue);
    final app = desktopAppToOasis(entries.single);
    expect(app.isExternal, isTrue);
    expect(app.exec, ['good']);
    expect(app.builder(_StubContext()), isNotNull);
  });
}

class _StubContext extends Fake implements BuildContext {}

Directory _tmpDir(String name) {
  final dir = Directory(
      '${Directory.systemTemp.path}/oasis_test_$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

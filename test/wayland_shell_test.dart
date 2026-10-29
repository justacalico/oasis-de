import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_de/wayland/wayland_surface_view.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';
import 'wayland_test.dart' show FakeWaylandHost;

OasisApp _builtin(String id) => OasisApp(
  id: id,
  name: 'App $id',
  icon: Icons.circle,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  builder: (_) => const SizedBox(),
);

OasisApp _external(String id) => OasisApp(
  id: 'desktop:$id',
  name: 'Ext $id',
  icon: Icons.apps,
  iconColors: const [Color(0xFF000000), Color(0xFF111111)],
  exec: [id],
  builder: (_) => const SizedBox(),
);

Future<WaylandService> _service(FakeWaylandHost host) async {
  final service = WaylandService(host: host);
  await service.start();
  return service;
}

void _emitToplevel(
  FakeWaylandHost host, {
  int id = 1,
  String title = '',
  String appId = '',
}) {
  host.emit({
    'event': 'toplevel',
    'id': id,
    'textureId': 100 + id,
    'title': title,
    'appId': appId,
  });
}

void main() {
  setUpAll(loadOasisFonts);

  test('external app cannot open without compositor', () {
    final host = FakeWaylandHost()..socket = null;
    final service = WaylandService(host: host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    expect(c.windows, isEmpty);
    c.dispose();
    service.dispose();
  });

  test('external app launch creates pending window', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    expect(c.windows.single.launching, isTrue);
    expect(host.calls, contains('launch:x'));

    _emitToplevel(host, title: 'Ext Window', appId: 'x');
    await pumpEventQueue();
    expect(c.windows.single.launching, isFalse);
    expect(c.windows.single.surface?.id, 1);
    expect(c.windows.single.displayTitle, 'Ext Window');

    host.emit({'event': 'toplevelClosed', 'id': 1});
    await pumpEventQueue();
    expect(c.windows, isEmpty);
    c.dispose();
    service.dispose();
  });

  test('surprise toplevel gets a window and app match', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(
      apps: [_builtin('a'), _external('gedit')],
      wayland: service,
    );
    _emitToplevel(host, id: 7, title: 'Titled', appId: '');
    await pumpEventQueue();
    expect(c.windows.single.surface?.id, 7);
    expect(c.windows.single.app.id, 'external:7');
    expect(c.windows.single.app.name, 'Titled');
    expect(c.windows.single.app.builder(_StubContext()), isNotNull);

    host.emit({'event': 'appId', 'id': 7, 'appId': 'gedit'});
    await pumpEventQueue();
    expect(c.windows.single.app.id, 'desktop:gedit');

    _emitToplevel(host, id: 8, title: '', appId: 'orphan');
    await pumpEventQueue();
    expect(c.windows.last.app.name, 'orphan');
    c.dispose();
    service.dispose();
  });

  test('close on surface window sends close to client', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    await pumpEventQueue();
    c.closeWindow(c.windows.single.id);
    expect(host.calls, contains('close:1'));
    expect(c.windows.single.surface, isNotNull);
    c.dispose();
    service.dispose();
  });

  test('client requests drive window state', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    await pumpEventQueue();
    final w = c.windows.single;

    host.emit({'event': 'move', 'id': 1});
    await pumpEventQueue();
    expect(c.surfaceDragWindowId, w.id);
    c.endSurfaceGesture();
    expect(c.surfaceDragWindowId, isNull);

    host.emit({'event': 'maximize', 'id': 1, 'on': true});
    await pumpEventQueue();
    expect(w.zoomed, isTrue);
    host.emit({'event': 'fullscreen', 'id': 1, 'on': true});
    await pumpEventQueue();
    expect(w.fullscreen, isTrue);
    expect(w.zoomed, isTrue);
    host.emit({'event': 'fullscreen', 'id': 1, 'on': false});
    await pumpEventQueue();
    expect(w.fullscreen, isFalse);
    host.emit({'event': 'maximize', 'id': 1, 'on': false});
    await pumpEventQueue();
    expect(w.zoomed, isFalse);

    host.emit({'event': 'minimize', 'id': 1});
    await pumpEventQueue();
    expect(w.minimized, isTrue);

    host.emit({'event': 'resize', 'id': 1, 'edges': 4});
    await pumpEventQueue();
    expect(c.surfaceResize?.id, w.id);
    expect(c.surfaceResize?.edge, OasisResizeEdge.left);
    host.emit({'event': 'resize', 'id': 1, 'edges': 0});
    host.emit({'event': 'resize', 'id': 999, 'edges': 4});
    host.emit({'event': 'move', 'id': 999});
    await pumpEventQueue();
    expect(c.surfaceResize?.edge, OasisResizeEdge.left);
    c.endSurfaceGesture();
    expect(c.surfaceResize, isNull);
    c.dispose();
    service.dispose();
  });

  test('focus pushes to compositor', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(
      apps: [_builtin('a'), _external('x')],
      wayland: service,
    );
    c.openApp(c.apps.last);
    _emitToplevel(host);
    await pumpEventQueue();
    c.openApp(c.apps.first);
    expect(host.calls, contains('focus:null'));
    c.closeWindow(c.windows.last.id);
    c.dispose();
    service.dispose();
  });

  testWidgets('surface window shows texture and popups', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(
      apps: [_builtin('a'), _external('x')],
      wayland: service,
    );
    c.openApp(c.apps.last);
    _emitToplevel(host, title: 'Ext');
    host.emit({'event': 'size', 'id': 1, 'w': 320, 'h': 240});
    host.emit({
      'event': 'popup',
      'id': 2,
      'parent': 1,
      'textureId': 55,
      'x': 10,
      'y': 10,
    });
    host.emit({'event': 'size', 'id': 2, 'w': 50, 'h': 30});
    host.emit({
      'event': 'popup',
      'id': 3,
      'parent': 2,
      'textureId': 56,
      'x': 4,
      'y': 4,
    });
    host.emit({'event': 'size', 'id': 3, 'w': 20, 'h': 10});
    await tester.pump();

    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    expect(find.byType(WaylandSurfaceView), findsOneWidget);
    expect(find.byType(Texture), findsNWidgets(3));
    expect(find.byType(WaylandPopupView), findsNWidgets(2));

    host.emit({'event': 'subsurface', 'id': 9, 'parent': 1, 'x': 10, 'y': 20});
    host.emit({'event': 'size', 'id': 9, 'w': 40, 'h': 30});
    host.emit({'event': 'texture', 'id': 9, 'textureId': 60});
    host.emit({'event': 'subsurface', 'id': 10, 'parent': 9, 'x': 2, 'y': 3});
    host.emit({'event': 'size', 'id': 10, 'w': 8, 'h': 8});
    host.emit({'event': 'texture', 'id': 10, 'textureId': 61});
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsNWidgets(5));
    host.emit({'event': 'subsurfaceClosed', 'id': 10});
    host.emit({'event': 'subsurfaceClosed', 'id': 9});
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsNWidgets(3));

    c.openApp(c.apps.first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.apps).first);
    await tester.pump();
    expect(c.focusedId, c.windows.firstWhere((w) => w.surface != null).id);

    await tester.tapAt(const Offset(20, 700));
    await tester.pump();
    expect(host.calls, contains('close:2'));
    expect(host.calls, contains('close:3'));
    c.dispose();
    service.dispose();
  });

  testWidgets('popup position scales with parent buffer', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({
      'event': 'size',
      'id': 1,
      'w': 320,
      'h': 240,
      'bw': 640,
      'bh': 480,
    });
    host.emit({
      'event': 'popup',
      'id': 2,
      'parent': 1,
      'textureId': 55,
      'x': 40,
      'y': 60,
    });
    host.emit({'event': 'size', 'id': 2, 'w': 50, 'h': 30});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    final w = c.windows.single;
    final expected =
        w.position +
        const Offset(0, kOasisWindowTitleBarHeight) +
        const Offset(20, 30);
    expect(tester.getTopLeft(find.byType(WaylandPopupView)), expected);
    c.dispose();
    service.dispose();
  });

  testWidgets('subsurface layers scale with parent buffer', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    _emitToplevel(host);
    host.emit({
      'event': 'size',
      'id': 1,
      'w': 200,
      'h': 100,
      'bw': 400,
      'bh': 200,
      'textureId': 50,
    });
    host.emit({'event': 'subsurface', 'id': 2, 'parent': 1, 'x': 40, 'y': 20});
    host.emit({'event': 'size', 'id': 2, 'w': 80, 'h': 40});
    host.emit({'event': 'texture', 'id': 2, 'textureId': 51});
    await tester.pump();
    final surface = service.surfaces[1]!;

    await pumpOasis(
      tester,
      SizedBox(
        width: 200,
        height: 100,
        child: WaylandLayerTree(service: service, surface: surface),
      ),
      size: const Size(200, 100),
    );

    final textures = tester.widgetList<Texture>(find.byType(Texture)).toList();
    expect(textures, hasLength(2));
    expect(tester.getTopLeft(find.byWidget(textures[1])), const Offset(20, 10));
    expect(tester.getSize(find.byWidget(textures[1])), const Size(40, 20));
    service.dispose();
  });

  testWidgets('stale surface gesture ends on releaseless move', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 100, 'h': 100});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    host.emit({'event': 'move', 'id': 1});
    await tester.pump();
    expect(c.surfaceDragWindowId, isNotNull);
    await tester.sendEventToBinding(
      TestPointer(1, PointerDeviceKind.mouse).hover(const Offset(300, 300)),
    );
    await tester.pump();
    expect(c.surfaceDragWindowId, isNull);
    c.dispose();
    service.dispose();
  });

  testWidgets('popup outside tap dismisses only outside', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 320, 'h': 240});
    host.emit({
      'event': 'popup',
      'id': 2,
      'parent': 1,
      'textureId': 55,
      'x': 10,
      'y': 10,
    });
    host.emit({'event': 'size', 'id': 2, 'w': 50, 'h': 30});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    final popupTopLeft = tester.getTopLeft(find.byType(WaylandPopupView).first);
    final pointer = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(popupTopLeft + const Offset(4, 4)),
    );
    final gesture = await tester.startGesture(
      popupTopLeft + const Offset(4, 4),
    );
    await gesture.moveBy(const Offset(3, 0));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -10)));
    await gesture.up();
    await tester.pump();
    expect(host.calls.where((c) => c == 'close:2'), isEmpty);
    expect(host.calls.where((c) => c.startsWith('motion:2:')), isNotEmpty);
    expect(host.calls.where((c) => c.startsWith('axis:')), isNotEmpty);
    expect(host.calls, contains('button:272:true'));

    host.emit({'event': 'popupClosed', 'id': 2});
    host.emit({'event': 'popupClosed', 'id': 999});
    await tester.pump();

    final stray = {
      'event': 'popup',
      'id': 3,
      'parent': 1234,
      'textureId': 56,
      'x': 0,
      'y': 0,
    };
    host.emit(stray);
    host.emit({'event': 'size', 'id': 3, 'w': 10, 'h': 10});
    await tester.pump();
    await tester.pump();
    c.dispose();
    service.dispose();
  });

  testWidgets('popup keeps button state across rebuilds', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 320, 'h': 240});
    host.emit({
      'event': 'popup',
      'id': 2,
      'parent': 1,
      'textureId': 55,
      'x': 10,
      'y': 10,
    });
    host.emit({'event': 'size', 'id': 2, 'w': 50, 'h': 30});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    final popupTopLeft = tester.getTopLeft(find.byType(WaylandPopupView).first);
    final gesture = await tester.startGesture(
      popupTopLeft + const Offset(4, 4),
    );
    await tester.pump();
    expect(host.calls, contains('button:272:true'));

    host.emit({'event': 'title', 'id': 2, 'title': 'm'});
    await tester.pump();

    await gesture.up();
    await tester.pump();
    expect(host.calls, contains('button:272:false'));

    final pointer = TestPointer(3, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(popupTopLeft + const Offset(4, 4)),
    );
    await tester.sendEventToBinding(pointer.hover(const Offset(2, 2)));
    await tester.pump();
    expect(host.calls, contains('exit:2'));
    c.dispose();
    service.dispose();
  });

  testWidgets('surface view forwards input and keys', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 640, 'h': 480});
    await tester.pump();
    final surface = service.surfaces[1]!;

    await pumpOasis(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          height: 150,
          child: WaylandSurfaceView(
            surface: surface,
            service: service,
            focused: true,
            maximized: false,
          ),
        ),
      ),
      size: const Size(400, 300),
    );
    await tester.pump();
    expect(host.calls, contains('focus:1'));
    expect(
      host.calls.where((c) => c.startsWith('configure:1:200x150')),
      isNotEmpty,
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(WaylandSurfaceView));
    await tester.sendEventToBinding(pointer.hover(center));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
    await tester.sendEventToBinding(pointer.hover(const Offset(1, 1)));
    await tester.pump();
    expect(host.calls.where((c) => c.startsWith('motion:1:')), isNotEmpty);
    expect(host.calls, contains('button:272:true'));
    expect(host.calls, contains('button:272:false'));
    expect(host.calls.where((c) => c.startsWith('axis:')), isNotEmpty);
    expect(host.calls, contains('exit:1'));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(host.calls, contains('key:30:true'));
    expect(host.calls, contains('key:30:false'));

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    service.dispose();
  });

  testWidgets('surface view sends buffer-space coordinates', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    _emitToplevel(host);
    host.emit({
      'event': 'size',
      'id': 1,
      'w': 200,
      'h': 100,
      'bw': 400,
      'bh': 300,
    });
    await tester.pump();
    final surface = service.surfaces[1]!;
    expect(surface.bufferSize, const Size(400, 300));

    await pumpOasis(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: WaylandSurfaceView(
            surface: surface,
            service: service,
            focused: true,
            maximized: false,
          ),
        ),
      ),
      size: const Size(400, 300),
    );
    await tester.pump();

    await tester.sendEventToBinding(
      TestPointer(1, PointerDeviceKind.mouse).hover(const Offset(200, 150)),
    );
    await tester.pump();
    expect(host.calls, contains('motion:1:200.0:150.0'));
    service.dispose();
  });

  testWidgets('surface view stretches the buffer to fill', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 400, 'h': 300});
    await tester.pump();
    final surface = service.surfaces[1]!;

    await pumpOasis(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: WaylandSurfaceView(
            surface: surface,
            service: service,
            focused: true,
            maximized: false,
          ),
        ),
      ),
      size: const Size(400, 300),
    );
    await tester.pump();

    final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
    expect(fitted.fit, BoxFit.fill);

    await tester.sendEventToBinding(
      TestPointer(
        1,
        PointerDeviceKind.mouse,
      ).hover(tester.getCenter(find.byType(WaylandSurfaceView))),
    );
    await tester.pump();
    expect(host.calls, contains('motion:1:200.0:150.0'));
    service.dispose();
  });

  testWidgets('surface view focus transitions', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 64, 'h': 48});
    await tester.pump();
    final surface = service.surfaces[1]!;

    Widget view(bool focused) => SizedBox(
      width: 100,
      height: 100,
      child: WaylandSurfaceView(
        surface: surface,
        service: service,
        focused: focused,
        maximized: true,
      ),
    );
    await pumpOasis(tester, view(false), size: const Size(100, 100));
    await tester.pump();
    await pumpOasis(tester, view(true), size: const Size(100, 100));
    await tester.pump();
    expect(host.calls, contains('focus:1'));
    expect(
      host.calls.where((c) => c.startsWith('configure:1:100x100:true')),
      isNotEmpty,
    );
    await pumpOasis(tester, view(false), size: const Size(100, 100));
    await tester.pump();
    expect(host.calls, contains('focus:null'));
    service.dispose();
  });

  testWidgets('launching placeholder shows app name', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('pending')], wayland: service);
    c.openApp(c.apps.single);
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );
    expect(find.text('Ext pending'), findsWidgets);
    c.dispose();
    service.dispose();
  });

  testWidgets('CSD move drags the window', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 100, 'h': 100});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );
    final before = c.windows.single.position;

    host.emit({'event': 'move', 'id': 1});
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WaylandSurfaceView)),
    );
    await gesture.moveBy(const Offset(30, 10));
    expect(c.windows.single.position, before + const Offset(30, 10));
    await gesture.up();
    expect(c.surfaceDragWindowId, isNull);
    c.dispose();
    service.dispose();
  });

  testWidgets('CSD resize resizes the window', (tester) async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 100, 'h': 100});
    await tester.pump();
    await pumpOasis(
      tester,
      DesktopShell(controller: c, menusBuilder: () => const []),
      size: const Size(1280, 800),
    );

    host.emit({'event': 'resize', 'id': 1, 'edges': 10});
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WaylandSurfaceView)),
    );
    await gesture.moveBy(const Offset(30, 20));
    expect(c.windows.single.size, const Size(100 + 30, 138 + 20));
    await gesture.up();
    expect(c.surfaceResize, isNull);
    c.dispose();
    service.dispose();
  });

  test('window adopts the surface size and honors client limits', () async {
    final host = FakeWaylandHost();
    final service = await _service(host);
    final c = ShellController(apps: [_external('x')], wayland: service);
    c.openApp(c.apps.single);
    _emitToplevel(host);
    host.emit({'event': 'size', 'id': 1, 'w': 320, 'h': 240});
    await pumpEventQueue();
    final w = c.windows.single;
    expect(w.size, const Size(320, 240 + kOasisWindowTitleBarHeight));

    host.emit({'event': 'size', 'id': 1, 'w': 400, 'h': 200});
    await pumpEventQueue();
    expect(w.size, const Size(400, 200 + kOasisWindowTitleBarHeight));

    c.toggleZoom(w.id);
    host.emit({'event': 'size', 'id': 1, 'w': 800, 'h': 600});
    await pumpEventQueue();
    expect(w.size, const Size(400, 200 + kOasisWindowTitleBarHeight));
    c.toggleZoom(w.id);

    host.emit({'event': 'minSize', 'id': 1, 'w': 500, 'h': 400});
    host.emit({'event': 'maxSize', 'id': 1, 'w': 700, 'h': 500});
    await pumpEventQueue();

    c.resizeWindow(
      w.id,
      const Offset(2000, 2000),
      OasisResizeEdge.bottomRight,
      const Size(500, 400),
    );
    expect(w.size, const Size(700, 500 + kOasisWindowTitleBarHeight));

    c.resizeWindow(
      w.id,
      const Offset(-2000, -2000),
      OasisResizeEdge.bottomRight,
      const Size(500, 400),
    );
    expect(w.size, const Size(500, 400 + kOasisWindowTitleBarHeight));
    c.dispose();
    service.dispose();
  });

  testWidgets('desktop app loads external apps', (tester) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        version: '1.0.0',
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        wayland: service,
        externalAppsLoader: () async => [_external('files')],
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(OasisDesktopApp));
    final controller = state.controller as ShellController;
    expect(state.wayland, same(service));
    expect(controller.apps.any((a) => a.id == 'desktop:files'), isTrue);
    expect(controller.pinned.any((a) => a.id == 'desktop:files'), isFalse);

    controller.openApp(
      controller.apps.firstWhere((a) => a.id == 'desktop:files'),
    );
    await tester.pump();
    _emitToplevel(host, id: 9, title: 'Files');
    await tester.pump();
    await tester.pump();
    expect(find.byType(WaylandSurfaceView), findsOneWidget);
  });

  testWidgets('external apps reload when app dirs change', (tester) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    final watchCtl = StreamController<void>();
    addTearDown(watchCtl.close);
    var loads = 0;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        version: '1.0.0',
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        wayland: service,
        externalAppsLoader: () async {
          loads++;
          return [_external('app$loads')];
        },
        appDirWatcher: () => watchCtl.stream,
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    watchCtl.add(null);
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('app icon renders file icons and fallback', (tester) async {
    final dir = Directory('${Directory.systemTemp.path}/oasis_test_apicon')
      ..createSync(recursive: true);
    final png = File('${dir.path}/icon.png');
    png.writeAsBytesSync(_onePxPng);
    await pumpOasis(
      tester,
      Column(
        children: [
          OasisAppIcon(
            icon: Icons.apps,
            colors: const [Color(0xFF000000), Color(0xFF333333)],
            iconPath: png.path,
          ),
          OasisAppIcon(
            icon: Icons.apps,
            colors: const [Color(0xFF000000), Color(0xFF333333)],
            iconPath: '${dir.path}/missing.png',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.apps), findsOneWidget);
  });
  testWidgets('shell state persists and restores', (tester) async {
    final store = MemoryOasisStore();
    store.write('shell.themeMode', 'dark');
    store.write('shell.accent', '4280391411');
    store.write('shell.locale', 'ru');
    store.write('shell.wifi', '0');
    store.write('shell.bluetooth', '0');
    store.write('shell.focus', '1');
    store.write('shell.nightLight', '1');
    store.write('shell.brightness', '0.5');
    store.write('shell.volume', '0.25');
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        version: '1.0.0',
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        wayland: WaylandService(host: FakeWaylandHost()),
        externalAppsLoader: () async => const [],
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(OasisDesktopApp));
    final c = state.controller as ShellController;
    expect(c.wifiOn, isFalse);
    expect(c.focusOn, isTrue);
    expect(c.brightness, 0.5);
    c.wifiOnValue = true;
    await tester.pump();
    expect(store.read('shell.wifi'), '1');
  });
  testWidgets('fullscreen window covers shell chrome', (tester) async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      OasisDesktopApp(
        version: '1.0.0',
        appearance: OasisAppearance(themeMode: OasisThemeMode.light),
        wayland: service,
        externalAppsLoader: () async => [_external('game')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    _emitToplevel(host, id: 3, appId: 'game');
    host.emit({'event': 'fullscreen', 'id': 3, 'on': true});
    await tester.pumpAndSettle();
    expect(find.text('File'), findsNothing);
    host.emit({'event': 'fullscreen', 'id': 3, 'on': false});
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
  });
}

class _StubContext extends Fake implements BuildContext {}

const _onePxPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

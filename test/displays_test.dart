import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_settings/oasis_settings.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';
import 'package:oasis_de/services/displays.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/top_bar.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/wayland/wayland_host.dart';
import 'package:oasis_de/wayland/wayland_service.dart';

import 'wayland_test.dart' show FakeWaylandHost;

class _FakeBus extends Fake implements DBusClient {
  var owner = true;
  var failRequest = false;

  @override
  Future<void> registerObject(DBusObject object) async {}

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    if (failRequest) throw StateError('bus down');
    return owner
        ? DBusRequestNameReply.primaryOwner
        : DBusRequestNameReply.exists;
  }

  @override
  Future<DBusReleaseNameReply> releaseName(String name) async =>
      DBusReleaseNameReply.released;

  @override
  Future<void> unregisterObject(DBusObject object) async {}
}

class _FakeDisplayBackend implements OasisDisplayBackend {
  List<OasisDisplay> list = const [];
  final applied = <OasisDisplay>[];
  var identified = 0;

  @override
  Future<List<OasisDisplay>> displays() async => list;

  @override
  Future<void> setDisplay(OasisDisplay display) async {
    applied.add(display);
    list = [
      for (final d in list)
        if (d.name == display.name) display else d,
    ];
  }

  @override
  Future<void> identifyDisplays() async {
    identified++;
  }
}

OasisDisplay _head(String name, {int x = 0, bool primary = false}) =>
    OasisDisplay(
      name: name,
      description: '$name panel',
      x: x,
      width: 1920,
      height: 1080,
      refreshMhz: 60000,
      primary: primary,
      modes: const [
        OasisDisplayMode(
          width: 1920,
          height: 1080,
          refreshMhz: 60000,
          preferred: true,
        ),
        OasisDisplayMode(width: 1920, height: 1080, refreshMhz: 120000),
        OasisDisplayMode(width: 1280, height: 720, refreshMhz: 60000),
      ],
    );

void main() {
  test('OasisDisplay json round trip', () {
    final d = OasisDisplay(
      name: 'DP-1',
      description: 'Panel',
      x: 1920,
      y: -50,
      width: 2560,
      height: 1440,
      scale: 1.5,
      refreshMhz: 144000,
      transform: 1,
      enabled: false,
      primary: true,
      powered: false,
      physWidthMm: 600,
      physHeightMm: 340,
      modes: const [
        OasisDisplayMode(
          width: 2560,
          height: 1440,
          refreshMhz: 144000,
          preferred: true,
        ),
      ],
    );
    final copy = OasisDisplay.fromJson(d.toJson())!;
    expect(copy.name, 'DP-1');
    expect(copy.x, 1920);
    expect(copy.y, -50);
    expect(copy.scale, 1.5);
    expect(copy.transform, 1);
    expect(copy.enabled, isFalse);
    expect(copy.powered, isFalse);
    expect(copy.physWidthMm, 600);
    expect(copy.modes.single.preferred, isTrue);
    expect(copy.modes.single.label, '2560x1440 @ 144Hz');
    expect(OasisDisplay.fromJson(null), isNull);
    expect(OasisDisplay.fromJson({'name': ''}), isNull);
    expect(OasisDisplayMode.fromJson('x'), isNull);
    final m = OasisDisplayMode.fromJson(
        const OasisDisplayMode(
          width: 800,
          height: 600,
          refreshMhz: 59940,
        ).toJson())!;
    expect(m.label, '800x600 @ 59.94Hz');
    final c = d.copyWith(x: 1, scale: 2.0, enabled: true);
    expect(c.x, 1);
    expect(c.scale, 2.0);
    expect(c.enabled, isTrue);
    expect(c.name, 'DP-1');
    final same = d.copyWith();
    expect(same.y, -50);
    expect(same.transform, 1);
    expect(NoopDisplayBackend().displays(), completes);
    expect(
      NoopDisplayBackend().setDisplay(d),
      completes,
    );
    expect(NoopDisplayBackend().identifyDisplays(), completes);
    expect(const CliDisplayBackend().displays(), completes);
  });

  test('WaylandDisplayBackend maps and applies', () async {
    final host = FakeWaylandHost();
    final wl = WaylandService(host: host);
    await wl.start();
    final store = MemoryOasisStore();
    var identified = 0;
    final backend = WaylandDisplayBackend(
      wl,
      store: store,
      onIdentify: () => identified++,
    );
    host.emit({
      'event': 'outputs',
      'list': [
        {
          'id': 1,
          'name': 'HDMI-A-1',
          'desc': 'Monitor',
          'enabled': true,
          'primary': true,
          'powered': true,
          'x': 0,
          'y': 0,
          'w': 1920,
          'h': 1080,
          'scale': 1.0,
          'refresh': 60000,
          'transform': 0,
          'physW': 530,
          'physH': 300,
          'modes': [
            {'w': 1920, 'h': 1080, 'refresh': 60000, 'preferred': true},
          ],
        },
      ],
    });
    await pumpEventQueue();
    expect(wl.primaryOutput!.name, 'HDMI-A-1');
    expect(wl.outputAt(const Offset(100, 100))!.id, 1);
    expect(
      wl.outputAt(const Offset(-50, -50), size: const Size(200, 200))!.id,
      1,
    );
    expect(wl.outputs.single.modes.single.label, '1920x1080');
    final list = await backend.displays();
    expect(list.single.name, 'HDMI-A-1');
    expect(list.single.primary, isTrue);
    await backend.setDisplay(_head('HDMI-A-1'));
    expect(host.calls.last, startsWith('configureOutput:HDMI-A-1'));
    await backend.identifyDisplays();
    expect(identified, 1);
    backend.restore();
    await pumpEventQueue();
    store.write('display.config', '{broken');
    backend.restore();
    store.write('display.config', '"x"');
    backend.restore();
    host.emit({
      'event': 'outputs',
      'list': [
        {
          'id': 2,
          'name': 'DP-1',
          'enabled': true,
          'w': 1920,
          'h': 1080,
        },
      ],
    });
    await pumpEventQueue();
    expect(wl.primaryOutput!.name, 'DP-1');
  });

  test('DisplaysDaemon registers, owns name and stops', () async {
    final backend = _FakeDisplayBackend();
    final bus = _FakeBus();
    var identified = 0;
    final daemon = DisplaysDaemon(
      backend,
      connect: () => bus,
      onIdentify: () => identified++,
    );
    await daemon.start();
    expect(daemon.started, isTrue);
    await daemon.start();
    await daemon.stop();
    expect(daemon.started, isFalse);

    bus.owner = false;
    await daemon.start();
    expect(daemon.started, isFalse);
    await daemon.stop();

    bus.owner = true;
    bus.failRequest = true;
    await daemon.start();
    expect(daemon.started, isFalse);
    await daemon.stop();
    daemon.onIdentify?.call();
    expect(identified, 1);
  });

  test('OasisDisplaysObject handles methods', () async {
    final backend = _FakeDisplayBackend()..list = [_head('eDP-1')];
    var identified = 0;
    final obj = OasisDisplaysObject(backend)..onIdentify = () => identified++;
    final r = await obj.handleMethodCall(
      DBusMethodCall(
        sender: 's',
        interface: 'org.oasis.Displays',
        name: 'GetOutputs',
        values: const [],
      ),
    );
    final success = r as DBusMethodSuccessResponse;
    final decoded = jsonDecode((success.values.first as DBusString).value);
    expect(decoded, isList);
    expect(decoded.first['name'], 'eDP-1');
    await obj.handleMethodCall(
      DBusMethodCall(
        sender: 's',
        interface: 'org.oasis.Displays',
        name: 'SetOutputs',
        values: [DBusString(jsonEncode([_head('eDP-1').toJson()]))],
      ),
    );
    expect(backend.applied.single.name, 'eDP-1');
    await obj.handleMethodCall(
      DBusMethodCall(
        sender: 's',
        interface: 'org.oasis.Displays',
        name: 'Identify',
        values: const [],
      ),
    );
    expect(identified, 1);
    expect(backend.identified, 1);
    final err = await obj.handleMethodCall(
      DBusMethodCall(
        sender: 's',
        interface: 'org.oasis.Displays',
        name: 'Bogus',
        values: const [],
      ),
    );
    expect(err, isA<DBusMethodErrorResponse>());
  });

  testWidgets('DisplaysPane arranges and applies', (tester) async {
    final backend = _FakeDisplayBackend()
      ..list = [_head('eDP-1', primary: true), _head('DP-1', x: 1920)];
    final state = SettingsState(displayBackend: backend);
    await tester.pumpWidget(
      wrapOasis(
        SingleChildScrollView(child: DisplaysPane(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Displays'), findsWidgets);
    expect(find.text('eDP-1 panel'), findsOneWidget);
    expect(find.textContaining('1920x1080'), findsWidgets);

    await tester.tap(find.text('Identify'), warnIfMissed: false);
    await tester.pump();
    expect(backend.identified, 1);

    final box = find.byType(DisplayArranger);
    final size = tester.getSize(box);
    expect(size.width, greaterThan(0));

    final handle = await tester.startGesture(
      tester.getCenter(
        find
            .descendant(
              of: box,
              matching: find.byWidgetPredicate(
                (w) => w is GestureDetector,
              ),
            )
            .first,
      ),
    );
    await handle.moveBy(const Offset(40, 0));
    await handle.moveBy(const Offset(20, 5));
    await handle.up();
    await tester.pump();

    await tester.tap(find.byWidgetPredicate(
      (w) => w is OasisToggle,
    ).first);
    await tester.pump();
    await tester.ensureVisible(find.text('Revert'));
    await tester.tap(find.text('Revert'));
    await tester.pump();

    await tester.tap(find.byWidgetPredicate(
      (w) => w is DropdownButton<String>,
    ).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1280x720').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byWidgetPredicate(
      (w) => w is DropdownButton<String>,
    ).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60Hz').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byWidgetPredicate(
      (w) => w is DropdownButton<String>,
    ).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byWidgetPredicate(
      (w) => w is DropdownButton<String>,
    ).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90°').last);
    await tester.pumpAndSettle();

    final gestures = find.descendant(
      of: box,
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector,
      ),
    );
    final select = await tester.startGesture(
      tester.getCenter(gestures.last),
    );
    await select.up();
    await tester.pump();

    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(backend.applied.length, greaterThan(0));
  });

  testWidgets('DisplaysPane selects heads and edits rotation', (
    tester,
  ) async {
    final backend = _FakeDisplayBackend()
      ..list = [
        _head('eDP-1', primary: true),
        _head('DP-1', x: 1920).copyWith(width: 1366, height: 768),
      ];
    final state = SettingsState(displayBackend: backend);
    await tester.pumpWidget(
      wrapOasis(
        SingleChildScrollView(child: DisplaysPane(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    final gestures = find.descendant(
      of: find.byType(DisplayArranger),
      matching: find.byWidgetPredicate((w) => w is GestureDetector),
    );
    await tester.tap(gestures.last);
    await tester.pump();
    expect(find.text('DP-1 panel'), findsOneWidget);
    expect(find.text('1366x768'), findsWidgets);

    for (final label in ['180°', '270°']) {
      final rotation = find.byWidgetPredicate(
        (w) => w is DropdownButton<String>,
      ).at(3);
      await tester.ensureVisible(rotation);
      await tester.tap(rotation);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
  });

  test('CliDisplayBackend parses busctl replies', () async {
    var command = <String>[];
    final payload = jsonEncode([_head('eDP-1').toJson()]);
    final reply = jsonEncode([
      {'type': 's', 'data': [payload]},
    ]);
    final backend = CliDisplayBackend(
      run: (exe, args) async {
        command = [exe, ...args];
        return ProcessResult(0, 0, reply, '');
      },
    );
    final list = await backend.displays();
    expect(list.single.name, 'eDP-1');
    await backend.setDisplay(_head('eDP-1'));
    expect(command.join(' '), contains('SetOutputs'));
    await backend.identifyDisplays();
    expect(command.join(' '), contains('Identify'));

    final failing = CliDisplayBackend(
      run: (exe, args) async => ProcessResult(0, 1, '', 'nope'),
    );
    expect(await failing.displays(), isEmpty);
    await failing.setDisplay(_head('x'));
    await failing.identifyDisplays();

    final garbled = CliDisplayBackend(
      run: (exe, args) async => ProcessResult(0, 0, 'junk', ''),
    );
    expect(await garbled.displays(), isEmpty);
    final badPayload = CliDisplayBackend(
      run: (exe, args) async => ProcessResult(
          0, 0, jsonEncode([{'type': 's', 'data': ['{broken']}]), ''),
    );
    expect(await badPayload.displays(), isEmpty);
    final throwing = CliDisplayBackend(
      run: (exe, args) async => throw const ProcessException('busctl', []),
    );
    expect(await throwing.displays(), isEmpty);
  });

  test('channel host sends output calls', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('oasis/wayland');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const host = ChannelWaylandHost();
    await host.surfaceOutputs(3, [1, 2]);
    await host.configureOutput(
      'DP-1',
      x: 10,
      y: 20,
      width: 1920,
      height: 1080,
      refreshMhz: 60000,
      scale: 1.5,
      transform: 1,
      enabled: false,
    );
    expect(calls[0].method, 'surfaceOutputs');
    expect(calls[0].arguments['outputs'], [1, 2]);
    expect(calls[1].method, 'configureOutput');
    expect(calls[1].arguments['name'], 'DP-1');
    expect(calls[1].arguments['enabled'], 0);
    await host.configureOutput('DP-1', enabled: true);
    expect(calls[2].arguments['enabled'], 1);
  });

  testWidgets('desktop renders per-head chrome and identify', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3840, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = FakeWaylandHost();
    final wayland = WaylandService(host: host);
    await wayland.start();
    final controller = ShellController(
      apps: const [],
      wayland: wayland,
      batteryPollInterval: null,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrapOasis(
        DesktopShell(controller: controller, menusBuilder: () => const []),
        size: const Size(3840, 1080),
      ),
    );
    host.emit({
      'event': 'outputs',
      'list': [
        {'id': 1, 'name': 'eDP-1', 'x': 0, 'y': 0, 'w': 1920, 'h': 1080,
         'enabled': true, 'primary': true, 'scale': 1.0,
         'modes': const []},
        {'id': 2, 'name': 'DP-1', 'x': 1920, 'y': 0, 'w': 1920, 'h': 1080,
         'enabled': true, 'primary': false, 'scale': 1.0,
         'modes': const []},
      ],
    });
    await tester.pumpAndSettle();
    expect(wayland.outputs.length, 2);
    host.emit({
      'event': 'layer',
      'id': 9,
      'ns': 'panel',
      'layer': 2,
      'output': 2,
      'dw': 400,
      'dh': 40,
    });
    host.emit({'event': 'size', 'id': 9, 'w': 400, 'h': 40});
    await tester.pumpAndSettle();
    expect(wayland.outputAt(const Offset(2000, 100))!.name, 'DP-1');
    expect(
      wayland.outputsFor(const Rect.fromLTWH(0, 0, 3840, 20)).length,
      2,
    );
    expect(find.byType(ShellTopBar), findsNWidgets(2));

    controller.lastPointerPosition = const Offset(2000, 200);
    controller.openApp(
      OasisApp(
        id: 'x',
        name: 'X',
        icon: Icons.home,
        iconColors: const [Colors.blue, Colors.blue],
        builder: (_) => const SizedBox(),
        exec: const ['x'],
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.windows.first.position.dx, greaterThan(1900));

    controller.identifyOutputs();
    await tester.pump();
    expect(find.text('1'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    host.emit({
      'event': 'toplevel',
      'id': 7,
      'textureId': 70,
      'title': 'App',
      'appId': 'app',
      'parent': -1,
    });
    await tester.pumpAndSettle();
    final w = controller.windows.first;
    w.size = const Size(400, 300);
    w.position = const Offset(2000, 200);
    controller.notifyListeners();
    expect(
      host.calls.any((c) => c.startsWith('surfaceOutputs:')),
      isTrue,
    );
    w.setZoomed(true);
    controller.notifyListeners();
    await tester.pumpAndSettle();
  });

  testWidgets('DisplaysPane shows empty state', (tester) async {
    final backend = _FakeDisplayBackend();
    final state = SettingsState(displayBackend: backend);
    await tester.pumpWidget(
      wrapOasis(
        SingleChildScrollView(child: DisplaysPane(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No displays found'), findsOneWidget);
    expect(find.byType(DisplayArranger), findsNothing);

    backend.list = [_head('eDP-1', primary: true)];
    await state.refreshDisplays();
    await tester.pumpAndSettle();
    expect(find.byType(DisplayArranger), findsOneWidget);
  });
}

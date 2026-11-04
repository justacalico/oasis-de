import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/app.dart';
import 'package:oasis_de/apps/screenshot_window.dart';
import 'package:oasis_de/services/screenshot.dart';
import 'package:oasis_de/shell/desktop_shell.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/shell/snip_overlay.dart';
import 'package:oasis_de/wayland/wayland_host.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'helpers/test_app.dart';
import 'wayland_test.dart' show FakeWaylandHost;

class _FakeShots extends ScreenshotService {
  _FakeShots({this.result = '/tmp/shot.png'});

  final String? result;
  Rect? lastRegion;
  int calls = 0;

  @override
  Future<String?> captureRegion(Rect rect) async {
    calls++;
    lastRegion = rect;
    return result;
  }

  void poke() => notifyListeners();
}

Uint8List _frame(int w, int h, [int v = 255]) =>
    Uint8List.fromList(List.filled(w * h * 4, v));

OasisApp _screenshotApp() => OasisApp(
  id: kScreenshotAppId,
  name: 'Screenshot',
  icon: Icons.crop,
  iconColors: const [Colors.white, Colors.grey],
  builder: (_) => const SizedBox.shrink(),
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('WaylandService.capture', () {
    test('returns null when the host is not up', () async {
      final service = WaylandService(host: FakeWaylandHost());
      expect(await service.capture(const Rect.fromLTWH(0, 0, 10, 10)), isNull);
      service.dispose();
    });

    test('returns null with no outputs', () async {
      final host = FakeWaylandHost();
      final service = WaylandService(host: host);
      await service.start();
      expect(await service.capture(const Rect.fromLTWH(0, 0, 10, 10)), isNull);
      service.dispose();
    });

    test('scales the region by output scale', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(40, 20);
      host.captureWidth = 40;
      host.captureHeight = 20;
      final service = WaylandService(host: host);
      await service.start();
      service.outputs = const [
        OasisOutput(
          id: 1,
          name: 'out',
          x: 0,
          y: 0,
          width: 2000,
          height: 1000,
          scale: 2,
        ),
      ];
      final frame = await service.capture(const Rect.fromLTWH(10, 20, 20, 10));
      expect(frame, isNotNull);
      expect(frame!.width, 40);
      expect(frame.height, 20);
      expect(host.calls, contains('capture:10:20:40x20'));
      service.dispose();
    });

    test('clips the region to the output under its centre', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(4, 4);
      host.captureWidth = 4;
      host.captureHeight = 4;
      final service = WaylandService(host: host);
      await service.start();
      service.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      final frame = await service.capture(const Rect.fromLTWH(90, 90, 40, 40));
      expect(frame, isNotNull);
      expect(host.calls, contains('capture:90:90:10x10'));
      service.dispose();
    });

    test('returns null when the rect misses every output', () async {
      final host = FakeWaylandHost();
      final service = WaylandService(host: host);
      await service.start();
      service.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      expect(
        await service.capture(const Rect.fromLTWH(-50, -50, 10, 10)),
        isNull,
      );
      service.dispose();
    });

    test('returns null when the host declines', () async {
      final host = FakeWaylandHost();
      final service = WaylandService(host: host);
      await service.start();
      service.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      expect(await service.capture(const Rect.fromLTWH(0, 0, 10, 10)), isNull);
      service.dispose();
    });

    test('returns null on a malformed reply', () async {
      final host = _BadCaptureHost();
      final service = WaylandService(host: host);
      await service.start();
      service.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      expect(await service.capture(const Rect.fromLTWH(0, 0, 10, 10)), isNull);
      service.dispose();
    });

    test('channel host sends capture and decodes the reply', () async {
      const channel = MethodChannel('oasis/wayland');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'capture') {
          return {'w': 3, 'h': 4, 'rgba': Uint8List(48)};
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const host = ChannelWaylandHost();
      final res = await host.capture(1, 2, 3, 4);
      expect(calls.single.method, 'capture');
      expect(calls.single.arguments, {'x': 1, 'y': 2, 'w': 3, 'h': 4});
      expect(res?['w'], 3);
    });
  });

  group('ScreenshotService', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('shots'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns null without a wayland service', () async {
      final shots = ScreenshotService(directory: dir);
      expect(
        await shots.captureRegion(const Rect.fromLTWH(0, 0, 4, 4)),
        isNull,
      );
      shots.dispose();
    });

    test('returns null when capture fails', () async {
      final shots = ScreenshotService(
        wayland: WaylandService(host: FakeWaylandHost()),
        directory: dir,
      );
      expect(
        await shots.captureRegion(const Rect.fromLTWH(0, 0, 4, 4)),
        isNull,
      );
      shots.dispose();
    });

    test('screenshotsDir falls back to the pictures folder', () {
      final shots = ScreenshotService();
      expect(shots.screenshotsDir.path, endsWith('Pictures/Screenshots'));
      shots.dispose();
    });

    test('writes a png and keeps a preview', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(4, 4);
      host.captureWidth = 4;
      host.captureHeight = 4;
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      final shots = ScreenshotService(wayland: wayland, directory: dir);
      var notified = 0;
      shots.addListener(() => notified++);
      final path = await shots.captureRegion(const Rect.fromLTWH(0, 0, 4, 4));
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, contains('Screenshot '));
      expect(path, endsWith('.png'));
      expect(shots.lastPath, path);
      expect(shots.lastCapture, isNotNull);
      expect(notified, 1);
      shots.dispose();
      wayland.dispose();
    });

    test('suffixes colliding filenames', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(2, 2);
      host.captureWidth = 2;
      host.captureHeight = 2;
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      final shots = ScreenshotService(wayland: wayland, directory: dir);
      await withClock(Clock.fixed(DateTime(2026, 3, 4, 5, 6, 7)), () async {
        final first = await shots.captureRegion(
          const Rect.fromLTWH(0, 0, 2, 2),
        );
        final second = await shots.captureRegion(
          const Rect.fromLTWH(0, 0, 2, 2),
        );
        expect(first, endsWith('05.06.07.png'));
        expect(second, endsWith('05.06.07 (2).png'));
      });
      shots.dispose();
      wayland.dispose();
    });

    test('rejects malformed frames', () async {
      final host = FakeWaylandHost()..captureRgba = Uint8List(4);
      host.captureWidth = 4;
      host.captureHeight = 4;
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      final shots = ScreenshotService(wayland: wayland, directory: dir);
      expect(
        await shots.captureRegion(const Rect.fromLTWH(0, 0, 4, 4)),
        isNull,
      );
      shots.dispose();
      wayland.dispose();
    });

    test('reports encoder failures', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(2, 2);
      host.captureWidth = 2;
      host.captureHeight = 2;
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      final shots = ScreenshotService(wayland: wayland, directory: dir)
        ..encodePng = (_) async => null;
      expect(
        await shots.captureRegion(const Rect.fromLTWH(0, 0, 2, 2)),
        isNull,
      );
      expect(shots.lastCapture, isNull);
      shots.dispose();
      wayland.dispose();
    });

    test('survives unwritable destinations', () async {
      final host = FakeWaylandHost()..captureRgba = _frame(2, 2);
      host.captureWidth = 2;
      host.captureHeight = 2;
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'out', width: 100, height: 100),
      ];
      // A directory path sitting inside a regular file can never be
      // created, so the write throws FileSystemException.
      final blocker = File('${dir.path}/file')..createSync();
      final shots = ScreenshotService(
        wayland: wayland,
        directory: Directory('${blocker.path}/sub'),
      );
      expect(
        await shots.captureRegion(const Rect.fromLTWH(0, 0, 2, 2)),
        isNull,
      );
      shots.dispose();
      wayland.dispose();
    });
  });

  group('ShellController snip flow', () {
    testWidgets('beginSnip opens the overlay and closes others', (
      tester,
    ) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.launcherOpen = true;
      c.beginSnip();
      expect(c.snipActive, isTrue);
      expect(c.launcherOpen, isFalse);
    });

    testWidgets('a delayed begin waits for the timer', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.beginSnip(delaySeconds: 3);
      expect(c.snipActive, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(c.snipActive, isTrue);
    });

    testWidgets('cancelSnip kills a pending delay', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.beginSnip(delaySeconds: 3);
      c.cancelSnip();
      await tester.pump(const Duration(seconds: 3));
      expect(c.snipActive, isFalse);
    });

    testWidgets('dismiss keybind cancels the snip', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.beginSnip();
      c.runKeybindAction(OasisKeybindsService.actionDismiss);
      expect(c.snipActive, isFalse);
    });

    testWidgets('screenshot keybind starts a snip', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.runKeybindAction(OasisKeybindsService.actionScreenshot);
      expect(c.snipActive, isTrue);
    });

    testWidgets('completeSnip saves and notifies', (tester) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      c.beginSnip();
      c.completeSnip(const Rect.fromLTWH(10, 10, 50, 40));
      expect(c.snipActive, isFalse);
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.calls, 1);
      expect(shots.lastRegion, const Rect.fromLTWH(10, 10, 50, 40));
      expect(c.notifications.last.body, '/tmp/shot.png');
      await tester.pump(kBannerTimeout);
    });

    testWidgets('a failed capture reports failure', (tester) async {
      final shots = _FakeShots(result: null);
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      c.completeSnip(const Rect.fromLTWH(0, 0, 10, 10));
      await tester.pump(kScreenshotSettle * 2);
      expect(
        c.notifications.last.summary,
        lookupOasisLocalizations(const Locale('en')).screenshotFailed,
      );
      await tester.pump(kBannerTimeout);
    });

    testWidgets('fullscreen capture unions the outputs', (tester) async {
      final shots = _FakeShots();
      final host = FakeWaylandHost();
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'a', width: 100, height: 100),
        OasisOutput(id: 2, name: 'b', x: 100, width: 100, height: 100),
        OasisOutput(
          id: 3,
          name: 'off',
          x: 200,
          width: 50,
          height: 50,
          enabled: false,
        ),
      ];
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wayland,
        screenshots: shots,
      );
      addTearDown(c.dispose);
      addTearDown(wayland.dispose);
      c.captureFullscreen();
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.lastRegion, const Rect.fromLTWH(0, 0, 200, 100));
      await tester.pump(kBannerTimeout);
    });

    testWidgets('fullscreen with no outputs still notifies', (tester) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      c.captureFullscreen();
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.calls, 0);
      expect(c.notifications, isNotEmpty);
      await tester.pump(kBannerTimeout);
    });

    testWidgets('requestScreenshot parks the app window', (tester) async {
      final shots = _FakeShots();
      final app = _screenshotApp();
      final c = ShellController(
        batteryPollInterval: null,
        apps: [app],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      c.openApp(app);
      expect(c.windows.single.app.id, kScreenshotAppId);
      c.requestScreenshot(ScreenshotMode.region);
      expect(c.windows.single.minimized, isTrue);
      expect(c.snipActive, isTrue);
      c.completeSnip(const Rect.fromLTWH(0, 0, 20, 20));
      await tester.pump(kScreenshotSettle * 2);
      await tester.pump();
      expect(c.windows.single.minimized, isFalse);
      expect(shots.calls, 1);
      await tester.pump(kBannerTimeout);
    });

    testWidgets('a second capture in flight is dropped', (tester) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      c.completeSnip(const Rect.fromLTWH(0, 0, 10, 10));
      c.completeSnip(const Rect.fromLTWH(0, 0, 30, 30));
      await tester.pump(kScreenshotSettle * 2);
      await tester.pump(kBannerTimeout);
      expect(shots.calls, 1);
      expect(shots.lastRegion, const Rect.fromLTWH(0, 0, 10, 10));
    });

    testWidgets('cancelSnip restores the app window', (tester) async {
      final app = _screenshotApp();
      final c = ShellController(batteryPollInterval: null, apps: [app]);
      addTearDown(c.dispose);
      c.openApp(app);
      c.requestScreenshot(ScreenshotMode.region);
      expect(c.windows.single.minimized, isTrue);
      c.cancelSnip();
      expect(c.windows.single.minimized, isFalse);
    });

    testWidgets('fullscreen request grabs the whole layout', (tester) async {
      final shots = _FakeShots();
      final host = FakeWaylandHost();
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'a', width: 640, height: 480),
      ];
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wayland,
        screenshots: shots,
      );
      addTearDown(c.dispose);
      addTearDown(wayland.dispose);
      c.requestScreenshot(ScreenshotMode.fullscreen, delaySeconds: 1);
      expect(c.snipActive, isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.lastRegion, const Rect.fromLTWH(0, 0, 640, 480));
      await tester.pump(kBannerTimeout);
    });
  });

  group('SnipOverlay', () {
    testWidgets('shows the hint until a drag starts', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      await pumpOasis(tester, SnipOverlay(controller: c));
      final l10n = lookupOasisLocalizations(const Locale('en'));
      expect(find.text(l10n.screenshotHint), findsOneWidget);

      final center = tester.getCenter(find.byType(SnipOverlay));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(find.text(l10n.screenshotHint), findsNothing);
      await gesture.moveBy(const Offset(120, 90));
      await tester.pump();
      expect(find.text('120 × 90'), findsOneWidget);
      await gesture.up();
      await tester.pump(kScreenshotSettle * 2);
      await tester.pump(kBannerTimeout);
    });

    testWidgets('a real drag completes the snip', (tester) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      await pumpOasis(tester, SnipOverlay(controller: c));
      await tester.drag(find.byType(SnipOverlay), const Offset(150, 120));
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.calls, 1);
      expect(shots.lastRegion!.width, 150);
      expect(shots.lastRegion!.height, 120);
      await tester.pump(kBannerTimeout);
    });

    testWidgets('a cancelled gesture clears the selection', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      await pumpOasis(tester, SnipOverlay(controller: c));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SnipOverlay)),
      );
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      expect(find.text('40 × 30'), findsOneWidget);
      await gesture.cancel();
      await tester.pump();
      expect(find.text('40 × 30'), findsNothing);
    });

    testWidgets('the size label flips above a selection at the edge', (
      tester,
    ) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      await pumpOasis(tester, SnipOverlay(controller: c));
      final gesture = await tester.startGesture(const Offset(400, 650));
      await gesture.moveTo(const Offset(350, 790));
      await tester.pump();
      expect(find.text('50 × 140'), findsOneWidget);
      await gesture.up();
      await tester.pump(kScreenshotSettle * 2);
      await tester.pump(kBannerTimeout);
    });

    testWidgets('a tiny drag keeps waiting', (tester) async {
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      await pumpOasis(tester, SnipOverlay(controller: c));
      await tester.drag(find.byType(SnipOverlay), const Offset(2, 2));
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.calls, 0);
    });

    testWidgets('secondary click cancels', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      c.beginSnip();
      await pumpOasis(tester, SnipOverlay(controller: c));
      await tester.tap(find.byType(SnipOverlay), buttons: kSecondaryButton);
      expect(c.snipActive, isFalse);
    });

    testWidgets('renders through the desktop shell', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      await pumpOasis(
        tester,
        DesktopShell(controller: c, menusBuilder: () => const []),
      );
      expect(find.byType(SnipOverlay), findsNothing);
      c.beginSnip();
      await tester.pump();
      expect(find.byType(SnipOverlay), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(SnipOverlay), findsNothing);
    });
  });

  group('ScreenshotWindow', () {
    testWidgets('mode, delay and trigger buttons work', (tester) async {
      final shots = _FakeShots();
      final host = FakeWaylandHost();
      final wayland = WaylandService(host: host);
      await wayland.start();
      wayland.outputs = const [
        OasisOutput(id: 1, name: 'a', width: 640, height: 480),
      ];
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        wayland: wayland,
        screenshots: shots,
      );
      addTearDown(c.dispose);
      addTearDown(wayland.dispose);
      await pumpOasis(tester, ScreenshotWindow(controller: c));
      final l10n = lookupOasisLocalizations(const Locale('en'));

      expect(find.text(l10n.screenshotNoCapture), findsOneWidget);
      await tester.tap(find.text(l10n.screenshotModeFullscreen));
      await tester.pump();
      await tester.tap(find.text(l10n.screenshotModeRegion));
      await tester.pump();
      await tester.tap(find.text(l10n.screenshotModeFullscreen));
      await tester.pump();
      await tester.tap(find.text(l10n.screenshotDelaySeconds(5)));
      await tester.pump();
      await tester.tap(find.text(l10n.screenshotTake));
      await tester.pump();
      expect(c.snipActive, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(kScreenshotSettle * 2);
      expect(shots.lastRegion, const Rect.fromLTWH(0, 0, 640, 480));
      await tester.pump(kBannerTimeout);
    });

    testWidgets('region mode starts the snip overlay', (tester) async {
      final c = ShellController(batteryPollInterval: null, apps: const []);
      addTearDown(c.dispose);
      await pumpOasis(tester, ScreenshotWindow(controller: c));
      final l10n = lookupOasisLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.screenshotTake));
      await tester.pump();
      expect(c.snipActive, isTrue);
    });

    testWidgets('the app wires up snipping end to end', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final wayland = WaylandService(host: FakeWaylandHost());
      await wayland.start();
      await tester.pumpWidget(
        OasisDesktopApp(
          version: '1.0.0',
          backend: const NoopSystemBackend(),
          wayland: wayland,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupOasisLocalizations(const Locale('en'));
      await tester.tap(find.byIcon(Icons.crop).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.screenshotTake));
      await tester.pumpAndSettle();
      expect(find.byType(SnipOverlay), findsOneWidget);
      final appState = tester.state(find.byType(OasisDesktopApp)) as dynamic;
      expect(
        appState.controller.screenshotSavedTitle(),
        l10n.screenshotSavedTitle,
      );
    });

    testWidgets('shows the last capture preview', (tester) async {
      final image = await tester.runAsync(_testImage);
      expect(image, isNotNull);
      final shots = _FakeShots();
      final c = ShellController(
        batteryPollInterval: null,
        apps: const [],
        screenshots: shots,
      );
      addTearDown(c.dispose);
      shots.lastCapture = image;
      shots.lastPath = '/tmp/one.png';
      await pumpOasis(tester, ScreenshotWindow(controller: c));
      shots.poke();
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('/tmp/one.png'), findsOneWidget);
    });
  });
}

class _BadCaptureHost extends FakeWaylandHost {
  @override
  Future<Map<String, Object?>?> capture(int x, int y, int w, int h) async => {
    'rgba': 'not-bytes',
  };
}

Future<ui.Image> _testImage() {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    _frame(2, 2),
    2,
    2,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/shell/view_scale.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_de/wayland/wayland_surface_view.dart';

import 'wayland_test.dart' show FakeWaylandHost;

Map<String, Object?> _outputEvent(double scale) => {
      'event': 'outputs',
      'list': [
        {
          'id': 1,
          'name': 'eDP-1',
          'enabled': true,
          'primary': true,
          'x': 0,
          'y': 0,
          'w': 1920,
          'h': 1080,
          'scale': scale,
        },
      ],
    };

Widget _wrap(Size size, double dpr, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: dpr),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    ),
  );
}

void main() {
  testWidgets('null wayland passes the child through unscaled', (
    tester,
  ) async {
    double factor = -1;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShellViewScaler(
          child: Builder(
            builder: (context) {
              factor = ViewScale.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(factor, 1);
  });

  testWidgets('no outputs leaves the view scale at one', (tester) async {
    final host = FakeWaylandHost();
    final wl = WaylandService(host: host);
    await wl.start();
    double factor = -1;
    await tester.pumpWidget(
      _wrap(
        const Size(1920, 1080),
        1,
        ShellViewScaler(
          wayland: wl,
          child: Builder(
            builder: (context) {
              factor = ViewScale.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(factor, 1);
    wl.dispose();
  });

  testWidgets('scaled output shrinks logical space and scales content', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final wl = WaylandService(host: host);
    await wl.start();
    await tester.pumpWidget(
      _wrap(
        const Size(1920, 1080),
        1,
        ShellViewScaler(
          wayland: wl,
          child: Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('probe'),
                  width: mq.size.width,
                  height: mq.size.height,
                ),
              );
            },
          ),
        ),
      ),
    );
    host.emit(_outputEvent(2.0));
    await tester.pumpAndSettle();
    final probe = find.byKey(const ValueKey('probe'));
    final context = tester.element(probe);
    expect(ViewScale.of(context), 2);
    expect(
      ViewScale.globalToLogical(context, const Offset(200, 80)),
      const Offset(100, 40),
    );
    final mq = MediaQuery.of(context);
    expect(mq.size, const Size(960, 540));
    expect(mq.devicePixelRatio, 2);
    // The 960x540 logical box fills the whole 1920x1080 view.
    expect(tester.getSize(probe), const Size(960, 540));
    expect(tester.getBottomRight(probe), const Offset(1920, 1080));

    // Dropping back to 1x notifies dependents and restores the view.
    host.emit(_outputEvent(1.0));
    await tester.pumpAndSettle();
    expect(ViewScale.of(tester.element(probe)), 1);
    wl.dispose();
  });

  testWidgets('engine ratio matching the output scale is a pass-through', (
    tester,
  ) async {
    final host = FakeWaylandHost();
    final wl = WaylandService(host: host);
    await wl.start();
    double factor = -1;
    await tester.pumpWidget(
      _wrap(
        const Size(1920, 1080),
        2,
        ShellViewScaler(
          wayland: wl,
          child: Builder(
            builder: (context) {
              factor = ViewScale.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    host.emit(_outputEvent(2.0));
    await tester.pumpAndSettle();
    expect(factor, 1);
    wl.dispose();
  });

  test('logicalSurfaceSize prefers the viewport crop', () {
    final s = WaylandSurface(id: 1)
      ..size = const Size(800, 600)
      ..bufferSize = const Size(1200, 900)
      ..scale = 2
      ..vpSrc = const Rect.fromLTWH(0, 0, 800, 600);
    expect(logicalSurfaceSize(s), const Size(800, 600));
  });
}

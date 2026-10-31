import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/services/power.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'wayland_test.dart' show FakeWaylandHost;

void main() {
  test('service applies idle timeouts now or once started', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);

    await service.setIdleTimeouts(60000, 900000);
    expect(host.calls, isEmpty);

    await service.start();
    expect(host.calls, ['idleTimeouts:60000:900000']);

    await service.setIdleTimeouts(120000, 0);
    expect(host.calls.last, 'idleTimeouts:120000:0');
  });

  test('idleSuspend event reaches the callback', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();

    var fired = 0;
    service.onIdleSuspend = () => fired++;
    host.emit({'event': 'idleSuspend'});
    await pumpEventQueue();
    expect(fired, 1);
  });

  test('WaylandPowerBackend forwards and restores timeouts', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();
    final store = MemoryOasisStore();
    final backend = WaylandPowerBackend(service, store: store);

    await backend.setIdleTimeouts(
      displayOff: const Duration(minutes: 2),
      suspend: const Duration(minutes: 15),
    );
    expect(host.calls, ['idleTimeouts:120000:900000']);

    await backend.setIdleTimeouts();
    expect(host.calls.last, 'idleTimeouts:0:0');

    backend.restore();
    expect(host.calls.length, 2);

    await store.write('shell.displayOffAfter', '300000');
    await store.write('shell.sleepAfter', '1800000');
    backend.restore();
    expect(host.calls.last, 'idleTimeouts:300000:1800000');
  });

  test('NoopPowerBackend accepts timeouts', () {
    expect(
      const NoopPowerBackend().setIdleTimeouts(
        displayOff: const Duration(minutes: 5),
      ),
      completes,
    );
  });

  test('controller suspends when the compositor reports idle', () async {
    final host = FakeWaylandHost();
    final service = WaylandService(host: host);
    addTearDown(service.dispose);
    await service.start();

    final backend = _RecordingBackend();
    final controller = ShellController(
      apps: const [],
      wayland: service,
      backend: backend,
      batteryPollInterval: null,
    );
    addTearDown(controller.dispose);

    host.emit({'event': 'idleSuspend'});
    await pumpEventQueue();
    expect(controller.locked, isTrue);
    expect(
      backend.actions,
      [OasisSessionAction.lock, OasisSessionAction.suspend],
    );
  });
}

class _RecordingBackend extends NoopSystemBackend {
  final actions = <OasisSessionAction>[];

  @override
  void session(OasisSessionAction action) => actions.add(action);
}

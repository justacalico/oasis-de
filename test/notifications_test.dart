import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/services/notifications.dart';
import 'package:oasis_de/shell/shell_controller.dart';

OasisNotification _n(int id, {String body = 'b'}) => OasisNotification(
  id: id,
  appName: 'app',
  summary: 's$id',
  body: body,
  timestamp: DateTime(2024),
);

void main() {
  test('dbus server handles notify, close and info calls', () async {
    final pushed = <OasisNotification>[];
    final closed = <int>[];
    final server = OasisNotificationServer(
      onNotify: pushed.add,
      onClose: closed.add,
    );
    final info = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'GetServerInformation',
      ),
    );
    expect(info.returnValues.length, 4);
    final caps = await server.handleMethodCall(
      DBusMethodCall(sender: 'x', name: 'GetCapabilities'),
    );
    expect(caps.returnValues, isNotEmpty);
    final notify = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'Notify',
        values: [
          DBusString('app'),
          DBusUint32(0),
          DBusString('icon'),
          DBusString('Hi'),
          DBusString('Body'),
          DBusArray.string([]),
          DBusDict.stringVariant({}),
          DBusInt32(-1),
        ],
      ),
    );
    expect(pushed.single.summary, 'Hi');
    expect(
      (notify.returnValues.single as DBusUint32).value,
      pushed.single.id,
    );
    final bad = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'Notify',
        values: [DBusString('app'), DBusUint32(0)],
      ),
    );
    expect(bad, isA<DBusMethodErrorResponse>());
    final second = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'Notify',
        values: [
          DBusString('app'),
          DBusUint32(0),
          DBusString('icon'),
          DBusString('Hi2'),
          DBusString(''),
          DBusArray.string([]),
          DBusDict.stringVariant({}),
          DBusInt32(-1),
        ],
      ),
    );
    expect(
      (second.returnValues.single as DBusUint32).value,
      greaterThan(pushed.first.id),
    );
    await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'CloseNotification',
        values: [DBusUint32(9)],
      ),
    );
    expect(closed, [9]);
    final unknown = await server.handleMethodCall(
      DBusMethodCall(sender: 'x', name: 'Nope'),
    );
    expect(unknown, isA<DBusMethodErrorResponse>());
  });

  test('daemon registers, owns name and stops', () async {
    final bus = _FakeBus();
    final daemon = NotificationDaemon(connect: () => bus);
    await daemon.start(onNotify: (_) {}, onClose: (_) {});
    expect(daemon.started, isTrue);
    expect(bus.registered, isTrue);
    await daemon.stop();
    expect(daemon.started, isFalse);
    expect(bus.released, isTrue);
    await daemon.stop();
    bus.owner = false;
    await daemon.start(onNotify: (_) {}, onClose: (_) {});
    expect(daemon.started, isFalse);
  });

  test('controller pushes, dismisses, clears and toggles', () async {
    final c = ShellController(apps: const []);
    c.pushNotification(_n(1));
    c.pushNotification(_n(2, body: ''));
    expect(c.notifications.map((n) => n.id), [2, 1]);
    expect(c.bannerNotification?.id, 2);
    c.focusOnValue = true;
    c.pushNotification(_n(3));
    expect(c.bannerNotification?.id, 2);
    c.focusOnValue = false;
    c.dismissNotification(2);
    expect(c.bannerNotification, isNull);
    expect(c.notifications.map((n) => n.id), [3, 1]);
    c.toggleNotificationCenter();
    expect(c.notificationCenterOpen, isTrue);
    c.toggleNotificationCenter();
    expect(c.notificationCenterOpen, isFalse);
    c.toggleNotificationCenter();
    c.closeOverlays();
    expect(c.notificationCenterOpen, isFalse);
    c.clearNotifications();
    expect(c.notifications, isEmpty);
    c.dispose();
  });
}

class _FakeBus extends Fake implements DBusClient {
  var registered = false;
  var released = false;
  var owner = true;

  @override
  Future<void> registerObject(DBusObject object) async {
    registered = true;
  }

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    return owner
        ? DBusRequestNameReply.primaryOwner
        : DBusRequestNameReply.exists;
  }

  @override
  Future<DBusReleaseNameReply> releaseName(String name) async {
    released = true;
    return DBusReleaseNameReply.released;
  }

  @override
  Future<void> unregisterObject(DBusObject object) async {}
}

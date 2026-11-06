import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/services/notifications.dart';
import 'package:oasis_de/shell/notification_panel.dart';
import 'package:oasis_de/shell/shell_controller.dart';
import 'package:oasis_de/wayland/wayland_service.dart';
import 'package:oasis_ui/oasis_ui.dart';

import 'wayland_test.dart' show FakeWaylandHost;

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
        name: 'Notify',
        values: [
          DBusString('app'),
          DBusUint32(0),
          DBusString('icon'),
          DBusString('With actions'),
          DBusString(''),
          DBusArray.string(['default', 'Open', 'reply', 'Reply']),
          DBusDict.stringVariant({}),
          DBusInt32(-1),
        ],
      ),
    );
    expect(pushed.last.actions, ['default', 'Open', 'reply', 'Reply']);
    await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'CloseNotification',
        values: [DBusUint32(9)],
      ),
    );
    expect(closed, [9]);
    final badClose = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'CloseNotification',
        values: [DBusString('x')],
      ),
    );
    expect(badClose, isA<DBusMethodErrorResponse>());
    final emptyClose = await server.handleMethodCall(
      DBusMethodCall(
        sender: 'x',
        name: 'CloseNotification',
        values: const [],
      ),
    );
    expect(emptyClose, isA<DBusMethodErrorResponse>());
    final unknown = await server.handleMethodCall(
      DBusMethodCall(sender: 'x', name: 'Nope'),
    );
    expect(unknown, isA<DBusMethodErrorResponse>());
  });

  test('notify reads icon and desktop-entry hints', () async {
    final pushed = <OasisNotification>[];
    final server = OasisNotificationServer(
      onNotify: pushed.add,
      onClose: (_) {},
    );
    Future<OasisNotification> notify(
      String appIcon,
      Map<String, DBusValue> hints,
    ) async {
      await server.handleMethodCall(
        DBusMethodCall(
          sender: 'x',
          name: 'Notify',
          values: [
            DBusString('app'),
            DBusUint32(0),
            DBusString(appIcon),
            DBusString('S'),
            DBusString('B'),
            DBusArray.string([]),
            DBusDict.stringVariant(hints),
            DBusInt32(-1),
          ],
        ),
      );
      return pushed.last;
    }

    var n = await notify('firefox', {
      'desktop-entry': DBusString('org.mozilla.firefox'),
    });
    expect(n.desktopEntry, 'org.mozilla.firefox');
    expect(n.iconPath, isNull);
    expect(n.imageProvider, isNull);

    n = await notify('/tmp/app.png', {
      'image-path': DBusString('/tmp/hint.png'),
    });
    expect(n.iconPath, '/tmp/hint.png');

    n = await notify('/tmp/app.png', {});
    expect(n.iconPath, '/tmp/app.png');

    n = await notify('name-only', {
      'image_path': DBusString('/tmp/alt.png'),
      'desktop_entry': DBusString('entry'),
    });
    expect(n.iconPath, '/tmp/alt.png');
    expect(n.desktopEntry, 'entry');
  });

  test('decodeImageData handles valid and malformed payloads', () async {
    DBusValue imageData(
      int w,
      int h,
      int stride,
      int channels,
      List<int> bytes,
    ) => DBusVariant(
      DBusStruct([
        DBusInt32(w),
        DBusInt32(h),
        DBusInt32(stride),
        DBusBoolean(true),
        DBusInt32(8),
        DBusInt32(channels),
        DBusArray(DBusSignature('y'), [
          for (final b in bytes) DBusByte(b),
        ]),
      ]),
    );

    expect(await decodeImageData(null), isNull);
    expect(await decodeImageData(DBusString('x')), isNull);
    expect(
      await decodeImageData(DBusVariant(DBusStruct([DBusInt32(1)]))),
      isNull,
    );
    expect(
      await decodeImageData(
        DBusStruct([
          DBusString('w'),
          DBusInt32(1),
          DBusInt32(4),
          DBusBoolean(true),
          DBusInt32(8),
          DBusInt32(4),
          DBusArray(DBusSignature('y'), []),
        ]),
      ),
      isNull,
    );
    expect(await decodeImageData(imageData(0, 1, 4, 4, [])), isNull);
    expect(
      await decodeImageData(imageData(1, 1, 4, 5, [0, 0, 0, 0, 0])),
      isNull,
    );
    expect(
      await decodeImageData(
        DBusStruct([
          DBusInt32(1),
          DBusInt32(1),
          DBusInt32(4),
          DBusBoolean(true),
          DBusInt32(8),
          DBusInt32(4),
          DBusArray(DBusSignature('s'), [DBusString('x')]),
        ]),
      ),
      isNull,
    );
    expect(
      await decodeImageData(imageData(2, 2, 8, 4, [1, 2, 3])),
      isNull,
    );

    final rgba = imageData(2, 1, 8, 4, [
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
    ]);
    expect(await decodeImageData(rgba), isA<MemoryImage>());
    final rgb = imageData(1, 1, 3, 3, [10, 20, 30]);
    expect(await decodeImageData(rgb), isA<MemoryImage>());
  });

  test('notificationApp matches entry, name and suffix case-insensitively', () {
    OasisApp app(String id, String name) => OasisApp(
      id: id,
      name: name,
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000)],
      builder: (_) => const SizedBox(),
    );
    final apps = [
      app('files', 'Files'),
      app('desktop:org.mozilla.firefox', 'Firefox'),
      app('desktop:vlc', 'VLC'),
    ];
    OasisNotification n(String appName, {String? entry}) =>
        OasisNotification(
          id: 1,
          appName: appName,
          summary: '',
          body: '',
          timestamp: DateTime(2024),
          desktopEntry: entry,
        );

    expect(notificationApp(apps, n('Files'))!.id, 'files');
    expect(
      notificationApp(apps, n('notify-send', entry: 'org.mozilla.firefox'))!
          .id,
      'desktop:org.mozilla.firefox',
    );
    expect(
      notificationApp(apps, n('notify-send', entry: 'vlc.desktop'))!.id,
      'desktop:vlc',
    );
    expect(
      notificationApp(apps, n('firefox'))!.id,
      'desktop:org.mozilla.firefox',
    );
    expect(
      notificationApp(apps, n('org.mozilla.firefox'))!.id,
      'desktop:org.mozilla.firefox',
    );
    expect(notificationApp(apps, n('unknown')), isNull);
    expect(notificationApp(const [], n('Files')), isNull);
  });

  test('daemon registers, owns name and stops', () async {
    final bus = _FakeBus();
    final daemon = NotificationDaemon(connect: () => bus);
    await daemon.start(onNotify: (_) {}, onClose: (_) {});
    expect(daemon.started, isTrue);
    expect(bus.registered, isTrue);
    await daemon.invokeAction(4, 'reply');
    await daemon.notifyClosed(4, 2);
    expect(bus.signals, [
      'ActionInvoked:4:reply',
      'NotificationClosed:4:2',
    ]);
    await daemon.stop();
    expect(daemon.started, isFalse);
    expect(bus.released, isTrue);
    await daemon.stop();
    bus.owner = false;
    await daemon.start(onNotify: (_) {}, onClose: (_) {});
    expect(daemon.started, isFalse);
    bus.owner = true;
    bus.failRequest = true;
    await daemon.start(onNotify: (_) {}, onClose: (_) {});
    expect(daemon.started, isFalse);
    expect(bus.closed, isTrue);
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
    c.toggleNotificationPanel();
    expect(c.notificationPanelOpen, isTrue);
    c.toggleNotificationPanel();
    expect(c.notificationPanelOpen, isFalse);
    c.toggleNotificationPanel();
    c.closeOverlays();
    expect(c.notificationPanelOpen, isFalse);
    c.clearNotifications();
    expect(c.notifications, isEmpty);
    c.dispose();
  });

  test('controller actions, timeouts, pins and launchAction', () async {
    final c = ShellController(apps: const []);
    final closed = <int>[];
    final actions = <String>[];
    c.notificationClosedHandler = (id, reason) => closed.add(id);
    c.notificationActionHandler = (id, action) => actions.add(action);
    c.pushNotification(
      OasisNotification(
        id: 5,
        appName: 'app',
        summary: 's',
        body: 'b',
        timestamp: DateTime(2024),
        expireTimeout: 60000,
        actions: const ['reply', 'Reply'],
      ),
    );
    c.invokeNotificationAction(c.notifications.single, 'reply');
    expect(actions, ['reply']);
    c.pushNotification(_n(6));
    c.pushNotification(_n(7));
    c.clearNotifications();
    expect(closed, [5, 7, 6]);

    expect(c.unknownAppName(), isNotEmpty);
    c.launchAction(['noop']);
    c.dispose();

    final app = OasisApp(
      id: 'a',
      name: 'A',
      icon: Icons.circle,
      iconColors: const [Color(0xFF000000), Color(0xFF111111)],
      builder: (_) => const SizedBox(),
    );
    final c2 = ShellController(
      apps: [app],
      batteryPollInterval: null,
    );
    c2.syncApps(List.of(c2.apps), pinnedIds: ['a', 'gone']);
    expect(c2.pinned.single.id, 'a');
    c2.syncApps(const [], pinnedIds: null);
    c2.dispose();

    final host = FakeWaylandHost();
    final wayland = WaylandService(host: host);
    await wayland.start();
    final c3 = ShellController(
      apps: const [],
      wayland: wayland,
      batteryPollInterval: null,
    );
    c3.launchAction(['term', '-e', 'htop']);
    await Future<void>.delayed(Duration.zero);
    expect(host.calls, contains('launch:term -e htop'));
    c3.dispose();
    wayland.dispose();
  });
}

class _FakeBus extends Fake implements DBusClient {
  var registered = false;
  var released = false;
  var closed = false;
  var owner = true;
  var failRequest = false;
  final signals = <String>[];

  @override
  Future<void> registerObject(DBusObject object) async {
    registered = true;
  }

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
  Future<DBusReleaseNameReply> releaseName(String name) async {
    released = true;
    return DBusReleaseNameReply.released;
  }

  @override
  Future<void> unregisterObject(DBusObject object) async {}

  @override
  Future<void> emitSignal({
    required DBusObjectPath path,
    required String interface,
    required String name,
    Iterable<DBusValue> values = const [],
    String? destination,
  }) async {
    signals.add(
      '$name:${values.map((v) => v.toNative()).join(':')}',
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

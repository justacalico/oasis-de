import 'dart:async';

import 'package:dbus/dbus.dart';

class OasisNotification {
  const OasisNotification({
    required this.id,
    required this.appName,
    required this.summary,
    required this.body,
    required this.timestamp,
    this.urgency = 1,
    this.expireTimeout = -1,
    this.transient = false,
    this.actions = const [],
  });

  final int id;
  final String appName;
  final String summary;
  final String body;
  final DateTime timestamp;
  final int urgency;
  final int expireTimeout;
  final bool transient;
  final List<String> actions;
}

class OasisNotificationServer extends DBusObject {
  OasisNotificationServer({
    required this.onNotify,
    required this.onClose,
  }) : super(DBusObjectPath('/org/freedesktop/Notifications'));

  final void Function(OasisNotification) onNotify;
  final void Function(int) onClose;
  int _nextId = 1;

  @override
  Future<DBusMethodResponse> handleMethodCall(
    DBusMethodCall methodCall,
  ) async {
    switch (methodCall.name) {
      case 'GetServerInformation':
        return DBusMethodSuccessResponse([
          const DBusString('oasis'),
          const DBusString('Oasis'),
          const DBusString('1'),
          const DBusString('1.2'),
        ]);
      case 'GetCapabilities':
        return DBusMethodSuccessResponse([
          DBusArray.string(['body', 'actions']),
        ]);
      case 'Notify':
        final values = methodCall.values;
        final replaces = (values[1] as DBusUint32).value;
        final id = replaces != 0 ? replaces : _nextId++;
        final hints = values[6] as DBusDict;
        final urgency =
            hints.children[const DBusString('urgency')]?.toNative();
        final transient =
            hints.children[const DBusString('transient')]?.toNative();
        final actionsValue = values[5];
        onNotify(
          OasisNotification(
            id: id,
            appName: (values[0] as DBusString).value,
            summary: (values[3] as DBusString).value,
            body: (values[4] as DBusString).value,
            timestamp: DateTime.now(),
            urgency: urgency is int ? urgency : 1,
            expireTimeout: (values[7] as DBusInt32).value,
            transient: transient == true,
            actions: [
              if (actionsValue is DBusArray)
                for (final a in actionsValue.children)
                  if (a is DBusString) a.value,
            ],
          ),
        );
        return DBusMethodSuccessResponse([DBusUint32(id)]);
      case 'CloseNotification':
        onClose((methodCall.values[0] as DBusUint32).value);
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class NotificationDaemon {
  NotificationDaemon({DBusClient Function()? connect})
    : _connect = connect ?? DBusClient.session;

  final DBusClient Function() _connect;
  DBusClient? _bus;
  OasisNotificationServer? _server;
  var started = false;

  Future<void> start({
    required void Function(OasisNotification) onNotify,
    required void Function(int) onClose,
  }) async {
    final bus = _connect();
    final server = OasisNotificationServer(
      onNotify: onNotify,
      onClose: onClose,
    );
    await bus.registerObject(server);
    final reply = await bus.requestName(
      'org.freedesktop.Notifications',
    );
    started = reply == DBusRequestNameReply.primaryOwner;
    _bus = bus;
    _server = server;
  }

  Future<void> invokeAction(int id, String action) async {
    await _bus?.emitSignal(
      path: DBusObjectPath('/org/freedesktop/Notifications'),
      interface: 'org.freedesktop.Notifications',
      name: 'ActionInvoked',
      values: [DBusUint32(id), DBusString(action)],
    );
  }

  Future<void> stop() async {
    await _bus?.releaseName('org.freedesktop.Notifications');
    final server = _server;
    if (server != null) await _bus?.unregisterObject(server);
    _bus = null;
    _server = null;
    started = false;
  }
}

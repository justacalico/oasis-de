import 'dart:async';

import 'package:dbus/dbus.dart';

class OasisNotification {
  const OasisNotification({
    required this.id,
    required this.appName,
    required this.summary,
    required this.body,
    required this.timestamp,
  });

  final int id;
  final String appName;
  final String summary;
  final String body;
  final DateTime timestamp;
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
          DBusArray.string(['body']),
        ]);
      case 'Notify':
        final id = _nextId++;
        final values = methodCall.values;
        onNotify(
          OasisNotification(
            id: id,
            appName: (values[0] as DBusString).value,
            summary: (values[3] as DBusString).value,
            body: (values[4] as DBusString).value,
            timestamp: DateTime.now(),
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

  Future<void> stop() async {
    await _bus?.releaseName('org.freedesktop.Notifications');
    final server = _server;
    if (server != null) await _bus?.unregisterObject(server);
    _bus = null;
    _server = null;
    started = false;
  }
}

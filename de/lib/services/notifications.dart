import 'dart:async';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
    this.desktopEntry,
    this.iconPath,
    this.imageProvider,
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
  final String? desktopEntry;
  final String? iconPath;
  final ImageProvider? imageProvider;
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
        if (values.length < 8 ||
            values[0] is! DBusString ||
            values[1] is! DBusUint32 ||
            values[3] is! DBusString ||
            values[4] is! DBusString ||
            values[6] is! DBusDict ||
            values[7] is! DBusInt32) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final replaces = (values[1] as DBusUint32).value;
        final id = replaces != 0 ? replaces : _nextId++;
        final hints = values[6] as DBusDict;
        final urgency =
            hints.children[const DBusString('urgency')]?.toNative();
        final transient =
            hints.children[const DBusString('transient')]?.toNative();
        final actionsValue = values[5];
        final appIcon = values[2] is DBusString
            ? (values[2] as DBusString).value
            : '';
        final imageProvider = await decodeImageData(
          hints.children[const DBusString('image-data')] ??
              hints.children[const DBusString('image_data')],
        );
        onNotify(
          OasisNotification(
            id: id,
            appName: (values[0] as DBusString).value,
            summary: (values[3] as DBusString).value,
            body: (values[4] as DBusString).value,
            timestamp: clock.now(),
            urgency: urgency is int ? urgency : 1,
            expireTimeout: (values[7] as DBusInt32).value,
            transient: transient == true,
            desktopEntry:
                _hintString(hints, 'desktop-entry') ??
                _hintString(hints, 'desktop_entry'),
            iconPath:
                _hintString(hints, 'image-path') ??
                _hintString(hints, 'image_path') ??
                (appIcon.startsWith('/') ? appIcon : null),
            imageProvider: imageProvider,
            actions: [
              if (actionsValue is DBusArray)
                for (final a in actionsValue.children)
                  if (a is DBusString) a.value,
            ],
          ),
        );
        return DBusMethodSuccessResponse([DBusUint32(id)]);
      case 'CloseNotification':
        if (methodCall.values.isEmpty ||
            methodCall.values[0] is! DBusUint32) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        onClose((methodCall.values[0] as DBusUint32).value);
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

String? _hintString(DBusDict hints, String key) {
  final v = hints.children[DBusString(key)]?.toNative();
  return v is String && v.isNotEmpty ? v : null;
}

Future<ImageProvider?> decodeImageData(DBusValue? raw) async {
  var v = raw;
  if (v is DBusVariant) v = v.value;
  if (v is! DBusStruct || v.children.length != 7) return null;
  final c = v.children;
  if (c[0] is! DBusInt32 ||
      c[1] is! DBusInt32 ||
      c[2] is! DBusInt32 ||
      c[3] is! DBusBoolean ||
      c[4] is! DBusInt32 ||
      c[5] is! DBusInt32 ||
      c[6] is! DBusArray) {
    return null;
  }
  final w = (c[0] as DBusInt32).value;
  final h = (c[1] as DBusInt32).value;
  final stride = (c[2] as DBusInt32).value;
  final bits = (c[4] as DBusInt32).value;
  final channels = (c[5] as DBusInt32).value;
  final bytes = (c[6] as DBusArray).children;
  if (w <= 0 || h <= 0 || bits != 8 || (channels != 3 && channels != 4)) {
    return null;
  }
  final data = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b is! DBusByte) return null;
    data[i] = b.value;
  }
  final pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final si = y * stride + x * channels;
      if (si + 2 >= data.length) return null;
      final di = (y * w + x) * 4;
      pixels[di] = data[si];
      pixels[di + 1] = data[si + 1];
      pixels[di + 2] = data[si + 2];
      pixels[di + 3] =
          channels == 4 && si + 3 < data.length ? data[si + 3] : 255;
    }
  }
  try {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return MemoryImage(png.buffer.asUint8List());
  } catch (_) {
    return null;
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
    try {
      final server = OasisNotificationServer(
        onNotify: onNotify,
        onClose: onClose,
      );
      await bus.registerObject(server);
      final reply = await bus.requestName(
        'org.freedesktop.Notifications',
      );
      started = reply == DBusRequestNameReply.primaryOwner;
      if (!started) {
        debugPrint(
          'Oasis: org.freedesktop.Notifications name not owned ($reply)',
        );
        await bus.unregisterObject(server);
        await bus.close();
        return;
      }
      _bus = bus;
      _server = server;
    } catch (e) {
      debugPrint('Oasis: notification daemon failed to start: $e');
      await bus.close();
    }
  }

  Future<void> invokeAction(int id, String action) async {
    await _bus?.emitSignal(
      path: DBusObjectPath('/org/freedesktop/Notifications'),
      interface: 'org.freedesktop.Notifications',
      name: 'ActionInvoked',
      values: [DBusUint32(id), DBusString(action)],
    );
  }

  Future<void> notifyClosed(int id, int reason) async {
    await _bus?.emitSignal(
      path: DBusObjectPath('/org/freedesktop/Notifications'),
      interface: 'org.freedesktop.Notifications',
      name: 'NotificationClosed',
      values: [DBusUint32(id), DBusUint32(reason)],
    );
  }

  Future<void> stop() async {
    await _bus?.releaseName('org.freedesktop.Notifications');
    final server = _server;
    if (server != null) await _bus?.unregisterObject(server);
    await _bus?.close();
    _bus = null;
    _server = null;
    started = false;
  }
}

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class MprisService extends ChangeNotifier {
  MprisService({DBusClient Function()? connect, this.signalStream})
    : _connect = connect ?? DBusClient.session;

  final DBusClient Function() _connect;
  final Stream<DBusSignal> Function(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  })?
  signalStream;

  DBusClient? _bus;
  DBusRemoteObject? _player;
  StreamSubscription<DBusSignal>? _propsSub;
  StreamSubscription<DBusSignal>? _ownerSub;

  var hasPlayer = false;
  var playing = false;
  var title = '';
  var artist = '';
  var album = '';
  var playerName = '';

  Stream<DBusSignal> _signals(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  }) =>
      (signalStream ??
              (DBusClient b, {sender, interface, name, path}) =>
                  DBusSignalStream(
                    b,
                    sender: sender,
                    interface: interface,
                    name: name,
                    path: path,
                  ))(bus, sender: sender, interface: interface, name: name, path: path);

  Future<void> start() async {
    final bus = _connect();
    try {
      _bus = bus;
      final root = DBusRemoteObject(
        bus,
        name: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      );
      final reply = await root.callMethod(
        'org.freedesktop.DBus',
        'ListNames',
        const [],
        replySignature: DBusSignature('as'),
      );
      _ownerSub =
          _signals(
            bus,
            interface: 'org.freedesktop.DBus',
            name: 'NameOwnerChanged',
          ).listen(_onOwnerChanged, onError: (_) {});
      for (final v in (reply.returnValues.first as DBusArray).children) {
        final n = (v as DBusString).value;
        if (n.startsWith('org.mpris.MediaPlayer2.')) {
          await _bind(n);
          break;
        }
      }
    } catch (e) {
      debugPrint('Oasis: mpris failed to start: $e');
      await bus.close();
      _bus = null;
    }
  }

  void _onOwnerChanged(DBusSignal signal) {
    if (signal.values.length < 3) return;
    final name = (signal.values[0] as DBusString).value;
    final newOwner = (signal.values[2] as DBusString).value;
    if (!name.startsWith('org.mpris.MediaPlayer2.')) return;
    if (newOwner.isNotEmpty) {
      unawaited(_bind(name));
    } else if (name == playerName) {
      _propsSub?.cancel();
      _propsSub = null;
      _player = null;
      hasPlayer = false;
      playing = false;
      title = artist = album = playerName = '';
      notifyListeners();
    }
  }

  Future<void> _bind(String name) async {
    final bus = _bus;
    if (bus == null) return;
    playerName = name;
    hasPlayer = true;
    _player = DBusRemoteObject(
      bus,
      name: name,
      path: DBusObjectPath('/mpris/MediaPlayer2'),
    );
    await _readState();
    await _propsSub?.cancel();
    _propsSub =
        _signals(
          bus,
          sender: name,
          path: DBusObjectPath('/mpris/MediaPlayer2'),
          interface: 'org.freedesktop.DBus.Properties',
          name: 'PropertiesChanged',
        ).listen(
          (signal) {
            for (final e
                in (signal.values[1] as DBusDict).children.entries) {
              _apply(e.key as DBusString, e.value);
            }
            notifyListeners();
          },
          onError: (_) {},
        );
    notifyListeners();
  }

  Future<void> _readState() async {
    final player = _player;
    if (player == null) return;
    try {
      final props = await player.getAllProperties(
        'org.mpris.MediaPlayer2.Player',
      );
      for (final e in props.entries) {
        _apply(DBusString(e.key), e.value);
      }
    } catch (_) {}
  }

  void _apply(DBusString key, DBusValue value) {
    if (value is DBusVariant) value = value.value;
    if (key.value == 'PlaybackStatus') {
      playing = (value as DBusString).value == 'Playing';
    } else if (key.value == 'Metadata') {
      var t = '';
      var ar = '';
      var al = '';
      for (final e in (value as DBusDict).children.entries) {
        final k = (e.key as DBusString).value;
        final v = e.value is DBusVariant
            ? (e.value as DBusVariant).value
            : e.value;
        if (k == 'xesam:title') {
          t = (v as DBusString).value;
        } else if (k == 'xesam:artist') {
          ar = (v as DBusArray)
              .children
              .map((a) => (a as DBusString).value)
              .join(', ');
        } else if (k == 'xesam:album') {
          al = (v as DBusString).value;
        }
      }
      title = t;
      artist = ar;
      album = al;
    }
  }

  Future<void> _call(String method) async {
    final player = _player;
    if (player == null) return;
    try {
      await player.callMethod(
        'org.mpris.MediaPlayer2.Player',
        method,
        const [],
        noReplyExpected: true,
      );
    } catch (_) {}
  }

  Future<void> playPause() => _call('PlayPause');
  Future<void> next() => _call('Next');
  Future<void> previous() => _call('Previous');

  @override
  void dispose() {
    _propsSub?.cancel();
    _ownerSub?.cancel();
    _bus?.close();
    super.dispose();
  }
}

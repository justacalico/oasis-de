import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class MprisService extends ChangeNotifier {
  MprisService({
    DBusClient Function()? connect,
    this.signalStream = platformSignalStream,
  }) : _connect = connect ?? DBusClient.session;

  final DBusClient Function() _connect;
  final Stream<DBusSignal> Function(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  })
  signalStream;

  static Stream<DBusSignal> platformSignalStream(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  }) => DBusSignalStream(
    bus,
    sender: sender,
    interface: interface,
    name: name,
    path: path,
  );

  DBusClient? _bus;
  DBusRemoteObject? _player;
  StreamSubscription<DBusSignal>? _propsSub;
  StreamSubscription<DBusSignal>? _ownerSub;
  final _recent = <String>[];

  var hasPlayer = false;
  var playing = false;
  var title = '';
  var artist = '';
  var album = '';
  var playerName = '';
  var playerIdentity = '';

  Stream<DBusSignal> _signals(
    DBusClient bus, {
    String? sender,
    String? interface,
    String? name,
    DBusObjectPath? path,
  }) => signalStream(
    bus,
    sender: sender,
    interface: interface,
    name: name,
    path: path,
  );

  Future<void> start() async {
    final bus = _connect();
    try {
      _bus = bus;
      await _bindBest();
      _ownerSub =
          _signals(
            bus,
            interface: 'org.freedesktop.DBus',
            name: 'NameOwnerChanged',
          ).listen(_onOwnerChanged, onError: (_) {});
    } catch (e) {
      debugPrint('Oasis: mpris failed to start: $e');
      await bus.close();
      _bus = null;
    }
  }

  Future<List<String>> _listPlayers(DBusClient bus) async {
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
    final names = reply.returnValues.isEmpty
        ? null
        : reply.returnValues.first;
    if (names is! DBusArray) return const [];
    return [
      for (final v in names.children)
        if (v is DBusString &&
            v.value.startsWith('org.mpris.MediaPlayer2.'))
          v.value,
    ];
  }

  Future<void> _bindBest() async {
    final bus = _bus;
    if (bus == null) return;
    final names = await _listPlayers(bus);
    if (names.isEmpty) return;
    final ordered = [
      for (final n in _recent)
        if (names.contains(n)) n,
      for (final n in names)
        if (!_recent.contains(n)) n,
    ];
    for (final n in ordered) {
      if (await _isPlaying(bus, n)) {
        await _bind(n);
        return;
      }
    }
    await _bind(ordered.first);
  }

  Future<bool> _isPlaying(DBusClient bus, String name) async {
    try {
      final props = await DBusRemoteObject(
        bus,
        name: name,
        path: DBusObjectPath('/mpris/MediaPlayer2'),
      ).getAllProperties('org.mpris.MediaPlayer2.Player');
      DBusValue? v = props['PlaybackStatus'];
      if (v is DBusVariant) v = v.value;
      return v is DBusString && v.value == 'Playing';
    } catch (_) {
      return false;
    }
  }

  void _onOwnerChanged(DBusSignal signal) {
    if (signal.values.length < 3) return;
    final name = (signal.values[0] as DBusString).value;
    final newOwner = (signal.values[2] as DBusString).value;
    if (!name.startsWith('org.mpris.MediaPlayer2.')) return;
    if (newOwner.isNotEmpty) {
      if (!hasPlayer) unawaited(_bind(name));
      return;
    }
    if (name != playerName) return;
    _propsSub?.cancel();
    _propsSub = null;
    _player = null;
    hasPlayer = false;
    playing = false;
    title = artist = album = playerName = playerIdentity = '';
    notifyListeners();
    unawaited(_bindBest().catchError((Object _) {}));
  }

  Future<void> _bind(String name) async {
    final bus = _bus;
    if (bus == null) return;
    playerName = name;
    hasPlayer = true;
    _touch(name);
    _player = DBusRemoteObject(
      bus,
      name: name,
      path: DBusObjectPath('/mpris/MediaPlayer2'),
    );
    await _readState();
    await _readIdentity();
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

  void _touch(String name) {
    _recent
      ..remove(name)
      ..insert(0, name);
  }

  Future<void> _readIdentity() async {
    final player = _player;
    if (player == null) return;
    var identity = '';
    try {
      final props = await player.getAllProperties(
        'org.mpris.MediaPlayer2',
      );
      DBusValue? v = props['Identity'];
      if (v is DBusVariant) v = v.value;
      if (v is DBusString) identity = v.value;
    } catch (_) {}
    playerIdentity = identity.isEmpty
        ? playerName.replaceFirst('org.mpris.MediaPlayer2.', '')
        : identity;
  }

  void _apply(DBusString key, DBusValue value) {
    if (value is DBusVariant) value = value.value;
    if (key.value == 'PlaybackStatus' && value is DBusString) {
      playing = value.value == 'Playing';
      if (playing) _touch(playerName);
    } else if (key.value == 'Metadata' && value is DBusDict) {
      var t = '';
      var ar = '';
      var al = '';
      for (final e in value.children.entries) {
        final k = e.key;
        if (k is! DBusString) continue;
        var v = e.value;
        if (v is DBusVariant) v = v.value;
        if (k.value == 'xesam:title' && v is DBusString) {
          t = v.value;
        } else if (k.value == 'xesam:artist' && v is DBusArray) {
          ar = v.children
              .whereType<DBusString>()
              .map((a) => a.value)
              .join(', ');
        } else if (k.value == 'xesam:album' && v is DBusString) {
          al = v.value;
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

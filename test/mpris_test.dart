import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/services/mpris.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:oasis_de/shell/shell_controller.dart';

import 'package:oasis_de/shell/control_center.dart';

import 'helpers/test_app.dart';

class _FakeBus extends Fake implements DBusClient {
  _FakeBus({this.names = const [], this.props = const {}});

  final List<String> names;
  final Map<String, DBusValue> props;
  final calls = <String>[];
  var fail = false;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
    Duration? timeout,
    bool requiresPrivilegedSocket = false,
  }) async {
    if (fail) throw StateError('bus down');
    calls.add('$interface.$name');
    if (name == 'ListNames') {
      return DBusMethodSuccessResponse([
        DBusArray.string(names),
      ]);
    }
    if (name == 'GetAll') {
      return DBusMethodSuccessResponse([
        DBusDict.stringVariant(props),
      ]);
    }
    return DBusMethodSuccessResponse(const []);
  }

  @override
  Future<void> close() async {}
}

DBusDict _metadata(String title, List<String> artists, String album) {
  return DBusDict.stringVariant({
    'xesam:title': DBusString(title),
    'xesam:artist': DBusArray.string(artists),
    'xesam:album': DBusString(album),
  });
}

DBusDict _plainMetadata(String title) => DBusDict(
  DBusSignature('s'),
  DBusSignature('s'),
  {DBusString('xesam:title'): DBusString(title)},
);

MprisService _service(
  _FakeBus bus,
  StreamController<DBusSignal> signals,
) => MprisService(
  connect: () => bus,
  signalStream: (bus, {sender, interface, name, path}) =>
      signals.stream.where(
        (s) =>
            (sender == null || s.sender == sender) &&
            (interface == null || s.interface == interface) &&
            (name == null || s.name == name) &&
            (path == null || s.path == path),
      ),
);

DBusSignal _propsChanged(Map<String, DBusValue> changed) => DBusSignal(
  sender: 'org.mpris.MediaPlayer2.spotify',
  path: DBusObjectPath('/mpris/MediaPlayer2'),
  interface: 'org.freedesktop.DBus.Properties',
  name: 'PropertiesChanged',
  values: [
    DBusString('org.mpris.MediaPlayer2.Player'),
    DBusDict.stringVariant(changed),
    DBusArray.string(const []),
  ],
);

DBusSignal _ownerChanged(String name, String oldOwner, String newOwner) =>
    DBusSignal(
      sender: 'org.freedesktop.DBus',
      path: DBusObjectPath('/org/freedesktop/DBus'),
      interface: 'org.freedesktop.DBus',
      name: 'NameOwnerChanged',
      values: [DBusString(name), DBusString(oldOwner), DBusString(newOwner)],
    );

void main() {
  test('mpris binds player, tracks state, controls', () async {
    final bus = _FakeBus(
      names: const ['org.freedesktop.DBus', 'org.mpris.MediaPlayer2.spotify'],
      props: {
        'PlaybackStatus': DBusString('Playing'),
        'Metadata': _metadata('Song', ['A', 'B'], 'Record'),
      },
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();

    expect(s.hasPlayer, isTrue);
    expect(s.playing, isTrue);
    expect(s.title, 'Song');
    expect(s.artist, 'A, B');
    expect(s.album, 'Record');
    expect(s.playerName, 'org.mpris.MediaPlayer2.spotify');

    signals.add(_propsChanged({'PlaybackStatus': DBusString('Paused')}));
    await Future<void>.delayed(Duration.zero);
    expect(s.playing, isFalse);

    signals.add(
      _propsChanged({'Metadata': _metadata('Next song', [], '')}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.title, 'Next song');
    expect(s.artist, isEmpty);

    signals.add(
      _propsChanged({'Metadata': _plainMetadata('Plain')}),
    );
    signals.addError(StateError('stream hiccup'));
    await Future<void>.delayed(Duration.zero);
    expect(s.title, 'Plain');

    await s.playPause();
    await s.next();
    await s.previous();
    expect(
      bus.calls.where((c) => c.contains('Player.')),
      containsAll([
        'org.mpris.MediaPlayer2.Player.PlayPause',
        'org.mpris.MediaPlayer2.Player.Next',
        'org.mpris.MediaPlayer2.Player.Previous',
      ]),
    );

    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.other', '', 'dest'),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(s.playerName, 'org.mpris.MediaPlayer2.other');

    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.other', 'dest', ''),
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.hasPlayer, isFalse);
    expect(s.title, isEmpty);

    await s.playPause();
    s.dispose();
  });

  test('mpris ignores malformed owner signals', () async {
    final bus = _FakeBus();
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();
    expect(s.hasPlayer, isFalse);

    signals.add(
      DBusSignal(
        sender: 'x',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
        values: const [],
      ),
    );
    signals.add(_ownerChanged('org.other.Service', '', 'dest'));
    await Future<void>.delayed(Duration.zero);
    expect(s.hasPlayer, isFalse);
    s.dispose();
  });

  test('mpris tolerates a dead bus', () async {
    final bus = _FakeBus()..fail = true;
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();
    expect(s.hasPlayer, isFalse);
    s.dispose();
  });

  test('platform signal stream wraps DBusSignalStream', () {
    final stream = MprisService.platformSignalStream(
      _FakeBus(),
      sender: 'org.mpris.MediaPlayer2.spotify',
      interface: 'org.freedesktop.DBus.Properties',
      name: 'PropertiesChanged',
      path: DBusObjectPath('/mpris/MediaPlayer2'),
    );
    expect(stream, isA<Stream<DBusSignal>>());
  });

  testWidgets('media card shows track and controls', (tester) async {
    final bus = _FakeBus(
      names: const ['org.mpris.MediaPlayer2.spotify'],
      props: {
        'PlaybackStatus': DBusString('Playing'),
        'Metadata': _metadata('Tune', ['Band'], ''),
      },
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final mpris = _service(bus, signals);
    await mpris.start();
    addTearDown(mpris.dispose);
    final c = ShellController(
      apps: const [],
      backend: const NoopSystemBackend(),
      mpris: mpris,
      batteryPollInterval: null,
    );
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      ListenableBuilder(
        listenable: c,
        builder: (context, _) => Text(
          c.mpris!.hasPlayer
              ? '${c.mpris!.artist} - ${c.mpris!.title}'
              : 'nothing',
        ),
      ),
    );
    expect(find.text('Band - Tune'), findsOneWidget);
  });

  testWidgets('control center media card drives playback', (tester) async {
    final bus = _FakeBus(
      names: const ['org.mpris.MediaPlayer2.spotify'],
      props: {
        'PlaybackStatus': DBusString('Playing'),
        'Metadata': _metadata('Tune', ['Band'], 'Record'),
      },
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final mpris = _service(bus, signals);
    await mpris.start();
    addTearDown(mpris.dispose);
    final c = ShellController(
      apps: const [],
      mpris: mpris,
      batteryPollInterval: null,
    );
    addTearDown(c.dispose);
    await pumpOasis(
      tester,
      Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ShellControlCenter(controller: c),
        ),
      ),
    );
    expect(find.text('Band - Tune'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.tap(find.byIcon(Icons.skip_next));
    expect(
      bus.calls.where((c) => c.contains('Player.')),
      containsAll([
        'org.mpris.MediaPlayer2.Player.PlayPause',
        'org.mpris.MediaPlayer2.Player.Next',
        'org.mpris.MediaPlayer2.Player.Previous',
      ]),
    );

    mpris.playing = false;
    mpris.title = mpris.artist = '';
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('Nothing playing'), findsOneWidget);
  });
}

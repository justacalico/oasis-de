import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_de/services/mpris.dart';
import 'package:oasis_ui/oasis_ui.dart';
import 'package:oasis_de/shell/shell_controller.dart';

import 'package:oasis_de/shell/quick_settings.dart';

import 'helpers/test_app.dart';

class _FakeBus extends Fake implements DBusClient {
  _FakeBus({
    this.names = const [],
    this.props = const {},
    this.propsByDest = const {},
    this.failDest = const {},
  });

  final List<String> names;
  final Map<String, DBusValue> props;
  final Map<String, Map<String, DBusValue>> propsByDest;
  final Set<String> failDest;
  final calls = <String>[];
  var fail = false;
  var malformedNames = false;

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
    if (fail || failDest.contains(destination)) {
      throw StateError('bus down');
    }
    calls.add('$interface.$name');
    if (name == 'ListNames') {
      return DBusMethodSuccessResponse([
        if (malformedNames) DBusString('x') else DBusArray.string(names),
      ]);
    }
    if (name == 'GetAll') {
      return DBusMethodSuccessResponse([
        DBusDict.stringVariant(propsByDest[destination] ?? props),
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
    final names = ['org.freedesktop.DBus', 'org.mpris.MediaPlayer2.spotify'];
    final bus = _FakeBus(
      names: names,
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

    names.add('org.mpris.MediaPlayer2.other');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.other', '', 'dest'),
    );
    await pumpEventQueue();
    expect(s.playerName, 'org.mpris.MediaPlayer2.spotify');

    names.remove('org.mpris.MediaPlayer2.spotify');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.spotify', 'dest', ''),
    );
    await pumpEventQueue();
    expect(s.hasPlayer, isTrue);
    expect(s.playerName, 'org.mpris.MediaPlayer2.other');

    names.remove('org.mpris.MediaPlayer2.other');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.other', 'dest', ''),
    );
    await pumpEventQueue();
    expect(s.hasPlayer, isFalse);
    expect(s.title, isEmpty);

    await s.playPause();
    s.dispose();
  });

  test('mpris fails over to the playing survivor', () async {
    final names = [
      'org.mpris.MediaPlayer2.spotify',
      'org.mpris.MediaPlayer2.broken',
      'org.mpris.MediaPlayer2.paused',
      'org.mpris.MediaPlayer2.other',
    ];
    final bus = _FakeBus(
      names: names,
      props: {
        'PlaybackStatus': DBusString('Playing'),
        'Metadata': _metadata('Song', ['A'], ''),
      },
      propsByDest: {
        'org.mpris.MediaPlayer2.paused': {
          'PlaybackStatus': DBusString('Paused'),
        },
        'org.mpris.MediaPlayer2.other': {
          'PlaybackStatus': DBusString('Playing'),
          'Metadata': _metadata('Other Song', ['C'], ''),
        },
      },
      failDest: {'org.mpris.MediaPlayer2.broken'},
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();
    expect(s.playerName, 'org.mpris.MediaPlayer2.spotify');
    expect(s.playerIdentity, 'spotify');

    names.add('org.mpris.MediaPlayer2.newbie');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.newbie', '', 'o'),
    );
    await pumpEventQueue();
    expect(s.playerName, 'org.mpris.MediaPlayer2.spotify');

    names.remove('org.mpris.MediaPlayer2.spotify');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.spotify', 'o', ''),
    );
    await pumpEventQueue();
    expect(s.playerName, 'org.mpris.MediaPlayer2.other');
    expect(s.title, 'Other Song');

    names.add('org.mpris.MediaPlayer2.spotify');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.spotify', '', 'o2'),
    );
    await pumpEventQueue();
    expect(s.playerName, 'org.mpris.MediaPlayer2.other');

    names.remove('org.mpris.MediaPlayer2.other');
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.other', 'o', ''),
    );
    await pumpEventQueue();
    expect(s.playerName, 'org.mpris.MediaPlayer2.spotify');
    expect(s.title, 'Song');

    names.clear();
    bus.fail = true;
    signals.add(
      _ownerChanged('org.mpris.MediaPlayer2.spotify', 'o2', ''),
    );
    await pumpEventQueue();
    expect(s.hasPlayer, isFalse);
    s.dispose();
  });

  test('mpris exposes the bound player identity', () async {
    final bus = _FakeBus(
      names: const ['org.mpris.MediaPlayer2.vlc'],
      props: {
        'PlaybackStatus': DBusString('Paused'),
        'Identity': DBusString('VLC media player'),
      },
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();
    expect(s.playerIdentity, 'VLC media player');
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

  test('mpris ignores malformed metadata values', () async {
    final bus = _FakeBus(
      names: const ['org.mpris.MediaPlayer2.spotify'],
      props: {
        'PlaybackStatus': DBusString('Playing'),
        'Metadata': _metadata('Song', ['A'], 'Rec'),
      },
    );
    final signals = StreamController<DBusSignal>.broadcast();
    addTearDown(signals.close);
    final s = _service(bus, signals);
    await s.start();
    expect(s.title, 'Song');

    signals.add(_propsChanged({'PlaybackStatus': DBusInt32(1)}));
    signals.add(_propsChanged({'Metadata': DBusString('not a dict')}));
    signals.add(
      _propsChanged({
        'Metadata': DBusDict.stringVariant({
          'xesam:title': DBusInt32(1),
          'xesam:artist': DBusString('not-an-array'),
          'xesam:album': DBusArray.string(const []),
        }),
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.playing, isTrue);
    expect(s.title, isEmpty);
    expect(s.artist, isEmpty);

    signals.add(
      _propsChanged({'Metadata': _metadata('Back', ['B'], 'Al')}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.title, 'Back');
    expect(s.artist, 'B');
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

  test('mpris tolerates a malformed names reply', () async {
    final bus = _FakeBus(
      names: const ['org.mpris.MediaPlayer2.spotify'],
    )..malformedNames = true;
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

  testWidgets('quick settings media card drives playback', (tester) async {
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
          builder: (context, _) => ShellQuickSettings(controller: c),
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

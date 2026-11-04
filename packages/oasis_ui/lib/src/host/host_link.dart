import 'dart:async';
import 'dart:convert';

import 'host_endpoint.dart';

/// Transport between a remote [OasisHostConnection] and the shell's
/// [OasisHostEndpoint]. Implementations carry opaque contract payloads;
/// all contract semantics live in the endpoint and the codec.
abstract class OasisHostLink {
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]);

  Stream<Map<String, Object?>> get events;

  /// Resolves once a subscription on [events] is guaranteed delivery.
  /// On dbus the signal match rule lands asynchronously; awaiting this
  /// before snapshotting closes the window where an emitted event would
  /// never reach the client.
  Future<void> get eventsReady;

  Future<void> close();
}

/// In-process link. Payloads are JSON round-tripped so it exercises the
/// exact same wire format as the dbus transport.
class OasisHostLocalLink implements OasisHostLink {
  OasisHostLocalLink(OasisHostEndpoint endpoint)
      : _endpoint = endpoint,
        _events = StreamController<Map<String, Object?>>.broadcast() {
    _sub = endpoint.events.map(_wire<Map<String, Object?>>).listen(
          _events.add,
          onError: _events.addError,
        );
  }

  final OasisHostEndpoint _endpoint;
  final StreamController<Map<String, Object?>> _events;
  late final StreamSubscription<Map<String, Object?>> _sub;

  static T _wire<T>(Object? value) =>
      jsonDecode(jsonEncode(value)) as T;

  @override
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async =>
      _wire(await _endpoint.handleRequest(method, _wire(params)));

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<void> get eventsReady => Future.value();

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _events.close();
  }
}

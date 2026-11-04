import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

import 'host_endpoint.dart';
import 'host_link.dart';

const kOasisHostBusName = 'dev.oasis.Host';
const kOasisHostInterface = 'dev.oasis.Host';
const kOasisHostPath = '/dev/oasis/Host';

/// Client side link to a host service on the session bus. The dbus
/// surface is a single Call method and Event signal carrying codec
/// payloads, so it can never drift from the in-process path.
class OasisHostDbusLink implements OasisHostLink {
  OasisHostDbusLink(this._client, {bool ownsClient = false})
      : _ownsClient = ownsClient;

  final DBusClient _client;
  final bool _ownsClient;

  static Future<OasisHostDbusLink> session({
    DBusClient Function()? connect,
  }) async {
    final client = (connect ?? DBusClient.session)();
    await client.ping();
    return OasisHostDbusLink(client, ownsClient: true);
  }

  DBusRemoteObject get _object => DBusRemoteObject(
        _client,
        name: kOasisHostBusName,
        path: DBusObjectPath(kOasisHostPath),
      );

  @override
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final response = await _object.callMethod(
      kOasisHostInterface,
      'Call',
      [DBusString(method), DBusString(jsonEncode(params))],
      replySignature: DBusSignature('s'),
    );
    return Map<String, Object?>.from(
      jsonDecode(response.returnValues.single.asString()) as Map,
    );
  }

  @override
  Stream<Map<String, Object?>> get events => DBusSignalStream(
        _client,
        sender: kOasisHostBusName,
        interface: kOasisHostInterface,
        name: 'Event',
        path: DBusObjectPath(kOasisHostPath),
        signature: DBusSignature('s'),
      ).map(
        (signal) => Map<String, Object?>.from(
          jsonDecode(signal.values.single.asString()) as Map,
        ),
      );

  @override
  Future<void> close() async {
    if (_ownsClient) await _client.close();
  }
}

/// Exposes an [OasisHostEndpoint] on the session bus so apps running as
/// their own binaries can share the shell's appearance, locale and
/// update state.
class OasisHostDbusServer {
  OasisHostDbusServer(
    this.endpoint, {
    DBusClient Function()? connect,
    this.busName = kOasisHostBusName,
  }) : _connect = connect ?? DBusClient.session;

  final OasisHostEndpoint endpoint;
  final DBusClient Function() _connect;
  final String busName;

  DBusClient? _bus;
  _OasisHostObject? _object;
  StreamSubscription<Map<String, Object?>>? _sub;

  Future<void> serve() async {
    final bus = _bus = _connect();
    _object = _OasisHostObject(endpoint);
    await bus.registerObject(_object!);
    _sub = endpoint.events.listen(
      (event) => unawaited(
        bus.emitSignal(
          path: DBusObjectPath(kOasisHostPath),
          interface: kOasisHostInterface,
          name: 'Event',
          values: [DBusString(jsonEncode(event))],
        ),
      ),
    );
    await bus.requestName(busName);
  }

  Future<void> close() async {
    final bus = _bus;
    final object = _object;
    if (bus == null || object == null) return;
    _bus = null;
    _object = null;
    await _sub?.cancel();
    _sub = null;
    await bus.unregisterObject(object);
    await bus.releaseName(busName);
    await bus.close();
  }
}

class _OasisHostObject extends DBusObject {
  _OasisHostObject(this.endpoint) : super(DBusObjectPath(kOasisHostPath));

  final OasisHostEndpoint endpoint;

  @override
  Future<DBusMethodResponse> handleMethodCall(
    DBusMethodCall call,
  ) async {
    if (call.interface != kOasisHostInterface || call.name != 'Call') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    try {
      final result = await endpoint.handleRequest(
        call.values[0].asString(),
        Map<String, Object?>.from(
          jsonDecode(call.values[1].asString()) as Map,
        ),
      );
      return DBusMethodSuccessResponse([DBusString(jsonEncode(result))]);
    } on ArgumentError catch (e) {
      return DBusMethodErrorResponse.invalidArgs(e.message.toString());
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          kOasisHostInterface,
          methods: [
            DBusIntrospectMethod(
              'Call',
              args: [
                DBusIntrospectArgument(
                  DBusSignature('s'),
                  DBusArgumentDirection.in_,
                  name: 'method',
                ),
                DBusIntrospectArgument(
                  DBusSignature('s'),
                  DBusArgumentDirection.in_,
                  name: 'params',
                ),
                DBusIntrospectArgument(
                  DBusSignature('s'),
                  DBusArgumentDirection.out,
                  name: 'result',
                ),
              ],
            ),
          ],
          signals: [
            DBusIntrospectSignal(
              'Event',
              args: [
                DBusIntrospectArgument(
                  DBusSignature('s'),
                  DBusArgumentDirection.out,
                  name: 'event',
                ),
              ],
            ),
          ],
        ),
      ];
}

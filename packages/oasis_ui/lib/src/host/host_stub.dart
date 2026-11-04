import 'host_endpoint.dart';
import 'host_link.dart';

const kOasisHostBusName = 'dev.oasis.Host';
const kOasisHostInterface = 'dev.oasis.Host';
const kOasisHostPath = '/dev/oasis/Host';

class OasisHostDbusLink implements OasisHostLink {
  OasisHostDbusLink(Object client, {bool ownsClient = false});

  static Future<OasisHostDbusLink> session({
    Object Function()? connect,
  }) =>
      throw UnsupportedError('dbus is not available on this platform');

  @override
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) =>
      throw UnsupportedError('dbus is not available on this platform');

  @override
  Stream<Map<String, Object?>> get events => const Stream.empty();

  @override
  Future<void> get eventsReady => Future.value();

  @override
  Future<void> close() async {}
}

class OasisHostDbusServer {
  OasisHostDbusServer(
    OasisHostEndpoint endpoint, {
    Object Function()? connect,
    String busName = kOasisHostBusName,
  });

  Future<void> serve() =>
      throw UnsupportedError('dbus is not available on this platform');

  Future<void> close() async {}
}

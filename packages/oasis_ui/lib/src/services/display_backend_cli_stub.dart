import 'display_backend.dart';

class CliDisplayBackend extends NoopDisplayBackend {
  const CliDisplayBackend({this.run});

  final Object? run;
}

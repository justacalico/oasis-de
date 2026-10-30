import 'system_backend.dart';

class CliSystemBackend extends NoopSystemBackend {
  const CliSystemBackend({this.run, this.powerSupplyDir});

  final Object? run;
  final Object? powerSupplyDir;
}

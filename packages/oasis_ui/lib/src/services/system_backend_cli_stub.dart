import 'system_backend.dart';

class CliSystemBackend extends NoopSystemBackend {
  const CliSystemBackend({
    this.run,
    this.powerSupplyDir,
    this.startProcess,
    this.userName,
  });

  final Object? run;
  final Object? powerSupplyDir;
  final Object? startProcess;
  final Object? userName;
}
